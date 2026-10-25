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

function imageRequest(kind, { id = "82852", query = "", lang } = {}) {
  const qs = query ? (query.startsWith("?") ? query : `?${query}`) : "";
  const headers = {};
  if (lang) headers["Accept-Language"] = lang;
  return new Request(`https://example.test/img/${kind}/by/kinopub/${id}${qs}`, { headers });
}

afterEach(async () => {
  await Promise.allSettled(originalWaitUntil.splice(0));
});

const TVOE_COVER = "https://static.cdn.tvoe.live/images/cover.jpg";
const TVOE_LOGO = "https://static.cdn.tvoe.live/images/logo.png";
const TVOE_POSTER = "https://static.cdn.tvoe.live/images/poster.jpg";
const TMDB_TEXTLESS = "https://image.tmdb.org/t/p/original/textless.jpg";
const TMDB_TITLED = "https://image.tmdb.org/t/p/original/titled.jpg";
const TMDB_LOGO_RU = "https://image.tmdb.org/t/p/original/logo-ru.png";
const TMDB_LOGO_EN = "https://image.tmdb.org/t/p/original/logo-en.png";
const TMDB_POSTER_RU = "https://image.tmdb.org/t/p/original/poster-ru.jpg";
const TMDB_POSTER_EN = "https://image.tmdb.org/t/p/original/poster-en.jpg";
const KINOPUB_WIDE = "https://m.staticpop.net/poster/item/wide/82852.jpg";

test("the size-in-path image route is gone", async () => {
  const response = await handleImage(
    new Request("https://example.test/img/backdrop/orig/kinopub/82852"),
    kvEnv(),
    ctxSpy(),
  );
  assert.equal(response.status, 404);
  assert.equal(response.headers.get("location"), null);
});

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
  const response = await handleImage(imageRequest("logo"), env, ctxSpy());
  assert.equal(response.status, 302);
  assert.equal(
    response.headers.get("location"),
    "https://example.test/img/logo/by/kinopub/82852/ru/logo.png",
  );
});

test("Accept-Language en picks the English logo", async () => {
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
  const response = await handleImage(
    imageRequest("logo", { lang: "en-US,en;q=0.9" }),
    env,
    ctxSpy(),
  );
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "https://example.test/img/logo/by/kinopub/82852/en/logo.png");
  assert.equal(response.headers.get("content-language"), "en");
});

test("a Russian logo request with only an English file sends the English logo", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: { logo: [{ source: "tmdb", url: TMDB_LOGO_EN, lang: "en", width: 800 }] },
    },
  });
  const response = await handleImage(imageRequest("logo"), env, ctxSpy());
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "https://example.test/img/logo/by/kinopub/82852/en/logo.png");
  assert.equal(response.headers.get("content-language"), "en");
});

test("query logo snaps w up the TMDB ladder and never through tvoe", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: { logo: [{ source: "tmdb", url: TMDB_LOGO_EN, lang: "en" }] },
    },
  });
  const response = await handleImage(imageRequest("logo", { query: "w=400", lang: "en" }), env, ctxSpy());
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "https://example.test/img/logo/by/kinopub/82852/en/logo.png?w=400");
});

test("query logo with nothing stored is 404 and still resolves", async () => {
  const ctx = ctxSpy();
  const response = await handleImage(imageRequest("logo"), kvEnv(), ctx);
  assert.equal(response.status, 404);
  assert.equal(response.headers.get("location"), null);
  assert.equal((await response.json()).hint, "no stored logo");
  assert.equal(ctx.pending.length, 1);
});

test("backdrop is textless and wide, prefers tvoe, and ignores Accept-Language and ?lang=", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        backdrop: [
          { source: "tmdb", url: TMDB_TITLED, lang: "ru", width: 3840, height: 2160 },
          { source: "tmdb", url: TMDB_TEXTLESS, lang: null, width: 3840, height: 2160 },
          { source: "tvoe", url: TVOE_COVER, lang: null },
          { source: "kinopub", url: KINOPUB_WIDE, lang: null, width: 3840, height: 2160 },
        ],
      },
    },
  });
  const response = await handleImage(
    imageRequest("backdrop", { query: "lang=ru&w=1920", lang: "en" }),
    env,
    ctxSpy(),
  );
  assert.equal(response.status, 302);
  assert.equal(
    response.headers.get("location"),
    "https://example.test/img/backdrop/by/kinopub/82852/und/backdrop.jpg?w=1920",
  );
  assert.equal(response.headers.get("vary"), null);
});

