/**
 * /v1/title/by/kinopub/{id}
 * /img/{logo|backdrop|cover|poster|thumbnail}/by/kinopub/{id}?w=&s=&e=
 *
 * The contract the client actually wanted: ask by kino.pub id, get everything,
 * never resolve anything yourself, never make a second call to find out whether
 * something exists.
 *
 * Image route: `w` is a pixel width (omit it for the largest file we will
 * serve, 3840). Language is the `Accept-Language` header, default ru — it is
 * not a query parameter. Backdrop ignores that header completely: it is always
 * a textless wide frame, never a titled banner and never a poster. Cover is the
 * opposite of backdrop: a language-tagged wide TMDB backdrop (`images.backdrops`
 * with `iso_639_1`), never a poster. `s` / `e` pick a season poster or an
 * episode thumbnail. Logos / backdrops / covers never redirect at a kino.pub
 * CDN. A title poster may, as one rung of its chain (TMDB → kino.pub `src=` →
 * Kinopoisk → another language), because the app now asks the worker for
 * every poster instead of kino.pub's CDN. Episode thumbnails may: a staticpop
 * still is resized through wsrv.nl so the client does not pull a raw 1280×720
 * JPEG into a 300–600 px rail slot. Optional `src=` (kino.pub CDN only) seeds
 * a thumb the document never stored.
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
import { findKinopubId, handleCard, json as cardJson, publishCard } from "./card.js";
import { applySeasonLocale, ensureEpisodeStill, loadSeasons } from "./seasons.js";

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
    if (stored.pending === true || missingImdb || missingFacts) {
      ctx.waitUntil(resolveAndStore(env, id, hints, stored));
    }
    return json(stored, 200, { "X-Cache": "hit" });
  }

  // Cold: answer now from the hints, resolve behind the response.
  const draft = draftDocument(id, hints);
  ctx.waitUntil(resolveAndStore(env, id, hints, draft));
  return json(draft, 200, { "X-Cache": "miss" });
}

/**
 * GET /v2/title/by/kinopub/{id}
 * GET /v2/title?imdb=&kinopoisk=&runtime=&year=&name_ru=&name_original=
 *
 * The page's card. A stored D1 row answers as before. Identity hints — the same
 * ones /v1/title already takes, with v2's names for the title — let a cold id
 * match TMDB instead of 404. `/v2/title/by/kinopub/{id}` with no query is unchanged.
 */
export async function handleTitleV2(url, env, ctx) {
  const hints = readHints(url);
  const byId = url.pathname.match(/\/(?:v2\/title|v1\/card)\/by\/kinopub\/(\d+)$/);
  const pathId = byId?.[1]
    || (hints.kinopub && /^\d+$/.test(hints.kinopub) ? hints.kinopub : null);

  if (pathId) {
    const cardURL = new URL(`https://title.invalid/v2/title/by/kinopub/${pathId}`);
    const existing = await handleCard(cardURL, env);
    if (existing.status !== 404) {
      if (ctx && existing.status === 200) {
        ctx.waitUntil(refreshScore(env, pathId, existing.clone()).catch((error) => {
          console.log(JSON.stringify({ score: "failed", id: pathId, message: error?.message || String(error) }));
        }));
      }
      if (ctx && (hints.imdb || hints.kinopoisk)) {
        const stored = await readDocument(env, pathId);
        const missingImdb = hints.imdb && !stored?.ids?.imdb;
        const missingFacts = hints.kinopoisk && !stored?.factsChecked;
        if (stored && (stored.pending === true || missingImdb || missingFacts)) {
          ctx.waitUntil(resolveAndStore(env, pathId, hints, stored));
        }
      }
      return existing;
    }
    if (!canMatch(hints)) return existing;
    const draft = draftDocument(pathId, hints);
    await resolveAndStore(env, pathId, hints, draft);
    const again = await handleCard(cardURL, env);
    if (again.status !== 404) return again;
    const resolved = await readDocument(env, pathId);
    return cardJson(cardFromDocument(pathId, resolved || draft, hints), 200);
  }

  if (url.pathname.replace(/\/$/, "") !== "/v2/title") {
    return cardJson({ error: "bad_request", hint: HINT_V2 }, 400);
  }
  if (!canMatch(hints)) {
    return cardJson({ error: "bad_request", hint: HINT_V2 }, 400);
  }
  const found = await findKinopubId(env, hints);
  if (found) {
    return handleCard(new URL(`https://title.invalid/v2/title/by/kinopub/${found}`), env);
  }
  return cardJson({ error: "not_found", hint: "no card" }, 404);
}

/**
 * The stored TMDB score is written when a title is built and nothing read it again,
 * so a title built before its first vote never got one. Opening the card now asks
 * TMDB behind the response (`tmdb()` answers from the edge for six hours) and
 * writes D1 only when the score moved. KV is left alone: it has a daily write cap.
 */
async function refreshScore(env, id, response) {
  if (!env.CATALOG || !env.TMDB_READ_TOKEN) return;
  const card = await response.json();
  const tmdbId = card?.ids?.tmdb;
  if (!/^(tv|movie)\/\d+$/.test(tmdbId || "")) return;
  const details = await tmdb(env, `/3/${tmdbId}`, { language: "ru-RU" });
  if (!details?.vote_count) return;
  const held = card.ratings?.tmdb;
  if (held?.value === details.vote_average && held?.votes === details.vote_count) return;
  await env.CATALOG.prepare(
    "UPDATE c2_card SET tmdb = ?, tmdb_votes = ? WHERE kinopub_id = ? AND tmdb_id = ?",
  ).bind(details.vote_average, details.vote_count, Number(id), tmdbId).run();
}

const HINT_V2 = "/v2/title/by/kinopub/{id} · /v2/title?imdb=&kinopoisk=&runtime=&year=&name_ru=&name_original=";

function canMatch(hints) {
  return Boolean(hints.imdb || hints.kinopoisk || hints.title || hints.original);
}

/** Sparse v2 body from a KV document (or the cold draft) when D1 has no row yet. */
function cardFromDocument(id, document, hints) {
  const ids = document?.ids || {};
  const val = (namespace) => idValue(ids, namespace);
  const kind = document?.kind;
  return {
    kinopub_id: Number(id),
    type: kind === "show" ? "serial" : (kind === "movie" ? "movie" : hints.type || null),
    title: {
      ru: document?.title?.ru ?? hints.title ?? null,
      original: document?.title?.original ?? hints.original ?? null,
    },
    year: document?.year ?? (hints.year ? Number(hints.year) : null),
    status: document?.status ?? null,
    tagline_ru: null,
    synopsis_ru: (document?.synopsis || []).find((item) => item.variant === "full" && item.lang === "ru")?.text ?? null,
    ids: {
      imdb: val("imdb"), tmdb: val("tmdb"), tvdb: val("tvdb"),
      kinopoisk: val("kinopoisk"), kinopoisk_hd: null,
      tvoe: val("tvoe"), wikidata: val("wikidata"), myshows: val("myshows"),
    },
    ratings: {
      imdb: null, kinopoisk: null,
      tmdb: (document?.ratings || []).find((item) => item.source === "tmdb")
        ? { value: document.ratings.find((item) => item.source === "tmdb").value,
            votes: document.ratings.find((item) => item.source === "tmdb").votes ?? null }
        : null,
      tvoe: null,
    },
    billing: {},
    counts: {},
    images: [],
    top_episodes: [],
    networks: [],
    seasons: [],
  };
}

const QUERY_KINDS = new Set(["logo", "backdrop", "cover", "poster", "thumbnail"]);
const QUERY_HINT = "/img/{logo|backdrop|cover|poster|thumbnail}/by/kinopub/{id}?w=&s=&e=";

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
//
// The CDN serves the same width tokens for logo / poster / backdrop / still
// paths (measured 2026-11-14: w45…w1920 and face crops all 200). One ladder.
const TMDB_WIDTHS = [45, 92, 154, 185, 227, 300, 320, 342, 454, 500, 780, 1280, 1920];
const TMDB_LADDER = {
  logo: TMDB_WIDTHS,
  poster: TMDB_WIDTHS,
  backdrop: TMDB_WIDTHS,
  // Cover reuses the backdrop ladder — same wide TMDB plate, language kept.
  cover: TMDB_WIDTHS,
  thumbnail: TMDB_WIDTHS,
};
const TMDB_ORIGINAL_IF_WIDTH_UNKNOWN = new Set(["logo", "poster", "thumbnail"]);
// Width → CDN size token. Missing entries use `w{n}`. Face crops keep episode
// stills 16:9; logos/posters/backdrops stay on plain `w{n}` (also 200 on CDN).
const TMDB_SIZE_TOKEN = {
  thumbnail: {
    227: "w227_and_h127_bestv2",
    320: "w320_and_h180_face",
    454: "w454_and_h254_face",
    1920: "w1920_and_h1080_face",
  },
};
// kinopoiskapiunofficial.tech, measured: kp 667×1000, kp_small 360×540.
const KINOPOISK_POSTER = "https://kinopoiskapiunofficial.tech/images/posters";

// Same language first, then source. tvoe wins ru logos and textless backdrops.
// Russian posters prefer TMDB over Kinopoisk (Sasha, 2026-11-24): KP often
// lacks a Russian plate for non-Russian titles while TMDB has one. Kinopoisk
// stays as a fallback when we have (or just resolved) that id. Cover is the
// lang-aware TMDB backdrop only. kino.pub's own CDN is never a candidate.
const SOURCE_ORDER = {
  logo: ["tvoe", "tmdb"],
  backdrop: ["tvoe", "tmdb"],
  cover: ["tmdb"],
  // kinopub sits between TMDB and Kinopoisk (Sasha, 2026-11-26) but only
  // ever arrives as the client's `src=`; see posterChain.
  // Sasha 2026-11-26: TMDB, tvoe, Kinopoisk, kino.pub. tvoe sits behind TMDB
  // because its posters often carry an «Эксклюзивно на TVOE» badge.
  poster: ["tmdb", "tvoe", "kinopoisk", "kinopub"],
  // kinopub last: real stills beat a catalogue thumb, but a catalogue thumb
  // beats a 404 that forces the client to download a giant staticpop JPEG.
  thumbnail: ["tvoe", "tmdb", "kinopub"],
};

export async function handleImage(request, env, ctx) {
  const url = new URL(request.url);
  const stamped = parseStampedPath(url.pathname);
  if (stamped) return proxyStamped(request, url, env, ctx, stamped);
  const route = parseImagePath(url.pathname);
  if (!route) return imageNotFound(QUERY_HINT);
  return handleImageQuery(request, url, env, ctx, route);
}

