import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { handleImage, parseImageRequest, tmdbBucket } from "./title.js";

const originalWaitUntil = [];

function ctxSpy() {
  const pending = [];
  return {
    pending,
    waitUntil(promise) {
      pending.push(promise);
      originalWaitUntil.push(promise);
    },
  };
}

function kvEnv(documents = {}) {
  return {
    DOCUMENTS: {
      async get(key, opts) {
        const raw = documents[key];
        if (raw == null) return null;
        return opts?.type === "json" ? raw : JSON.stringify(raw);
      },
      async put() {},
    },
  };
}

function imageURL(kind, { size = "md", id = "82852", search = "" } = {}) {
  return new URL(`https://example.test/img/${kind}/${size}/kinopub/${id}${search}`);
}

afterEach(async () => {
  await Promise.allSettled(originalWaitUntil.splice(0));
});

test("logo with no stored document answers 404, never a poster, and still resolves behind the response", async () => {
  const ctx = ctxSpy();
  const response = await handleImage(imageURL("logo"), kvEnv(), ctx);

  assert.equal(response.status, 404);
  assert.equal(response.headers.get("location"), null);
  const body = await response.json();
  assert.equal(body.error, "not_found");
  assert.equal(ctx.pending.length, 1);
});

test("logo with a stored document that has no logo answers 404, never a poster", async () => {
  const ctx = ctxSpy();
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        poster: [{ source: "kinopub", url: "https://m.staticpop.net/poster/item/big/82852.jpg", lang: null }],
      },
    },
  });
  const response = await handleImage(imageURL("logo"), env, ctx);

  assert.equal(response.status, 404);
  assert.equal(response.headers.get("location"), null);
  assert.equal(ctx.pending.length, 0);
});

test("logo with a stored TMDB logo redirects to it at the asked size, through the worker", async () => {
  const logo = "https://image.tmdb.org/t/p/original/logo.png";
  const ctx = ctxSpy();
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        logo: [{ source: "tmdb", url: logo, lang: "en" }],
      },
    },
  });
  const response = await handleImage(imageURL("logo"), env, ctx);

  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "https://example.test/t/p/w300/logo.png");
});

test("logo prefers the Russian stored logo when several languages exist", async () => {
  const ctx = ctxSpy();
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        logo: [
          { source: "tmdb", url: "https://image.tmdb.org/t/p/original/en.png", lang: "en" },
          { source: "tmdb", url: "https://image.tmdb.org/t/p/original/ru.png", lang: "ru" },
        ],
      },
    },
  });
  const response = await handleImage(imageURL("logo"), env, ctx);

  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "https://example.test/t/p/w300/ru.png");
});

test("logo honours lang=en, and orig keeps TMDB's original bucket", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        logo: [
          { source: "tmdb", url: "https://image.tmdb.org/t/p/original/ru.png", lang: "ru" },
          { source: "tmdb", url: "https://image.tmdb.org/t/p/original/en.png", lang: "en" },
        ],
      },
    },
  });
  const response = await handleImage(imageURL("logo", { size: "orig", search: "?lang=en" }), env, ctxSpy());

  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "https://example.test/t/p/original/en.png");
});

test("backdrop picks the textless TMDB one at the backdrop bucket", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        backdrop: [
          { source: "tmdb", url: "https://image.tmdb.org/t/p/original/ru.jpg", lang: "ru" },
          { source: "tmdb", url: "https://image.tmdb.org/t/p/original/clean.jpg", lang: null },
        ],
      },
    },
  });
  const response = await handleImage(imageURL("backdrop", { size: "lg" }), env, ctxSpy());

  assert.equal(response.headers.get("location"), "https://example.test/t/p/w1280/clean.jpg");
});

