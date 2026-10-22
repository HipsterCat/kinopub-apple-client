/**
 * /v1/title/by/kinopub/{id}
 * /img/{logo|backdrop|poster|thumbnail}/by/kinopub/{id}?w=&lang=&s=&e=
 * /img/{kind}/{size}/kinopub/{id}   (older size-in-path; still answered)
 *
 * The contract the client actually wanted: ask by kino.pub id, get everything,
 * never resolve anything yourself, never make a second call to find out whether
 * something exists.
 *
 * The image route the app should call is the query one. `w` is a pixel width
 * (omit it for the largest file we will serve, 3840). `lang` defaults to ru
 * and is ignored for backdrops, which are always textless. `s` / `e` pick a
 * season poster or an episode thumbnail. The size-in-path route stays so
 * existing callers keep working.
 *
 * Two rules shape the whole file:
 *
 *   Always answer fast, from whatever is warm. A cold title still returns a
 *   usable document built from the hints the client sent, immediately — the
 *   client is drawing a screen and cannot wait for four providers.
 *
 *   Resolve in the background, once. `ctx.waitUntil` keeps the isolate alive
 *   after the response is sent, so the first person to open a cold title pays
 *   nothing and warms it for everyone after them.
 *
 * Hints are the reason this works without a database of our own being complete.
 * The client already holds the imdb id, the kinopoisk id, the original title,
 * the year — kino.pub hands them over on every item. Sending them costs nothing
 * and means a title we have never seen is still resolvable on the spot.
 */

import { tmdbGenres } from "./genres.js";

const KINOPUB_POSTER = "https://m.staticpop.net/poster/item";
// kino.pub's own sizes, addressable from the id. Poster and backdrop fall
// back here; logo and unknown kinds 404 — never a different picture.
const KINOPUB_SIZE = { sm: "small", md: "medium", lg: "big", orig: "big", wide: "wide" };

const DOC_TTL = 60 * 60 * 24 * 30;

// The keyless kpapp.link proxy over Kinopoisk (docs/providers/kinopoisk-proxy.md).
// No auth, no documented quota — the cheap tier, safe to call on every cold
// resolve. Only `facts` is wired here for now; `staff`/`reviews`/`images` stay
// on the offline pipeline (tools/metadata-ingest/fetch_kinopoisk_proxy.py)
// until the live merge logic there is worth duplicating in a worker.
const KINOPOISK_PROXY = "https://kpapp.link/kpapi/films";

// --------------------------------------------------------------------- MD5
//
// Web Crypto's `crypto.subtle.digest` does not implement MD5 (not in the spec)
// — pushbr's URL scheme needs it anyway, so a small pure-JS implementation
// rides along. Standard bitwise MD5, RFC 1321.

function md5(input) {
  const bytes = new TextEncoder().encode(input);
  const bitLength = bytes.length * 8;
  const padded = new Uint8Array((((bytes.length + 8) >> 6) + 1) * 64);
  padded.set(bytes);
  padded[bytes.length] = 0x80;
  new DataView(padded.buffer).setUint32(padded.length - 8, bitLength >>> 0, true);
  new DataView(padded.buffer).setUint32(padded.length - 4, Math.floor(bitLength / 4294967296), true);

  const K = new Int32Array([
    -680876936, -389564586, 606105819, -1044525330, -176418897, 1200080426, -1473231341,
    -45705983, 1770035416, -1958414417, -42063, -1990404162, 1804603682, -40341101,
    -1502002290, 1236535329, -165796510, -1069501632, 643717713, -373897302, -701558691,
    38016083, -660478335, -405537848, 568446438, -1019803690, -187363961, 1163531501,
    -1444681467, -51403784, 1735328473, -1926607734, -378558, -2022574463, 1839030562,
    -35309556, -1530992060, 1272893353, -155497632, -1094730640, 681279174, -358537222,
    -722521979, 76029189, -640364487, -421815835, 530742520, -995338651, -198630844,
    1126891415, -1416354905, -57434055, 1700485571, -1894986606, -1051523, -2054922799,
    1873313359, -30611744, -1560198380, 1309151649, -145523070, -1120210379, 718787259,
    -343485551,
  ]);
  const S = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
             5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
             4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
             6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21];

  let [a0, b0, c0, d0] = [1732584193, -271733879, -1732584194, 271733878];
  const view = new DataView(padded.buffer);

  for (let chunk = 0; chunk < padded.length; chunk += 64) {
    const M = [];
    for (let j = 0; j < 16; j++) M.push(view.getUint32(chunk + j * 4, true));
    let [a, b, c, d] = [a0, b0, c0, d0];
    for (let i = 0; i < 64; i++) {
      let f, g;
      if (i < 16) { f = (b & c) | (~b & d); g = i; }
      else if (i < 32) { f = (d & b) | (~d & c); g = (5 * i + 1) % 16; }
      else if (i < 48) { f = b ^ c ^ d; g = (3 * i + 5) % 16; }
      else { f = c ^ (b | ~d); g = (7 * i) % 16; }
      const temp = d;
      d = c; c = b;
      const sum = (a + f + K[i] + M[g]) | 0;
      const rotated = (sum << S[i]) | (sum >>> (32 - S[i]));
      b = (b + rotated) | 0;
      a = temp;
    }
    a0 = (a0 + a) | 0; b0 = (b0 + b) | 0; c0 = (c0 + c) | 0; d0 = (d0 + d) | 0;
  }

  const toHex = (n) => {
    const bytes4 = new Uint8Array(4);
    new DataView(bytes4.buffer).setUint32(0, n, true);
    return Array.from(bytes4).map((b) => b.toString(16).padStart(2, "0")).join("");
  };
  return toHex(a0) + toHex(b0) + toHex(c0) + toHex(d0);
}

