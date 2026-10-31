/**
 * GET /v2/title/by/kinopub/{id}
 *
 * The title the page reads. D1 holds the curated card, including every
 * episode we know. A resolve on the worker writes that row itself; the
 * upload script only catches up what was already stored.
 */

const HINT = "/v2/title/by/kinopub/{id}";

export async function handleCard(url, env) {
  const id = url.pathname.split("/").pop();
  if (!/^\d+$/.test(id || "")) return json({ error: "bad_request", hint: HINT }, 400);
  if (!env.CATALOG) return json({ error: "misconfigured", hint: "D1 CATALOG is not bound" }, 500);

  const db = env.CATALOG;
  const kinopubId = Number(id);
  const [card, billing, roles, counts, images, episodes, rows, networks, seasons] = await db.batch([
    db.prepare("SELECT * FROM c2_card WHERE kinopub_id = ?").bind(kinopubId),
    db.prepare(
      `SELECT b.section, b.position, b.person_id, b.name_ru, b.name_en, b.character, b.job,
              b.episode_count, b.popularity, p.gender, p.profile_url, p.known_for_department
         FROM c2_billing b
         LEFT JOIN c2_person p ON p.person_id = b.person_id
        WHERE b.kinopub_id = ?
        ORDER BY b.section, b.position`,
    ).bind(kinopubId),
    db.prepare(
      `SELECT section, position, role_ord, credit_id, character, job, episode_count
         FROM c2_billing_role
        WHERE kinopub_id = ?
        ORDER BY section, position, role_ord`,
    ).bind(kinopubId),
    db.prepare(
      "SELECT section, total FROM c2_cast_count WHERE kinopub_id = ? ORDER BY section",
    ).bind(kinopubId),
    db.prepare(
      `SELECT kind, lang, url, source, width, height, person_id, season, episode
         FROM c2_image WHERE kinopub_id = ?`,
    ).bind(kinopubId),
    db.prepare(
      `SELECT rank, season, number, name_ru, name_en, tmdb_id, tmdb_value, tmdb_votes,
              imdb_value, imdb_votes, season_finale
         FROM c2_top_episode WHERE kinopub_id = ? ORDER BY rank`,
    ).bind(kinopubId),
    db.prepare(
      `SELECT season, number, name_ru, name_en, runtime_min, air_date, still, imdb_id,
              tmdb_id, tmdb_value, tmdb_votes, imdb_value, imdb_votes, season_finale
         FROM c2_episode WHERE kinopub_id = ? ORDER BY season, number`,
    ).bind(kinopubId),
    db.prepare(
      "SELECT tmdb_id, name, logo_url, origin_country FROM c2_network WHERE kinopub_id = ?",
    ).bind(kinopubId),
    db.prepare(
      `SELECT number, name, episodes, air_date, end_date, poster
         FROM c2_season WHERE kinopub_id = ? ORDER BY number`,
    ).bind(kinopubId),
  ]);

  const row = card.results?.[0];
  if (!row) return json({ error: "not_found", hint: "no card" }, 404);

  const roleOf = new Map();
  for (const role of roles.results || []) {
    const key = `${role.section}:${role.position}`;
    const list = roleOf.get(key) || [];
    list.push({
      credit_id: role.credit_id, character: role.character, job: role.job,
      episode_count: role.episode_count,
    });
    roleOf.set(key, list);
  }
  const grouped = {};
  for (const person of billing.results || []) {
    const list = grouped[person.section] || [];
    list.push({
      person_id: person.person_id,
      name_ru: person.name_ru,
      name_en: person.name_en,
      character: person.character,
      job: person.job,
      episode_count: person.episode_count,
      popularity: person.popularity,
      gender: person.gender,
      profile_url: person.profile_url,
      known_for_department: person.known_for_department,
      roles: roleOf.get(`${person.section}:${person.position}`) || [],
    });
    grouped[person.section] = list;
  }
  const count = {};
  for (const item of counts.results || []) count[item.section] = item.total;

  return json({
    kinopub_id: row.kinopub_id,
    type: row.type,
    title: { ru: row.title_ru, original: row.title_original },
    year: row.year,
    status: row.status,
    tagline_ru: row.tagline_ru,
    synopsis_ru: row.synopsis_ru,
    ids: {
      imdb: row.imdb_id, tmdb: row.tmdb_id, tvdb: row.tvdb_id,
      kinopoisk: row.kinopoisk_id, kinopoisk_hd: row.kinopoisk_hd_id,
      tvoe: row.tvoe_id, wikidata: row.wikidata_id, myshows: row.myshows_id,
    },
    ratings: {
      imdb: score(row.imdb, row.imdb_votes),
      kinopoisk: score(row.kinopoisk, row.kinopoisk_votes),
      tmdb: score(row.tmdb, row.tmdb_votes),
      tvoe: score(row.tvoe, row.tvoe_votes),
    },
    billing: grouped,
    counts: count,
    images: images.results || [],
    top_episodes: episodes.results || [],
    networks: networks.results || [],
    seasons: (seasons.results || []).map((season) => ({
      number: season.number,
      name: season.name,
      episode_count: season.episodes,
      air_date: season.air_date,
      end_date: season.end_date,
      poster: season.poster,
      episodes: (rows.results || []).filter((episode) => episode.season === season.number),
    })),
  });
}

/** After a KV write, the same title is updated in D1. A failure here does not
 * undo the KV write. */
