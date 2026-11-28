/**
 * Image sources beyond TMDB for the Change Images picker
 * (`POST /admin/kinopub/{id}/images?…&sources=1`).
 *
 *   tvoe, kinopoisk  Our own rows: D1 c2_image (offline card pipeline) and the KV
 *                    document's stored artwork. Kinopoisk's ru logos live here.
 *   upload, admin    Pictures an admin uploaded (`/img/upload/…`) or pinned by link.
 *   fanart           fanart.tv v3. Needs a personal API key.
 *   tvdb             TheTVDB v4. Needs a project API key.
 *   wikidata         The logo statement (P154) of the title's Wikidata item. No key.
 *
 * Keys come from Worker secrets (FANART_API_KEY, TVDB_API_KEY) or, without them,
 * from what an admin saved with `POST /admin/keys` (KV `config:source-keys`).
 * ThePosterDB has no API, so it is not a source here.
 *
 * Every file is `{ url, preview, lang, source, width, height, vote, votes }`,
 * `lang` an iso 639-1 code or null for no language. One slow source never holds
 * the others: each answers within SOURCE_TIMEOUT_MS or is reported as `failed`.
 */

export const SOURCE_KEYS_KEY = "config:source-keys";
const TVDB_TOKEN_KEY = "config:tvdb-token";
const SOURCE_TIMEOUT_MS = 8000;
const FANART_API = "https://webservice.fanart.tv/v3";
const TVDB_API = "https://api4.thetvdb.com/v4";
const WIKIDATA_ENTITY = "https://www.wikidata.org/wiki/Special:EntityData";
const COMMONS_FILE = "https://commons.wikimedia.org/wiki/Special:FilePath";
// Wikimedia asks every client to name itself.
const USER_AGENT = "PiraticImageWorker/1.0 (+https://github.com/HipsterCat/kinopub-apple-client)";

/** Display order of the source chips after TMDB. */
export const SOURCE_ORDER = ["tmdb", "fanart", "tvdb", "tvoe", "kinopoisk", "wikidata", "upload", "admin"];

export async function sourceKeys(env) {
  let saved = {};
  try {
    saved = (await env?.DOCUMENTS?.get(SOURCE_KEYS_KEY, { type: "json" })) || {};
  } catch {
    saved = {};
  }
  return {
    fanart: nonEmpty(env?.FANART_API_KEY) || nonEmpty(saved.fanart),
    tvdb: nonEmpty(env?.TVDB_API_KEY) || nonEmpty(saved.tvdb),
  };
}

/** `POST /admin/keys { fanart, tvdb }`: an empty string removes a saved key. */
export async function saveSourceKeys(env, body) {
  if (!env?.DOCUMENTS) return { error: "no KV" };
  const saved = (await env.DOCUMENTS.get(SOURCE_KEYS_KEY, { type: "json" })) || {};
  for (const name of ["fanart", "tvdb"]) {
    if (!(name in (body || {}))) continue;
    const value = nonEmpty(body[name]);
    if (value) saved[name] = value;
    else delete saved[name];
    if (name === "tvdb") await env.DOCUMENTS.delete?.(TVDB_TOKEN_KEY);
  }
  await env.DOCUMENTS.put(SOURCE_KEYS_KEY, JSON.stringify(saved));
  const keys = await sourceKeys(env);
  return { configured: Object.keys(keys).filter((name) => keys[name]) };
}

/**
 * Files of `kind` from every source but TMDB, and a status per source:
 * `{ files, sources: { fanart: { status: "ok" | "no_key" | "no_id" | "failed", count } } }`.
 */