/** Mirrors common.pushbr_url() — same CDN, same hash, same input contract. */
function pushbrUrl(name) {
  const trimmed = (name || "").trim();
  if (!trimmed) return null;
  return `https://m.pushbr.com/actors/${md5(trimmed)}.jpg`;
}

export async function handleTitle(url, env, ctx) {
  const id = url.pathname.split("/").pop();
  if (!id) return json({ error: "bad_request", hint: "/v1/title/by/kinopub/{id}" }, 400);

  const hints = readHints(url);
  const stored = await readDocument(env, id);

  if (stored) {
    // Warm: answer from the store, and refresh in the background if the client
    // brought an id we did not have.
    const missingImdb = hints.imdb && !stored.ids?.imdb;
    const missingFacts = hints.kinopoisk && !stored.factsChecked;
    if (missingImdb || missingFacts) {
      ctx.waitUntil(resolveAndStore(env, id, hints, stored));
    }
    return json(stored, 200, { "X-Cache": "hit" });
  }

  // Cold: answer now from the hints, resolve behind the response.
  const draft = draftDocument(id, hints);
  ctx.waitUntil(resolveAndStore(env, id, hints, draft));
  return json(draft, 200, { "X-Cache": "miss" });
}

const IMAGE_KINDS = new Set(["poster", "backdrop", "logo"]);
const QUERY_KINDS = new Set(["logo", "backdrop", "poster", "thumbnail"]);
const QUERY_HINT = "/img/{logo|backdrop|poster|thumbnail}/by/kinopub/{id}?w=&lang=&s=&e=";

// Largest file we will send. TMDB "original" backdrops run well past this;
// tvoe's resizer tops out here. 1920×2.
const MAX_WIDTH = 3840;

// tvoe.live/_next/image rejects any width not in this list (400) and rejects
// any URL that is not its own static.cdn.tvoe.live file.
const TVOE_WIDTHS = [
  16, 32, 48, 64, 96, 128, 140, 175, 256, 280, 305, 320, 375, 384, 414, 425,
  512, 530, 640, 750, 768, 828, 1024, 1080, 1200, 1280, 1380, 1440, 1536, 1600,
  1920, 2048, 2300, 2560, 2732, 3000, 3440, 3840,
];

// TMDB configuration sizes, minus "original" — that bucket is chosen only when
// the file we know about is within MAX_WIDTH (or the kind's originals are not
// the multi-thousand-pixel backdrops).
const TMDB_LADDER = {
  logo: [45, 92, 154, 185, 300, 500],
  poster: [92, 154, 185, 342, 500, 780],
  backdrop: [300, 780, 1280],
  thumbnail: [92, 185, 300],
};
const TMDB_ORIGINAL_IF_WIDTH_UNKNOWN = new Set(["logo", "poster", "thumbnail"]);

// Measured 2026-10-22: small 165×250, medium 250×375, big 500×750.
// wide is 3840×2160 and has the title baked in — never a backdrop answer here.
const KINOPUB_POSTER_LADDER = [
  { w: 165, size: "small" },
  { w: 250, size: "medium" },
  { w: 500, size: "big" },
];

// kinopoiskapiunofficial.tech, measured: kp 667×1000, kp_small 360×540.
const KINOPOISK_POSTER = "https://kinopoiskapiunofficial.tech/images/posters";