// /img/{kind}/by/kinopub/{id}?w=&s=&e=
// Language is Accept-Language, not a query param. Backdrop does not read it.
async function handleImageQuery(request, url, env, ctx, route) {
  const id = numericId(route.id);
  if (!id) return json({ error: "bad_request", hint: QUERY_HINT }, 400);
  if (!QUERY_KINDS.has(route.kind)) {
    return imageNotFound("kind must be logo, backdrop, cover, poster, or thumbnail");
  }

  const imageRequest = {
    kind: route.kind,
    id,
    w: readWidth(url),
    // Backdrop is a wide textless frame. The header cannot turn it into a
    // titled banner, a wide poster, or a portrait. Cover keeps the language:
    // it is the titled / lang-tagged TMDB backdrop.
    // `?lang=` wins over the header: Top Shelf and other system loaders fetch
    // the URL without our Accept-Language.
    lang: route.kind === "backdrop" ? null : (readLangQuery(url) || preferredLang(request)),
    s: readIndex(url, "s"),
    e: readIndex(url, "e"),
    format: readFormatQuery(url),
    // Title poster / cover only: kino.pub's own file, the last rung of the chain.
    src: readIndex(url, "s") == null ? chainSource(url, route.kind, id) : null,
  };
  if (imageRequest.kind === "thumbnail" && (imageRequest.s == null || imageRequest.e == null)) {
    return json({ error: "bad_request", hint: "thumbnail needs ?s=&e=" }, 400);
  }

  const hints = readHints(url);
  const started = Date.now();
  let stored = await readDocument(env, id);
  let asset = selectQueryAsset(stored, imageRequest, hints);
  const canResolveTMDB = hints.imdb && (!stored || stored.pending === true);
  const vary = imageRequest.kind === "poster"
    || imageRequest.kind === "logo"
    || imageRequest.kind === "cover";

  // A finished document with no file is a real miss. Anything still cold
  // waits, up to five seconds, and only then 404s. A locale with no logo is
  // asked again on a later request for that same locale, once six hours have
  // passed, skipping the response cache. Posters and covers missing in the
  // asked language are asked again after a day, and every document after a
  // week (Sasha 2026-11-26: a miss used to stick for the document's 30 days).
  // When a fallback is already on hand it is served and the refresh runs
  // behind the response.
  const fresh = imageRequest.s == null && artworkRecheckDue(stored, imageRequest.kind, imageRequest.lang);
  if (asset && fresh) refreshInBackground(env, ctx, id, hints, stored);
  let waitedMs = 0;
  const coldArtworkWithIMDb = imageRequest.s == null && !!imageRequest.src
    && canResolveTMDB && (!asset || asset.source === "kinopoisk");
  if (coldArtworkWithIMDb || (!asset && (!stored || stored.pending === true || fresh))) {
    const waited = await resolveWithin(env, ctx, id, hints, stored, { fresh });
    waitedMs = Date.now() - started;
    const posterFallback = waited.timedOut && imageRequest.src;
    if (waited.timedOut && !posterFallback) {
      noteImage(env, ctx, "timeout", imageRequest, waitedMs);
      return imageNotFound("timed out", vary, { timeout: true });
    }
    stored = waited.stored;
    asset = selectQueryAsset(stored, imageRequest, hints);
    if (asset) noteImage(env, ctx, "waited", imageRequest, waitedMs);
  }

  // Russian poster miss with no Kinopoisk id on the document: resolve that id
  // in this request (Wikidata via IMDb) so the KP poster URL can still answer
  // when TMDB has no ru file either.
  if (!asset && imageRequest.kind === "poster" && imageRequest.lang === "ru" && stored) {
    const withKp = await ensureKinopoiskId(env, stored, hints);
    if (withKp && withKp !== stored) {
      await writeDocument(env, id, withKp);
      stored = withKp;
      asset = selectQueryAsset(stored, imageRequest, hints);
    }
  }

  // The title payload lists seasons with no episodes. The still is a separate
  // /tv/{id}/season/{n} read, done when this frame is actually asked for.
  if (!asset && imageRequest.kind === "thumbnail" && stored) {
    const filled = await ensureEpisodeStill(
      env, stored, imageRequest.s, imageRequest.e, imageRequest.lang || "ru",
    );
    if (filled && filled !== stored) {
      await writeDocument(env, id, filled);
      stored = filled;
      asset = selectQueryAsset(stored, imageRequest, hints);
    }
  }

  // The current CDN still is a fallback behind tvoe/TMDB. Keep it on the stamped
  // request too, so it works if this document could not be written to KV.
  if (imageRequest.kind === "thumbnail" && (!asset || isKinopubHost(asset.url))) {
    const src = readKinopubSrc(url, "thumbnail");
    if (src) {
      if (!asset) {
        const base = stored || draftDocument(id, hints);
        const seeded = seedEpisodeThumb(base, imageRequest.s, imageRequest.e, src);
        if (seeded !== stored) {
          await writeDocument(env, id, seeded);
          stored = seeded;
        }
      }
      asset = { source: "kinopub", url: src, lang: null, width: null, height: null };
    }
  }

  // Title poster, nothing in the asked language from TMDB / tvoe / Kinopoisk:
  // kino.pub's own file (client `src=`), then a poster in another language.
  // The stamped proxy walks the same chain, so a dead kino.pub CDN still ends
  // on a picture.
  if (imageRequest.kind === "poster" && imageRequest.s == null) {
    asset = posterChain(stored, hints, imageRequest.lang || "ru", imageRequest.src)[0] || null;
  }
  // Wide title card (`src=` = kino.pub's wide): cover in the language → textless
  // backdrop → kino.pub's wide. Without `src` a cover stays strict.
  // Covers stored by the offline card pipeline (D1 c2_image: Kinopoisk / tvoe
  // covers) fill a language TMDB has nothing in.
  if (!asset && imageRequest.kind === "cover") {
    const view = await withCatalogCovers(env, id, stored, imageRequest.lang || "ru");
    asset = selectQueryAsset(view, imageRequest, hints);
    if (!asset && imageRequest.src) {
      asset = coverChain(view, imageRequest.lang || "ru", imageRequest.src)[0] || null;
    }
  }

  if (!asset) {
    noteImage(env, ctx, "missing", imageRequest, Date.now() - started);
    // Logo and thumbnail misses must not sit on the edge: a still added on
    // TMDB (or a newly-released episode) would stay invisible until the TTL.
    const stickyMiss = imageRequest.kind !== "logo" && imageRequest.kind !== "thumbnail";
    return imageNotFound(missHint(imageRequest), vary, { store: stickyMiss });
  }
  const location = stampedURL(url, { ...imageRequest, kinopoisk: numericId(hints.kinopoisk || "") },
    asset, stored?.art_rev);
  if (!location) return imageNotFound(missHint(imageRequest), vary);
  return redirect(location, vary, langTag(asset.lang));
}

// ------------------------------------------------------------------ helpers

function readHints(url) {
  const get = (name) => {
    const value = url.searchParams.get(name);
    return value && value.trim() ? value.trim() : undefined;
  };
  return {
    imdb: get("imdb"),
    kinopoisk: get("kinopoisk"),
    title: get("name_ru") || get("title"),
    original: get("name_original") || get("original"),
    year: get("year"),
    type: get("type"),
    runtime: get("runtime"),
    kinopub: get("kinopub"),
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
    // Empty on purpose. kino.pub artwork stays in the app: its CDN host
    // depends on the viewer, and echoing it makes the card fade from a
    // picture the app already painted to the same picture again.
    artwork: { poster: [], backdrop: [], cover: [], logo: [] },
    ratings: [], synopsis: [], genres: [], genre_sources: [], countries: [], credits: [],
    seasons: [], trailers: [], awards: [], badges: [], copies: [],
    facts: [], reviews: [],
    // Honest about its own state: absent because nobody has asked yet, not
    // absent as a fact. The client hides sections on empty either way, but a
    // log tells the truth about which it was.
    pending: true,
  };
}

export async function readDocument(env, id) {
  if (!env.DOCUMENTS) return null;         // KV not bound yet — degrade, do not fail
  return await env.DOCUMENTS.get(`title:kinopub:${id}`, { type: "json" });
}

export async function writeDocument(env, id, document) {
  let stored = false;
  if (env.DOCUMENTS) {
    try {
      await env.DOCUMENTS.put(`title:kinopub:${id}`, JSON.stringify(document),
                              { expirationTtl: DOC_TTL });
      stored = true;
    } catch (error) {
      // The daily KV write cap is a real wall. The picture for this request
      // can still be served from the document we already built.
      console.log(JSON.stringify({
        kv: "put_failed",
        id,
        message: error?.message || String(error),
      }));
    }
  }
  if (env.CATALOG && document?.built_at) {
    try {
      await publishCard(env, id, document);
    } catch (error) {
      console.log(JSON.stringify({
        d1: "put_failed",
        id,
        message: error?.message || String(error),
      }));
    }
  }
  return stored;
}

/**
 * Resolve from hints and store. Runs after the response has gone out, so its
 * latency is nobody's problem — which is exactly why the client never has to
 * choose between "fast" and "complete".
 */
export function idValue(ids, namespace) {
  const slot = ids?.[namespace];
  if (!slot) return null;
  const value = typeof slot === "string" ? slot : slot.value;
  if (value == null || value === "") return null;
  return String(value);
}

/** A hand-stitched `movie/123` or `tv/123`. Find-by-IMDb must not replace it. */
export function manualTmdbTarget(document) {
  const slot = document?.ids?.tmdb;
  if (!slot || slot.method !== "manual") return null;
  const match = /^(movie|tv)\/(\d+)$/.exec(String(slot.value || ""));
  if (!match) return null;
  return { type: match[1], id: match[2] };
}

const LINK_FIELDS = {
  imdb: /^tt\d+$/,
  kinopoisk: /^\d+$/,
  myshows: /^\d+$/,
};

/**
 * Pin external ids onto a kino.pub document. A missing document becomes a
 * pending stub, so the next open downloads from these ids. An existing
 * document keeps its artwork and pending flag; refresh is what rebuilds it.
 */
export function stitchDocument(stored, id, body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { error: "JSON object with imdb, kinopoisk, tmdb, or myshows" };
  }
  const linked = {};
  const ids = { ...(stored?.ids || {}) };
  if (!ids.kinopub) {
    ids.kinopub = { value: String(id), confidence: 1, method: "manual" };
  }
  for (const [namespace, pattern] of Object.entries(LINK_FIELDS)) {
    if (body[namespace] == null || body[namespace] === "") continue;
    const value = String(body[namespace]).trim();
    if (!pattern.test(value)) return { error: `${namespace} is not a valid id` };
    ids[namespace] = { value, confidence: 1, method: "manual" };
    linked[namespace] = value;
  }
  let tmdb = null;
  if (body.tmdb != null && body.tmdb !== "") {
    tmdb = normalizeTmdb(body.tmdb, body.kind || stored?.kind);
    if (!tmdb) {
      return { error: "tmdb needs tv/123, movie/123, or a number with kind show or movie" };
    }
    ids.tmdb = { value: tmdb, confidence: 1, method: "manual" };
    linked.tmdb = tmdb;
  }
  if (!Object.keys(linked).length) return { error: "pass imdb, kinopoisk, tmdb, or myshows" };
  const kind = stored?.kind || kindFromLink(body.kind, tmdb);
  if (stored) return { document: { ...stored, ids, kind: stored.kind || kind }, linked };
  const draft = draftDocument(id, { type: kind || undefined });
  return { document: { ...draft, ids, kind, pending: true }, linked };
}

