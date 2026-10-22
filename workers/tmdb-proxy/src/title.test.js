import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { handleImage } from "./title.js";

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