// Same language first, then source. tvoe wins ru logos and textless backdrops.
// Kinopoisk posters are Russian; kino.pub posters are English and come last.
const SOURCE_ORDER = {
  logo: ["tvoe", "tmdb"],
  backdrop: ["tvoe", "tmdb"],
  poster: ["tvoe", "tmdb", "kinopoisk", "kinopub"],
  thumbnail: ["tvoe", "tmdb"],
};

export async function handleImage(url, env, ctx) {
  const route = parseImagePath(url.pathname);
  if (!route) {
    return json({ error: "bad_request", hint: QUERY_HINT }, 400);
  }
  if (route.mode === "query") return handleImageQuery(url, env, ctx, route);
  return handleLegacyImage(url, env, ctx, route);
}

// /img/{kind}/{size}/kinopub/{id} — unchanged contract.
async function handleLegacyImage(url, env, ctx, route) {
  const { kind, size, id } = route;
  if (!id) {
    return json({ error: "bad_request", hint: "/img/{kind}/{size}/kinopub/{id}" }, 400);
  }
  // Kind mismatch is a hole, never a different picture. A logo that 302s to a
  // poster is what the banner would paint instead of the lettered title.
  if (!IMAGE_KINDS.has(kind)) {
    return json({ error: "not_found", hint: "kind must be poster, backdrop, or logo" }, 404);
  }

  const stored = await readDocument(env, id);
  const chosen = stored && pickArtwork(stored, kind);
  if (chosen) return Response.redirect(chosen, 302);

  // Nothing known yet: resolve in the background so the next request can get
  // the good one. Poster/backdrop still fall back to kino.pub's own artwork
  // (always addressable from the id). Logo has no kino.pub equivalent — a
  // poster-as-logo is a lie the banner would paint instead of the lettered
  // title — so kind=logo with nothing stored is 404, never a poster.
  const hints = readHints(url);
  if (!stored) ctx.waitUntil(resolveAndStore(env, id, hints, draftDocument(id, hints)));

  if (kind === "logo") {
    return new Response(JSON.stringify({ error: "not_found", hint: "no stored logo" }), {
      status: 404,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        // Short: a cold miss 404s now, then the background resolve may fill a
        // real logo. Do not pin that miss for the document TTL.
        "Cache-Control": "public, max-age=30",
        "Access-Control-Allow-Origin": "*",
      },
    });
  }

  const fallbackSize = KINOPUB_SIZE[size] || (kind === "backdrop" ? "wide" : "medium");
  return Response.redirect(`${KINOPUB_POSTER}/${fallbackSize}/${id}.jpg`, 302);
}

// /img/{kind}/by/kinopub/{id}?w=&lang=&s=&e=
async function handleImageQuery(url, env, ctx, route) {
  const id = numericId(route.id);
  if (!id) return json({ error: "bad_request", hint: QUERY_HINT }, 400);
  if (!QUERY_KINDS.has(route.kind)) {
    return imageNotFound("kind must be logo, backdrop, poster, or thumbnail");
  }

  const request = {
    kind: route.kind,
    id,
    w: readWidth(url),
    lang: normalizeLang(url.searchParams.get("lang")),
    s: readIndex(url, "s"),
    e: readIndex(url, "e"),
  };
  if (request.kind === "thumbnail" && (request.s == null || request.e == null)) {
    return json({ error: "bad_request", hint: "thumbnail needs ?s=&e=" }, 400);
  }

  const stored = await readDocument(env, id);
  const hints = readHints(url);
  // Cold: answer now, warm the document behind the response. Hints are
  // optional — the details page is what usually brings them. An image call
  // with only the id still works once that document exists.
  if (!stored) ctx.waitUntil(resolveAndStore(env, id, hints, draftDocument(id, hints)));

  const asset = selectQueryAsset(stored, request, hints);
  const location = asset && resizeAsset(asset, request.kind, request.w);
  if (!location) return imageNotFound(missHint(request));
  return redirect(location);
}

// ------------------------------------------------------------------ helpers

function readHints(url) {
  const get = (name) => url.searchParams.get(name) || undefined;
  return {
    imdb: get("imdb"),
    kinopoisk: get("kinopoisk"),
    title: get("title"),
    original: get("original"),
    year: get("year"),
    type: get("type"),
  };
}

