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

test("logo with a stored TMDB logo redirects to that URL", async () => {
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
  assert.equal(response.headers.get("location"), logo);
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
  assert.equal(response.headers.get("location"), "https://image.tmdb.org/t/p/original/ru.png");
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
