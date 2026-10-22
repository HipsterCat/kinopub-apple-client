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

function byId(kind, { id = "82852", query = "" } = {}) {
  const qs = query ? (query.startsWith("?") ? query : `?${query}`) : "";
  return new URL(`https://example.test/img/${kind}/by/kinopub/${id}${qs}`);
}

const TVOE_COVER = "https://static.cdn.tvoe.live/images/cover.jpg";
const TVOE_LOGO = "https://static.cdn.tvoe.live/images/logo.png";
const TMDB_TEXTLESS = "https://image.tmdb.org/t/p/original/textless.jpg";
const TMDB_TITLED = "https://image.tmdb.org/t/p/original/titled.jpg";
const TMDB_LOGO_RU = "https://image.tmdb.org/t/p/original/logo-ru.png";
const TMDB_LOGO_EN = "https://image.tmdb.org/t/p/original/logo-en.png";
const TMDB_POSTER_RU = "https://image.tmdb.org/t/p/original/poster-ru.jpg";

test("query logo defaults to Russian and prefers tvoe over TMDB", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        logo: [
          { source: "tmdb", url: TMDB_LOGO_RU, lang: "ru" },
          { source: "tvoe", url: TVOE_LOGO, lang: "ru" },
          { source: "tmdb", url: TMDB_LOGO_EN, lang: "en" },
        ],
      },
    },
  });
  const response = await handleImage(byId("logo"), env, ctxSpy());
  assert.equal(response.status, 302);
  const location = response.headers.get("location");
  assert.equal(
    location,
    `https://tvoe.live/_next/image?url=${encodeURIComponent(TVOE_LOGO)}&w=3840&q=80`,
  );
});

test("query logo lang=en_US picks the English logo, not the Russian one", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        logo: [
          { source: "tvoe", url: TVOE_LOGO, lang: "ru" },
          { source: "tmdb", url: TMDB_LOGO_EN, lang: "en", width: 800 },
        ],
      },
    },
  });
  const response = await handleImage(byId("logo", { query: "lang=en_US" }), env, ctxSpy());
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "https://image.tmdb.org/t/p/original/logo-en.png");
});

test("query logo snaps w up the TMDB ladder and never through tvoe", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: { logo: [{ source: "tmdb", url: TMDB_LOGO_EN, lang: "en" }] },
    },
  });
  const response = await handleImage(byId("logo", { query: "w=400&lang=en" }), env, ctxSpy());
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "https://image.tmdb.org/t/p/w500/logo-en.png");
});

test("query logo with nothing stored is 404, never a poster, and still resolves", async () => {
  const ctx = ctxSpy();
  const response = await handleImage(byId("logo"), kvEnv(), ctx);
  assert.equal(response.status, 404);
  assert.equal(response.headers.get("location"), null);
  assert.equal((await response.json()).hint, "no stored logo");
  assert.equal(ctx.pending.length, 1);
});

test("query backdrop is textless, prefers tvoe, and ignores lang", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        backdrop: [
          { source: "tmdb", url: TMDB_TITLED, lang: "en", width: 3840 },
          { source: "tmdb", url: TMDB_TEXTLESS, lang: null, width: 3840 },
          { source: "tvoe", url: TVOE_COVER, lang: null },
          { source: "kinopub", url: "https://m.staticpop.net/poster/item/wide/82852.jpg", lang: null },
        ],
      },
    },
  });
  const response = await handleImage(byId("backdrop", { query: "lang=en&w=1920" }), env, ctxSpy());
  assert.equal(response.status, 302);
  assert.equal(
    response.headers.get("location"),
    `https://tvoe.live/_next/image?url=${encodeURIComponent(TVOE_COVER)}&w=1920&q=80`,
  );
});

test("query backdrop snaps a non-bucket width up and caps an omitted width at 3840", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: { backdrop: [{ source: "tvoe", url: TVOE_COVER, lang: null }] },
    },
  });
  const snapped = await handleImage(byId("backdrop", { query: "w=1000" }), env, ctxSpy());
  assert.equal(
    snapped.headers.get("location"),
    `https://tvoe.live/_next/image?url=${encodeURIComponent(TVOE_COVER)}&w=1024&q=80`,
  );
  const maxed = await handleImage(byId("backdrop"), env, ctxSpy());
  assert.equal(
    maxed.headers.get("location"),
    `https://tvoe.live/_next/image?url=${encodeURIComponent(TVOE_COVER)}&w=3840&q=80`,
  );
});