/** What we can say about a title we have never seen, using only what the client sent. */
function draftDocument(id, hints) {
  return {
    version: 2,
    id: null,
    // The app's model says `show`; older clients still hint `series`.
    kind: hints.type === "series" || hints.type === "show" ? "show" : hints.type ? "movie" : null,
    title: { ru: hints.title || null, original: hints.original || null },
    year: hints.year ? Number(hints.year) : null,
    ids: {
      kinopub: { value: id, confidence: 1, method: "client" },
      ...(hints.imdb ? { imdb: { value: hints.imdb, confidence: 1, method: "client" } } : {}),
      ...(hints.kinopoisk
        ? { kinopoisk: { value: hints.kinopoisk, confidence: 1, method: "client" } }
        : {}),
    },
    artwork: {
      poster: [{ source: "kinopub", url: `${KINOPUB_POSTER}/big/${id}.jpg`, lang: null }],
      backdrop: [{ source: "kinopub", url: `${KINOPUB_POSTER}/wide/${id}.jpg`, lang: null }],
    },
    ratings: [], synopsis: [], genres: [], genre_sources: [], countries: [], credits: [],
    seasons: [], trailers: [], awards: [], badges: [], copies: [],
    facts: [], reviews: [],
    // Honest about its own state: absent because nobody has asked yet, not
    // absent as a fact. The client hides sections on empty either way, but a
    // log tells the truth about which it was.
    pending: true,
  };
}

async function readDocument(env, id) {
  if (!env.DOCUMENTS) return null;         // KV not bound yet — degrade, do not fail
  return await env.DOCUMENTS.get(`title:kinopub:${id}`, { type: "json" });
}

async function writeDocument(env, id, document) {
  if (!env.DOCUMENTS) return;
  await env.DOCUMENTS.put(`title:kinopub:${id}`, JSON.stringify(document),
                          { expirationTtl: DOC_TTL });
}

/**
 * Resolve from hints and store. Runs after the response has gone out, so its
 * latency is nobody's problem — which is exactly why the client never has to
 * choose between "fast" and "complete".
 */
async function resolveAndStore(env, id, hints, base) {
  let document = base;

  // No key, no quota risk — safe to run on every cold resolve that has a
  // Kinopoisk hint. Gated on `factsChecked`, not on `ids.kinopoisk`: the draft
  // already carries the hinted id (see draftDocument), so gating on its
  // presence would mean this branch never runs — the actual first bug found
  // testing this live: a title with two real facts came back with zero.
  if (hints.kinopoisk && !base.factsChecked) {
    try {
      const facts = await kinopoiskProxyFacts(hints.kinopoisk);
      document = {
        ...document,
        factsChecked: true,
        ids: { ...document.ids, kinopoisk: { value: hints.kinopoisk, confidence: 1,
                                              method: "client" } },
        facts: facts?.items?.filter((item) => item.text).map((item) => ({
          source: "kinopoisk_proxy", text: item.text, spoiler: item.spoiler ? 1 : 0,
        })) || [],
      };
    } catch (_) {
      // Someone else's server, best-effort — a failure here must not block
      // TMDB, and must not be mistaken for "no facts" — leave factsChecked
      // unset so a later request tries again instead of caching a network blip.
    }
  }

  if (!hints.imdb || !env.TMDB_READ_TOKEN) {
    if (document !== base) await writeDocument(env, id, document);
    return;
  }

  try {
    const found = await tmdb(env, `/3/find/${hints.imdb}`, { external_source: "imdb_id" });
    const preferTv = base.kind === "show";
    const order = preferTv ? ["tv", "movie"] : ["movie", "tv"];
    let match = null, mediaType = null;
    for (const type of order) {
      const results = found?.[`${type}_results`];
      if (results?.length) { match = results[0]; mediaType = type; break; }
    }
    if (!match) {
      if (document !== base) await writeDocument(env, id, document);
      return;
    }

    const append = mediaType === "tv"
      ? "aggregate_credits,images,videos,external_ids,content_ratings,keywords,watch/providers"
      : "credits,images,videos,external_ids,keywords,release_dates,watch/providers";
    const details = await tmdb(env, `/3/${mediaType}/${match.id}`, {
      language: "ru-RU", append_to_response: append,
      include_image_language: "ru,en,null",
    });
    if (!details) {
      if (document !== base) await writeDocument(env, id, document);
      return;
    }

    await writeDocument(env, id, mergeTMDB(document, mediaType, match.id, details));
  } catch (_) {
    // Background work: a failure must never be visible, and must not poison the
    // store with a half-built document.
    if (document !== base) await writeDocument(env, id, document);
  }
}

