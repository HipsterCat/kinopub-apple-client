/**
 * Private routes. They answer 404 unless ADMIN_TOKEN matches
 * `Authorization: Bearer …`, so a missing or wrong token looks like no route.
 *
 *   POST /admin/kinopub/{id}/forget?kind=logo|backdrop|cover|poster
 *   POST /admin/kinopub/{id}/refresh?kind=logo|backdrop|cover|poster&imdb=&kinopoisk=
 *   POST /admin/stats
 *   POST /admin/kinopub/{id}/images?kind=logo|backdrop|cover|poster&imdb=tt…
 *   POST /admin/kinopub/{id}/pick
 *        { "logo": "https://…", "logo_lang": "en", "logo_width": 1200, "logo_height": 400,
 *          "backdrop": "https://…",
 *          "cover": "https://…", "cover_lang": "ru" }
 *        A logo, poster or cover pick replaces every file of its language
 *        (`*_lang`, none = textless), pinned or not; a backdrop pick replaces
 *        all backdrops. Cover lists/picks language-tagged TMDB backdrops
 *        (`images.backdrops` with iso_639_1). The pin is also written to D1
 *        c2_image. Any https URL is accepted, not only TMDB's.
 *   POST /admin/kinopub/{id}/upload?kind=logo|backdrop|cover|poster&lang=ru&width=&height=
 *        body: PNG / JPEG / WebP bytes. Stored in KV (src/uploads.js), served from
 *        /img/upload/{sha256}.{ext}, pinned like a pick and listed in `uploads[]`.
 *   POST /admin/keys { "fanart": "…", "tvdb": "…" }
 *        Saves source API keys in KV when the Worker has no secret for them; an
 *        empty string removes one. Answers which sources have a key, never the keys.
 *   POST /admin/kinopub/{id}/link
 *        { "imdb": "tt…", "kinopoisk": "123", "tmdb": "tv/123", "myshows": "123", "kind": "show" }
 *        Pins ids kino.pub never sent. A bare tmdb number needs kind show or movie.
 *        Does not download. The next open of a stub fills from these ids.
 *
 * images asks TMDB once for this title and returns the ru / en / und files. With
 * `sources=1` every file carries `source` and `preview`, the other sources of
 * src/sources.js (fanart.tv, TheTVDB, tvoe, Kinopoisk, Wikidata, uploads) join the
 * same language buckets, `sources` lists each source with its count and status, and
 * a title TMDB does not know still answers (TMDB empty). Older apps send no flag and
 * get the TMDB-only shape they decode.
 * The url in that list is what pick expects. pick pins that file until forget.
 * forget drops that kind and bumps art_rev, so the next image URL is new.
 * refresh asks TMDB again and stores the result on the same KV document.
 */

import {
  artworkFromTmdb, freshImageLanguages, imageStats, readDocument, resolveAndStore,
  stitchDocument, writeDocument,
} from "./title.js";
import { SOURCE_ORDER, extraImageFiles, saveSourceKeys, urlKey } from "./sources.js";
import { isUploadURL, storeUpload } from "./uploads.js";

const KINDS = new Set(["logo", "backdrop", "cover", "poster"]);

export async function handleAdmin(request, env) {
  if (request.method !== "POST") return json({ error: "not_found" }, 404);
  if (!authorized(request, env)) return json({ error: "not_found" }, 404);

  const url = new URL(request.url);
  if (url.pathname === "/admin/stats") return json({ ok: true, ...(await imageStats(env)) });
  if (url.pathname === "/admin/keys") return keys(request, env);
  const match = url.pathname.match(/^\/admin\/kinopub\/(\d+)\/(forget|refresh|pick|images|link|upload)$/);
  if (!match) return json({ error: "not_found" }, 404);
  const id = match[1];
  const action = match[2];

  if (action === "images") return images(env, id, url);
  if (action === "pick") return pick(request, env, id);
  if (action === "link") return link(request, env, id);
  if (action === "upload") return upload(request, env, id, url);
  const kind = url.searchParams.get("kind") || "logo";
  if (!KINDS.has(kind)) return json({ error: "bad_request", hint: "kind=logo|backdrop|cover|poster" }, 400);
  if (action === "forget") return forget(env, id, kind);
  return refresh(env, id, kind, url);
}

