/**
 * Owner-key proxies. The keys stay on the worker. Callers never send them.
 *
 *   GET /omdb?i=tt0111161&plot=short
 *   GET /kp/api/v2.2/films/326
 *   GET /tvoe/api/v2/catalog?categoryAlias=films&limit=1
 *   GET /tvoe/site/_next/data/{buildId}/p/{slug}.json
 *   GET /tvoe/site/_next/image?url=…&w=1920&q=80
 *
 * Kinopoisk accepts two owner keys (KINOPOISK_API_KEY, KINOPOISK_API_KEY_2).
 * A 402 from one is retried on the other. The viewer's own key stays in the app.
 */

const OMDB = "https://www.omdbapi.com/";
const KINOPOISK = "https://kinopoiskapiunofficial.tech";
const TVOE_API = "https://api.tvoe.live";
const TVOE_SITE = "https://tvoe.live";

const TVOE_HOSTS = new Set(["api.tvoe.live", "tvoe.live", "static.cdn.tvoe.live"]);

const DAY = 60 * 60 * 24;
const HOUR = 60 * 60;

const TVOE_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36";

export function kinopoiskKeys(env) {
  const keys = [];
  for (const name of ["KINOPOISK_API_KEY", "KINOPOISK_API_KEY_2"]) {
    const value = env?.[name];
    if (typeof value === "string" && value.trim()) keys.push(value.trim());
  }
  return keys;
}

export async function handleOwners(url, request, env, ctx) {
  if (url.pathname === "/omdb") return proxyOmdb(url, env, ctx);
  if (url.pathname.startsWith("/kp/")) return proxyKinopoisk(url, env, ctx);
  if (url.pathname === "/kp") {
    return json({ error: "bad_request", hint: "/kp/api/v2.2/films/{id}" }, 400);
  }
  if (url.pathname.startsWith("/tvoe/api/") || url.pathname === "/tvoe/api") {
    const path = url.pathname.slice("/tvoe/api".length) || "/";
    return proxyPlain(`${TVOE_API}${path}${url.search}`, env, ctx, HOUR, tvoeHeaders());
  }
  if (url.pathname.startsWith("/tvoe/site/") || url.pathname === "/tvoe/site") {
    const path = url.pathname.slice("/tvoe/site".length) || "/";
    return proxyPlain(`${TVOE_SITE}${path}${url.search}`, env, ctx, HOUR, tvoeHeaders());
  }
  if (url.pathname === "/tvoe" || url.pathname === "/tvoe/") {
    return json({
      error: "bad_request",
      hint: "/tvoe/api/v2/catalog · /tvoe/site/_next/data/{buildId}/p/{slug}.json",
    }, 400);
  }
  return null;
}

async function proxyOmdb(url, env, ctx) {
  const key = typeof env?.OMDB_API_KEY === "string" ? env.OMDB_API_KEY.trim() : "";
  if (!key) return json({ error: "misconfigured", hint: "OMDB_API_KEY secret missing" }, 500);

  const params = new URLSearchParams(url.search);
  params.delete("apikey");
  params.delete("apiKey");
  const cacheURL = `${OMDB}?${params.toString()}`;
  params.set("apikey", key);
  const upstreamURL = `${OMDB}?${params.toString()}`;

  return proxyPlain(upstreamURL, env, ctx, DAY, { Accept: "application/json" }, {
    cacheURL,
    cacheIf(status, text) {
      if (status < 200 || status >= 300) return false;
      try {
        return JSON.parse(text).Response === "True";
      } catch {
        return false;
      }
    },
  });
}

async function proxyKinopoisk(url, env, ctx) {
  const keys = kinopoiskKeys(env);
  if (!keys.length) {
    return json({ error: "misconfigured", hint: "KINOPOISK_API_KEY secret missing" }, 500);
  }
  const path = url.pathname.slice("/kp".length);
  const upstreamURL = `${KINOPOISK}${path}${url.search}`;
  let last = null;
  for (let i = 0; i < keys.length; i++) {
    const response = await proxyPlain(upstreamURL, env, ctx, DAY, {
      Accept: "application/json",
      "X-API-KEY": keys[i],
    }, {
      cacheURL: upstreamURL,
      cacheIf(status) {
        return status >= 200 && status < 300;
      },
    });
    if (response.status !== 402 || i === keys.length - 1) return response;
    last = response;
  }
  return last;
}

function tvoeHeaders() {
  return {
    Accept: "application/json,text/plain,*/*",
    "User-Agent": TVOE_UA,
  };
}

async function proxyPlain(upstreamURL, env, ctx, maxAge, headers, options = {}) {
  const cacheURL = options.cacheURL || upstreamURL;
  const cache = edgeCache();
  const cacheKey = new Request(cacheURL, { method: "GET" });
  if (cache) {
    const cached = await cache.match(cacheKey);
    if (cached) return withCORS(cached);
  }

  const upstream = await fetch(upstreamURL, {
    method: "GET",
    headers,
    redirect: "manual",
  });
  const text = await upstream.text();
  const cacheable = options.cacheIf
    ? options.cacheIf(upstream.status, text)
    : upstream.status >= 200 && upstream.status < 300;

  const outHeaders = new Headers();
  const type = upstream.headers.get("content-type");
  if (type) outHeaders.set("content-type", type);
  outHeaders.set("Cache-Control", cacheable ? `public, max-age=${maxAge}` : "no-store");
  outHeaders.set("Access-Control-Allow-Origin", "*");
  const location = upstream.headers.get("location");
  if (location && allowedRedirect(location)) outHeaders.set("location", location);

  const response = new Response(text, { status: upstream.status, headers: outHeaders });
  if (cacheable && cache) ctx.waitUntil(cache.put(cacheKey, response.clone()));
  return response;
}

function allowedRedirect(location) {
  try {
    return TVOE_HOSTS.has(new URL(location).hostname);
  } catch {
    return false;
  }
}

function edgeCache() {
  try {
    return caches?.default ?? null;
  } catch {
    return null;
  }
}

function withCORS(response) {
  const headers = new Headers(response.headers);
  headers.set("Access-Control-Allow-Origin", "*");
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function json(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