/** kpapp.link/kpapi/films/{id}/facts — see docs/providers/kinopoisk-proxy.md. */
async function kinopoiskProxyFacts(kinopoiskId) {
  const response = await fetch(`${KINOPOISK_PROXY}/${kinopoiskId}/facts`, {
    headers: { Accept: "application/json" },
    cf: { cacheTtl: 60 * 60 * 24 * 14, cacheEverything: true },
  });
  return response.ok ? await response.json() : null;
}

async function tmdb(env, path, params) {
  const url = new URL(path, "https://api.themoviedb.org");
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
  const response = await fetch(url.toString(), {
    headers: { Accept: "application/json", Authorization: `Bearer ${env.TMDB_READ_TOKEN}` },
    cf: { cacheTtl: 21600, cacheEverything: true },
  });
  return response.ok ? await response.json() : null;
}

const IMAGE_BASE = "https://image.tmdb.org/t/p/original";

function mergeTMDB(base, mediaType, tmdbId, details) {
  const document = { ...base, pending: false, built_at: new Date().toISOString() };
  document.ids = { ...document.ids, tmdb: { value: `${mediaType}/${tmdbId}`, confidence: 1,
                                            method: "find:imdb" } };
  const external = details.external_ids || {};
  for (const [namespace, key] of [["wikidata", "wikidata_id"], ["tvdb", "tvdb_id"]]) {
    if (external[key]) {
      document.ids[namespace] = { value: String(external[key]), confidence: 1,
                                  method: "tmdb:external_ids" };
    }
  }

  document.title = {
    ru: details.name || details.title || document.title.ru,
    original: details.original_name || details.original_title || document.title.original,
  };
  document.kind = mediaType === "tv" ? "show" : "movie";

  // One per language, capped to ru / en / textless — see capArtwork. The
  // kino.pub fallback the draft carried is appended last, so it only survives
  // the cap if TMDB left a language slot empty.
  const images = details.images || {};
  const toAssets = (list) => (list || [])
    .filter((a) => a.file_path)
    .sort((a, b) => (b.width || 0) - (a.width || 0))
    .map((a) => ({ source: "tmdb", url: IMAGE_BASE + a.file_path, lang: a.iso_639_1 || null,
                   width: a.width, height: a.height }));
  document.artwork = {
    poster: capArtwork([...toAssets(images.posters), ...(document.artwork.poster || [])]),
    backdrop: capArtwork([...toAssets(images.backdrops), ...(document.artwork.backdrop || [])]),
    logo: capArtwork(toAssets(images.logos)),
  };

  if (details.vote_count) {
    document.ratings = [{ source: "tmdb", value: details.vote_average,
                          votes: details.vote_count, scale: 10 }];
  }
  if (details.overview) {
    document.synopsis = [{ source: "tmdb", lang: "ru", variant: "full",
                           text: details.overview }];
  }
  // Ours, primary first (genres.json); the raw names ride along, as in the record.
  document.genres = tmdbGenres(details.genres);
  document.genre_sources = (details.genres || []).map((g) => ({ source: "tmdb", name: g.name }));

  // `name` is localized by the request's `language` (ru-RU below), so it is
  // the Russian spelling, not English — mislabeling it name_en would split
  // this person from the identical Russian name a Kinopoisk fetch might
  // supply later, same bug fixed in fetch_tmdb.py's _credit_names(). Prefer
  // `original_name` for the English slot when it actually differs.
  const credits = details.aggregate_credits || details.credits || {};
  document.credits = (credits.cast || [])
    .sort((a, b) => (a.order ?? 999) - (b.order ?? 999))
    .slice(0, 30)
    .map((person) => {
      const nameRu = person.name || null;
      const nameEn = person.original_name && person.original_name !== person.name
        ? person.original_name : null;
      const tmdbPhoto = person.profile_path ? IMAGE_BASE + person.profile_path : null;
      // pushbr is free (a hash of a name we already have) and, for this
      // majority-RU/CIS-facing catalogue, usually the better default — see
      // policies/metadata-architecture's photo precedence note. TMDB's photo
      // still rides along as the fallback candidate.
      const photos = [pushbrUrl(nameRu), tmdbPhoto].filter(Boolean);
      return {
        department: "actor",
        character: person.roles?.[0]?.character ?? person.character ?? null,
        ord: person.order ?? null,
        episode_count: person.total_episode_count ?? null,
        sources: ["tmdb"],
        name_en: nameEn, name_ru: nameRu,
        photos,
      };
    });

  document.trailers = (details.videos?.results || [])
    .filter((video) => video.key)
    .map((video) => ({
      source: "tmdb", source_key: video.key, kind: (video.type || "trailer").toLowerCase(),
      name: video.name, lang: video.iso_639_1, official: video.official ? 1 : 0,
      url: video.site === "YouTube" ? `https://www.youtube.com/watch?v=${video.key}` : null,
    }));

  document.seasons = (details.seasons || [])
    .filter((season) => season.season_number != null)
    .map((season) => ({
      number: season.season_number, name: season.name, synopsis: season.overview || null,
      air_date: season.air_date, end_date: null, episode_cnt: season.episode_count,
      poster: season.poster_path ? IMAGE_BASE + season.poster_path : null,
      source: "tmdb", episodes: [], ratings: [],
    }));

  return document;
}

