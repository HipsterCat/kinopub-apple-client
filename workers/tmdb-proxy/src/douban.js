/**
 * GET /v1/douban/by/imdb/{tt…}
 *
 * Douban's score for a title, by IMDb id, through Frodo, the API of Douban's own mobile
 * app. Douban closed its public API in 2023. Frodo answers requests signed with the
 * app's key and secret (HMAC-SHA1 over `GET&{path}&{ts}`). Those two live in
 * Cloudflare secrets (DOUBAN_API_KEY, DOUBAN_API_SECRET), never in this repo, so a new
 * pair after Douban rotates them needs no app release (Sasha, 2026-11-09).
 *
 * Two upstream calls on a miss: search by IMDb id, which Frodo matches exactly, then
 * `/{movie|tv}/{id}/rating` for the star breakdown, the watched / want / watching
 * counts and the "better than N% of crime films" ranks. Everything in Chinese is left
 * out: genres in the ranks come back as English slugs, unknown ones are dropped.
 *
 * Answers are kept in KV, a day for a found title and a week for a miss. That keeps
 * the traffic to Douban close to one request per title per day, whoever asks.
 */

const ORIGIN = "https://frodo.douban.com";
const USER_AGENT =
  "api-client/1 com.douban.frodo/7.22.0.beta9(231) Android/23 product/Mate40 vendor/HUAWEI "
  + "model/Mate40 brand/HUAWEI rom/android network/wifi platform/AndroidPad";
const FOUND_TTL = 60 * 60 * 24;
const MISS_TTL = 60 * 60 * 24 * 7;
const HINT = "/v1/douban/by/imdb/{tt…}";

/** Douban's genre names (片 film / 剧 series dropped) → English slugs. */
const GENRES = {
  "剧情": "drama", "犯罪": "crime", "喜剧": "comedy", "动作": "action", "爱情": "romance",
  "科幻": "sci-fi", "动画": "animation", "悬疑": "mystery", "惊悚": "thriller", "恐怖": "horror",
  "纪录": "documentary", "短": "short", "音乐": "music", "歌舞": "musical", "家庭": "family",
  "儿童": "kids", "传记": "biography", "历史": "history", "战争": "war", "西部": "western",
  "奇幻": "fantasy", "冒险": "adventure", "灾难": "disaster", "武侠": "wuxia", "古装": "costume",
  "运动": "sport", "黑色电影": "film-noir", "同性": "lgbt",
};

export async function handleDouban(url, env, ctx) {
  const match = url.pathname.match(/^\/v1\/douban\/by\/imdb\/(tt\d{5,10})$/);
  if (!match) return json({ error: "bad_request", hint: HINT }, 400);
  const imdb = match[1];
  if (!env.DOUBAN_API_KEY || !env.DOUBAN_API_SECRET) {
    return json({ error: "misconfigured", hint: "DOUBAN_API_KEY / DOUBAN_API_SECRET secrets missing" }, 500);
  }

  const key = `douban:imdb:${imdb}`;
  const stored = await env.DOCUMENTS.get(key, { type: "json" });
  if (stored && Date.now() - stored.fetchedAt < (stored.title ? FOUND_TTL : MISS_TTL) * 1000) {
    return stored.title ? json(stored.title, 200) : json({ error: "not_found" }, 404);
  }

  let title;
  try {
    title = await lookup(env, imdb);
  } catch (error) {
    // A refused key or a network error is not a miss: keep serving what we had.
    if (stored?.title) return json(stored.title, 200);
    return json({ error: "upstream", detail: String(error?.message || error) }, 502);
  }
  const write = env.DOCUMENTS.put(key, JSON.stringify({ fetchedAt: Date.now(), title: title || null }));
  if (ctx?.waitUntil) ctx.waitUntil(write); else await write;
  return title ? json(title, 200) : json({ error: "not_found" }, 404);
}

async function lookup(env, imdb) {
  const search = await frodo(env, "/api/v2/search/movie", { q: imdb, count: "3" });
  const item = (search.items || []).find((entry) =>
    ["movie", "tv"].includes(entry.target_type) && entry.target?.id);
  if (!item) return null;
  const type = item.target_type;
  const id = String(item.target.id);
  let stats = null;
  try {
    stats = await frodo(env, `/api/v2/${type}/${id}/rating`, {});
  } catch {
    // The score from the search still stands without the breakdown.
  }
  return project(item, stats);
}

/** The worker's answer: numbers and English only. */
export function project(item, stats) {
  const target = item.target || {};
  const id = String(target.id);
  const value = Number(target.rating?.value) || 0;
  const votes = Number(target.rating?.count) || 0;
  const distribution = Array.isArray(stats?.stats) && stats.stats.length === 5
    ? stats.stats.map((share) => Number(share) || 0)
    : null;
  const ranks = (stats?.type_ranks || [])
    .map((entry) => ({ genre: genreSlug(entry.type), betterThan: Number(entry.rank) || 0 }))
    .filter((entry) => entry.genre && entry.betterThan > 0);
  return {
    id,
    type: item.target_type,
    url: `https://movie.douban.com/subject/${id}/`,
    year: Number(target.year) || null,
    rating: value > 0 && votes > 0 ? { value, votes } : null,
    // Shares of 1★…5★ (Douban's 2…10), summing to 1.
    distribution,
    watched: numberOrNull(stats?.done_count),
    wantToWatch: numberOrNull(stats?.wish_count),
    watching: numberOrNull(stats?.doing_count),
    ranks,
  };
}

export function genreSlug(name) {
  const text = String(name || "");
  return GENRES[text] || GENRES[text.replace(/[片剧]$/, "")] || null;
}

function numberOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) && value != null ? number : null;
}

async function frodo(env, path, params) {
  const ts = String(Math.floor(Date.now() / 1000));
  const query = new URLSearchParams({
    ...params,
    apikey: env.DOUBAN_API_KEY,
    os_rom: "android",
    _ts: ts,
    _sig: await signature(env.DOUBAN_API_SECRET, "GET", path, ts),
  });
  const response = await fetch(`${ORIGIN}${path}?${query}`, {
    headers: { "User-Agent": USER_AGENT, Accept: "application/json" },
  });
  if (!response.ok) throw new Error(`frodo ${response.status}`);
  return response.json();
}

/** base64(HMAC-SHA1(secret, "GET&" + percent-encoded path + "&" + ts)), as the app signs. */
export async function signature(secret, method, path, ts) {
  const raw = [method.toUpperCase(), encodeURIComponent(path), ts].join("&");
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret),
    { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
  const digest = await crypto.subtle.sign("HMAC", key, encoder.encode(raw));
  return btoa(String.fromCharCode(...new Uint8Array(digest)));
}

function json(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": status === 200 ? "public, max-age=3600" : "no-store",
    },
  });
}