function authorized(request, env) {
  const expected = typeof env?.ADMIN_TOKEN === "string" ? env.ADMIN_TOKEN : "";
  if (!expected) return false;
  const header = request.headers.get("Authorization") || "";
  const got = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (got.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < got.length; i++) diff |= got.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}

async function forget(env, id, kind) {
  const stored = await readDocument(env, id);
  if (!stored) return json({ error: "not_found", hint: "no document" }, 404);
  const artwork = { ...(stored.artwork || {}) };
  artwork[kind] = [];
  const next = { ...stored, artwork, art_rev: (stored.art_rev || 0) + 1, pending: true };
  await writeDocument(env, id, next);
  await forgetImageRows(env, id, kind);
  return json({ ok: true, id, kind, art_rev: next.art_rev });
}

async function refresh(env, id, kind, url) {
  const stored = (await readDocument(env, id)) || { artwork: {}, ids: {} };
  const artwork = { ...(stored.artwork || {}) };
  // Cover pins live in artwork.cover; automatic candidates are the lang-tagged
  // files under artwork.backdrop. Clear both so resolve re-fills from TMDB.
  if (kind === "cover") {
    artwork.cover = [];
    artwork.backdrop = [];
  } else {
    artwork[kind] = [];
  }
  const base = { ...stored, artwork, pending: true };
  const hints = {
    imdb: url.searchParams.get("imdb") || stored.ids?.imdb?.value,
    kinopoisk: url.searchParams.get("kinopoisk") || stored.ids?.kinopoisk?.value,
    type: stored.kind === "show" ? "show" : stored.kind,
  };
  await resolveAndStore(env, id, hints, base, { fresh: true });
  const saved = await readDocument(env, id);
  const countKind = kind === "cover" ? "backdrop" : kind;
  return json({
    ok: true,
    id,
    kind,
    count: Array.isArray(saved?.artwork?.[countKind]) ? saved.artwork[countKind].length : 0,
  });
}