test("a portrait filed as a backdrop is not stretched across the screen", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        backdrop: [
          { source: "tmdb", url: TMDB_TEXTLESS, lang: null, width: 300, height: 600 },
        ],
      },
    },
  });
  const response = await handleImage(imageRequest("backdrop"), env, ctxSpy());
  assert.equal(response.status, 404);
  assert.equal(response.headers.get("location"), null);
  assert.equal((await response.json()).hint, "no textless backdrop");
});

test("query backdrop snaps a non-bucket width up and caps an omitted width at 3840", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: { backdrop: [{ source: "tvoe", url: TVOE_COVER, lang: null }] },
    },
  });
  const snapped = await handleImage(imageRequest("backdrop", { query: "w=1000" }), env, ctxSpy());
  assert.equal(
    snapped.headers.get("location"),
    "https://example.test/img/backdrop/by/kinopub/82852/und/backdrop.jpg?w=1000",
  );
  const maxed = await handleImage(imageRequest("backdrop"), env, ctxSpy());
  assert.equal(
    maxed.headers.get("location"),
    "https://example.test/img/backdrop/by/kinopub/82852/und/backdrop.jpg",
  );
});

test("query backdrop unwraps a stored tvoe resizer URL back to the durable CDN file", async () => {
  const stored = `https://tvoe.live/_next/image?url=${encodeURIComponent(TVOE_COVER)}&w=16&q=75`;
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: { backdrop: [{ source: "tvoe", url: stored, lang: null }] },
    },
  });
  const response = await handleImage(imageRequest("backdrop", { query: "w=1920" }), env, ctxSpy());
  assert.equal(
    response.headers.get("location"),
    "https://example.test/img/backdrop/by/kinopub/82852/und/backdrop.jpg?w=1920",
  );
});

test("query backdrop uses TMDB original only when the file is within 3840", async () => {
  const within = kvEnv({
    "title:kinopub:82852": {
      artwork: { backdrop: [{ source: "tmdb", url: TMDB_TEXTLESS, lang: null, width: 3840, height: 2160 }] },
    },
  });
  const atCap = await handleImage(imageRequest("backdrop", { query: "w=1920" }), within, ctxSpy());
  assert.equal(atCap.headers.get("location"), "https://example.test/img/backdrop/by/kinopub/82852/und/backdrop.jpg?w=1920");

  const unknown = kvEnv({
    "title:kinopub:82852": {
      artwork: { backdrop: [{ source: "tmdb", url: TMDB_TEXTLESS, lang: null }] },
    },
  });
  const capped = await handleImage(imageRequest("backdrop"), unknown, ctxSpy());
  assert.equal(capped.headers.get("location"), "https://example.test/img/backdrop/by/kinopub/82852/und/backdrop.jpg");

  const huge = kvEnv({
    "title:kinopub:82852": {
      artwork: { backdrop: [{ source: "tmdb", url: TMDB_TEXTLESS, lang: null, width: 9000, height: 5062 }] },
    },
  });
  const held = await handleImage(imageRequest("backdrop"), huge, ctxSpy());
  assert.equal(held.headers.get("location"), "https://example.test/img/backdrop/by/kinopub/82852/und/backdrop.jpg");
});

test("backdrop 404s when the only frame is a kino.pub wide", async () => {
  const ctx = ctxSpy();
  const env = kvEnv({
    "title:kinopub:82852": {
      pending: false,
      artwork: { backdrop: [{ source: "kinopub", url: KINOPUB_WIDE, lang: null, width: 3840, height: 2160 }] },
    },
  });
  const response = await handleImage(imageRequest("backdrop"), env, ctx);
  assert.equal(response.status, 404);
  assert.equal(response.headers.get("location"), null);
  assert.equal(ctx.pending.length, 1);
});

test("backdrop on a cold id 404s and resolves behind it", async () => {
  const ctx = ctxSpy();
  const response = await handleImage(imageRequest("backdrop"), kvEnv(), ctx);
  assert.equal(response.status, 404);
  assert.equal(response.headers.get("location"), null);
  assert.equal(ctx.pending.length, 1);
});