export async function extraImageFiles(env, id, stored, kind, options = {}) {
  const fetchImpl = options.fetch || fetch;
  const keys = options.keys || await sourceKeys(env);
  const ids = stored?.ids || {};
  const tmdbRef = parseTmdb(ids.tmdb?.value);
  const isShow = stored?.kind === "show" || tmdbRef?.type === "tv";
  const context = {
    env, kind, keys, fetch: fetchImpl, isShow,
    tmdbId: tmdbRef?.id || null,
    imdb: idString(ids.imdb?.value),
    tvdb: idString(ids.tvdb?.value),
    wikidata: idString(ids.wikidata?.value),
  };
  const jobs = {
    stored: () => storedFiles(env, id, stored, kind),
    fanart: () => fanartFiles(context),
    tvdb: () => tvdbFiles(context),
    wikidata: () => wikidataFiles(context),
  };
  const names = Object.keys(jobs);
  const settled = await Promise.all(names.map((name) => withTimeout(jobs[name]())
    .catch((error) => ({ status: "failed", message: error?.message || String(error) }))));

  const sources = {};
  const files = [];
  const seen = new Set(options.exclude || []);
  names.forEach((name, index) => {
    const result = settled[index];
    for (const file of result.files || []) {
      const key = urlKey(file.url);
      if (seen.has(key)) continue;
      seen.add(key);
      files.push(file);
    }
    if (name !== "stored") sources[name] = { status: result.status || "ok" };
  });
  for (const file of files) {
    const slot = sources[file.source] || (sources[file.source] = { status: "ok" });
    slot.count = (slot.count || 0) + 1;
  }
  for (const slot of Object.values(sources)) slot.count = slot.count || 0;
  return { files, sources };
}

/** Same file whatever size token or extension TMDB's URL names. */
export function urlKey(url) {
  const raw = String(url || "");
  const tmdb = raw.match(/image\.tmdb\.org\/t\/p\/[^/]+\/([^/.?]+)/);
  if (tmdb) return `tmdb:${tmdb[1]}`;
  return raw;
}

// MARK: - Our own rows

const OWN_SOURCES = new Set(["tvoe", "kinopoisk", "upload", "admin", "wikidata", "fanart", "tvdb"]);

async function storedFiles(env, id, stored, kind) {
  const files = [];
  const push = (asset, rowKind) => {
    if (!asset?.url) return;
    // A link pin is stored as "admin"; name where the file came from when the URL says.
    const source = (asset.source && asset.source !== "admin" ? asset.source : null)
      || inferOwnSource(asset.url) || asset.source;
    if (!OWN_SOURCES.has(source)) return;
    if (!sameKind(kind, rowKind, source, asset.lang)) return;
    files.push(file({
      url: asset.url, lang: asset.lang ?? null, source,
      width: asset.width, height: asset.height,
    }));
  };
  for (const upload of stored?.uploads || []) push({ ...upload, source: "upload" }, upload.kind);
  for (const rowKind of ["logo", "poster", "backdrop", "cover"]) {
    for (const asset of stored?.artwork?.[rowKind] || []) push(asset, rowKind);
  }
  if (env?.CATALOG) {
    try {
      const { results } = await env.CATALOG.prepare(
        `SELECT kind, lang, url, source, width, height FROM c2_image
          WHERE kinopub_id = ? AND person_id IS NULL AND season IS NULL AND episode IS NULL`,
      ).bind(Number(id)).all();
      for (const row of results || []) push(row, row.kind);
    } catch (error) {
      console.warn("c2_image sources", id, error?.message || error);
    }
  }
  return { files };
}

/**
 * The picker's cover is a wide picture with lettering: Kinopoisk's "backdrop" rows are
 * its cover (text, Russian), and a backdrop with a language is a cover too.
 */
function sameKind(wanted, rowKind, source, lang) {
  if (wanted === rowKind) {
    if (wanted === "backdrop" && source === "kinopoisk") return false;
    return true;
  }
  if (wanted === "cover" && rowKind === "backdrop") return source === "kinopoisk" || lang != null;
  return false;
}