async function images(env, id, url) {
  const kind = url.searchParams.get("kind") || "logo";
  if (!KINDS.has(kind)) return json({ error: "bad_request", hint: "kind=logo|backdrop|cover|poster" }, 400);
  const withSources = url.searchParams.get("sources") === "1";
  const stored = await readDocument(env, id);
  const imdb = url.searchParams.get("imdb") || stored?.ids?.imdb?.value;
  const located = await locateTmdb(env, stored, imdb);
  if (!located && !withSources) {
    return json({ error: "bad_request", hint: "pass ?imdb=tt… or open the title once" }, 400);
  }
  // ru / en / textless only, past TMDB's gateway cache: see freshImageLanguages.
  const languages = encodeURIComponent(freshImageLanguages());
  const fetched = located
    ? await tmdbGet(env, `/3/${located.type}/${located.tmdbId}/images?include_image_language=${languages}`)
    : null;
  if (!fetched && !withSources) return json({ error: "bad_gateway", hint: "TMDB images did not answer" }, 502);
  const tmdbStatus = !located ? "no_id" : fetched ? "ok" : "failed";
  const payload = fetched || {};
  // Cover and backdrop both list TMDB `backdrops`. Cover's automatic set is the
  // language-tagged rows already stored on artwork.backdrop.
  const field = kind === "logo" ? "logos" : kind === "poster" ? "posters" : "backdrops";
  const storeKind = kind === "cover" ? "backdrop" : kind;
  // The list is fresh from TMDB, so the stored automatic choice follows it now: a
  // file uploaded to TMDB a minute ago is served without a refresh. Pins stay.
  const adopted = stored && fetched
    ? await adoptTmdbFiles(env, id, stored, storeKind, payload[field])
    : [];
  const storedArt = kind === "cover"
    ? (stored?.artwork?.cover || [])
    : (fetched ? adopted : (stored?.artwork?.[storeKind] || []));
  const grouped = {};
  for (const file of payload[field] || []) {
    const bucket = langBucket(file.iso_639_1);
    // Cover is lang-aware: skip textless plates in the picker grid (backdrop
    // still lists them under und).
    if (kind === "cover" && bucket === "und") continue;
    if (!grouped[bucket]) grouped[bucket] = [];
    grouped[bucket].push(presentFile(file, bucket, withSources));
  }
  for (const bucket of Object.keys(grouped)) {
    grouped[bucket].sort((a, b) => compareRank(rankOf(storeKind, a), rankOf(storeKind, b)));
    // The automatic choice is only ru / en / no-language. Every other file
    // is still listed, so a pin can select it.
    const auto = kind === "cover"
      ? (bucket === "ru" || bucket === "en")
      : (bucket === "ru" || bucket === "en" || bucket === "und");
    if (auto && grouped[bucket][0]) {
      grouped[bucket][0].pick = true;
    }
  }
  let sources = null;
  if (withSources) {
    const tmdbFiles = Object.values(grouped).flat();
    const extra = await extraImageFiles(env, id, stored, kind, {
      exclude: tmdbFiles.map((file) => urlKey(file.url)),
    });
    for (const file of extra.files) {
      const bucket = langBucket(file.lang);
      if (kind === "cover" && bucket === "und") continue;
      if (!grouped[bucket]) grouped[bucket] = [];
      grouped[bucket].push({ ...file, lang: bucket });
    }
    const all = { tmdb: { status: tmdbStatus, count: tmdbFiles.length }, ...extra.sources };
    sources = SOURCE_ORDER.filter((name) => all[name])
      .map((name) => ({ id: name, count: all[name].count || 0, status: all[name].status }));
  }
  const body = {
    ok: true,
    id,
    kind,
    tmdb: located ? `${located.type}/${located.tmdbId}` : null,
    ru: grouped.ru || [],
    en: grouped.en || [],
    und: grouped.und || [],
    stored: storedArt.map((item) => ({
      url: item.url, lang: item.lang ?? null, pinned: item.pinned === true,
      width: item.width ?? null, height: item.height ?? null,
    })),
  };
  for (const [key, list] of Object.entries(grouped)) {
    if (key === "ru" || key === "en" || key === "und") continue;
    body[key] = list;
  }
  // After the language buckets: an older decoder reads unknown keys as buckets.
  if (sources) body.sources = sources;
  return json(body);
}

async function adoptTmdbFiles(env, id, stored, kind, files) {
  const current = stored.artwork?.[kind] || [];
  const next = artworkFromTmdb(stored.artwork, kind, files);
  const sameURLs = (a, b) => a.length === b.length && a.every((item, i) => item?.url === b[i]?.url);
  if (sameURLs(current, next)) return current;
  const artwork = { ...(stored.artwork || {}), [kind]: next };
  await writeDocument(env, id, { ...stored, artwork, art_rev: (stored.art_rev || 0) + 1 });
  return next;
}

async function locateTmdb(env, stored, imdb) {
  const existing = stored?.ids?.tmdb?.value;
  if (typeof existing === "string" && existing.includes("/")) {
    const [type, tmdbId] = existing.split("/");
    if ((type === "movie" || type === "tv") && tmdbId) return { type, tmdbId };
  }
  if (!imdb) return null;
  const found = await tmdbGet(env, `/3/find/${imdb}?external_source=imdb_id`);
  const preferTv = stored?.kind === "show";
  const order = preferTv ? ["tv", "movie"] : ["movie", "tv"];
  for (const type of order) {
    const hit = found?.[`${type}_results`]?.[0];
    if (hit?.id) return { type, tmdbId: String(hit.id) };
  }
  return null;
}

async function tmdbGet(env, path) {
  if (!env?.TMDB_READ_TOKEN) return null;
  const response = await fetch(`https://api.themoviedb.org${path}`, {
    headers: { Accept: "application/json", Authorization: `Bearer ${env.TMDB_READ_TOKEN}` },
    cache: "no-store",
  });
  return response.ok ? response.json() : null;
}