test("Russian poster with a Kinopoisk id skips TMDB and never echoes kino.pub", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      ids: { kinopoisk: { value: "326" } },
      artwork: {
        poster: [
          { source: "tmdb", url: TMDB_POSTER_RU, lang: "ru", width: 2000, height: 3000 },
          { source: "kinopub", url: "https://m.staticpop.net/poster/item/big/82852.jpg", lang: null },
        ],
      },
    },
  });
  const response = await handleImage(imageRequest("poster"), env, ctxSpy());
  assert.equal(response.status, 302);
  assert.equal(
    response.headers.get("location"),
    "https://example.test/img/poster/by/kinopub/82852/ru/poster.jpg",
  );
});

test("Russian poster prefers tvoe over the Kinopoisk file", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      ids: { kinopoisk: { value: "326" } },
      artwork: { poster: [{ source: "tvoe", url: TVOE_POSTER, lang: "ru" }] },
    },
  });
  const response = await handleImage(imageRequest("poster"), env, ctxSpy());
  assert.equal(
    response.headers.get("location"),
    "https://example.test/img/poster/by/kinopub/82852/ru/poster.jpg",
  );
});

test("Russian poster without a Kinopoisk id uses the TMDB ru file", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        poster: [
          { source: "tmdb", url: TMDB_POSTER_EN, lang: "en", width: 2000, height: 3000 },
          { source: "tmdb", url: TMDB_POSTER_RU, lang: "ru", width: 2000, height: 3000 },
        ],
      },
    },
  });
  const response = await handleImage(imageRequest("poster"), env, ctxSpy());
  assert.equal(response.headers.get("location"), "https://example.test/img/poster/by/kinopub/82852/ru/poster.jpg");
});

test("Russian poster does not fall back to an English one", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: { poster: [{ source: "tmdb", url: TMDB_POSTER_EN, lang: "en" }] },
    },
  });
  const response = await handleImage(imageRequest("poster", { query: "lang=ru" }), env, ctxSpy());
  assert.equal(response.status, 404);
  assert.equal(response.headers.get("location"), null);
  assert.equal(response.headers.get("vary"), "Accept-Language");
});

test("English poster uses the TMDB en file and not the Kinopoisk one", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      ids: { kinopoisk: { value: "326" } },
      artwork: { poster: [{ source: "tmdb", url: TMDB_POSTER_EN, lang: "en", width: 500, height: 750 }] },
    },
  });
  const response = await handleImage(imageRequest("poster", { lang: "en", query: "w=400" }), env, ctxSpy());
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "https://example.test/img/poster/by/kinopub/82852/en/poster.jpg?w=400");
});

test("poster with no better file 404s instead of echoing kino.pub, and still resolves", async () => {
  const ctx = ctxSpy();
  const response = await handleImage(imageRequest("poster", { query: "w=100" }), kvEnv(), ctx);
  assert.equal(response.status, 404);
  assert.equal(response.headers.get("location"), null);
  assert.equal(ctx.pending.length, 1);
});

test("a Kinopoisk hint on a cold poster answers the Russian file", async () => {
  const response = await handleImage(
    imageRequest("poster", { query: "kinopoisk=326" }),
    kvEnv({ "title:kinopub:82852": { artwork: {} } }),
    ctxSpy(),
  );
  assert.equal(
    response.headers.get("location"),
    "https://example.test/img/poster/by/kinopub/82852/ru/poster.jpg",
  );
});

test("poster w under 360 uses the small Kinopoisk file", async () => {
  const response = await handleImage(
    imageRequest("poster", { query: "kinopoisk=326&w=300" }),
    kvEnv({ "title:kinopub:82852": { artwork: {} } }),
    ctxSpy(),
  );
  assert.equal(
    response.headers.get("location"),
    "https://example.test/img/poster/by/kinopub/82852/ru/poster.jpg?w=300",
  );
});