test("cold logo with an IMDb hint waits for the resolve and redirects to the logo it found", async () => {
  const realFetch = globalThis.fetch;
  const requested = [];
  globalThis.fetch = async (input) => {
    const url = String(input);
    requested.push(url);
    if (url.includes("/3/find/tt0133093")) {
      return Response.json({ movie_results: [{ id: 603 }], tv_results: [] });
    }
    if (url.includes("/3/movie/603")) {
      return Response.json({
        title: "Матрица",
        images: { logos: [{ file_path: "/matrix-ru.png", iso_639_1: "ru", width: 800 }] },
      });
    }
    return new Response("nope", { status: 404 });
  };
  try {
    const stored = {};
    const env = {
      TMDB_READ_TOKEN: "token",
      DOCUMENTS: {
        async get(key) { return stored[key] ?? null; },
        async put(key, value) { stored[key] = JSON.parse(value); },
      },
    };
    const response = await handleImage(
      imageURL("logo", { size: "lg", search: "?imdb=tt0133093" }), env, ctxSpy());

    assert.equal(response.status, 302);
    assert.equal(response.headers.get("location"), "https://example.test/t/p/w500/matrix-ru.png");
    assert.ok(stored["title:kinopub:82852"], "the resolved document is stored for the next ask");
    assert.equal(requested.filter((u) => u.includes("kpapp.link")).length, 0,
                 "an image ask never pays for Kinopoisk facts");
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("poster with no stored document still falls back to kino.pub artwork", async () => {
  const ctx = ctxSpy();
  const response = await handleImage(imageURL("poster"), kvEnv(), ctx);

  assert.equal(response.status, 302);
  assert.equal(
    response.headers.get("location"),
    "https://m.staticpop.net/poster/item/medium/82852.jpg",
  );
  assert.equal(ctx.pending.length, 1);
});

test("unknown kind answers 404, never a poster, and does not resolve", async () => {
  const ctx = ctxSpy();
  const response = await handleImage(imageURL("still"), kvEnv(), ctx);

  assert.equal(response.status, 404);
  assert.equal(response.headers.get("location"), null);
  const body = await response.json();
  assert.equal(body.error, "not_found");
  assert.equal(ctx.pending.length, 0);
});

test("backdrop with an unknown size still falls back to the wide kino.pub still", async () => {
  const ctx = ctxSpy();
  const response = await handleImage(imageURL("backdrop", { size: "unknown" }), kvEnv(), ctx);

  assert.equal(response.status, 302);
  assert.equal(
    response.headers.get("location"),
    "https://m.staticpop.net/poster/item/wide/82852.jpg",
  );
});

test("backdrop at orig with nothing stored is kino.pub's wide still, never the vertical poster", async () => {
  const response = await handleImage(imageURL("backdrop", { size: "orig" }), kvEnv(), ctxSpy());

  assert.equal(response.headers.get("location"), "https://m.staticpop.net/poster/item/wide/82852.jpg");
});

// ------------------------------------------------- /img/{kind}/by/kinopub/{id}

function byURL(kind, { id = "82852", search = "" } = {}) {
  return new URL(`https://example.test/img/${kind}/by/kinopub/${id}${search}`);
}

const TMDB = "https://image.tmdb.org/t/p/original";

test("w picks the smallest TMDB width that covers it, original past w1920 or without w", () => {
  assert.equal(tmdbBucket(500), "w500");
  assert.equal(tmdbBucket(501), "w780");
  assert.equal(tmdbBucket(960), "w1280");
  assert.equal(tmdbBucket(1920), "w1920");
  assert.equal(tmdbBucket(1921), "original");
  assert.equal(tmdbBucket(3840), "original");
  assert.equal(tmdbBucket(250), "w300");
  assert.equal(tmdbBucket(null), "original");
});

test("parse accepts the by-route with upper-case S/E and the legacy size words", () => {
  assert.deepEqual(parseImageRequest(byURL("thumbnail", { search: "?w=300&lang=en&S=01&E=05" })),
    { kind: "thumbnail", id: "82852", lang: "en", width: 300, season: 1, episode: 5 });
  assert.deepEqual(parseImageRequest(imageURL("logo", { size: "lg" })),
    { kind: "logo", id: "82852", lang: "ru", width: 500, season: null, episode: null });
  assert.equal(parseImageRequest(new URL("https://example.test/img/logo/by/imdb/tt1")), null);
  assert.equal(parseImageRequest(new URL("https://example.test/img/logo")), null);
});

test("logo by kino.pub id at w=1920 is TMDB w1920, at w=300 the w300 bucket", async () => {
  const env = kvEnv({
    "title:kinopub:82852": { ids: { tmdb: { value: "tv/1" } },
      artwork: { logo: [{ source: "tmdb", url: `${TMDB}/logo.png`, lang: "ru" }] } },
  });
  const large = await handleImage(byURL("logo", { search: "?w=1920" }), env, ctxSpy());
  assert.equal(large.headers.get("location"), "https://example.test/t/p/w1920/logo.png");
  const small = await handleImage(byURL("logo", { search: "?w=300" }), env, ctxSpy());
  assert.equal(small.headers.get("location"), "https://example.test/t/p/w300/logo.png");
});

test("poster with s is that season's poster, and the title poster when the season has none", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      ids: { tmdb: { value: "tv/1" } },
      artwork: { poster: [{ source: "tmdb", url: `${TMDB}/title.jpg`, lang: "ru" }] },
      seasons: [{ number: 2, poster: `${TMDB}/season2.jpg` }],
    },
  });
  const season = await handleImage(byURL("poster", { search: "?s=2&w=342" }), env, ctxSpy());
  assert.equal(season.headers.get("location"), "https://example.test/t/p/w342/season2.jpg");
  const missing = await handleImage(byURL("poster", { search: "?s=9&w=342" }), env, ctxSpy());
  assert.equal(missing.headers.get("location"), "https://example.test/t/p/w342/title.jpg");
});