// ru first (our primary audience), then en, then textless (no title baked
// into the image — the one you want under your own logo overlay). Any other
// language is dropped: it does carry text, just not one we asked for, so
// folding it into "textless" would be a lie.
const ARTWORK_LANG_ORDER = ["ru", "en", null];

/** One image per (kind, language), at most 3. First match per language wins,
 * so pass assets already sorted by trust/width for the best pick to survive. */
function capArtwork(assets) {
  const picked = new Map();
  for (const asset of assets) {
    const lang = asset.lang ?? null;
    if (!ARTWORK_LANG_ORDER.includes(lang) || picked.has(lang)) continue;
    picked.set(lang, { ...asset, lang });
    if (picked.size === ARTWORK_LANG_ORDER.length) break;
  }
  return ARTWORK_LANG_ORDER.filter((lang) => picked.has(lang)).map((lang) => picked.get(lang));
}

/** Best artwork of a kind: our precedence, applied here so the client has none.
 * For `backdrop`, prefer textless (`lang === null`) so our own logo/title overlay
 * never collides with a title baked into the backdrop art. For `logo` and `poster`,
 * prefer `ru`. */
function pickArtwork(document, kind) {
  const list = document.artwork?.[kind];
  if (!list?.length) return null;
  if (kind === "backdrop") {
    const textless = list.find((asset) => asset.lang === null && asset.source === "tmdb")
      || list.find((asset) => asset.lang === null);
    return (textless || list[0]).url;
  }
  const russian = list.find((asset) => asset.lang === "ru");
  return (russian || list[0]).url;
}

// ---------------------------------------------------------------- query route

function parseImagePath(pathname) {
  const parts = pathname.split("/").filter(Boolean);
  if (parts[0] !== "img" || parts.length < 5) return null;
  const id = (parts[4] || "").replace(/\.\w+$/, "");
  if (parts[2] === "by" && parts[3] === "kinopub") {
    return { mode: "query", kind: parts[1], id };
  }
  if (parts[3] === "kinopub") {
    return { mode: "legacy", kind: parts[1], size: parts[2], id };
  }
  return null;
}

function numericId(raw) {
  return /^\d+$/.test(raw || "") ? raw : null;
}

function readWidth(url) {
  const raw = url.searchParams.get("w");
  if (raw == null || raw.trim() === "") return null;
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return null;
  return Math.min(Math.ceil(n), MAX_WIDTH);
}

function readIndex(url, name) {
  for (const key of [name, name.toUpperCase()]) {
    const raw = url.searchParams.get(key);
    if (raw == null || raw.trim() === "") continue;
    if (!/^\d+$/.test(raw.trim())) return null;
    return Number(raw.trim());
  }
  return null;
}

function normalizeLang(value) {
  if (!value) return "ru";
  const primary = value.toLowerCase().split(/[-_]/)[0];
  if (!primary || primary === "ru") return "ru";
  if (primary === "en") return "en";
  return primary.length === 2 ? primary : "ru";
}

function selectQueryAsset(document, request, hints) {
  const { kind, id, lang, s, e } = request;
  if (kind === "thumbnail") {
    if (!document || s == null || e == null) return null;
    return episodeAsset(document, s, e);
  }
  if (kind === "poster" && s != null) {
    if (!document) return null;
    return seasonPosterAsset(document, s);
  }
  if (kind === "backdrop") {
    if (!document) return null;
    return bestAsset(textlessBackdrops(document), "backdrop", null);
  }
  const assets = kind === "poster"
    ? posterCandidates(document, id, hints)
    : logoCandidates(document);
  return bestAsset(assets, kind, lang);
}

