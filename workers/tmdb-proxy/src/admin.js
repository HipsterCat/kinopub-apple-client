/**
 * Private routes. They answer 404 unless ADMIN_TOKEN matches
 * `Authorization: Bearer …`, so a missing or wrong token looks like no route.
 *
 *   POST /admin/kinopub/{id}/forget?kind=logo|backdrop|poster
 *   POST /admin/kinopub/{id}/refresh?kind=logo|backdrop|poster&imdb=&kinopoisk=
 *   POST /admin/kinopub/{id}/pick
 *        { "logo": "https://…", "backdrop": "https://…", "poster": "https://…" }
 *
 * forget drops that kind and bumps art_rev, so the next image URL is new.
 * refresh asks TMDB again and stores the result on the same KV document.
 * pick pins one URL; the image route serves that file until forget.
 */

import { readDocument, resolveAndStore, writeDocument } from "./title.js";

const KINDS = new Set(["logo", "backdrop", "poster"]);

export async function handleAdmin(request, env) {
  if (request.method !== "POST") return json({ error: "not_found" }, 404);
  if (!authorized(request, env)) return json({ error: "not_found" }, 404);

  const url = new URL(request.url);
  const match = url.pathname.match(/^\/admin\/kinopub\/(\d+)\/(forget|refresh|pick)$/);
  if (!match) return json({ error: "not_found" }, 404);
  const id = match[1];
  const action = match[2];

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
    artwork[kind] = [{
      source: "admin", url: safe, lang: lang === "ru" || lang === "en" ? lang : null,
      pinned: true, width: null, height: null,
    }];
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