test("query backdrop unwraps a stored tvoe resizer URL back to the durable CDN file", async () => {
  const stored = `https://tvoe.live/_next/image?url=${encodeURIComponent(TVOE_COVER)}&w=16&q=75`;
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: { backdrop: [{ source: "tvoe", url: stored, lang: null }] },
    },
  });
  const response = await handleImage(byId("backdrop", { query: "w=1920" }), env, ctxSpy());
  assert.equal(
    response.headers.get("location"),
    `https://tvoe.live/_next/image?url=${encodeURIComponent(TVOE_COVER)}&w=1920&q=80`,
  );
});

test("query backdrop uses TMDB original only when the file is within 3840", async () => {
  const within = kvEnv({
    "title:kinopub:82852": {
      artwork: { backdrop: [{ source: "tmdb", url: TMDB_TEXTLESS, lang: null, width: 3840 }] },
    },
  });
  const atCap = await handleImage(byId("backdrop", { query: "w=1920" }), within, ctxSpy());
  assert.equal(atCap.headers.get("location"), "https://image.tmdb.org/t/p/original/textless.jpg");

  const unknown = kvEnv({
    "title:kinopub:82852": {
      artwork: { backdrop: [{ source: "tmdb", url: TMDB_TEXTLESS, lang: null }] },
    },
  });
  const capped = await handleImage(byId("backdrop"), unknown, ctxSpy());
  assert.equal(capped.headers.get("location"), "https://image.tmdb.org/t/p/w1280/textless.jpg");

  const huge = kvEnv({
    "title:kinopub:82852": {
      artwork: { backdrop: [{ source: "tmdb", url: TMDB_TEXTLESS, lang: null, width: 8000 }] },
    },
  });
  const held = await handleImage(byId("backdrop"), huge, ctxSpy());
  assert.equal(held.headers.get("location"), "https://image.tmdb.org/t/p/w1280/textless.jpg");
});

test("query backdrop 404s when the only frame is a lettered kino.pub wide", async () => {
  const ctx = ctxSpy();
  const env = kvEnv({
    "title:kinopub:82852": {
      pending: false,
      artwork: {
        backdrop: [{ source: "kinopub", url: "https://m.staticpop.net/poster/item/wide/82852.jpg", lang: null }],
      },
    },
  });
  const response = await handleImage(byId("backdrop"), env, ctx);
  assert.equal(response.status, 404);
  assert.equal(response.headers.get("location"), null);
  assert.equal((await response.json()).hint, "no textless backdrop");
  assert.equal(ctx.pending.length, 0);
});

test("query backdrop on a cold id 404s instead of the lettered wide, and resolves behind it", async () => {
  const ctx = ctxSpy();
  const response = await handleImage(byId("backdrop"), kvEnv(), ctx);
  assert.equal(response.status, 404);
  assert.equal(response.headers.get("location"), null);
  assert.equal(ctx.pending.length, 1);
});

test("query poster prefers a Russian TMDB poster over Kinopoisk, and Kinopoisk over kino.pub", async () => {
  const both = kvEnv({
    "title:kinopub:82852": {
      ids: { kinopoisk: { value: "326" } },
      artwork: { poster: [{ source: "tmdb", url: TMDB_POSTER_RU, lang: "ru", width: 2000 }] },
    },
  });
  const tmdb = await handleImage(byId("poster"), both, ctxSpy());
  assert.equal(tmdb.headers.get("location"), "https://image.tmdb.org/t/p/original/poster-ru.jpg");

  const kpOnly = kvEnv({
    "title:kinopub:82852": {
      ids: { kinopoisk: { value: "326" } },
      artwork: { poster: [{ source: "tmdb", url: TMDB_TITLED, lang: "en", width: 2000 }] },
    },
  });
  const kp = await handleImage(byId("poster"), kpOnly, ctxSpy());
  assert.equal(kp.headers.get("location"), "https://kinopoiskapiunofficial.tech/images/posters/kp/326.jpg");
});

test("query poster lang=en uses the English kino.pub poster, not the Russian Kinopoisk one", async () => {
  const env = kvEnv({
    "title:kinopub:82852": { ids: { kinopoisk: { value: "326" } }, artwork: {} },
  });
  const response = await handleImage(byId("poster", { query: "lang=en&w=200" }), env, ctxSpy());
  assert.equal(response.status, 302);
  assert.equal(
    response.headers.get("location"),
    "https://m.staticpop.net/poster/item/medium/82852.jpg",
  );
});