function langBucket(iso) {
  if (!iso) return "und";
  const tag = String(iso).trim().toLowerCase();
  if (!/^[a-z]{2,3}$/.test(tag)) return "und";
  return tag;
}

function presentFile(file, lang, withSource = false) {
  const path = file.file_path || "";
  const from = (path.match(/\.([a-z0-9]+)$/i) || [])[1]?.toLowerCase() || "";
  const original = `https://image.tmdb.org/t/p/original${path}`;
  const url = from === "svg" ? original.replace(/\.svg$/i, ".png") : original;
  const presented = {
    url,
    lang,
    from: from || null,
    width: file.width ?? null,
    height: file.height ?? null,
    vote: file.vote_average ?? null,
    votes: file.vote_count ?? null,
  };
  if (withSource) {
    presented.source = "tmdb";
    presented.preview = url.replace("/t/p/original/", "/t/p/w780/");
  }
  return presented;
}

// Most votes first — the same order title.js uses for its automatic choice. Logos
// keep PNG before SVG; size only breaks ties.
function rankOf(kind, item) {
  if (kind !== "logo") return [-(item.vote || 0), -(item.votes || 0), -(item.width || 0)];
  const raster = item.from === "png" || item.from === "jpg" || item.from === "jpeg" || item.from === "webp";
  return [raster ? 0 : 1, -(item.vote || 0), -(item.votes || 0), -(item.height || 0), item.width || 0];
}

function compareRank(a, b) {
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1;
  }
  return 0;
}

async function link(request, env, id) {
  let body;
  try { body = await request.json(); } catch { body = null; }
  const stored = await readDocument(env, id);
  const result = stitchDocument(stored, id, body);
  if (result.error) return json({ error: "bad_request", hint: result.error }, 400);
  await writeDocument(env, id, result.document);
  return json({
    ok: true,
    id,
    ids: result.linked,
    pending: result.document.pending === true,
    created: !stored,
  });
}

async function pick(request, env, id) {
  let body;
  try { body = await request.json(); } catch { body = null; }
  if (!body || typeof body !== "object") return json({ error: "bad_request" }, 400);
  const result = await pin(env, id, body);
  return result.error ? json({ error: "bad_request", hint: result.error }, 400) : json(result);
}

async function upload(request, env, id, url) {
  const kind = url.searchParams.get("kind") || "poster";
  if (!KINDS.has(kind)) return json({ error: "bad_request", hint: "kind=logo|backdrop|cover|poster" }, 400);
  const stored = await storeUpload(request, env);
  if (stored.error) return json({ error: "bad_request", hint: stored.error }, stored.status || 400);
  const lang = kind === "backdrop" ? null : languageTag(url.searchParams.get("lang"));
  const width = positiveInt(url.searchParams.get("width"));
  const height = positiveInt(url.searchParams.get("height"));
  const body = { [kind]: stored.url, [`${kind}_lang`]: lang, [`${kind}_width`]: width, [`${kind}_height`]: height };
  const result = await pin(env, id, body, { kind, url: stored.url, lang, width, height });
  if (result.error) return json({ error: "bad_request", hint: result.error }, 400);
  return json({ ...result, url: stored.url });
}

async function keys(request, env) {
  let body;
  try { body = await request.json(); } catch { body = {}; }
  const result = await saveSourceKeys(env, body && typeof body === "object" ? body : {});
  return result.error ? json({ error: "bad_request", hint: result.error }, 500) : json({ ok: true, ...result });
}