function normalizeTmdb(raw, kind) {
  const text = String(raw).trim();
  if (/^(movie|tv)\/\d+$/.test(text)) return text;
  if (!/^\d+$/.test(text)) return null;
  if (kind === "show" || kind === "series") return `tv/${text}`;
  if (kind === "movie") return `movie/${text}`;
  return null;
}

function kindFromLink(kind, tmdb) {
  if (kind === "show" || kind === "series") return "show";
  if (kind === "movie") return "movie";
  if (String(tmdb || "").startsWith("tv/")) return "show";
  if (String(tmdb || "").startsWith("movie/")) return "movie";
  return null;
}

function preferredId(ids, namespace, hint) {
  if (ids?.[namespace]?.method === "manual") return idValue(ids, namespace);
  return hint || idValue(ids, namespace);
}

export async function resolveAndStore(env, id, hints, base, options = {}) {
  let document = base;
  const kinopoisk = preferredId(base.ids, "kinopoisk", hints.kinopoisk);
  const imdb = preferredId(base.ids, "imdb", hints.imdb);
  const pinned = manualTmdbTarget(base);

  // No key, no quota risk — safe to run on every cold resolve that has a
  // Kinopoisk hint. Gated on `factsChecked`, not on `ids.kinopoisk`: the draft
  // already carries the hinted id (see draftDocument), so gating on its
  // presence would mean this branch never runs — the actual first bug found
  // testing this live: a title with two real facts came back with zero.
  if (kinopoisk && !base.factsChecked) {
    try {
      const facts = await kinopoiskProxyFacts(kinopoisk);
      const previous = document.ids?.kinopoisk;
      const kinopoiskSlot = previous?.method === "manual"
        ? previous
        : { value: String(kinopoisk), confidence: 1, method: previous?.method || "client" };
      document = {
        ...document,
        factsChecked: true,
        ids: { ...document.ids, kinopoisk: kinopoiskSlot },
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

  const canSearch = Boolean(imdb || pinned || hints?.original || hints?.title);
  if (!canSearch || !env.TMDB_READ_TOKEN) {
    if (document !== base) await writeDocument(env, id, document);
    return document !== base ? document : undefined;
  }

  try {
    const located = await locateTmdb(env, document, hints, { imdb, pinned }, options);
    const mediaType = located?.type || null;
    const tmdbId = located?.id || null;
    if (!mediaType || !tmdbId) {
      if (document !== base) await writeDocument(env, id, document);
      return document !== base ? document : undefined;
    }

    const append = mediaType === "tv"
      ? "aggregate_credits,images,videos,external_ids,content_ratings,keywords,watch/providers"
      : "credits,images,videos,external_ids,keywords,release_dates,watch/providers";
    const details = await tmdb(env, `/3/${mediaType}/${tmdbId}`, {
      language: "ru-RU", append_to_response: append,
      include_image_language: "ru,en,null",
    }, options);
    if (!details) {
      if (document !== base) await writeDocument(env, id, document);
      return document !== base ? document : undefined;
    }

    const merged = await enrichResolved(
      env, mergeTMDB(document, mediaType, tmdbId, details, located.method), mediaType, tmdbId, options,
    );
    await writeDocument(env, id, merged);
    return merged;
  } catch (error) {
    console.log(JSON.stringify({
      resolve: "failed",
      id,
      message: error?.message || String(error),
    }));
    if (document !== base) await writeDocument(env, id, document);
    return document !== base ? document : null;
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

async function locateTmdb(env, document, hints, { imdb, pinned }, options) {
  if (pinned) return { type: pinned.type, id: pinned.id, method: "manual" };
  if (imdb) {
    const found = await tmdb(env, `/3/find/${imdb}`, { external_source: "imdb_id" }, options);
    const preferTv = document.kind === "show" || hints.type === "show"
      || hints.type === "serial" || hints.type === "series";
    const order = preferTv ? ["tv", "movie"] : ["movie", "tv"];
    for (const type of order) {
      const results = found?.[`${type}_results`];
      if (results?.length) return { type, id: String(results[0].id), method: "find:imdb" };
    }
  }
  return searchTmdb(env, hints, document.kind, options);
}

async function searchTmdb(env, hints, kind, options) {
  const query = hints.original || hints.title;
  if (!query) return null;
  const preferTv = kind === "show" || hints.type === "show"
    || hints.type === "serial" || hints.type === "series";
  const year = hints.year ? Number(hints.year) : null;
  const runtime = hints.runtime ? Number(hints.runtime) : null;
  const order = preferTv ? ["tv", "movie"] : ["movie", "tv"];
  for (const type of order) {
    const params = { query, language: "ru-RU" };
    if (Number.isFinite(year)) {
      if (type === "movie") params.year = String(year);
      else params.first_air_date_year = String(year);
    }
    const found = await tmdb(env, `/3/search/${type}`, params, options);
    const results = found?.results || [];
    if (!results.length) continue;
    let pick = pickSearchResult(results, hints, year);
    if (type === "movie" && Number.isFinite(runtime) && runtime > 0 && results.length > 1) {
      pick = (await pickByRuntime(env, results, runtime, options)) || pick;
    }
    if (pick?.id != null) return { type, id: String(pick.id), method: "search:name" };
  }
  return null;
}

function pickSearchResult(results, hints, year) {
  const names = [hints.original, hints.title]
    .filter(Boolean)
    .map((name) => name.toLowerCase());
  const exact = results.find((item) => {
    const title = (item.title || item.name || "").toLowerCase();
    const original = (item.original_title || item.original_name || "").toLowerCase();
    return names.includes(title) || names.includes(original);
  });
  if (exact) return exact;
  if (Number.isFinite(year)) {
    const inYear = results.find((item) => {
      const date = item.release_date || item.first_air_date || "";
      return date.startsWith(String(year));
    });
    if (inYear) return inYear;
  }
  return results[0];
}

async function pickByRuntime(env, results, runtime, options) {
  let best = null;
  let bestDelta = Infinity;
  for (const item of results.slice(0, 5)) {
    const details = await tmdb(env, `/3/movie/${item.id}`, { language: "ru-RU" }, options);
    const minutes = details?.runtime;
    if (!Number.isFinite(minutes) || minutes <= 0) continue;
    const delta = Math.abs(minutes - runtime);
    if (delta < bestDelta) {
      bestDelta = delta;
      best = item;
    }
  }
  return best && bestDelta <= 12 ? best : null;
}

/**
 * `include_image_language` for a read that must see TMDB's images as they are now.
 *
 * TMDB's own gateway (x-gateway-cache-status) caches each URL for hours and ignores
 * parameters it does not know, so `?_=now` still gets the old answer: a title whose
 * logos were uploaded after the first read kept answering "no logos" (Майор Мырза,
 * 2026-11-23 — bare /images empty, a new language list three backdrops and a logo).
 * A private-use ISO 639-2 code (qaa–qtz, which no image carries) at the end of the
 * list makes a new cache key per minute and changes nothing in the answer.
 */
export function freshImageLanguages(base = "ru,en,null", now = Date.now()) {
  const minute = Math.floor(now / 60000);
  const letters = "abcdefghijklmnopqrst";
  const second = letters[Math.floor(minute / 26) % letters.length];
  const third = String.fromCharCode(97 + (minute % 26));
  return `${base},q${second}${third}`;
}

async function tmdb(env, path, params, options = {}) {
  const url = new URL(path, "https://api.themoviedb.org");
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
  if (options.fresh && params.include_image_language) {
    url.searchParams.set("include_image_language", freshImageLanguages(params.include_image_language));
  }
  const requestURL = url.toString();
  // A fresh read must not reuse the six-hour entry from the last resolve.
  const cf = options.fresh
    ? { cacheTtl: 0, cacheEverything: false, cacheKey: `${requestURL} fresh` }
    : { cacheTtl: 21600, cacheEverything: true };
  const response = await fetch(requestURL, {
    headers: { Accept: "application/json", Authorization: `Bearer ${env.TMDB_READ_TOKEN}` },
    cf,
  });
  return response.ok ? await response.json() : null;
}

const IMAGE_BASE = "https://image.tmdb.org/t/p/original";

function mergeTMDB(base, mediaType, tmdbId, details, method = "find:imdb") {
  const document = {
    ...base,
    pending: false,
    built_at: new Date().toISOString(),
    logo_checked_at: new Date().toISOString(),
    // Drives how often the artwork is reread (artworkRecheckDue). A show's
    // latest air date counts as a release: a new season is news too.
    released_at: details.last_air_date || details.release_date || details.first_air_date
      || base.released_at || null,
  };
  const tmdbValue = `${mediaType}/${tmdbId}`;
  const previousTmdb = base.ids?.tmdb;
  const tmdbSlot = previousTmdb?.method === "manual" && String(previousTmdb.value) === tmdbValue
    ? previousTmdb
    : { value: tmdbValue, confidence: 1, method };
  document.ids = { ...document.ids, tmdb: tmdbSlot };
  const external = details.external_ids || {};
  for (const [namespace, key] of [["wikidata", "wikidata_id"], ["tvdb", "tvdb_id"]]) {
    if (external[key] && document.ids[namespace]?.method !== "manual") {
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
  const previousArt = document.artwork || {};
  document.artwork = {
    poster: artworkFromTmdb(previousArt, "poster", images.posters),
    backdrop: artworkFromTmdb(previousArt, "backdrop", images.backdrops),
    logo: artworkFromTmdb(previousArt, "logo", images.logos),
  };

  // Replaced, not kept: after a relink the old id's score must not stay.
  document.ratings = (document.ratings || []).filter((item) => item?.source !== "tmdb");
  if (details.vote_count) {
    document.ratings.push({ source: "tmdb", value: details.vote_average,
                            votes: details.vote_count, scale: 10 });
  }
  document.status = details.status || null;
  document.networks = (details.networks || []).map((network) => ({
    id: network.id,
    name: network.name || null,
    logo: network.logo_path ? IMAGE_BASE + network.logo_path : null,
    origin_country: network.origin_country || null,
  })).filter((network) => network.id != null);
  const synopsis = [];
  if (details.overview) {
    synopsis.push({ source: "tmdb", lang: "ru", variant: "full", text: details.overview });
  }
  if (details.tagline) {
    synopsis.push({ source: "tmdb", lang: "ru", variant: "tagline", text: details.tagline });
  }
  if (synopsis.length) document.synopsis = synopsis;
  // Ours, primary first (genres.json); the raw names ride along, as in the record.
  document.genres = tmdbGenres(details.genres);
  document.genre_sources = (details.genres || []).map((g) => ({ source: "tmdb", name: g.name }));

  // `name` is localized by the request's `language` (ru-RU below), so it is
  // the Russian spelling, not English — mislabeling it name_en would split
  // this person from the identical Russian name a Kinopoisk fetch might
  // supply later, same bug fixed in fetch_tmdb.py's _credit_names(). Prefer
  // `original_name` for the English slot when it actually differs.
  document.credits = mapCredits(details);

  document.trailers = (details.videos?.results || [])
    .filter((video) => video.key)
    .map((video) => ({
      source: "tmdb", source_key: video.key, kind: (video.type || "trailer").toLowerCase(),
      name: video.name, lang: video.iso_639_1, official: video.official ? 1 : 0,
      published_at: video.published_at || null,
      // TMDB's video object has no duration. Keep the field when a payload grows one.
      duration_sec: Number.isFinite(video.duration) ? video.duration : null,
      url: video.site === "YouTube" ? `https://www.youtube.com/watch?v=${video.key}` : null,
    }));

  document.seasons = (details.seasons || [])
    .filter((season) => season.season_number != null)
    .map((season) => ({
      id: season.id ?? null,
      number: season.season_number,
      name: season.name ? { ru: season.name } : {},
      synopsis: season.overview ? { ru: season.overview } : {},
      air_date: season.air_date, end_date: null, episode_cnt: season.episode_count,
      poster: season.poster_path ? { ru: IMAGE_BASE + season.poster_path } : {},
      source: "tmdb", episodes: [],
    }));

  return document;
}

const CREW_JOBS = new Set([
  "Director", "Producer", "Executive Producer", "Co-Producer",
  "Creator", "Original Series Creator", "Writer", "Screenplay", "Story",
]);

function mapCredits(details) {
  const bundle = details.aggregate_credits || details.credits || {};
  const seen = new Set();
  const credits = [];
  for (const person of capCast(bundle.cast || [])) {
    const record = mapPerson(person, "actor", rolesOf(person));
    credits.push(record);
    if (record.id != null) seen.add(record.id);
  }
  for (const person of bundle.crew || []) {
    const roles = rolesOf(person).filter((role) => role.job && CREW_JOBS.has(role.job));
    if (!roles.length) continue;
    if (person.id != null && seen.has(person.id)) {
      const existing = credits.find((item) => item.id === person.id);
      if (existing) existing.roles.push(...roles);
      continue;
    }
    const record = mapPerson(person, person.department || "crew", roles);
    credits.push(record);
    if (record.id != null) seen.add(record.id);
  }
  for (const person of details.created_by || []) {
    const role = {
      character: null, job: "Creator", credit_id: person.credit_id || null, episode_count: null,
    };
    if (person.id != null && seen.has(person.id)) {
      const existing = credits.find((item) => item.id === person.id);
      if (existing) existing.roles.push(role);
      continue;
    }
    credits.push(mapPerson(person, "Creator", [role]));
  }
  return credits;
}

function capCast(people) {
  if (people.length <= 120) return people;
  const leads = people.filter((person) => (person.order ?? 999) < 15);
  const popular = [...people].sort((a, b) => (b.popularity || 0) - (a.popularity || 0)).slice(0, 80);
  const seen = new Set();
  const out = [];
  for (const person of [...leads, ...popular]) {
    const key = person.id ?? person.name;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(person);
  }
  return out;
}

function rolesOf(person) {
  if (Array.isArray(person.roles) && person.roles.length) {
    return person.roles.map((role) => ({
      character: role.character || null,
      job: null,
      credit_id: role.credit_id || null,
      episode_count: role.episode_count ?? null,
    }));
  }
  if (Array.isArray(person.jobs) && person.jobs.length) {
    return person.jobs.map((job) => ({
      character: null,
      job: job.job || null,
      credit_id: job.credit_id || null,
      episode_count: job.episode_count ?? null,
    }));
  }
  if (person.character || person.job) {
    return [{
      character: person.character || null,
      job: person.job || null,
      credit_id: person.credit_id || null,
      episode_count: null,
    }];
  }
  return [];
}

function mapPerson(person, department, roles) {
  const nameRu = person.name || null;
  const nameEn = person.original_name && person.original_name !== person.name
    ? person.original_name : null;
  const tmdbPhoto = person.profile_path ? IMAGE_BASE + person.profile_path : null;
  const photos = [pushbrUrl(nameRu), tmdbPhoto].filter(Boolean);
  const first = roles[0] || {};
  return {
    id: person.id ?? null,
    department,
    known_for_department: person.known_for_department || null,
    gender: person.gender ?? null,
    popularity: person.popularity ?? null,
    adult: person.adult ? 1 : 0,
    character: first.character || null,
    ord: person.order ?? null,
    episode_count: person.total_episode_count ?? null,
    sources: ["tmdb"],
    name_en: nameEn,
    name_ru: nameRu,
    photos,
    roles,
  };
}

async function enrichResolved(env, document, mediaType, tmdbId, options) {
  let next = document;
  try {
    const english = await tmdb(env, `/3/${mediaType}/${tmdbId}`, { language: "en-US" }, options);
    if (english) next = applyEnglishCopy(next, english);
  } catch (_) {
    // The Russian document is already complete enough to keep.
  }
  if (mediaType === "tv") {
    try {
      next = await loadSeasons(env, next, "ru");
    } catch (_) {
      // Episode ratings can be filled on the next season request.
    }
  }
  return next;
}

function applyEnglishCopy(document, details) {
  const next = applySeasonLocale(document, "en", details);
  const synopsis = [...(next.synopsis || [])];
  if (details.tagline && !synopsis.some((item) => item.variant === "tagline" && item.lang === "en")) {
    synopsis.push({ source: "tmdb", lang: "en", variant: "tagline", text: details.tagline });
  }
  if (details.overview && !synopsis.some((item) => item.variant === "full" && item.lang === "en")) {
    synopsis.push({ source: "tmdb", lang: "en", variant: "full", text: details.overview });
  }
  return { ...next, synopsis };
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


function pinnedAsset(document, kind) {
  const list = document?.artwork?.[kind];
  if (!Array.isArray(list)) return null;
  for (const item of list) {
    const asset = normalizeAsset(item);
    if (asset?.pinned) return asset;
  }
  return null;
}

/** Admin pin for one language (logo / poster). Backdrop uses a single pin. */
function pinnedAssetForLang(document, kind, lang) {
  const list = document?.artwork?.[kind];
  if (!Array.isArray(list)) return null;
  const want = langTag(lang);
  for (const item of list) {
    const asset = normalizeAsset(item);
    if (asset?.pinned && langTag(asset.lang) === want) return asset;
  }
  return null;
}

function langTag(lang) {
  if (typeof lang === "string" && /^[a-z]{2,3}$/.test(lang)) return lang;
  return "und";
}

function extensionOf(raw) {
  const match = String(raw || "").split("?")[0].match(/\.([a-z0-9]+)$/i);
  return (match?.[1] || "").toLowerCase();
}

function fileExt(raw) {
  const ext = extensionOf(raw);
  if (ext === "jpeg") return "jpg";
  if (ext === "png" || ext === "jpg" || ext === "webp") return ext;
  return "jpg";
}

// PNG before SVG, then most votes. Size only breaks ties: among rasters the
// taller file wins, then the narrower one (a short wide PNG is the black wordmark;
// the taller smaller one is the white).
function logoRank(asset) {
  const ext = extensionOf(asset?.url);
  const raster = ext === "png" || ext === "jpg" || ext === "jpeg" || ext === "webp";
  return [raster ? 0 : 1, -(asset?.vote || 0), -(asset?.votes || 0),
          -(asset?.height || 0), asset?.width || 0];
}

/** TMDB image files as stored assets, most votes first (TMDB's own pick is
 * usually right); size only breaks ties. */
function tmdbAssets(list) {
  return (list || [])
    .filter((a) => a.file_path)
    .sort((a, b) => compareKey(voteRank(a.vote_average, a.vote_count, a.width),
                               voteRank(b.vote_average, b.vote_count, b.width)))
    .map((a) => ({ source: "tmdb", url: IMAGE_BASE + a.file_path, lang: a.iso_639_1 || null,
                   width: a.width, height: a.height,
                   vote: a.vote_average ?? null, votes: a.vote_count ?? null }));
}

/** One kind's stored list rebuilt from a TMDB file list: pins first, then TMDB's
 * files, one per language (capArtwork). Posters and backdrops keep earlier unpinned
 * files (other sources) after TMDB's. */
export function artworkFromTmdb(previousArt, kind, tmdbFiles) {
  const previous = previousArt?.[kind] || [];
  const pinned = previous.filter((item) => item?.pinned === true);
  const unpinned = previous.filter((item) => item?.pinned !== true);
  if (kind === "logo") return capArtwork([...pinned, ...sortLogos(tmdbAssets(tmdbFiles))]);
  return capArtwork([...pinned, ...tmdbAssets(tmdbFiles), ...unpinned]);
}

/** Most votes, then most voters, then the wider file. */
function voteRank(vote, votes, width) {
  return [-(vote || 0), -(votes || 0), -(width || 0)];
}

function sortLogos(assets) {
  return [...assets].sort((a, b) => compareKey(logoRank(a), logoRank(b)));
}

function stampedURL(url, imageRequest, asset, rev) {
  const lang = langTag(asset.lang);
  const ext = imageRequest.kind === "logo" ? "png" : fileExt(asset.url);
  const params = new URLSearchParams();
  if (imageRequest.w != null) params.set("w", String(imageRequest.w));
  if (imageRequest.s != null) params.set("s", String(imageRequest.s));
  if (imageRequest.e != null) params.set("e", String(imageRequest.e));
  // Optional override; stamped proxy defaults to WebP via weserv when omitted.
  if (imageRequest.format) params.set("format", imageRequest.format);
  if (rev) params.set("v", String(rev));
  // Only an explicit src rides along (older clients); one derived from the id
  // is derived again on the stamped side. `wide` keeps the wide-card chain.
  const explicitSrc = readKinopubSrc(url, imageRequest.kind);
  if (explicitSrc && (imageRequest.src || (imageRequest.kind === "thumbnail" && asset.source === "kinopub"))) {
    params.set("src", explicitSrc);
  }
  if (imageRequest.kind === "cover" && url.searchParams.has("wide")) params.set("wide", "1");
  // The Kinopoisk rung needs the id even when the document never stored it.
  if (imageRequest.kinopoisk && (imageRequest.kind === "poster" || imageRequest.kind === "cover")) {
    params.set("kinopoisk", imageRequest.kinopoisk);
  }
  if (imageRequest.s == null && imageRequest.src && imageRequest.lang && imageRequest.lang !== lang) {
    params.set("lang", imageRequest.lang);
  }
  const qs = params.toString();
  return `${url.origin}/img/${imageRequest.kind}/by/kinopub/${imageRequest.id}/${lang}/${imageRequest.kind}.${ext}${qs ? `?${qs}` : ""}`;
}

function parseStampedPath(pathname) {
  const parts = pathname.split("/").filter(Boolean);
  // img / kind / by / kinopub / id / lang / file
  if (parts.length !== 7 || parts[0] !== "img") return null;
  if (parts[2] !== "by" || parts[3] !== "kinopub") return null;
  if (!QUERY_KINDS.has(parts[1])) return null;
  if (parts[5] !== "und" && !/^[a-z]{2,3}$/.test(parts[5])) return null;
  return { kind: parts[1], id: parts[4], lang: parts[5] };
}

async function proxyStamped(request, url, env, ctx, stamp) {
  const id = numericId(stamp.id);
  if (!id) return json({ error: "bad_request", hint: QUERY_HINT }, 400);
  const season = readIndex(url, "s");
  const chainSrc = season == null ? chainSource(url, stamp.kind, id) : null;
  if (season == null && (stamp.kind === "poster" || (stamp.kind === "cover" && chainSrc))) {
    return proxyTitleArtwork(url, env, ctx, stamp, id, chainSrc);
  }

  // Edge-cache the stamped answer so repeat Home/detail hits never re-tax
  // wsrv.nl. Key is the stamped URL (kind/id/lang/file + w/s/e/format).
  const cache = edgeCache();
  const cacheURL = new URL(url);
  // Old thumbnail responses could contain a processing frame already encoded as WebP.
  if (stamp.kind === "thumbnail") cacheURL.searchParams.set("thumb-v", "2");
  const cacheKey = cache ? new Request(cacheURL, { method: "GET" }) : null;
  if (cache && cacheKey) {
    const hit = await cache.match(cacheKey);
    if (hit) return hit;
  }

  let stored = await readDocument(env, id);
  const lang = stamp.lang === "und" ? null : stamp.lang;
  if (stamp.kind === "cover" && lang) stored = await withCatalogCovers(env, id, stored, lang);
  const imageRequest = {
    kind: stamp.kind,
    id,
    w: readWidth(url),
    lang: stamp.kind === "backdrop" ? null : (lang || "ru"),
    s: season,
    e: readIndex(url, "e"),
  };
  const hints = readHints(url);
  const format = readOutputFormat(url, stamp.kind);
  let asset = (stamp.kind === "thumbnail" || imageRequest.s != null)
    ? selectQueryAsset(stored, imageRequest, hints)
    : assetInLang(stored, stamp.kind, lang, hints);
  if (stamp.kind === "thumbnail" && (!asset || isKinopubHost(asset.url))) {
    const source = readKinopubSrc(url, "thumbnail");
    if (source) asset = { source: "kinopub", url: source, lang: null };
  }
  if (asset && langTag(asset.lang) !== stamp.lang) asset = null;
  if (!asset) return imageNotFound(missHint({ ...imageRequest, lang }));

  const thumbOrigins = stamp.kind === "thumbnail" && kinopubArtworkOrigins(asset.url, KINOPUB_THUMB_PATH);
  if (thumbOrigins) {
    const served = await fetchKinopubThumbnail(thumbOrigins, imageRequest.w, format, weservEnabled(env));
    if (!served) return imageNotFound(missHint(imageRequest), false, { store: false });
    const response = imageResponse(served, stamp.kind, format, stamp.lang);
    if (cache && cacheKey && ctx?.waitUntil) ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  }

  const legacy = resizeAsset(asset, stamp.kind, imageRequest.w);
  let fetched = null;
  let via = "legacy";

  // Prefer wsrv.nl for every kind: q=80 + WebP (or `format=`). Logo / backdrop /
  // cover / poster feed the durable original so weserv can hit exact `w=`
  // (incl. 2400). Thumbnails feed the TMDB ladder URL — face crops live in the
  // size token (`w454_and_h254_face`, …); weserv only re-encodes that file, it
  // does not invent the crop. Kill switch: WESERV_DISABLED=1 (or true/yes).
  if (weservEnabled(env)) {
    const source = stamp.kind === "thumbnail"
      ? legacy
      : durableOrigin(asset);
    if (source) {
      const transformed = weservURL(source, imageRequest.w, format);
      fetched = await fetch(transformed);
      if (fetched.ok) {
        via = "weserv";
      } else {
        fetched = null;
      }
    }
  }

  if (!fetched) {
    if (!legacy) return imageNotFound(missHint({ ...imageRequest, lang }));
    fetched = await fetch(legacy);
    via = "legacy";
  }
  if (!fetched.ok) return imageNotFound(missHint(imageRequest));

  const headers = new Headers();
  const type = fetched.headers.get("content-type");
  headers.set(
    "Content-Type",
    type || defaultContentType(stamp.kind, format, via),
  );
  headers.set("Cache-Control", "public, max-age=86400");
  headers.set("Access-Control-Allow-Origin", "*");
  headers.set("Content-Language", stamp.lang);
  headers.set("X-KinoPub-Image-Via", via);
  const response = new Response(fetched.body, { status: 200, headers });
  if (cache && cacheKey && ctx?.waitUntil) {
    ctx.waitUntil(cache.put(cacheKey, response.clone()));
  }
  return response;
}

// Choose a source before looking at the output size. The render cache is keyed
// by that source, so stale cached bytes from a different poster cannot win.
async function proxyTitleArtwork(url, env, ctx, stamp, id, chainSrc) {
  const { kind } = stamp;
  const lang = readLangQuery(url) || (stamp.lang === "und" ? "ru" : stamp.lang);
  const fromStore = await readDocument(env, id);
  const document = kind === "cover" ? await withCatalogCovers(env, id, fromStore, lang) : fromStore;
  const chain = kind === "poster"
    ? posterChain(document, readHints(url), lang, chainSrc)
    : coverChain(document, lang, chainSrc);
  const cache = edgeCache();
  const width = readWidth(url);
  const format = readOutputFormat(url, kind);
  for (const asset of chain) {
    const origin = await titleArtworkOrigin(asset, url.origin, cache, ctx);
    if (!origin) continue;
    const language = langTag(asset.source === "kinopub" ? null : asset.lang);
    const key = artworkCacheKey(url.origin, `render/${kind}/${id}/${language}`, {
      origin, width, format, revision: url.searchParams.get("v"),
    });
    const hit = await cache?.match(key);
    if (hit) return hit;
    const resized = weservEnabled(env) ? await fetchArtwork(weservURL(origin, width, format)) : null;
    const direct = asset.source === "tmdb" ? resizeAsset({ ...asset, url: origin }, kind, width) : origin;
    const rendered = resized ?? await fetchArtwork(direct)
      ?? (direct !== origin ? await fetchArtwork(origin) : null);
    if (!rendered) break;
    const via = resized ? "weserv" : "legacy";
    const response = imageResponse({ response: rendered, via }, kind, format, language);
    response.headers.set("X-KinoPub-Image-Source", asset.source);
    if (ctx?.waitUntil) ctx.waitUntil(rememberServedImage(env, id, kind, asset));
    if (cache && ctx?.waitUntil) {
      if (resized || !weservEnabled(env)) ctx.waitUntil(cache.put(key, response.clone()));
      else response.headers.set("Cache-Control", "public, max-age=300");
    }
    return response;
  }
  return imageNotFound(missHint({ kind, lang }), false, { store: false });
}

// The title poster / cover a request was actually served, kept in D1 c2_image
// next to the admin picks and the offline covers (Sasha 2026-11-28: "убедись что
// лежат в базе"). One row per title, kind, language and source: a newer pick
// from the same source replaces the old one; other sources' rows stay.
// kino.pub's own file is not kept (it is derived from the id), nor a textless
// backdrop served for a wide card (that is a backdrop, not a cover).
const remembered = new Set();

export async function rememberServedImage(env, id, kind, asset) {
  if (!env?.CATALOG || (kind !== "poster" && kind !== "cover")) return false;
  if (!asset?.url || asset.source === "kinopub" || isKinopubHost(asset.url)) return false;
  if (kind === "cover" && (asset.lang ?? null) === null) return false;
  const url = durableOrigin(asset) || asset.url;
  const key = `${id}|${kind}|${url}`;
  if (remembered.has(key)) return false;
  const db = env.CATALOG;
  const kinopubId = Number(id);
  const lang = asset.lang ?? null;
  const source = asset.source || inferSource(url);
  try {
    const known = await db.prepare(
      `SELECT 1 FROM c2_image WHERE kinopub_id = ? AND kind = ? AND url = ? AND ${TITLE_IMAGE_ROW} LIMIT 1`,
    ).bind(kinopubId, kind, url).first();
    if (!known) {
      await db.batch([
        db.prepare(
          `DELETE FROM c2_image WHERE kinopub_id = ? AND kind = ? AND lang IS ? AND source IS ? AND ${TITLE_IMAGE_ROW}`,
        ).bind(kinopubId, kind, lang, source),
        db.prepare(
          "INSERT INTO c2_image (kinopub_id, kind, lang, url, source, width, height) VALUES (?, ?, ?, ?, ?, ?, ?)",
        ).bind(kinopubId, kind, lang, url, source, asset.width ?? null, asset.height ?? null),
      ]);
    }
    if (remembered.size > 5000) remembered.clear();
    remembered.add(key);
    return !known;
  } catch (error) {
    console.warn("c2_image served", id, kind, error?.message || error);
    return false;
  }
}

const TITLE_IMAGE_ROW = "person_id IS NULL AND season IS NULL AND episode IS NULL";

function artworkCacheKey(origin, path, params) {
  const key = new URL(`/img-cache/cover-source-v1/${path}`, origin);
  for (const [name, value] of Object.entries(params)) {
    if (value != null) key.searchParams.set(name, value);
  }
  return new Request(key);
}

async function titleArtworkOrigin(asset, workerOrigin, cache, ctx) {
  const origin = durableOrigin(asset);
  if (!origin) return null;
  const mirrors = (asset.source === "kinopub" && kinopubArtworkOrigins(origin, KINOPUB_POSTER_PATH)) || [origin];
  const key = artworkCacheKey(workerOrigin, "origin", { origin });
  const hit = await cache?.match(key);
  if (hit) return hit.text();
  for (const mirror of mirrors) {
    if (!await fetchArtwork(mirror, { method: "HEAD" })) continue;
    if (cache && ctx?.waitUntil) {
      ctx.waitUntil(cache.put(key, new Response(mirror, { headers: { "Cache-Control": "max-age=3600" } })));
    }
    return mirror;
  }
  return null;
}

async function fetchArtwork(url, options) {
  try {
    const response = await fetch(url, { ...timeoutSignal(CDN_MIRROR_TIMEOUT_MS), ...options });
    const type = response.headers.get("content-type") || "";
    const placeholder = response.url.toLowerCase().includes("/no-poster.");
    if (response.ok && type.startsWith("image/") && !type.startsWith("image/gif") && !placeholder) {
      return response;
    }
    await response.body?.cancel();
  } catch {
    // The source or resizer is temporarily unavailable.
  }
  return null;
}

/** Languages a title picture walks (Sasha 2026-11-28): ru → en, en → ru; no-language last. */
function languageOrder(lang) {
  const order = [lang || "ru"];
  for (const other of ["ru", "en"]) if (!order.includes(other)) order.push(other);
  return order;
}

/**
 * Title poster, language by language (ru → en → none for Russian, en → ru →
 * none for English). Within a language: pin → TMDB → tvoe → Kinopoisk →
 * kino.pub (kino.pub's file belongs to the Russian step). Then a textless
 * TMDB poster, then anything in a third language.
 */
function posterChain(document, hints, lang, kinopubSrc) {
  const chain = [];
  const push = (asset) => {
    if (asset?.url && !chain.some((item) => item.url === asset.url)) chain.push(asset);
  };
  for (const step of languageOrder(lang)) {
    push(pinnedAssetForLang(document, "poster", step));
    const inLang = posterCandidates(document, hints, step);
    const from = (source) => inLang.filter((a) => (source === "tmdb"
      ? a.source !== "kinopoisk" && a.source !== "tvoe" : a.source === source));
    push(bestAsset(from("tmdb"), "poster", step, { strict: true }));
    push(bestAsset(from("tvoe"), "poster", step, { strict: true }));
    push(bestAsset(from("kinopoisk"), "poster", step, { strict: true }));
    if (step === "ru" && kinopubSrc) push({ source: "kinopub", url: kinopubSrc, lang: "ru", width: null, height: null });
  }
  const rest = (document?.artwork?.poster || [])
    .map(normalizeAsset)
    .filter((a) => a && a.source !== "kinopub" && !isKinopubHost(a.url));
  push(bestAsset(rest.filter((a) => a.lang == null), "poster", null));
  push(bestAsset(rest.filter((a) => a.lang != null && !languageOrder(lang).includes(a.lang)), "poster", null));
  return chain;
}

const DAY_MS = 24 * 60 * 60 * 1000;
/** A title is new for two weeks after its release (or its latest air date). */
export const NEW_TITLE_MS = 14 * DAY_MS;
/** Missing language: new title daily, older weekly. Whole document: daily / monthly. */
export const RECHECK_NEW_MS = DAY_MS;
export const RECHECK_MISSING_MS = 7 * DAY_MS;
export const RECHECK_STALE_MS = 30 * DAY_MS;

/**
 * Whether this request should re-read TMDB for the title (Sasha 2026-11-26:
 * a logo, poster or cover missing in the asked language used to stick for
 * the document's 30 days). A new title (released in the last two weeks) is
 * reread a day after the last build. An older one is reread after a week when
 * the asked language has no logo / poster / cover, and after a month anyway.
 */
export function artworkRecheckDue(stored, kind, lang, now = Date.now()) {
  if (!stored || stored.pending === true) return false;
  const built = Date.parse(stored.built_at || "");
  if (!Number.isFinite(built)) return kind === "poster" || kind === "cover" || kind === "logo";
  const age = now - built;
  const released = Date.parse(stored.released_at || "");
  const isNew = Number.isFinite(released) && now - released < NEW_TITLE_MS && now >= released - NEW_TITLE_MS;
  if (age >= (isNew ? RECHECK_NEW_MS : RECHECK_STALE_MS)) return true;
  if (age < RECHECK_MISSING_MS || !lang) return false;
  return missingInLanguage(stored, kind, lang);
}

function missingInLanguage(stored, kind, lang) {
  if (kind === "cover") return coverCandidates(stored, lang).length === 0;
  if (kind === "poster" || kind === "logo") {
    return !(stored.artwork?.[kind] || []).some((item) => {
      const asset = normalizeAsset(item);
      return asset && langTag(asset.lang) === lang && asset.source !== "kinopub" && asset.source !== "kinopoisk";
    });
  }
  return false;
}

// One background refresh per title per isolate per ten minutes: a grid of
// forty posters of one title must not queue forty TMDB reads.
const refreshing = new Map();
const REFRESH_THROTTLE_MS = 10 * 60 * 1000;

function refreshInBackground(env, ctx, id, hints, stored) {
  const now = Date.now();
  const last = refreshing.get(id);
  if (last && now - last < REFRESH_THROTTLE_MS) return;
  refreshing.set(id, now);
  if (refreshing.size > 2000) refreshing.clear();
  ctx?.waitUntil?.(resolveAndStore(env, id, hints, stored, { fresh: true }).catch(() => {}));
}

/**
 * The document with the covers the offline card pipeline stored in D1
 * (`c2_image` kind cover: Kinopoisk / tvoe plates) added, when the document
 * has none in `lang`. Read-only view: never written back to KV.
 */
async function withCatalogCovers(env, id, document, lang) {
  if (!env?.CATALOG) return document;
  if (coverCandidates(document, lang).length) return document;
  try {
    const rows = await env.CATALOG.prepare(
      `SELECT lang, url, width, height FROM c2_image
        WHERE kinopub_id = ? AND kind = 'cover' AND person_id IS NULL AND season IS NULL`,
    ).bind(Number(id)).all();
    const extra = (rows?.results || [])
      .filter((row) => row.url && safeHttpURL(row.url))
      .map((row) => {
        const source = inferSource(row.url);
        return {
          source: source === "unknown" ? "catalog" : source,
          url: row.url, lang: row.lang || null,
          width: row.width || null, height: row.height || null,
        };
      });
    if (!extra.length) return document;
    return {
      ...document,
      artwork: { ...document?.artwork, cover: [...(document?.artwork?.cover || []), ...extra] },
    };
  } catch {
    return document;
  }
}

/**
 * Wide title card chain: cover in the language, then in the other one (ru ↔ en,
 * Sasha 2026-11-28) → textless backdrop → kino.pub's wide. Only with `wide=1`.
 */
function coverChain(document, lang, kinopubSrc) {
  const chain = [];
  const push = (asset) => {
    if (asset?.url && !chain.some((item) => item.url === asset.url)) chain.push(asset);
  };
  if (lang) {
    for (const step of languageOrder(lang)) {
      push(pinnedAssetForLang(document, "cover", step));
      push(bestAsset(coverCandidates(document, step), "cover", step, { strict: true }));
    }
  }
  push(pinnedAsset(document, "backdrop"));
  if (document) push(bestAsset(textlessBackdrops(document), "backdrop", null));
  if (kinopubSrc) push({ source: "kinopub", url: kinopubSrc, lang: lang || null, width: null, height: null });
  return chain;
}

const POSTER_FETCH_TIMEOUT_MS = 6000;
// Five attempts plus the direct thumbnail fallback fit the client's 15 s request budget.
const CDN_MIRROR_TIMEOUT_MS = 2500;

async function fetchKinopubThumbnail(origins, width, format, transform) {
  if (transform) {
    const served = await fetchTransformedKinopubThumbnail(origins, width, format);
    if (served) return served;
  }
  const options = timeoutSignal(CDN_MIRROR_TIMEOUT_MS);
  for (const origin of origins) {
    try {
      const response = await fetch(origin, options);
      if (response.ok && /^image\/jpeg\b/i.test(response.headers.get("content-type") || "")) {
        return { response, via: "legacy" };
      }
      await response.body?.cancel();
    } catch {
      if (options.signal?.aborted) break;
    }
  }
  return null;
}

async function fetchTransformedKinopubThumbnail(origins, width, format) {
  for (const origin of origins) {
    const options = timeoutSignal(CDN_MIRROR_TIMEOUT_MS);
    try {
      // A transformed processing PNG is a valid WebP. Ask weserv about its input
      // format on the same network path used for the transform.
      const probe = await fetch(weservURL(origin, width, "json"), options);
      if (!probe.ok) {
        await probe.body?.cancel();
        continue;
      }
      if ((await probe.json()).format !== "jpeg") continue;
      const response = await fetch(weservURL(origin, width, format), options);
      // The JSON and WebP have separate cache entries. Reject a cached transform
      // when weserv reports that it was made from different source bytes.
      const probedLength = probe.headers.get("x-upstream-response-length");
      const transformedLength = response.headers.get("x-upstream-response-length");
      if (response.ok && response.headers.get("content-type")?.startsWith("image/")
          && (!probedLength || !transformedLength || probedLength === transformedLength)) {
        return { response, via: "weserv" };
      }
      await response.body?.cancel();
    } catch {
      // An unavailable host or malformed probe gives the next mirror a chance.
    }
  }
  return null;
}

function timeoutSignal(ms) {
  try {
    return typeof AbortSignal?.timeout === "function" ? { signal: AbortSignal.timeout(ms) } : {};
  } catch {
    return {};
  }
}

function imageResponse({ response, via }, kind, format, language) {
  const headers = new Headers();
  headers.set("Content-Type", response.headers.get("content-type") || defaultContentType(kind, format, via));
  headers.set("Cache-Control", "public, max-age=86400");
  headers.set("Access-Control-Allow-Origin", "*");
  headers.set("Content-Language", language);
  headers.set("X-KinoPub-Image-Via", via);
  return new Response(response.body, { status: 200, headers });
}

/** `?lang=ru|en` on the query route. Anything else defers to Accept-Language. */
function readLangQuery(url) {
  const raw = (url.searchParams.get("lang") || "").trim().toLowerCase().split("-")[0];
  return raw === "ru" || raw === "en" ? raw : null;
}

/** Cloudflare `caches.default`, or null under node --test. */
function edgeCache() {
  try {
    return typeof caches !== "undefined" ? caches.default : null;
  } catch {
    return null;
  }
}

function weservEnabled(env) {
  const raw = String(env?.WESERV_DISABLED ?? "").trim().toLowerCase();
  return !(raw === "1" || raw === "true" || raw === "yes");
}

/** Durable CDN / original URL — not a ladder token or tvoe `_next/image` URL. */
function durableOrigin(asset) {
  if (!asset?.url) return null;
  const cdn = tvoeCdn(asset.url);
  if (cdn) return cdn;
  if (asset.source === "tmdb" || asset.url.includes("image.tmdb.org")) {
    const match = asset.url.match(/\/t\/p\/[^/]+(\/.+)$/);
    if (!match) return safeHttpURL(asset.url);
    // TMDB serves the same logo as PNG when the path ends in .png (SVG breaks
    // image views). Always ask for the original; weserv applies `w=`.
    const path = match[1].replace(/\.svg$/i, ".png");
    return `https://image.tmdb.org/t/p/original${path}`;
  }
  if (asset.source === "kinopoisk" || asset.url.includes("kinopoiskapiunofficial.tech")) {
    return kinopoiskSized(asset.url, MAX_WIDTH);
  }
  // Episode thumbs only — logos/posters/backdrops never select a kinopub asset.
  if (asset.source === "kinopub" || isKinopubHost(asset.url)) {
    return safeHttpURL(asset.url);
  }
  return safeHttpURL(asset.url);
}

/**
 * Free public transform CDN. Limit is ~2500 *uncached* requests / 10 min /
 * visitor IP (https://wsrv.nl/faq/). Cached hits (theirs + our edge) do not
 * count. We coalesce via `caches.default` on the stamped URL and fall back
 * to `resizeAsset` when weserv fails or is disabled.
 */
function weservURL(source, w, output = "webp") {
  const params = new URLSearchParams();
  params.set("url", source);
  params.set("output", output);
  params.set("q", "80");
  if (w != null && w > 0) {
    params.set("w", String(Math.min(w, MAX_WIDTH)));
  }
  return `https://wsrv.nl/?${params.toString()}`;
}

/** `format=` on the stamped URL, or default WebP. */
function readOutputFormat(url, _kind) {
  return readFormatQuery(url) || "webp";
}

/** Optional `format=webp|jpeg|jpg|png` on the query or stamped URL. */
function readFormatQuery(url) {
  const raw = (url.searchParams.get("format") || "").trim().toLowerCase();
  if (raw === "webp") return "webp";
  if (raw === "jpeg" || raw === "jpg") return "jpg";
  if (raw === "png") return "png";
  return null;
}

function defaultContentType(kind, format, via) {
  if (via === "weserv" || format === "webp") return "image/webp";
  if (format === "png" || kind === "logo") return "image/png";
  return "image/jpeg";
}

function assetInLang(document, kind, lang, hints) {
  const pinned = kind === "logo" || kind === "poster" || kind === "cover"
    ? pinnedAssetForLang(document, kind, lang)
    : pinnedAsset(document, kind);
  if (pinned) return pinned;
  if (kind === "backdrop") return bestAsset(textlessBackdrops(document), "backdrop", null);
  if (kind === "cover") {
    return bestAsset(coverCandidates(document, lang || "ru"), "cover", lang || "ru", { strict: true });
  }
  if (kind === "logo") return bestAsset(logoCandidates(document), "logo", lang, { strict: true });
  if (kind === "poster") return bestAsset(posterCandidates(document, hints, lang || "ru"), "poster", lang, { strict: true });
  return null;
}

const IMAGE_STATS_KEY = "stats:img";

function noteImage(_env, _ctx, reason, imageRequest, ms) {
  // Console only. A KV counter here burned the daily write cap and then
  // threw on every later miss, which hid the picture we had just fetched.
  console.log(JSON.stringify({
    img: reason,
    kind: imageRequest.kind,
    id: imageRequest.id,
    ms,
  }));
}

export async function imageStats(env) {
  if (!env?.DOCUMENTS) return {};
  return (await env.DOCUMENTS.get(IMAGE_STATS_KEY, { type: "json" })) || {};
}

function imageWaitMs(env) {
  const n = Number(env?.IMAGE_WAIT_MS);
  if (Number.isFinite(n) && n >= 0) return n;
  return 5000;
}

async function resolveWithin(env, ctx, id, hints, stored, options = {}) {
  const ms = imageWaitMs(env);
  let timer;
  const job = resolveAndStore(env, id, hints, stored || draftDocument(id, hints), options)
    .then(async (built) => ({
      timedOut: false,
      stored: built || await readDocument(env, id) || stored,
    }))
    .catch(() => ({ timedOut: false, stored }));
  const timeout = new Promise((resolve) => {
    timer = setTimeout(() => resolve({ timedOut: true, stored }), ms);
  });
  const result = await Promise.race([job, timeout]);
  clearTimeout(timer);
  if (result.timedOut) ctx.waitUntil(job);
  return result;
}

// ---------------------------------------------------------------- query route

function parseImagePath(pathname) {
  const parts = pathname.split("/").filter(Boolean);
  // img / kind / by / kinopub / id
  if (parts.length < 5 || parts[0] !== "img") return null;
  if (parts[2] !== "by" || parts[3] !== "kinopub") return null;
  return { kind: parts[1], id: (parts[4] || "").replace(/\.\w+$/, "") };
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

/** First language the caller actually wants. Absent header, `*`, or anything
 * we don't serve yet means Russian. `en-US,en;q=0.9` is English. */
export function preferredLang(request) {
  const header = request.headers?.get("Accept-Language") || "";
  const ranges = [];
  for (const part of header.split(",")) {
    const [tagRaw, ...params] = part.trim().split(";");
    const tag = (tagRaw || "").trim().toLowerCase();
    if (!tag) continue;
    let q = 1;
    for (const param of params) {
      const [key, value] = param.trim().split("=");
      if (key === "q") q = Number(value);
    }
    if (!Number.isFinite(q) || q <= 0) continue;
    ranges.push({ tag, q });
  }
  ranges.sort((a, b) => b.q - a.q);
  for (const { tag } of ranges) {
    const primary = tag.split("-")[0];
    if (primary === "en") return "en";
    if (primary === "ru" || primary === "*") return "ru";
  }
  return "ru";
}

function selectQueryAsset(document, request, hints) {
  const { kind, lang, s, e } = request;
  const pinned = kind === "logo" || kind === "poster" || kind === "cover"
    ? pinnedAssetForLang(document, kind, lang)
    : pinnedAsset(document, kind);
  if (pinned) return pinned;
  if (kind === "thumbnail") {
    if (!document || s == null || e == null) return null;
    return episodeAsset(document, s, e);
  }
  if (kind === "poster" && s != null) {
    if (!document) return null;
    return seasonPosterAsset(document, s, lang || "ru");
  }
  if (kind === "backdrop") {
    if (!document) return null;
    return bestAsset(textlessBackdrops(document), "backdrop", null);
  }
  if (kind === "cover") {
    if (!document) return null;
    // Language-tagged wide plates already stored under artwork.backdrop
    // (TMDB `images.backdrops` with iso_639_1), plus any admin cover pin.
    return bestAsset(coverCandidates(document, lang || "ru"), "cover", lang || "ru", { strict: true });
  }
  const assets = kind === "poster"
    ? posterCandidates(document, hints, lang)
    : logoCandidates(document);
  // Posters stay in the requested language. A missing Russian poster is a
  // fast 404 so the app keeps the kino.pub frame it already has — we do not
  // slide an English one in under a Russian request. Logos do fall through:
  // an English logo is better than letters where a logo was supposed to be.
  return bestAsset(assets, kind, lang, { strict: kind === "poster" });
}

function posterCandidates(document, hints, lang) {
  const stored = (document?.artwork?.poster || [])
    .map(normalizeAsset)
    .filter((asset) => asset && !isKinopubHost(asset.url) && asset.source !== "kinopub");
  const kp = numericId(String(document?.ids?.kinopoisk?.value || hints.kinopoisk || ""));
  // TMDB ru stays in the pool even when we have a Kinopoisk id — SOURCE_ORDER
  // prefers tmdb over kinopoisk. Inject the synthetic KP URL as a fallback
  // candidate when that id is known.
  if (lang === "ru" && kp) {
    const kept = stored.filter((asset) => (asset.lang ?? null) === "ru");
    if (!kept.some((asset) => asset.source === "kinopoisk")) {
      kept.push({
        source: "kinopoisk",
        url: `${KINOPOISK_POSTER}/kp/${kp}.jpg`,
        lang: "ru",
        width: 667,
        height: 1000,
      });
    }
    return kept;
  }
  return stored.filter((asset) => (asset.lang ?? null) === lang);
}

/** Lang-aware wide backdrop from the stored TMDB backdrop list (not textless). */
function coverCandidates(document, lang) {
  const want = lang ?? null;
  const fromBackdrop = (document?.artwork?.backdrop || [])
    .map(normalizeAsset)
    .filter((asset) => asset
      && (asset.lang ?? null) === want
      && asset.source !== "kinopub"
      && !isKinopubHost(asset.url)
      && isWideFrame(asset));
  const fromCover = (document?.artwork?.cover || [])
    .map(normalizeAsset)
    .filter((asset) => asset
      && (asset.lang ?? null) === want
      && asset.source !== "kinopub"
      && !isKinopubHost(asset.url)
      && isWideFrame(asset));
  return [...fromCover, ...fromBackdrop];
}

/**
 * When a Russian poster is asked and the document has no Kinopoisk id, look it
 * up via Wikidata (IMDb → P2603) inside this request and persist it.
 */
export async function ensureKinopoiskId(env, document, hints = {}) {
  if (!document) return document;
  const existing = numericId(String(document.ids?.kinopoisk?.value || hints.kinopoisk || ""));
  if (existing) {
    if (!document.ids?.kinopoisk?.value && hints.kinopoisk) {
      return {
        ...document,
        ids: {
          ...document.ids,
          kinopoisk: { value: String(existing), confidence: 1, method: "client" },
        },
      };
    }
    return document;
  }
  const imdb = preferredId(document.ids, "imdb", hints.imdb);
  const wikidata = document.ids?.wikidata?.value;
  let kp = null;
  let method = "wikidata:P2603";
  try {
    if (wikidata) {
      kp = await kinopoiskIdFromWikidataEntity(wikidata);
    } else if (imdb) {
      kp = await kinopoiskIdFromImdb(imdb);
      method = "wikidata:imdb";
    }
  } catch (_) {
    return document;
  }
  if (!kp) return document;
  return {
    ...document,
    ids: {
      ...document.ids,
      kinopoisk: { value: String(kp), confidence: 0.9, method },
    },
  };
}

async function kinopoiskIdFromImdb(imdb) {
  const tt = String(imdb).startsWith("tt") ? String(imdb) : `tt${imdb}`;
  const searchURL = "https://www.wikidata.org/w/api.php"
    + "?action=query&format=json&list=search&srlimit=1"
    + `&srsearch=${encodeURIComponent(`haswbstatement:P345=${tt}`)}`;
  const search = await fetch(searchURL, {
    headers: {
      Accept: "application/json",
      "User-Agent": "Piratic/1.0 (https://github.com/HipsterCat/kinopub-apple-client)",
    },
    cf: { cacheTtl: 60 * 60 * 24 * 7, cacheEverything: true },
  });
  if (!search.ok) return null;
  const body = await search.json();
  const qid = body?.query?.search?.[0]?.title;
  if (!qid || !String(qid).startsWith("Q")) return null;
  return kinopoiskIdFromWikidataEntity(qid);
}

async function kinopoiskIdFromWikidataEntity(qid) {
  const entityURL = "https://www.wikidata.org/w/api.php"
    + `?action=wbgetentities&format=json&props=claims&ids=${encodeURIComponent(qid)}`;
  const response = await fetch(entityURL, {
    headers: {
      Accept: "application/json",
      "User-Agent": "Piratic/1.0 (https://github.com/HipsterCat/kinopub-apple-client)",
    },
    cf: { cacheTtl: 60 * 60 * 24 * 7, cacheEverything: true },
  });
  if (!response.ok) return null;
  const body = await response.json();
  const claims = body?.entities?.[qid]?.claims?.P2603;
  const raw = claims?.[0]?.mainsnak?.datavalue?.value;
  return numericId(String(raw || ""));
}

function logoCandidates(document) {
  return (document?.artwork?.logo || [])
    .map(normalizeAsset)
    .filter((asset) => asset && asset.source !== "kinopub" && !isKinopubHost(asset.url));
}

function textlessBackdrops(document) {
  return (document?.artwork?.backdrop || [])
    .map(normalizeAsset)
    .filter((asset) => asset
      && (asset.lang ?? null) === null
      && asset.source !== "kinopub"
      && !isKinopubHost(asset.url)
      && isWideFrame(asset));
}

function seasonPosterAsset(document, seasonNumber, lang = "ru") {
  const season = (document.seasons || []).find((item) => Number(item.number) === seasonNumber);
  if (!season) return null;
  const raw = season.poster || season.artwork?.poster;
  if (!raw) return null;
  if (Array.isArray(raw)) {
    // Prefer the asked language, then ru / en / textless — a Russian request must
    // not 404 when only an English or und season poster exists.
    return dropKinopub(bestAsset(raw.map(normalizeAsset).filter(Boolean), "poster", lang));
  }
  // mergeLangPoster / title resolve store `{ ru: url, en: url }`, not a file asset.
  if (typeof raw === "object" && !raw.url && !raw.file_path) {
    const order = [];
    for (const key of [lang, "ru", "en", "und", null]) {
      if (key !== undefined && !order.includes(key)) order.push(key);
    }
    for (const key of order) {
      const value = key == null ? (raw.und ?? raw[""]) : raw[key];
      if (!value) continue;
      const asset = dropKinopub(normalizeAsset(value));
      if (asset) return { ...asset, lang: key === "und" ? null : key };
    }
    for (const [key, value] of Object.entries(raw)) {
      const asset = dropKinopub(normalizeAsset(value));
      if (asset) return { ...asset, lang: key === "und" ? null : key };
    }
    return null;
  }
  return dropKinopub(normalizeAsset(raw));
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

/**
 * kino.pub's own file, the last rung of a title poster / wide-card chain. The
 * file is addressed by the kino.pub id (Sasha 2026-11-26: no need for the
 * client to send it): poster `big`, wide card `wide` (asked with `?wide=1`).
 * An explicit `src=` from an older client still wins.
 */
function chainSource(url, kind, id) {
  if (kind !== "poster" && kind !== "cover") return null;
  const explicit = readKinopubSrc(url, kind);
  if (explicit) return explicit;
  if (kind === "poster") return `${KINOPUB_POSTER_BASE}/big/${id}.jpg`;
  return url.searchParams.has("wide") ? `${KINOPUB_POSTER_BASE}/wide/${id}.jpg` : null;
}

const KINOPUB_IMAGE_HOSTS = [
  "m.staticpop.net", "m.pushbr.com", "m.boramoraboom.ru", "m.alador.space", "media.service-kp.com",
];
const KINOPUB_POSTER_BASE = `https://${KINOPUB_IMAGE_HOSTS[0]}/poster/item`;
const KINOPUB_POSTER_PATH = /^\/poster\/item\/(small|medium|big|wide)\/[0-9]+\.jpg$/;
const KINOPUB_THUMB_PATH = /^\/thumb\/.+\.jpg$/;

function kinopubArtworkOrigins(origin, path) {
  if (!origin) return null;
  const url = new URL(origin);
  const host = url.hostname;
  if (url.protocol !== "https:" || url.port || url.username || url.password
    || !KINOPUB_IMAGE_HOSTS.includes(host) || !path.test(url.pathname)) return null;
  return [origin, ...KINOPUB_IMAGE_HOSTS.filter((mirror) => mirror !== host).map((mirror) => {
    url.hostname = mirror;
    return url.toString();
  })];
}

function readKinopubSrc(url, kind) {
  if (!["poster", "cover", "thumbnail"].includes(kind)) return null;
  const source = safeHttpURL((url.searchParams.get("src") || "").trim());
  if (!source) return null;
  if (/(^|\.)staticpop\.net$/i.test(new URL(source).hostname)) return source;
  return kinopubArtworkOrigins(source, kind === "thumbnail" ? KINOPUB_THUMB_PATH : KINOPUB_POSTER_PATH) ? source : null;
}

/** Persist a client-seeded staticpop thumb so the next hit needs no `src=`. */
function seedEpisodeThumb(document, seasonNumber, episodeNumber, url) {
  if (!document || seasonNumber == null || episodeNumber == null || !url) return document;
  const seasons = [...(document.seasons || [])];
  const index = seasons.findIndex((item) => Number(item.number) === seasonNumber);
  const previous = index >= 0 ? seasons[index] : { number: seasonNumber, episodes: [] };
  const episodes = [...(previous.episodes || [])];
  const epIndex = episodes.findIndex((item) => {
    const number = item.number ?? item.episode ?? item.episode_number;
    return Number(number) === episodeNumber;
  });
  const existing = epIndex >= 0 ? episodes[epIndex] : { number: episodeNumber };
  const current = existing.thumbnail || existing.still || existing.image;
  // Never overwrite a real (non-kinopub) still with a catalogue thumb.
  if (current && !isKinopubHost(current)) return document;
  if (current === url) return document;
  const next = { ...existing, number: episodeNumber, thumbnail: url };
  if (epIndex >= 0) episodes[epIndex] = next;
  else episodes.push(next);
  const season = { ...previous, number: seasonNumber, episodes };
  if (index >= 0) seasons[index] = season;
  else seasons.push(season);
  return { ...document, seasons };
}

function normalizeAsset(asset) {
  if (!asset) return null;
  if (typeof asset === "string") {
    const url = asset.startsWith("/") ? IMAGE_BASE + asset : asset;
    const safe = safeHttpURL(url);
    if (!safe) return null;
    const source = inferSource(safe);
    return { source, url: safe, lang: null, width: null, height: null };
  }
  const rawURL = asset.url || (asset.file_path ? IMAGE_BASE + asset.file_path : null);
  const safe = rawURL && safeHttpURL(rawURL);
  if (!safe) return null;
  const source = asset.source || inferSource(safe);
  return {
    source,
    url: safe,
    lang: asset.lang ?? null,
    width: asset.width ?? null,
    height: asset.height ?? null,
    vote: asset.vote ?? null,
    votes: asset.votes ?? null,
    pinned: asset.pinned === true,
  };
}

function dropKinopub(asset) {
  if (!asset?.url) return null;
  if (asset.source === "kinopub" || isKinopubHost(asset.url)) return null;
  return asset;
}

// A backdrop is a wide frame. A portrait (poster, 2:3) stretched across a 4K
// screen is not one. Unknown dimensions are trusted: tvoe covers often carry
// no pixel size, and the kind already says backdrop.
function isWideFrame(asset) {
  if (!asset.width || !asset.height) return true;
  return asset.width / asset.height >= 1.2;
}

function bestAsset(assets, kind, lang, { strict = false } = {}) {
  let best = null;
  let bestKey = null;
  for (const asset of assets) {
    if (!asset?.url) continue;
    // Episode thumbs may be a kino.pub catalogue file; every other kind must not.
    if (kind !== "thumbnail" && (asset.source === "kinopub" || isKinopubHost(asset.url))) continue;
    // Backdrop is textless or it is a miss. Language never promotes a titled frame.
    if (kind === "backdrop" && (asset.lang ?? null) !== null) continue;
    if (kind === "backdrop" && !isWideFrame(asset)) continue;
    // Cover is the lang-aware wide plate (TMDB backdrop with iso_639_1).
    if (kind === "cover" && (asset.lang ?? null) === null) continue;
    if (kind === "cover" && !isWideFrame(asset)) continue;
    if (strict && (asset.lang ?? null) !== lang) continue;
    const sizeKey = kind === "logo"
      ? logoRank(asset)
      : voteRank(asset.vote, asset.votes, asset.width);
    const key = [
      langRank(asset.lang ?? null, lang),
      sourceRank(kind, asset.source),
      ...sizeKey,
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
    const sized = tmdbSized(asset.url, kind, w, asset.width);
    // TMDB serves the same logo as PNG when the path ends in .png.
    // SVG in an image view is the broken case.
    return kind === "logo" && sized ? sized.replace(/\.svg(?=$|\?)/i, ".png") : sized;
  }
  if (asset.source === "kinopoisk" || asset.url.includes("kinopoiskapiunofficial.tech")) {
    return kinopoiskSized(asset.url, w);
  }
  // Episode stills: hand the staticpop URL to weserv (`w=` + WebP). Other
  // kinds never reach here with a kinopub asset.
  if (asset.source === "kinopub" || isKinopubHost(asset.url)) {
    return safeHttpURL(asset.url);
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
  if (bucket) {
    const token = TMDB_SIZE_TOKEN[kind]?.[bucket] || `w${bucket}`;
    return `https://image.tmdb.org/t/p/${token}${path}`;
  }
  const originalOK = knownWidth == null
    ? TMDB_ORIGINAL_IF_WIDTH_UNKNOWN.has(kind)
    : knownWidth <= MAX_WIDTH;
  if (originalOK) return `https://image.tmdb.org/t/p/original${path}`;
  const fallback = ladder[ladder.length - 1];
  const token = TMDB_SIZE_TOKEN[kind]?.[fallback] || `w${fallback}`;
  return `https://image.tmdb.org/t/p/${token}${path}`;
}

function kinopoiskSized(url, w) {
  const match = url.match(/\/posters\/kp(?:_small)?\/(\d+)\.jpg$/);
  if (!match) return safeHttpURL(url);
  const target = w == null ? MAX_WIDTH : w;
  const size = target <= 360 ? "kp_small" : "kp";
  return `${KINOPOISK_POSTER}/${size}/${match[1]}.jpg`;
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
  if (isKinopubHost(url)) return "kinopub";
  return "unknown";
}

export function isKinopubHost(url) {
  const source = typeof url === "string" && safeHttpURL(url);
  if (!source) return false;
  const { hostname } = new URL(source);
  return KINOPUB_IMAGE_HOSTS.includes(hostname) || /(^|\.)staticpop\.net$/i.test(hostname);
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
  if (request.kind === "cover") return "no language cover";
  if (request.kind === "thumbnail") return "no episode thumbnail";
  if (request.kind === "poster" && request.s != null) return "no season poster";
  return "no poster";
}

function redirect(location, vary, language) {
  // The discovery URL must not stick. A pin bumps `v` on the file URL, and the
  // next open has to see that new Location immediately.
  const headers = {
    Location: location,
    "Cache-Control": "no-store",
    "Access-Control-Allow-Origin": "*",
  };
  if (vary) headers.Vary = "Accept-Language";
  if (language) headers["Content-Language"] = language;
  return new Response(null, { status: 302, headers });
}

function imageNotFound(hint, vary, { timeout = false, store = true } = {}) {
  const headers = (timeout || !store)
    ? { "Cache-Control": "no-store", "Access-Control-Allow-Origin": "*" }
    : imageHeaders(30, vary);
  if ((timeout || !store) && vary) headers.Vary = "Accept-Language";
  return new Response(JSON.stringify({ error: "not_found", hint }), {
    status: 404,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...headers,
    },
  });
}

function imageHeaders(maxAge, vary) {
  const headers = {
    "Cache-Control": `public, max-age=${maxAge}`,
    "Access-Control-Allow-Origin": "*",
  };
  if (vary) headers.Vary = "Accept-Language";
  return headers;
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