export async function publishCard(env, id, document) {
  if (!env?.CATALOG || !document?.built_at) return;
  const db = env.CATALOG;
  const kinopubId = Number(id);
  const statements = [upsertCard(db, kinopubId, document)];
  const seasons = document.seasons || [];
  const episodeRows = seasons.flatMap((season) => (season.episodes || []).map((episode) => ({ season, episode })));
  statements.push(db.prepare("DELETE FROM c2_season WHERE kinopub_id = ?").bind(kinopubId));
  for (const season of seasons) statements.push(insertSeason(db, kinopubId, season));
  if (episodeRows.length) {
    statements.push(db.prepare("DELETE FROM c2_episode WHERE kinopub_id = ?").bind(kinopubId));
    for (const { season, episode } of episodeRows) statements.push(insertEpisode(db, kinopubId, season, episode));
  }
  await runBatch(db, statements.filter(Boolean));
}

function score(value, votes) {
  if (value == null) return null;
  return { value, votes: votes ?? null };
}

function upsertCard(db, kinopubId, document) {
  const ids = document.ids || {};
  const idOf = (name) => ids[name]?.value ?? null;
  const rating = (source) => (document.ratings || []).find((item) => item.source === source) || {};
  const synopsis = (document.synopsis || []).find((item) => item.variant === "full" && item.lang === "ru");
  const tagline = (document.synopsis || []).find((item) => item.variant === "tagline" && item.lang === "ru");
  const tmdb = rating("tmdb");
  return db.prepare(
    `INSERT INTO c2_card (
       kinopub_id, title_ru, title_original, year, status, synopsis_ru, tagline_ru,
       imdb_id, tmdb_id, tvdb_id, kinopoisk_id, wikidata_id, myshows_id, tmdb, tmdb_votes, updated_at
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(kinopub_id) DO UPDATE SET
       title_ru = COALESCE(excluded.title_ru, c2_card.title_ru),
       title_original = COALESCE(excluded.title_original, c2_card.title_original),
       year = COALESCE(excluded.year, c2_card.year),
       status = COALESCE(excluded.status, c2_card.status),
       synopsis_ru = COALESCE(excluded.synopsis_ru, c2_card.synopsis_ru),
       tagline_ru = COALESCE(excluded.tagline_ru, c2_card.tagline_ru),
       imdb_id = COALESCE(excluded.imdb_id, c2_card.imdb_id),
       tmdb_id = COALESCE(excluded.tmdb_id, c2_card.tmdb_id),
       tvdb_id = COALESCE(excluded.tvdb_id, c2_card.tvdb_id),
       kinopoisk_id = COALESCE(excluded.kinopoisk_id, c2_card.kinopoisk_id),
       wikidata_id = COALESCE(excluded.wikidata_id, c2_card.wikidata_id),
       myshows_id = COALESCE(excluded.myshows_id, c2_card.myshows_id),
       tmdb = COALESCE(excluded.tmdb, c2_card.tmdb),
       tmdb_votes = COALESCE(excluded.tmdb_votes, c2_card.tmdb_votes),
       updated_at = excluded.updated_at`,
  ).bind(
    kinopubId,
    document.title?.ru ?? null,
    document.title?.original ?? null,
    document.year ?? null,
    document.status ?? null,
    synopsis?.text ?? null,
    tagline?.text ?? null,
    idOf("imdb"), idOf("tmdb"), idOf("tvdb"), idOf("kinopoisk"), idOf("wikidata"), idOf("myshows"),
    tmdb.value ?? null, tmdb.votes ?? null,
    document.built_at,
  );
}

function insertSeason(db, kinopubId, season) {
  const poster = season.poster;
  const posterUrl = typeof poster === "string" ? poster : poster?.ru || null;
  return db.prepare(
    `INSERT INTO c2_season (kinopub_id, number, name, episodes, air_date, end_date, poster)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    kinopubId, season.number, langText(season.name, "ru"),
    season.episode_cnt ?? (season.episodes || []).length,
    season.air_date ?? null, season.end_date ?? null, posterUrl,
  );
}

function insertEpisode(db, kinopubId, season, episode) {
  const tmdb = episode.tmdb || {};
  const imdb = episode.imdb;
  const imdbId = typeof imdb === "string" ? imdb : (typeof imdb?.value === "string" ? imdb.value : null);
  const imdbValue = typeof imdb?.value === "number" ? imdb.value : null;
  return db.prepare(
    `INSERT INTO c2_episode (
       kinopub_id, season, number, name_ru, name_en, runtime_min, air_date, still, imdb_id,
       tmdb_id, season_tmdb_id, episode_type, season_finale, tmdb_value, tmdb_votes, imdb_value, imdb_votes
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    kinopubId, season.number, episode.number,
    langText(episode.name, "ru"), langText(episode.name, "en"),
    episode.runtime_min ?? null, episode.air_date ?? null,
    episode.thumbnail || episode.still || null,
    imdbId, episode.id ?? null, episode.season_id || season.id || null,
    episode.episode_type ?? null, episode.season_finale ? 1 : 0,
    tmdb.votes ? tmdb.value : null, tmdb.votes || null,
    imdbValue, typeof imdb?.votes === "number" && imdbValue != null ? imdb.votes : null,
  );
}

function langText(value, lang) {
  if (!value) return null;
  if (typeof value === "string") return lang === "ru" ? value : null;
  return value[lang] || null;
}

async function runBatch(db, statements) {
  for (let i = 0; i < statements.length; i += 25) {
    await db.batch(statements.slice(i, i + 25));
  }
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "public, max-age=60",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