function inferOwnSource(url) {
  if (/\/img\/upload\//.test(url)) return "upload";
  if (/tvoe\.live/.test(url)) return "tvoe";
  if (/kinopoisk|yandex\.net/.test(url)) return "kinopoisk";
  if (/fanart\.tv/.test(url)) return "fanart";
  if (/thetvdb\.com/.test(url)) return "tvdb";
  if (/wikimedia\.org/.test(url)) return "wikidata";
  return null;
}

// MARK: - fanart.tv

const FANART_FIELDS = {
  movie: {
    logo: ["hdmovielogo", "movielogo"],
    poster: ["movieposter"],
    backdrop: ["moviebackground"],
    cover: ["moviethumb"],
  },
  show: {
    logo: ["hdtvlogo", "clearlogo"],
    poster: ["tvposter"],
    backdrop: ["showbackground"],
    cover: ["tvthumb"],
  },
};

// fanart.tv sizes are fixed per type (their upload rules); the API sends none.
const FANART_SIZE = {
  hdmovielogo: [800, 310], movielogo: [400, 155], hdtvlogo: [800, 310], clearlogo: [400, 155],
  movieposter: [1000, 1426], tvposter: [1000, 1426],
  moviebackground: [1920, 1080], showbackground: [1920, 1080],
  moviethumb: [1000, 562], tvthumb: [500, 281],
};

async function fanartFiles({ keys, fetch: fetchImpl, isShow, tmdbId, imdb, tvdb, kind }) {
  if (!keys.fanart) return { status: "no_key" };
  const path = isShow ? (tvdb && `tv/${tvdb}`) : ((tmdbId || imdb) && `movies/${tmdbId || imdb}`);
  if (!path) return { status: "no_id" };
  const response = await fetchImpl(`${FANART_API}/${path}?api_key=${encodeURIComponent(keys.fanart)}`, {
    headers: { Accept: "application/json" },
  });
  if (response.status === 404) return { status: "ok", files: [] };
  if (response.status === 401 || response.status === 403) return { status: "bad_key" };
  if (!response.ok) return { status: "failed" };
  const body = await response.json();
  const files = [];
  for (const field of FANART_FIELDS[isShow ? "show" : "movie"][kind] || []) {
    const [width, height] = FANART_SIZE[field] || [];
    for (const item of body?.[field] || []) {
      if (!item?.url) continue;
      const lang = fanartLang(item.lang);
      // Thumbs carry the title, backgrounds rarely do: a cover is a thumb with a language.
      if (kind === "cover" && lang == null) continue;
      files.push(file({
        url: item.url,
        preview: item.url.replace("assets.fanart.tv/fanart/", "assets.fanart.tv/preview/"),
        lang, source: "fanart", width, height,
        votes: Number(item.likes) || 0,
      }));
    }
  }
  return { status: "ok", files: sortByVotes(files) };
}

function fanartLang(raw) {
  const tag = String(raw || "").trim().toLowerCase();
  return /^[a-z]{2}$/.test(tag) ? tag : null;   // "00" and "" are no language
}

// MARK: - TheTVDB

// v4 artwork types (GET /v4/artwork/types).
const TVDB_TYPES = {
  show: { poster: [2], backdrop: [3], logo: [23], cover: [3] },
  movie: { poster: [14], backdrop: [15], logo: [25], cover: [15] },
};

async function tvdbFiles({ env, keys, fetch: fetchImpl, isShow, tvdb, imdb, kind }) {
  if (!keys.tvdb) return { status: "no_key" };
  const token = await tvdbToken(env, keys.tvdb, fetchImpl);
  if (!token) return { status: "bad_key" };
  const get = async (path) => {
    const response = await fetchImpl(`${TVDB_API}${path}`, {
      headers: { Accept: "application/json", Authorization: `Bearer ${token}` },
    });
    if (response.status === 401) await env?.DOCUMENTS?.delete?.(TVDB_TOKEN_KEY);
    return response.ok ? (await response.json())?.data : null;
  };
  let series = isShow ? tvdb : null;
  let movie = null;
  if (!series && imdb) {
    const found = await get(`/search/remoteid/${encodeURIComponent(imdb)}`);
    for (const hit of Array.isArray(found) ? found : []) {
      if (isShow && hit?.series?.id) { series = hit.series.id; break; }
      if (!isShow && hit?.movie?.id) { movie = hit.movie.id; break; }
    }
  }
  if (!series && !movie) return { status: "no_id" };
  const data = series ? await get(`/series/${series}/artworks`) : await get(`/movies/${movie}/extended`);
  if (!data) return { status: "failed" };
  const types = new Set(TVDB_TYPES[series ? "show" : "movie"][kind] || []);
  const files = [];
  for (const art of data.artworks || []) {
    if (!types.has(art?.type) || !art.image) continue;
    const lang = tvdbLang(art.language);
    // A backdrop is textless and a cover has lettering; TVDB says which with includesText.
    if (kind === "backdrop" && (art.includesText === true || lang != null)) continue;
    if (kind === "cover" && !(art.includesText === true || lang != null)) continue;
    files.push(file({
      url: art.image, preview: art.thumbnail || art.image, lang, source: "tvdb",
      width: art.width, height: art.height, votes: Number(art.score) || 0,
    }));
  }
  return { status: "ok", files: sortByVotes(files) };
}

async function tvdbToken(env, apikey, fetchImpl) {
  try {
    const cached = await env?.DOCUMENTS?.get(TVDB_TOKEN_KEY, { type: "json" });
    if (cached?.token && cached.key === hashKey(apikey)) return cached.token;
  } catch {
    // A missing cache is only one more login.
  }
  const response = await fetchImpl(`${TVDB_API}/login`, {
    method: "POST",
    headers: { Accept: "application/json", "Content-Type": "application/json" },
    body: JSON.stringify({ apikey }),
  });
  if (!response.ok) return null;
  const token = (await response.json())?.data?.token;
  if (!token) return null;
  // Tokens live a month; keep one for 25 days.
  await env?.DOCUMENTS?.put?.(TVDB_TOKEN_KEY, JSON.stringify({ token, key: hashKey(apikey) }),
    { expirationTtl: 25 * 24 * 3600 });
  return token;
}

const TVDB_LANGS = { eng: "en", rus: "ru", ukr: "uk", deu: "de", fra: "fr", spa: "es", ita: "it",
  jpn: "ja", kor: "ko", zho: "zh", por: "pt", pol: "pl" };

function tvdbLang(raw) {
  const tag = String(raw || "").trim().toLowerCase();
  if (!tag) return null;
  if (/^[a-z]{2}$/.test(tag)) return tag;
  return TVDB_LANGS[tag] || tag.slice(0, 2);
}

// MARK: - Wikidata

async function wikidataFiles({ fetch: fetchImpl, wikidata, kind }) {
  if (kind !== "logo") return { status: "ok", files: [] };
  if (!wikidata || !/^Q\d+$/.test(wikidata)) return { status: "no_id" };
  const response = await fetchImpl(`${WIKIDATA_ENTITY}/${wikidata}.json`, {
    headers: { Accept: "application/json", "User-Agent": USER_AGENT },
  });
  if (!response.ok) return { status: "failed" };
  const body = await response.json();
  const claims = body?.entities?.[wikidata]?.claims?.P154 || [];
  const files = [];
  for (const claim of claims) {
    const name = claim?.mainsnak?.datavalue?.value;
    if (typeof name !== "string" || !name) continue;
    const path = `${COMMONS_FILE}/${encodeURIComponent(name.replace(/ /g, "_"))}`;
    // FilePath renders an SVG to PNG at the asked width; the picker pins that PNG.
    files.push(file({
      url: `${path}?width=1200`, preview: `${path}?width=500`, lang: null, source: "wikidata",
    }));
  }
  return { status: "ok", files };
}

// MARK: - Helpers

function file({ url, preview, lang, source, width, height, vote, votes }) {
  return {
    url,
    preview: preview || null,
    lang: lang ?? null,
    from: extension(url),
    source,
    width: positive(width),
    height: positive(height),
    vote: vote ?? null,
    votes: votes ?? null,
  };
}

function sortByVotes(files) {
  return files.sort((a, b) => (b.votes || 0) - (a.votes || 0) || (b.width || 0) - (a.width || 0));
}

function extension(url) {
  const path = String(url || "").split("?")[0];
  return (path.match(/\.([a-z0-9]{3,4})$/i) || [])[1]?.toLowerCase() || null;
}

function positive(raw) {
  const value = Number(raw);
  return Number.isFinite(value) && value > 0 ? Math.round(value) : null;
}

function parseTmdb(raw) {
  const match = String(raw || "").match(/^(movie|tv)\/(\d+)$/);
  return match ? { type: match[1], id: match[2] } : null;
}

function idString(raw) {
  if (raw == null || raw === "") return null;
  return String(raw);
}

function nonEmpty(raw) {
  const value = typeof raw === "string" ? raw.trim() : "";
  return value || null;
}

function hashKey(key) {
  let hash = 0;
  for (let i = 0; i < key.length; i++) hash = (hash * 31 + key.charCodeAt(i)) | 0;
  return String(hash);
}

function withTimeout(promise) {
  let timer;
  const timeout = new Promise((resolve) => {
    timer = setTimeout(() => resolve({ status: "failed", message: "timeout" }), SOURCE_TIMEOUT_MS);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}
