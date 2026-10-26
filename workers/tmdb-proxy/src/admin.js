/**
 * Private routes. They answer 404 unless ADMIN_TOKEN matches
 * `Authorization: Bearer …`, so a missing or wrong token looks like no route.
 *
 *   POST /admin/kinopub/{id}/forget?kind=logo|backdrop|poster
 *   POST /admin/kinopub/{id}/refresh?kind=logo|backdrop|poster&imdb=&kinopoisk=
 *   POST /admin/stats
 *   POST /admin/kinopub/{id}/images?kind=logo|backdrop|poster&imdb=tt…
 *   POST /admin/kinopub/{id}/pick
 *        { "logo": "https://…", "logo_lang": "en", "backdrop": "https://…" }
 *        Logo picks merge by `logo_lang` (ru / en) — one pinned file per language.
 *
 * images asks TMDB once for this title and returns the ru / en / und files.
 * The url in that list is what pick expects. pick pins that file until forget.
 * forget drops that kind and bumps art_rev, so the next image URL is new.
 * refresh asks TMDB again and stores the result on the same KV document.
 */

import { imageStats, readDocument, resolveAndStore, writeDocument } from "./title.js";

const KINDS = new Set(["logo", "backdrop", "poster"]);

export async function handleAdmin(request, env) {
  if (request.method !== "POST") return json({ error: "not_found" }, 404);
  if (!authorized(request, env)) return json({ error: "not_found" }, 404);

  const url = new URL(request.url);
  if (url.pathname === "/admin/stats") return json({ ok: true, ...(await imageStats(env)) });
  const match = url.pathname.match(/^\/admin\/kinopub\/(\d+)\/(forget|refresh|pick|images)$/);
  if (!match) return json({ error: "not_found" }, 404);
  const id = match[1];
  const action = match[2];

  if (action === "images") return images(env, id, url);
  if (action === "pick") return pick(request, env, id);
  const kind = url.searchParams.get("kind") || "logo";
  if (!KINDS.has(kind)) return json({ error: "bad_request", hint: "kind=logo|backdrop|poster" }, 400);
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
  return json({ ok: true, id, kind, art_rev: next.art_rev });
}

async function refresh(env, id, kind, url) {
  const stored = (await readDocument(env, id)) || { artwork: {}, ids: {} };
  const artwork = { ...(stored.artwork || {}) };
  artwork[kind] = [];
  const base = { ...stored, artwork, pending: true };
  const hints = {
    imdb: url.searchParams.get("imdb") || stored.ids?.imdb?.value,
    kinopoisk: url.searchParams.get("kinopoisk") || stored.ids?.kinopoisk?.value,
    type: stored.kind === "show" ? "show" : stored.kind,
  };
  await resolveAndStore(env, id, hints, base);
  const saved = await readDocument(env, id);
  return json({
    ok: true,
    id,
    kind,
    count: Array.isArray(saved?.artwork?.[kind]) ? saved.artwork[kind].length : 0,
  });
}

async function images(env, id, url) {
  const kind = url.searchParams.get("kind") || "logo";
  if (!KINDS.has(kind)) return json({ error: "bad_request", hint: "kind=logo|backdrop|poster" }, 400);
  const stored = await readDocument(env, id);
  const imdb = url.searchParams.get("imdb") || stored?.ids?.imdb?.value;
  const located = await locateTmdb(env, stored, imdb);
  if (!located) return json({ error: "bad_request", hint: "pass ?imdb=tt… or open the title once" }, 400);
  const payload = await tmdbGet(env, `/3/${located.type}/${located.tmdbId}/images`);
  if (!payload) return json({ error: "bad_gateway", hint: "TMDB images did not answer" }, 502);
  const field = kind === "logo" ? "logos" : kind === "poster" ? "posters" : "backdrops";
  const grouped = { ru: [], en: [], und: [] };
  for (const file of payload[field] || []) {
    const bucket = langBucket(file.iso_639_1);
    if (!bucket) continue;
    grouped[bucket].push(presentFile(file));
  }
  for (const bucket of Object.keys(grouped)) {
    grouped[bucket].sort((a, b) => compareRank(rankOf(kind, a), rankOf(kind, b)));
    if (grouped[bucket][0]) grouped[bucket][0].pick = true;
  }
  return json({
    ok: true,
    id,
    kind,
    tmdb: `${located.type}/${located.tmdbId}`,
    ...grouped,
    stored: (stored?.artwork?.[kind] || []).map((item) => ({
      url: item.url, lang: item.lang ?? null, pinned: item.pinned === true,
      width: item.width ?? null, height: item.height ?? null,
    })),
  });
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
  });
  return response.ok ? response.json() : null;
}

function langBucket(iso) {
  if (iso === "ru" || iso === "en") return iso;
  if (!iso) return "und";
  return null;
}

function presentFile(file) {
  const path = file.file_path || "";
  const from = (path.match(/\.([a-z0-9]+)$/i) || [])[1]?.toLowerCase() || "";
  const original = `https://image.tmdb.org/t/p/original${path}`;
  const url = from === "svg" ? original.replace(/\.svg$/i, ".png") : original;
  return {
    url,
    from: from || null,
    width: file.width ?? null,
    height: file.height ?? null,
    vote: file.vote_average ?? null,
  };
}

function rankOf(kind, item) {
  if (kind !== "logo") return [-(item.width || 0)];
  const raster = item.from === "png" || item.from === "jpg" || item.from === "jpeg" || item.from === "webp";
  return [raster ? 0 : 1, -(item.height || 0), item.width || 0];
}

function compareRank(a, b) {
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1;
  }
  return 0;
}

async function pick(request, env, id) {
  let body;
  try { body = await request.json(); } catch { body = null; }
  if (!body || typeof body !== "object") return json({ error: "bad_request" }, 400);
  const stored = (await readDocument(env, id)) || {
    version: 2, ids: { kinopub: { value: id, confidence: 1, method: "admin" } },
    artwork: { poster: [], backdrop: [], logo: [] }, pending: false,
  };
  const artwork = { ...(stored.artwork || {}) };
  const picked = {};
  for (const kind of KINDS) {
    const raw = body[kind];
    if (raw == null || raw === "") continue;
    const safe = safeURL(raw);
    if (!safe) return json({ error: "bad_request", hint: `${kind} must be an https URL` }, 400);
    const lang = body[`${kind}_lang`] ?? null;
    const pin = {
      source: "admin",
      url: safe,
      lang: lang === "ru" || lang === "en" ? lang : null,
      pinned: true,
      width: null,
      height: null,
    };
    if (kind === "logo") {
      const prev = Array.isArray(artwork.logo) ? artwork.logo : [];
      const tag = pin.lang;
      artwork.logo = prev.filter((item) => {
        if (item?.pinned !== true) return true;
        if (!tag) return false;
        const itemLang = item.lang === "ru" || item.lang === "en" ? item.lang : null;
        return itemLang !== tag;
      });
      artwork.logo.push(pin);
    } else {
      artwork[kind] = [pin];
    }
    picked[kind] = safe;
  }
  if (!Object.keys(picked).length) return json({ error: "bad_request", hint: "pass logo, backdrop, or poster" }, 400);
  const next = { ...stored, artwork, art_rev: (stored.art_rev || 0) + 1, pending: false };
  await writeDocument(env, id, next);
  return json({ ok: true, id, art_rev: next.art_rev, picked });
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