function posterCandidates(document, id, hints) {
  const list = (document?.artwork?.poster || []).map(normalizeAsset).filter(Boolean);
  const kp = numericId(String(document?.ids?.kinopoisk?.value || hints.kinopoisk || ""));
  if (kp && !list.some((asset) => asset.source === "kinopoisk")) {
    list.push({
      source: "kinopoisk",
      url: `${KINOPOISK_POSTER}/kp/${kp}.jpg`,
      lang: "ru",
      width: 667,
    });
  }
  if (id && !list.some((asset) => asset.source === "kinopub")) {
    list.push({
      source: "kinopub",
      url: `${KINOPUB_POSTER}/big/${id}.jpg`,
      lang: "en",
      width: 500,
    });
  }
  return list;
}

function logoCandidates(document) {
  return (document?.artwork?.logo || [])
    .map(normalizeAsset)
    .filter((asset) => asset && asset.source !== "kinopub" && !isKinopubPoster(asset.url));
}

function textlessBackdrops(document) {
  return (document?.artwork?.backdrop || [])
    .map(normalizeAsset)
    .filter((asset) => asset
      && (asset.lang ?? null) === null
      && asset.source !== "kinopub"
      && !isKinopubPoster(asset.url));
}

function seasonPosterAsset(document, seasonNumber) {
  const season = (document.seasons || []).find((item) => Number(item.number) === seasonNumber);
  if (!season) return null;
  const raw = season.poster || season.artwork?.poster;
  if (Array.isArray(raw)) {
    return bestAsset(raw.map(normalizeAsset).filter(Boolean), "poster", "ru");
  }
  return normalizeAsset(raw);
}

function episodeAsset(document, seasonNumber, episodeNumber) {
  const season = (document.seasons || []).find((item) => Number(item.number) === seasonNumber);
  if (!season) return null;
  const episode = (season.episodes || []).find((item) => {
    const number = item.number ?? item.episode ?? item.episode_number;
    return Number(number) === episodeNumber;
  });
  if (!episode) return null;
  const raw = episode.thumbnail || episode.still || episode.image;
  if (Array.isArray(raw)) {
    return bestAsset(raw.map(normalizeAsset).filter(Boolean), "thumbnail", null);
  }
  return normalizeAsset(raw);
}

function normalizeAsset(asset) {
  if (!asset) return null;
  if (typeof asset === "string") {
    const url = asset.startsWith("/") ? IMAGE_BASE + asset : asset;
    const safe = safeHttpURL(url);
    if (!safe) return null;
    const source = inferSource(safe);
    return { source, url: safe, lang: source === "kinopub" ? "en" : null, width: null };
  }
  const rawURL = asset.url || (asset.file_path ? IMAGE_BASE + asset.file_path : null);
  const safe = rawURL && safeHttpURL(rawURL);
  if (!safe) return null;
  const source = asset.source || inferSource(safe);
  let lang = asset.lang ?? null;
  // Untagged kino.pub posters are the English ones. A real textless file is
  // never served from staticpop on this route.
  if (lang == null && source === "kinopub") lang = "en";
  return { source, url: safe, lang, width: asset.width ?? null };
}

function bestAsset(assets, kind, lang) {
  let best = null;
  let bestKey = null;
  for (const asset of assets) {
    if (!asset?.url) continue;
    if ((kind === "logo" || kind === "backdrop") && asset.source === "kinopub") continue;
    if ((kind === "logo" || kind === "backdrop") && isKinopubPoster(asset.url)) continue;
    // Backdrop is textless or it is a miss. A titled frame is not a fallback.
    if (kind === "backdrop" && (asset.lang ?? null) !== null) continue;
    const key = [
      langRank(asset.lang ?? null, lang),
      sourceRank(kind, asset.source),
      -(asset.width || 0),
    ];
    if (!best || compareKey(key, bestKey) < 0) {
      best = asset;
      bestKey = key;
    }
  }
  return best;
}

function langRank(assetLang, wanted) {
  const order = [];
  for (const item of [wanted, "ru", "en", null]) {
    if (!order.includes(item)) order.push(item);
  }
  const idx = order.indexOf(assetLang);
  return idx === -1 ? order.length : idx;
}

function sourceRank(kind, source) {
  const order = SOURCE_ORDER[kind] || [];
  const idx = order.indexOf(source);
  return idx === -1 ? 50 : idx;
}

function compareKey(a, b) {
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1;
  }
  return 0;
}

