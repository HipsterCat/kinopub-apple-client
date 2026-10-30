/**
 * GET /v1/card/by/kinopub/{id}
 *
 * The curated card from D1 (tools/metadata-ingest/data/card-2.db, uploaded by
 * upload_card2.py). Featured people, a few regular names, counts for the
 * rest, pictures, top episodes, network. The full cast stays in kv.db.
 */

const HINT = "/v1/card/by/kinopub/{id}";

export async function handleCard(url, env) {
  const id = url.pathname.split("/").pop();
  if (!/^\d+$/.test(id || "")) return json({ error: "bad_request", hint: HINT }, 400);
  if (!env.CATALOG) return json({ error: "misconfigured", hint: "D1 CATALOG is not bound" }, 500);

  const db = env.CATALOG;
  const kinopubId = Number(id);
  const [card, billing, roles, counts, images, episodes, networks, seasons] = await db.batch([
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
    seasons: seasons.results || [],
  });
}

function score(value, votes) {
  if (value == null) return null;
  return { value, votes: votes ?? null };
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