test("thumbnail with s and e is the TMDB episode still; no still is 404; no e is 400", async () => {
  const env = {
    ...kvEnv({ "title:kinopub:82852": { ids: { tmdb: { value: "tv/1399" } }, artwork: {} } }),
    TMDB_READ_TOKEN: "test",
  };
  const realFetch = globalThis.fetch;
  const asked = [];
  globalThis.fetch = async (input) => {
    asked.push(String(input));
    return new Response(JSON.stringify({ episodes: [{ episode_number: 5, still_path: "/still5.jpg" }] }));
  };
  try {
    const hit = await handleImage(byURL("thumbnail", { search: "?S=01&E=05&w=300" }), env, ctxSpy());
    assert.equal(hit.status, 302);
    assert.equal(hit.headers.get("location"), "https://example.test/t/p/w300/still5.jpg");
    assert.match(asked[0], /\/3\/tv\/1399\/season\/1\b/);

    const miss = await handleImage(byURL("thumbnail", { search: "?s=1&e=6" }), env, ctxSpy());
    assert.equal(miss.status, 404);
  } finally {
    globalThis.fetch = realFetch;
  }
  const noEpisode = await handleImage(byURL("thumbnail", { search: "?s=1" }), env, ctxSpy());
  assert.equal(noEpisode.status, 400);
});

test("kino.pub fallback size follows w: small, medium, big; backdrop always the wide still", async () => {
  const at = async (kind, w) =>
    (await handleImage(byURL(kind, { search: `?w=${w}` }), kvEnv(), ctxSpy())).headers.get("location");
  assert.equal(await at("poster", 150), "https://m.staticpop.net/poster/item/small/82852.jpg");
  assert.equal(await at("poster", 342), "https://m.staticpop.net/poster/item/medium/82852.jpg");
  assert.equal(await at("poster", 780), "https://m.staticpop.net/poster/item/big/82852.jpg");
  assert.equal(await at("backdrop", 300), "https://m.staticpop.net/poster/item/wide/82852.jpg");
});