function resizeAsset(asset, kind, w) {
  // Only tvoe's own files survive tvoeCdn. A TMDB or staticpop URL sent
  // through _next/image comes back 400 "url parameter is not allowed".
  const cdn = tvoeCdn(asset.url);
  if (cdn) {
    const bucket = snapCeil(TVOE_WIDTHS, w);
    return `https://tvoe.live/_next/image?url=${encodeURIComponent(cdn)}&w=${bucket}&q=80`;
  }
  if (asset.source === "tmdb" || asset.url.includes("image.tmdb.org")) {
    return tmdbSized(asset.url, kind, w, asset.width);
  }
  if (asset.source === "kinopoisk" || asset.url.includes("kinopoiskapiunofficial.tech")) {
    return kinopoiskSized(asset.url, w);
  }
  if (asset.source === "kinopub" || isKinopubPoster(asset.url)) {
    return kinopubSized(asset.url, w);
  }
  return safeHttpURL(asset.url);
}

function tvoeCdn(url) {
  let current = url;
  for (let i = 0; i < 3; i++) {
    let parsed;
    try { parsed = new URL(current); } catch { return null; }
    if (parsed.hostname === "static.cdn.tvoe.live") return parsed.toString();
    if (parsed.hostname === "tvoe.live" && parsed.pathname === "/_next/image") {
      const inner = parsed.searchParams.get("url");
      if (!inner) return null;
      current = inner;
      continue;
    }
    return null;
  }
  return null;
}

function tmdbSized(url, kind, w, knownWidth) {
  const match = url.match(/\/t\/p\/[^/]+(\/.+)$/);
  if (!match) return safeHttpURL(url);
  const path = match[1];
  const ladder = TMDB_LADDER[kind] || TMDB_LADDER.poster;
  const target = w == null ? MAX_WIDTH : w;
  const bucket = ladder.find((size) => size >= target);
  if (bucket) return `https://image.tmdb.org/t/p/w${bucket}${path}`;
  const originalOK = knownWidth == null
    ? TMDB_ORIGINAL_IF_WIDTH_UNKNOWN.has(kind)
    : knownWidth <= MAX_WIDTH;
  if (originalOK) return `https://image.tmdb.org/t/p/original${path}`;
  return `https://image.tmdb.org/t/p/w${ladder[ladder.length - 1]}${path}`;
}

function kinopoiskSized(url, w) {
  const match = url.match(/\/posters\/kp(?:_small)?\/(\d+)\.jpg$/);
  if (!match) return safeHttpURL(url);
  const target = w == null ? MAX_WIDTH : w;
  const size = target <= 360 ? "kp_small" : "kp";
  return `${KINOPOISK_POSTER}/${size}/${match[1]}.jpg`;
}

function kinopubSized(url, w) {
  const match = url.match(/\/poster\/item\/[^/]+\/(\d+)\.jpg$/);
  if (!match) return safeHttpURL(url);
  const target = w == null ? MAX_WIDTH : w;
  let size = KINOPUB_POSTER_LADDER[KINOPUB_POSTER_LADDER.length - 1].size;
  for (const bucket of KINOPUB_POSTER_LADDER) {
    if (bucket.w >= target) { size = bucket.size; break; }
  }
  return `${KINOPUB_POSTER}/${size}/${match[1]}.jpg`;
}

function snapCeil(buckets, w) {
  const cap = buckets[buckets.length - 1];
  const target = w == null ? cap : Math.min(w, cap);
  for (const bucket of buckets) if (bucket >= target) return bucket;
  return cap;
}

function inferSource(url) {
  if (url.includes("image.tmdb.org")) return "tmdb";
  if (url.includes("static.cdn.tvoe.live") || url.includes("tvoe.live/_next/image")) return "tvoe";
  if (url.includes("kinopoiskapiunofficial.tech")) return "kinopoisk";
  if (url.includes("staticpop.net")) return "kinopub";
  return "unknown";
}

function isKinopubPoster(url) {
  return url.includes("staticpop.net/poster");
}

function safeHttpURL(url) {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "https:" && parsed.protocol !== "http:") return null;
    return parsed.toString();
  } catch {
    return null;
  }
}

function missHint(request) {
  if (request.kind === "logo") return "no stored logo";
  if (request.kind === "backdrop") return "no textless backdrop";
  if (request.kind === "thumbnail") return "no episode thumbnail";
  if (request.kind === "poster" && request.s != null) return "no season poster";
  return "no poster";
}

function redirect(location) {
  return new Response(null, {
    status: 302,
    headers: {
      Location: location,
      "Cache-Control": "public, max-age=300",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

function imageNotFound(hint) {
  return new Response(JSON.stringify({ error: "not_found", hint }), {
    status: 404,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "public, max-age=30",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

function json(body, status, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "public, max-age=300",
      "Access-Control-Allow-Origin": "*",
      ...extra,
    },
  });
}