/** Pins the files of `body`; `uploaded` is also kept in the document's `uploads[]`. */
async function pin(env, id, body, uploaded = null) {
  const stored = (await readDocument(env, id)) || {
    version: 2, ids: { kinopub: { value: id, confidence: 1, method: "admin" } },
    artwork: { poster: [], backdrop: [], cover: [], logo: [] }, pending: false,
  };
  const artwork = { ...(stored.artwork || {}) };
  const picked = {};
  const pins = [];
  for (const kind of KINDS) {
    const raw = body[kind];
    if (raw == null || raw === "") continue;
    const safe = safeURL(raw);
    if (!safe) return { error: `${kind} must be an https URL` };
    const lang = languageTag(body[`${kind}_lang`]);
    const pin = {
      source: isUploadURL(safe) ? "upload" : "admin",
      url: safe,
      lang,
      pinned: true,
      width: positiveInt(body[`${kind}_width`]),
      height: positiveInt(body[`${kind}_height`]),
    };
    if (kind === "backdrop") {
      artwork.backdrop = [pin];
    } else {
      // One file per language: the pick drops the language's automatic file too, so
      // the worker never holds two and a later refresh keeps the pin (title.js).
      // Cover pins live in artwork.cover; automatic covers still read lang-tagged
      // rows from artwork.backdrop when no pin exists.
      const prev = Array.isArray(artwork[kind]) ? artwork[kind] : [];
      artwork[kind] = [...prev.filter((item) => languageTag(item?.lang) !== lang), pin];
    }
    pins.push([kind, pin]);
    picked[kind] = safe;
  }
  if (!Object.keys(picked).length) return { error: "pass logo, backdrop, cover, or poster" };
  const next = { ...stored, artwork, art_rev: (stored.art_rev || 0) + 1, pending: false };
  if (uploaded) {
    const uploads = (stored.uploads || []).filter((item) => item?.url !== uploaded.url);
    next.uploads = [...uploads, uploaded];
  }
  await writeDocument(env, id, next);
  for (const [kind, pin] of pins) await storeImageRow(env, id, kind, pin);
  return { ok: true, id, art_rev: next.art_rev, picked };
}

function positiveInt(raw) {
  const value = Number(raw);
  return Number.isInteger(value) && value > 0 ? value : null;
}

// D1 c2_image is what /v2/title lists. The title-level rows of a kind (no person,
// season or episode) follow KV: a pick replaces its language's rows, forget drops
// them. A D1 failure does not undo the KV write.
const TITLE_ROW = "person_id IS NULL AND season IS NULL AND episode IS NULL";

async function storeImageRow(env, id, kind, pin) {
  if (!env?.CATALOG) return;
  const db = env.CATALOG;
  const kinopubId = Number(id);
  try {
    const clear = kind === "backdrop"
      ? db.prepare(`DELETE FROM c2_image WHERE kinopub_id = ? AND kind = ? AND ${TITLE_ROW}`)
        .bind(kinopubId, kind)
      : db.prepare(`DELETE FROM c2_image WHERE kinopub_id = ? AND kind = ? AND lang IS ? AND ${TITLE_ROW}`)
        .bind(kinopubId, kind, pin.lang);
    const insert = db.prepare(
      "INSERT INTO c2_image (kinopub_id, kind, lang, url, source, width, height) VALUES (?, ?, ?, ?, ?, ?, ?)",
    ).bind(kinopubId, kind, pin.lang, pin.url, pin.source, pin.width, pin.height);
    await db.batch([clear, insert]);
  } catch (error) {
    console.warn("c2_image pick", id, kind, error?.message || error);
  }
}

async function forgetImageRows(env, id, kind) {
  if (!env?.CATALOG) return;
  try {
    await env.CATALOG.prepare(`DELETE FROM c2_image WHERE kinopub_id = ? AND kind = ? AND ${TITLE_ROW}`)
      .bind(Number(id), kind).run();
  } catch (error) {
    console.warn("c2_image forget", id, kind, error?.message || error);
  }
}

function languageTag(raw) {
  if (raw == null || raw === "") return null;
  const tag = String(raw).trim().toLowerCase();
  if (!/^[a-z]{2,3}$/.test(tag) || tag === "und") return null;
  return tag;
}

function safeURL(raw) {
  try {
    const parsed = new URL(String(raw));
    if (parsed.protocol !== "https:") return null;
    return parsed.toString();
  } catch {
    return null;
  }
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}