test("season poster does not fall back to the title poster or to kino.pub", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: { poster: [{ source: "tmdb", url: TMDB_POSTER_RU, lang: "ru" }] },
      seasons: [
        { number: 1, poster: "https://image.tmdb.org/t/p/original/s1.jpg" },
        { number: 2, poster: KINOPUB_WIDE },
      ],
    },
  });
  const hit = await handleImage(imageRequest("poster", { query: "s=1&w=400" }), env, ctxSpy());
  assert.equal(hit.headers.get("location"), "https://example.test/img/poster/by/kinopub/82852/und/poster.jpg?w=400&s=1");
  const miss = await handleImage(imageRequest("poster", { query: "s=2" }), env, ctxSpy());
  assert.equal(miss.status, 404);
  assert.equal((await miss.json()).hint, "no season poster");
});

test("thumbnail is the episode still, needs both s and e, and refuses a kino.pub thumb", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      seasons: [{
        number: 1,
        episodes: [
          { number: 5, thumbnail: TVOE_COVER },
          { number: 6, thumbnail: "https://m.staticpop.net/poster/item/wide/82852.jpg" },
        ],
      }],
    },
  });
  const hit = await handleImage(imageRequest("thumbnail", { query: "s=01&e=05&w=1000" }), env, ctxSpy());
  assert.equal(hit.status, 302);
  assert.equal(
    hit.headers.get("location"),
    "https://example.test/img/thumbnail/by/kinopub/82852/und/thumbnail.jpg?w=1000&s=1&e=5",
  );
  const kinopubThumb = await handleImage(imageRequest("thumbnail", { query: "s=1&e=6" }), env, ctxSpy());
  assert.equal(kinopubThumb.status, 404);
  const ctx = ctxSpy();
  const missing = await handleImage(imageRequest("thumbnail", { query: "s=1" }), kvEnv(), ctx);
  assert.equal(missing.status, 400);
  assert.equal(ctx.pending.length, 0);
});

test("backdrop ignores season params and stays on the title frame", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: { backdrop: [{ source: "tmdb", url: TMDB_TEXTLESS, lang: null, width: 1920, height: 1080 }] },
      seasons: [{ number: 1, poster: "https://image.tmdb.org/t/p/original/s1.jpg" }],
    },
  });
  const response = await handleImage(imageRequest("backdrop", { query: "s=1&e=5" }), env, ctxSpy());
  assert.equal(response.headers.get("location"), "https://example.test/img/backdrop/by/kinopub/82852/und/backdrop.jpg?s=1&e=5");
});

test("a taller smaller PNG logo beats a wide SVG", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        logo: [
          { source: "tmdb", url: "https://image.tmdb.org/t/p/original/wide.svg", lang: "ru", width: 2000, height: 280 },
          { source: "tmdb", url: "https://image.tmdb.org/t/p/original/white.png", lang: "ru", width: 420, height: 640 },
        ],
      },
    },
  });
  const response = await handleImage(imageRequest("logo"), env, ctxSpy());
  assert.equal(response.headers.get("location"), "https://example.test/img/logo/by/kinopub/82852/ru/logo.png");
  assert.equal(response.headers.get("content-language"), "ru");
});

test("the stamped logo URL proxies an SVG as PNG", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        logo: [{ source: "tmdb", url: "https://image.tmdb.org/t/p/original/mark.svg", lang: "en", width: 800, height: 200 }],
      },
    },
  });
  const original = globalThis.fetch;
  let fetched = "";
  globalThis.fetch = async (url) => {
    fetched = String(url);
    return new Response(Uint8Array.from([1, 2, 3]), {
      status: 200,
      headers: { "content-type": "image/png" },
    });
  };
  try {
    const response = await handleImage(
      new Request("https://example.test/img/logo/by/kinopub/82852/en/logo.png"),
      env,
      ctxSpy(),
    );
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-language"), "en");
    assert.equal(fetched, "https://image.tmdb.org/t/p/original/mark.png");
  } finally {
    globalThis.fetch = original;
  }
});

test("query route rejects a non-numeric id and an unknown namespace", async () => {
  const badId = await handleImage(imageRequest("logo", { id: "tt123" }), kvEnv(), ctxSpy());
  assert.equal(badId.status, 400);
  const other = await handleImage(
    new Request("https://example.test/img/logo/by/imdb/tt123"),
    kvEnv(),
    ctxSpy(),
  );
  assert.equal(other.status, 404);
});