test("query poster with no document falls back to kino.pub and snaps w", async () => {
  const ctx = ctxSpy();
  const response = await handleImage(byId("poster", { query: "w=100" }), kvEnv(), ctx);
  assert.equal(response.status, 302);
  assert.equal(
    response.headers.get("location"),
    "https://m.staticpop.net/poster/item/small/82852.jpg",
  );
  assert.equal(ctx.pending.length, 1);
});

test("query poster with a kinopoisk hint and no stored poster answers the Russian poster", async () => {
  const env = kvEnv({ "title:kinopub:82852": { artwork: {} } });
  const response = await handleImage(byId("poster", { query: "kinopoisk=326" }), env, ctxSpy());
  assert.equal(
    response.headers.get("location"),
    "https://kinopoiskapiunofficial.tech/images/posters/kp/326.jpg",
  );
});

test("query poster w under 360 uses the small Kinopoisk file", async () => {
  const env = kvEnv({ "title:kinopub:82852": { artwork: {} } });
  const response = await handleImage(byId("poster", { query: "kinopoisk=326&w=300" }), env, ctxSpy());
  assert.equal(
    response.headers.get("location"),
    "https://kinopoiskapiunofficial.tech/images/posters/kp_small/326.jpg",
  );
});

test("query season poster does not fall back to the title poster", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: { poster: [{ source: "tmdb", url: TMDB_POSTER_RU, lang: "ru" }] },
      seasons: [
        { number: 1, poster: "https://image.tmdb.org/t/p/original/s1.jpg" },
        { number: 2, poster: null },
      ],
    },
  });
  const hit = await handleImage(byId("poster", { query: "s=1&w=400" }), env, ctxSpy());
  assert.equal(hit.headers.get("location"), "https://image.tmdb.org/t/p/w500/s1.jpg");
  const miss = await handleImage(byId("poster", { query: "s=2" }), env, ctxSpy());
  assert.equal(miss.status, 404);
  assert.equal((await miss.json()).hint, "no season poster");
});

test("query thumbnail is the episode still, and needs both s and e", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      seasons: [{
        number: 1,
        episodes: [{
          number: 5,
          thumbnail: TVOE_COVER,
        }],
      }],
    },
  });
  const hit = await handleImage(byId("thumbnail", { query: "s=01&e=05&w=1000" }), env, ctxSpy());
  assert.equal(hit.status, 302);
  assert.equal(
    hit.headers.get("location"),
    `https://tvoe.live/_next/image?url=${encodeURIComponent(TVOE_COVER)}&w=1024&q=80`,
  );
  const ctx = ctxSpy();
  const missing = await handleImage(byId("thumbnail", { query: "s=1" }), kvEnv(), ctx);
  assert.equal(missing.status, 400);
  assert.equal(ctx.pending.length, 0);
});

test("query thumbnail without a still is 404, not a backdrop", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: { backdrop: [{ source: "tmdb", url: TMDB_TEXTLESS, lang: null }] },
      seasons: [{ number: 1, episodes: [{ number: 5 }] }],
    },
  });
  const response = await handleImage(byId("thumbnail", { query: "s=1&e=5" }), env, ctxSpy());
  assert.equal(response.status, 404);
  assert.equal((await response.json()).hint, "no episode thumbnail");
});

test("query backdrop ignores season params and stays on the title frame", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: { backdrop: [{ source: "tmdb", url: TMDB_TEXTLESS, lang: null, width: 1920 }] },
      seasons: [{ number: 1, poster: "https://image.tmdb.org/t/p/original/s1.jpg" }],
    },
  });
  const response = await handleImage(byId("backdrop", { query: "s=1&e=5" }), env, ctxSpy());
  assert.equal(response.headers.get("location"), "https://image.tmdb.org/t/p/original/textless.jpg");
});

test("query route rejects a non-numeric id and an unknown namespace", async () => {
  const badId = await handleImage(byId("logo", { id: "tt123" }), kvEnv(), ctxSpy());
  assert.equal(badId.status, 400);
  const other = await handleImage(
    new URL("https://example.test/img/logo/by/imdb/tt123"),
    kvEnv(),
    ctxSpy(),
  );
  assert.equal(other.status, 400);
});
