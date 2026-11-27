import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { RECHECK_MISSING_MS, RECHECK_NEW_MS, RECHECK_STALE_MS, artworkRecheckDue, ensureKinopoiskId, handleImage, kinopoiskHasPoster, resolveAndStore } from "./title.js";

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
  assert.equal(ctx.pending.length, 0);
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
  assert.equal(ctx.pending.length, 0);
});

test("backdrop on a cold id 404s and resolves behind it", async () => {
  const ctx = ctxSpy();
  const response = await handleImage(imageRequest("backdrop"), kvEnv(), ctx);
  assert.equal(response.status, 404);
  assert.equal(response.headers.get("location"), null);
  assert.equal(ctx.pending.length, 0);
});

test("Russian poster with a Kinopoisk id prefers TMDB ru over Kinopoisk and never echoes kino.pub", async () => {
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

test("Russian poster falls back to Kinopoisk when TMDB has no ru file", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      ids: { kinopoisk: { value: "326" } },
      artwork: {
        poster: [
          { source: "tmdb", url: TMDB_POSTER_EN, lang: "en", width: 2000, height: 3000 },
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

test("cover picks the language-tagged TMDB backdrop, not the textless one", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        backdrop: [
          { source: "tmdb", url: TMDB_TEXTLESS, lang: null, width: 3840, height: 2160 },
          { source: "tmdb", url: TMDB_TITLED, lang: "ru", width: 3840, height: 2160 },
          { source: "tmdb", url: "https://image.tmdb.org/t/p/original/en-titled.jpg", lang: "en", width: 1920, height: 1080 },
        ],
      },
    },
  });
  const ru = await handleImage(imageRequest("cover"), env, ctxSpy());
  assert.equal(ru.status, 302);
  assert.equal(ru.headers.get("location"), "https://example.test/img/cover/by/kinopub/82852/ru/cover.jpg");
  assert.equal(ru.headers.get("content-language"), "ru");
  const en = await handleImage(imageRequest("cover", { lang: "en" }), env, ctxSpy());
  assert.equal(en.headers.get("location"), "https://example.test/img/cover/by/kinopub/82852/en/cover.jpg");
  assert.equal(en.headers.get("content-language"), "en");
});

test("cover does not fall back to textless or to poster", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        backdrop: [{ source: "tmdb", url: TMDB_TEXTLESS, lang: null, width: 3840, height: 2160 }],
        poster: [{ source: "tmdb", url: TMDB_POSTER_RU, lang: "ru", width: 2000, height: 3000 }],
      },
    },
  });
  const response = await handleImage(imageRequest("cover"), env, ctxSpy());
  assert.equal(response.status, 404);
  assert.equal((await response.json()).hint, "no language cover");
});

test("cover admin pin wins over the automatic lang-tagged backdrop", async () => {
  const pinned = "https://image.tmdb.org/t/p/original/pinned-cover-ru.jpg";
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        cover: [{ source: "admin", url: pinned, lang: "ru", pinned: true, width: 1920, height: 1080 }],
        backdrop: [
          { source: "tmdb", url: TMDB_TITLED, lang: "ru", width: 3840, height: 2160 },
        ],
      },
    },
  });
  const response = await handleImage(imageRequest("cover"), env, ctxSpy());
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "https://example.test/img/cover/by/kinopub/82852/ru/cover.jpg");
});

test("ensureKinopoiskId keeps an existing id and stores a client hint", async () => {
  const kept = await ensureKinopoiskId({}, {
    ids: { kinopoisk: { value: "326", method: "dump" } },
  });
  assert.equal(kept.ids.kinopoisk.value, "326");
  const fromHint = await ensureKinopoiskId({}, { ids: {} }, { kinopoisk: "999" });
  assert.equal(fromHint.ids.kinopoisk.value, "999");
  assert.equal(fromHint.ids.kinopoisk.method, "client");
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

test("Russian poster with nothing Russian and kino.pub down falls back to an English one", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: { poster: [{ source: "tmdb", url: TMDB_POSTER_EN, lang: "en" }] },
    },
  });
  const response = await handleImage(imageRequest("poster", { query: "lang=ru" }), env, ctxSpy());
  assert.equal(response.status, 302);
  // kino.pub's file (derived from the id) is the Russian rung.
  assert.equal(response.headers.get("location"), "https://example.test/img/poster/by/kinopub/82852/ru/poster.jpg");
  assert.equal(response.headers.get("vary"), "Accept-Language");
  const fetched = [];
  const restore = globalThis.fetch;
  globalThis.fetch = async (target) => {
    const url = String(target);
    fetched.push(url);
    if (url.includes("%2Fposter%2Fitem%2F")) return new Response("down", { status: 502 });
    return new Response("img", { status: 200, headers: { "content-type": "image/webp" } });
  };
  try {
    const stamped = await handleImage(new Request(response.headers.get("location")), env, ctxSpy());
    assert.equal(stamped.status, 200);
    assert.equal(stamped.headers.get("content-language"), "en");
    assert.equal(fetched.length, 6);
    assert.ok(fetched.at(-1).includes("poster-en.jpg"), fetched.at(-1));
  } finally {
    globalThis.fetch = restore;
  }
});

test("kino.pub poster mirrors keep the width and WebP transform on every attempt", async () => {
  const fetched = [];
  const restore = globalThis.fetch;
  globalThis.fetch = async (target) => {
    const transform = new URL(target);
    fetched.push(transform);
    if (fetched.length === 1) return new Response("blocked", { headers: { "content-type": "text/html" } });
    if (fetched.length === 2) throw new DOMException("deadline", "TimeoutError");
    if (fetched.length < 5) return new Response(null, { status: 503 });
    return new Response("img", { headers: { "content-type": "image/webp" } });
  };
  try {
    const request = new Request("https://example.test/img/poster/by/kinopub/82852/ru/poster.jpg?w=584");
    const response = await handleImage(request, kvEnv(), ctxSpy());
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("x-kinopub-image-via"), "weserv");
    assert.deepEqual(fetched.map((url) => new URL(url.searchParams.get("url")).hostname),
      ["m.staticpop.net", "m.pushbr.com", "m.boramoraboom.ru", "m.alador.space", "media.service-kp.com"]);
    for (const url of fetched) {
      assert.equal(url.hostname, "wsrv.nl");
      assert.equal(url.searchParams.get("w"), "584");
      assert.equal(url.searchParams.get("output"), "webp");
      assert.equal(url.searchParams.get("q"), "80");
      assert.equal(new URL(url.searchParams.get("url")).pathname, "/poster/item/big/82852.jpg");
    }
  } finally {
    globalThis.fetch = restore;
  }
});

test("an explicit wide poster starts on its own host when weserv is disabled", async () => {
  const env = { ...kvEnv(), WESERV_DISABLED: "1" };
  const source = "https://m.boramoraboom.ru/poster/item/wide/82852.jpg?size=full";
  const request = imageRequest("cover", { query: `src=${encodeURIComponent(source)}` });
  const fetched = [];
  const restore = globalThis.fetch;
  globalThis.fetch = async (target) => {
    fetched.push(target);
    if (fetched.length === 1) return new Response(null, { status: 404 });
    return new Response("img", { headers: { "content-type": "image/jpeg" } });
  };
  try {
    const redirect = await handleImage(request, env, ctxSpy());
    const response = await handleImage(new Request(redirect.headers.get("location")), env, ctxSpy());
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("x-kinopub-image-via"), "legacy");
    assert.deepEqual(fetched, [source, "https://m.staticpop.net/poster/item/wide/82852.jpg?size=full"]);
  } finally {
    globalThis.fetch = restore;
  }
});

const KINOPUB_POSTER = "https://m.staticpop.net/poster/item/big/82852.jpg";

test("Russian poster: kino.pub src is the last rung in the language", async () => {
  const src = `src=${encodeURIComponent(KINOPUB_POSTER)}`;
  const withRu = kvEnv({
    "title:kinopub:82852": {
      ids: { kinopoisk: { value: "326" } },
      artwork: { poster: [{ source: "tmdb", url: TMDB_POSTER_RU, lang: "ru" }] },
    },
  });
  const first = await handleImage(imageRequest("poster", { query: `w=600&${src}` }), withRu, ctxSpy());
  assert.equal(first.status, 302);
  // The 302 carries src so the stamped proxy can walk the same chain.
  assert.match(first.headers.get("location"), /\/ru\/poster\.jpg\?w=600&src=/);

  const fetched = [];
  const restore = globalThis.fetch;
  globalThis.fetch = async (target) => {
    fetched.push(String(target));
    return new Response("img", { status: 200, headers: { "content-type": "image/webp" } });
  };
  try {
    const noRu = kvEnv({
      "title:kinopub:82852": {
        artwork: { poster: [{ source: "tmdb", url: TMDB_POSTER_EN, lang: "en" }] },
      },
    });
    const stamped = await handleImage(
      new Request(`https://example.test/img/poster/by/kinopub/82852/ru/poster.jpg?w=600&${src}`),
      noRu, ctxSpy(),
    );
    assert.equal(stamped.status, 200);
    assert.equal(fetched.length, 1);
    assert.ok(fetched[0].includes(encodeURIComponent(KINOPUB_POSTER)), fetched[0]);
    assert.ok(fetched[0].startsWith("https://wsrv.nl/"));
  } finally {
    globalThis.fetch = restore;
  }
});

test("stamped poster walks past a dead Kinopoisk file to kino.pub", async () => {
  const fetched = [];
  const restore = globalThis.fetch;
  globalThis.fetch = async (target) => {
    const url = String(target);
    fetched.push(url);
    if (url.includes("kinopoiskapiunofficial")) return new Response("down", { status: 502 });
    return new Response("img", { status: 200, headers: { "content-type": "image/webp" } });
  };
  try {
    const env = kvEnv({ "title:kinopub:82852": { ids: { kinopoisk: { value: "326" } }, artwork: {} } });
    const src = encodeURIComponent(KINOPUB_POSTER);
    const response = await handleImage(
      new Request(`https://example.test/img/poster/by/kinopub/82852/ru/poster.jpg?w=600&src=${src}`),
      env, ctxSpy(),
    );
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-language"), "ru");
    // Kinopoisk's no-poster check, through weserv, direct, then kino.pub.
    assert.equal(fetched.length, 4);
    assert.ok(fetched[3].includes("staticpop"), fetched[3]);
  } finally {
    globalThis.fetch = restore;
  }
});

test("lang=en on the query wins over a missing Accept-Language", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: {
        poster: [
          { source: "tmdb", url: TMDB_POSTER_RU, lang: "ru" },
          { source: "tmdb", url: TMDB_POSTER_EN, lang: "en" },
        ],
      },
    },
  });
  const response = await handleImage(imageRequest("poster", { query: "lang=en" }), env, ctxSpy());
  assert.equal(response.headers.get("location"), "https://example.test/img/poster/by/kinopub/82852/en/poster.jpg");
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

test("poster with no other file ends on kino.pub's own, derived from the id", async () => {
  const ctx = ctxSpy();
  const response = await handleImage(imageRequest("poster", { query: "w=100" }), kvEnv(), ctx);
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "https://example.test/img/poster/by/kinopub/82852/ru/poster.jpg?w=100");
  assert.equal(ctx.pending.length, 0);
});

test("a Kinopoisk hint on a cold poster answers the Russian file", async () => {
  const response = await handleImage(
    imageRequest("poster", { query: "kinopoisk=326" }),
    kvEnv({ "title:kinopub:82852": { artwork: {} } }),
    ctxSpy(),
  );
  assert.equal(
    response.headers.get("location"),
    "https://example.test/img/poster/by/kinopub/82852/ru/poster.jpg?kinopoisk=326",
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
    "https://example.test/img/poster/by/kinopub/82852/ru/poster.jpg?w=300&kinopoisk=326",
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

test("season poster lang map prefers ru then falls through to en", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      seasons: [{
        number: 1,
        poster: {
          en: "https://image.tmdb.org/t/p/original/s1-en.jpg",
        },
      }],
    },
  });
  // Default Accept-Language is Russian — must not 404 when only en exists.
  const hit = await handleImage(imageRequest("poster", { query: "s=1&w=400" }), env, ctxSpy());
  assert.equal(hit.status, 302);
  assert.equal(
    hit.headers.get("location"),
    "https://example.test/img/poster/by/kinopub/82852/en/poster.jpg?w=400&s=1",
  );
  assert.equal(hit.headers.get("content-language"), "en");
});

test("stamped logo goes through wsrv.nl with w, q=80, output=webp", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: { logo: [{ source: "tmdb", url: TMDB_LOGO_EN, lang: "en", width: 2000, height: 400 }] },
    },
  });
  const original = globalThis.fetch;
  const fetched = [];
  globalThis.fetch = async (url) => {
    fetched.push(String(url));
    return new Response(Uint8Array.from([1, 2, 3]), {
      status: 200,
      headers: { "content-type": "image/webp" },
    });
  };
  try {
    for (const w of ["780", "1280", "1920", "2400"]) {
      fetched.length = 0;
      const response = await handleImage(
        new Request(`https://example.test/img/logo/by/kinopub/82852/en/logo.png?w=${w}`),
        env,
        ctxSpy(),
      );
      assert.equal(response.status, 200, `w=${w}`);
      assert.equal(response.headers.get("x-kinopub-image-via"), "weserv", `w=${w}`);
      assert.equal(response.headers.get("content-type"), "image/webp");
      const upstream = new URL(fetched[0]);
      assert.equal(upstream.hostname, "wsrv.nl", `w=${w}`);
      assert.equal(upstream.searchParams.get("w"), w);
      assert.equal(upstream.searchParams.get("q"), "80");
      assert.equal(upstream.searchParams.get("output"), "webp");
      assert.equal(
        upstream.searchParams.get("url"),
        "https://image.tmdb.org/t/p/original/logo-en.png",
      );
    }
  } finally {
    globalThis.fetch = original;
  }
});

test("stamped logo falls back to TMDB ladder when weserv fails", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      artwork: { logo: [{ source: "tmdb", url: TMDB_LOGO_EN, lang: "en", width: 2000, height: 400 }] },
    },
  });
  const original = globalThis.fetch;
  const fetched = [];
  globalThis.fetch = async (url) => {
    const href = String(url);
    fetched.push(href);
    if (href.includes("wsrv.nl")) {
      return new Response("nope", { status: 502 });
    }
    return new Response(Uint8Array.from([1, 2, 3]), {
      status: 200,
      headers: { "content-type": "image/png" },
    });
  };
  try {
    const response = await handleImage(
      new Request("https://example.test/img/logo/by/kinopub/82852/en/logo.png?w=400"),
      env,
      ctxSpy(),
    );
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("x-kinopub-image-via"), "legacy");
    assert.equal(fetched.length, 2);
    assert.match(fetched[0], /wsrv\.nl/);
    assert.match(fetched[1], /\/t\/p\/w454\//);
  } finally {
    globalThis.fetch = original;
  }
});

test("WESERV_DISABLED uses the legacy resize path", async () => {
  const env = {
    ...kvEnv({
      "title:kinopub:82852": {
        artwork: { logo: [{ source: "tmdb", url: TMDB_LOGO_EN, lang: "en", width: 2000, height: 400 }] },
      },
    }),
    WESERV_DISABLED: "1",
  };
  const original = globalThis.fetch;
  const fetched = [];
  globalThis.fetch = async (url) => {
    fetched.push(String(url));
    return new Response(Uint8Array.from([1, 2, 3]), {
      status: 200,
      headers: { "content-type": "image/png" },
    });
  };
  try {
    const response = await handleImage(
      new Request("https://example.test/img/logo/by/kinopub/82852/en/logo.png?w=780"),
      env,
      ctxSpy(),
    );
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("x-kinopub-image-via"), "legacy");
    assert.equal(fetched.length, 1);
    assert.match(fetched[0], /\/t\/p\/w780\//);
  } finally {
    globalThis.fetch = original;
  }
});


test("stamped thumbnail wraps the TMDB face / ladder URL through wsrv.nl as WebP", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      seasons: [{
        number: 1,
        episodes: [{ number: 5, thumbnail: "https://image.tmdb.org/t/p/original/still.jpg" }],
      }],
    },
  });
  const original = globalThis.fetch;
  const fetched = [];
  globalThis.fetch = async (url) => {
    fetched.push(String(url));
    return new Response(Uint8Array.from([0xff, 0xd8, 0xff]), {
      status: 200,
      headers: { "content-type": "image/webp" },
    });
  };
  try {
    const cases = [
      ["300", "https://image.tmdb.org/t/p/w300/still.jpg"],
      ["320", "https://image.tmdb.org/t/p/w320_and_h180_face/still.jpg"],
      ["360", "https://image.tmdb.org/t/p/w454_and_h254_face/still.jpg"],
      ["410", "https://image.tmdb.org/t/p/w454_and_h254_face/still.jpg"],
      ["454", "https://image.tmdb.org/t/p/w454_and_h254_face/still.jpg"],
      ["780", "https://image.tmdb.org/t/p/w780/still.jpg"],
      ["1280", "https://image.tmdb.org/t/p/w1280/still.jpg"],
      ["1920", "https://image.tmdb.org/t/p/w1920_and_h1080_face/still.jpg"],
    ];
    for (const [w, ladder] of cases) {
      fetched.length = 0;
      const response = await handleImage(
        new Request(`https://example.test/img/thumbnail/by/kinopub/82852/und/thumbnail.jpg?w=${w}&s=1&e=5`),
        env,
        ctxSpy(),
      );
      assert.equal(response.status, 200, `w=${w}`);
      assert.equal(response.headers.get("x-kinopub-image-via"), "weserv", `w=${w}`);
      assert.equal(response.headers.get("content-type"), "image/webp");
      const upstream = new URL(fetched[0]);
      assert.equal(upstream.hostname, "wsrv.nl", `w=${w}`);
      assert.equal(upstream.searchParams.get("url"), ladder, `w=${w}`);
      assert.equal(upstream.searchParams.get("w"), w);
      assert.equal(upstream.searchParams.get("q"), "80");
      assert.equal(upstream.searchParams.get("output"), "webp");
    }
  } finally {
    globalThis.fetch = original;
  }
});

test("thumbnail is the episode still, needs both s and e, and accepts a kino.pub thumb last", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      seasons: [{
        number: 1,
        episodes: [
          { number: 5, thumbnail: TVOE_COVER },
          { number: 6, thumbnail: "https://m.staticpop.net/thumb/item/123/1280.jpg" },
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
  const kinopubThumb = await handleImage(imageRequest("thumbnail", { query: "s=1&e=6&w=584" }), env, ctxSpy());
  assert.equal(kinopubThumb.status, 302);
  assert.equal(
    kinopubThumb.headers.get("location"),
    "https://example.test/img/thumbnail/by/kinopub/82852/und/thumbnail.jpg?w=584&s=1&e=6",
  );
  const ctx = ctxSpy();
  const missing = await handleImage(imageRequest("thumbnail", { query: "s=1" }), kvEnv(), ctx);
  assert.equal(missing.status, 400);
  assert.equal(ctx.pending.length, 0);
});

test("thumbnail miss is not edge-cached; src= seeds a staticpop thumb through weserv", async () => {
  const documents = {};
  const env = {
    DOCUMENTS: {
      async get(key, opts) {
        const raw = documents[key];
        if (raw == null) return null;
        return opts?.type === "json" ? raw : JSON.stringify(raw);
      },
      async put(key, value) { documents[key] = JSON.parse(value); },
    },
  };
  const miss = await handleImage(
    imageRequest("thumbnail", { id: "128431", query: "s=1&e=6&w=584" }),
    env,
    ctxSpy(),
  );
  assert.equal(miss.status, 404);
  assert.equal(miss.headers.get("cache-control"), "no-store");

  const src = "https://m.staticpop.net/thumb/item/abc/1280.jpg";
  const original = globalThis.fetch;
  const fetched = [];
  globalThis.fetch = async (url) => {
    fetched.push(String(url));
    if (new URL(url).searchParams.get("output") === "json") return Response.json({ format: "jpeg" });
    return new Response(Uint8Array.from([0xff, 0xd8, 0xff]), {
      status: 200,
      headers: { "content-type": "image/webp" },
    });
  };
  try {
    const redirect = await handleImage(
      new Request(
        `https://example.test/img/thumbnail/by/kinopub/128431?s=1&e=6&w=584&src=${encodeURIComponent(src)}`,
      ),
      env,
      ctxSpy(),
    );
    assert.equal(redirect.status, 302);
    assert.equal(
      documents["title:kinopub:128431"].seasons[0].episodes[0].thumbnail,
      src,
    );
    const stamped = await handleImage(
      new Request(redirect.headers.get("location")),
      env,
      ctxSpy(),
    );
    assert.equal(stamped.status, 200);
    assert.equal(stamped.headers.get("x-kinopub-image-via"), "weserv");
    assert.equal(fetched.length, 2);
    const upstream = new URL(fetched[1]);
    assert.equal(upstream.hostname, "wsrv.nl");
    assert.equal(upstream.searchParams.get("url"), src);
    assert.equal(upstream.searchParams.get("w"), "584");
    assert.equal(upstream.searchParams.get("output"), "webp");
  } finally {
    globalThis.fetch = original;
  }
});

test("thumbnail skips a processing PNG and a stale WebP, then resizes the third host's JPEG", async (t) => {
  const path = "/thumb/d/aa/fbfdda8071272f52e34173399083bd27/4317000/480.jpg";
  const source = `https://m.boramoraboom.ru${path}`;
  const fetched = [];
  t.mock.method(globalThis, "fetch", async (raw) => {
    const url = new URL(raw);
    const origin = new URL(url.searchParams.get("url"));
    const output = url.searchParams.get("output");
    assert.equal(url.hostname, "wsrv.nl");
    assert.equal(url.searchParams.get("w"), "584");
    assert.equal(origin.pathname, path);
    fetched.push(`${origin.hostname} ${output}`);
    if (output === "json") {
      return Response.json({ format: origin.hostname === "m.boramoraboom.ru" ? "png" : "jpeg" }, {
        headers: { "x-upstream-response-length": "6048" },
      });
    }
    const stale = origin.hostname === "m.staticpop.net";
    return new Response(stale ? "processing" : "real frame", {
      headers: { "content-type": "image/webp", "x-upstream-response-length": stale ? "3890" : "6048" },
    });
  });
  // No KV: the stamped route still has the original source from the client.
  const request = imageRequest("thumbnail", { query: `s=1&e=1&w=584&src=${encodeURIComponent(source)}` });
  const redirect = await handleImage(request, {}, ctxSpy());
  assert.equal(redirect.status, 302);
  const response = await handleImage(new Request(redirect.headers.get("location")), {}, ctxSpy());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "image/webp");
  assert.equal(await response.text(), "real frame");
  assert.deepEqual(fetched, [
    "m.boramoraboom.ru json", "m.staticpop.net json", "m.staticpop.net webp",
    "m.pushbr.com json", "m.pushbr.com webp",
  ]);
});

test("a thumbnail still processing on every mirror is a miss without negative caching", async (t) => {
  t.mock.method(globalThis, "fetch", async (raw) => {
    if (new URL(raw).hostname === "wsrv.nl") return Response.json({ format: "png" });
    return new Response("processing", { headers: { "content-type": "image/png" } });
  });
  const source = "https://m.pushbr.com/thumb/a/bc/hash/1000/480.jpg";
  const request = new Request(
    `https://example.test/img/thumbnail/by/kinopub/82852/und/thumbnail.jpg?s=1&e=1&src=${encodeURIComponent(source)}`,
  );
  const response = await handleImage(request, {}, ctxSpy());
  assert.equal(response.status, 404);
  assert.equal(response.headers.get("cache-control"), "no-store");
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

test("the stamped logo URL asks weserv for the PNG twin of an SVG path", async () => {
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
      headers: { "content-type": "image/webp" },
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
    assert.equal(response.headers.get("x-kinopub-image-via"), "weserv");
    const upstream = new URL(fetched);
    assert.equal(upstream.hostname, "wsrv.nl");
    assert.equal(upstream.searchParams.get("url"), "https://image.tmdb.org/t/p/original/mark.png");
    assert.equal(upstream.searchParams.get("output"), "webp");
  } finally {
    globalThis.fetch = original;
  }
});

test("RuPaul S1E1 still is loaded from the season, not left as an empty episode list", async () => {
  const documents = {
    "title:kinopub:58162": {
      pending: false,
      kind: "show",
      ids: { tmdb: { value: "tv/92611" }, imdb: { value: "tt9780442" } },
      seasons: [{ number: 1, episodes: [], poster: "https://image.tmdb.org/t/p/original/season.jpg" }],
      artwork: { logo: [], backdrop: [], poster: [] },
    },
  };
  const env = {
    TMDB_READ_TOKEN: "test",
    DOCUMENTS: {
      async get(key, opts) {
        const raw = documents[key];
        if (raw == null) return null;
        return opts?.type === "json" ? raw : JSON.stringify(raw);
      },
      async put(key, value) { documents[key] = JSON.parse(value); },
    },
  };
  const poster = await handleImage(
    new Request("https://example.test/img/poster/by/kinopub/58162?s=1"),
    env,
    ctxSpy(),
  );
  assert.equal(poster.status, 302);
  assert.match(poster.headers.get("location"), /\/und\/poster\.jpg\?s=1$/);

  const original = globalThis.fetch;
  let seasonURL = "";
  globalThis.fetch = async (url) => {
    seasonURL = String(url);
    return new Response(JSON.stringify({
      name: "Series 1",
      episodes: [{
        episode_number: 1,
        name: "Episode 1",
        still_path: "/dzT1jnR9Pg75Ur09AWtf3eKtinr.jpg",
        runtime: 60,
      }],
    }), { status: 200, headers: { "content-type": "application/json" } });
  };
  try {
    const response = await handleImage(
      new Request("https://example.test/img/thumbnail/by/kinopub/58162?S=1&E=1&imdb=tt9780442"),
      env,
      ctxSpy(),
    );
    assert.equal(response.status, 302);
    assert.equal(
      response.headers.get("location"),
      "https://example.test/img/thumbnail/by/kinopub/58162/und/thumbnail.jpg?s=1&e=1",
    );
    assert.match(seasonURL, /\/tv\/92611\/season\/1/);
    assert.equal(
      documents["title:kinopub:58162"].seasons[0].episodes[0].thumbnail,
      "https://image.tmdb.org/t/p/original/dzT1jnR9Pg75Ur09AWtf3eKtinr.jpg",
    );
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

test("a manual tmdb id is fetched directly and kept", async () => {
  const calls = [];
  const documents = {};
  const original = globalThis.fetch;
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    if (String(url).includes("/3/tv/55165")) {
      return new Response(JSON.stringify({
        id: 55165,
        name: "Следствие вели...",
        original_name: "Следствие вели...",
        images: {},
        videos: { results: [] },
        seasons: [],
        external_ids: {},
      }), { status: 200, headers: { "content-type": "application/json" } });
    }
    return new Response("no", { status: 404 });
  };
  const base = {
    version: 2,
    kind: "show",
    pending: true,
    factsChecked: true,
    title: { ru: null, original: null },
    ids: {
      kinopub: { value: "17262", confidence: 1, method: "manual" },
      imdb: { value: "tt4573370", confidence: 1, method: "manual" },
      kinopoisk: { value: "471002", confidence: 1, method: "manual" },
      tmdb: { value: "tv/55165", confidence: 1, method: "manual" },
      myshows: { value: "101353", confidence: 1, method: "manual" },
    },
    artwork: { poster: [], backdrop: [], logo: [] },
  };
  const env = {
    TMDB_READ_TOKEN: "token",
    DOCUMENTS: {
      async put(key, value) { documents[key] = JSON.parse(value); },
    },
  };
  try {
    const merged = await resolveAndStore(env, "17262", { imdb: "tt0000000" }, base);
    assert.equal(merged.ids.tmdb.method, "manual");
    assert.equal(merged.ids.tmdb.value, "tv/55165");
    assert.equal(merged.ids.imdb.value, "tt4573370");
    assert.equal(merged.ids.myshows.value, "101353");
    assert.equal(merged.pending, false);
    assert.equal(merged.title.ru, "Следствие вели...");
    assert.ok(calls.some((url) => url.includes("/3/tv/55165")));
    assert.equal(calls.some((url) => url.includes("/3/find/")), false);
    assert.equal(documents["title:kinopub:17262"].ids.tmdb.method, "manual");
  } finally {
    globalThis.fetch = original;
  }
});

test("without a manual tmdb id, resolve still finds by imdb", async () => {
  const calls = [];
  const original = globalThis.fetch;
  globalThis.fetch = async (url) => {
    const href = String(url);
    calls.push(href);
    if (href.includes("/3/find/tt4573370")) {
      return new Response(JSON.stringify({
        tv_results: [{ id: 55165 }],
        movie_results: [],
      }), { status: 200, headers: { "content-type": "application/json" } });
    }
    if (href.includes("/3/tv/55165")) {
      return new Response(JSON.stringify({
        id: 55165,
        name: "Следствие вели...",
        images: {},
        videos: { results: [] },
        seasons: [],
      }), { status: 200, headers: { "content-type": "application/json" } });
    }
    return new Response("no", { status: 404 });
  };
  const base = {
    version: 2,
    kind: "show",
    pending: true,
    factsChecked: true,
    title: { ru: null, original: null },
    ids: { kinopub: { value: "17262", confidence: 1, method: "client" } },
    artwork: { poster: [], backdrop: [], logo: [] },
  };
  const env = {
    TMDB_READ_TOKEN: "token",
    DOCUMENTS: { async put() {} },
  };
  try {
    const merged = await resolveAndStore(env, "17262", { imdb: "tt4573370" }, base);
    assert.equal(merged.ids.tmdb.value, "tv/55165");
    assert.equal(merged.ids.tmdb.method, "find:imdb");
    assert.ok(calls.some((url) => url.includes("/3/find/tt4573370")));
  } finally {
    globalThis.fetch = original;
  }
});

const KINOPUB_WIDE_SRC = "https://m.staticpop.net/poster/item/wide/82852.jpg";

test("wide card cover with src: language cover, then textless backdrop, then kino.pub wide", async () => {
  const src = `src=${encodeURIComponent(KINOPUB_WIDE_SRC)}`;
  const textless = { source: "tmdb", url: "https://image.tmdb.org/t/p/original/textless.jpg", lang: null, width: 3840, height: 2160 };
  const withBackdrop = kvEnv({ "title:kinopub:82852": { artwork: { backdrop: [textless] } } });
  const toBackdrop = await handleImage(imageRequest("cover", { query: `w=780&${src}` }), withBackdrop, ctxSpy());
  assert.equal(toBackdrop.status, 302);
  assert.match(toBackdrop.headers.get("location"), /\/img\/cover\/by\/kinopub\/82852\/und\/cover\.jpg\?w=780&src=/);

  const bare = kvEnv({ "title:kinopub:82852": { artwork: {} } });
  const toWide = await handleImage(imageRequest("cover", { query: `w=780&${src}` }), bare, ctxSpy());
  assert.equal(toWide.status, 302);
  assert.match(toWide.headers.get("location"), /\/ru\/cover\.jpg\?w=780&src=/);

  const strict = await handleImage(imageRequest("cover", { query: "w=780" }), withBackdrop, ctxSpy());
  assert.equal(strict.status, 404);

  const fetched = [];
  const restore = globalThis.fetch;
  globalThis.fetch = async (target) => {
    fetched.push(String(target));
    return new Response("img", { status: 200, headers: { "content-type": "image/webp" } });
  };
  try {
    const stamped = await handleImage(
      new Request(`https://example.test/img/cover/by/kinopub/82852/und/cover.jpg?w=780&${src}`),
      withBackdrop, ctxSpy(),
    );
    assert.equal(stamped.status, 200);
    assert.equal(stamped.headers.get("content-language"), "und");
    assert.ok(fetched[0].startsWith("https://wsrv.nl/") && fetched[0].includes("textless"), fetched[0]);
  } finally {
    globalThis.fetch = restore;
  }
});

test("stamped Russian poster: TMDB, then tvoe, then Kinopoisk", async () => {
  const fetched = [];
  const restore = globalThis.fetch;
  globalThis.fetch = async (target) => {
    fetched.push(String(target));
    return new Response("img", { status: 200, headers: { "content-type": "image/webp" } });
  };
  try {
    const env = kvEnv({
      "title:kinopub:82852": {
        ids: { kinopoisk: { value: "326" } },
        artwork: { poster: [
          { source: "tvoe", url: TVOE_POSTER, lang: "ru" },
          { source: "tmdb", url: TMDB_POSTER_RU, lang: "ru" },
        ] },
      },
    });
    await handleImage(new Request("https://example.test/img/poster/by/kinopub/82852/ru/poster.jpg?w=600"), env, ctxSpy());
    assert.ok(fetched[0].includes("poster-ru.jpg"), fetched[0]);
    const noTmdb = kvEnv({
      "title:kinopub:82852": {
        ids: { kinopoisk: { value: "326" } },
        artwork: { poster: [{ source: "tvoe", url: TVOE_POSTER, lang: "ru" }] },
      },
    });
    fetched.length = 0;
    await handleImage(new Request("https://example.test/img/poster/by/kinopub/82852/ru/poster.jpg?w=600"), noTmdb, ctxSpy());
    assert.ok(fetched[0].includes("static.cdn.tvoe.live"), fetched[0]);
  } finally {
    globalThis.fetch = restore;
  }
});

test("recheck: new titles daily, older ones weekly when a language is missing, monthly anyway", () => {
  const now = Date.parse("2026-11-26T12:00:00Z");
  const at = (ms) => new Date(now - ms).toISOString();
  const doc = (built, released) => ({
    built_at: built,
    released_at: released,
    artwork: {
      poster: [{ source: "tmdb", url: TMDB_POSTER_EN, lang: "en" }],
      logo: [{ source: "tmdb", url: TMDB_LOGO_EN, lang: "en" }],
      backdrop: [{ source: "tmdb", url: TMDB_TITLED, lang: "en", width: 1920, height: 1080 }],
    },
  });
  const fresh = at(3 * RECHECK_NEW_MS);
  const old = "2020-01-01";
  // New title: everything after a day.
  assert.equal(artworkRecheckDue(doc(at(60_000), fresh), "poster", "en", now), false);
  assert.equal(artworkRecheckDue(doc(at(RECHECK_NEW_MS), fresh), "poster", "en", now), true);
  // Old title, language missing: after a week, for logo, poster and cover alike.
  for (const kind of ["logo", "poster", "cover"]) {
    assert.equal(artworkRecheckDue(doc(at(RECHECK_NEW_MS), old), kind, "ru", now), false, kind);
    assert.equal(artworkRecheckDue(doc(at(RECHECK_MISSING_MS), old), kind, "ru", now), true, kind);
  }
  // Old title, language present: only after a month.
  assert.equal(artworkRecheckDue(doc(at(RECHECK_MISSING_MS), old), "logo", "en", now), false);
  assert.equal(artworkRecheckDue(doc(at(RECHECK_STALE_MS), old), "logo", "en", now), true);
  assert.equal(artworkRecheckDue({ ...doc(at(RECHECK_STALE_MS), old), pending: true }, "logo", "en", now), false);
});

test("a due recheck with a fallback on hand serves it and refreshes behind the response", async () => {
  const ctx = ctxSpy();
  const env = kvEnv({
    "title:kinopub:82853": {
      built_at: new Date(Date.now() - RECHECK_STALE_MS - 1000).toISOString(),
      artwork: { poster: [{ source: "tmdb", url: TMDB_POSTER_RU, lang: "ru" }] },
    },
  });
  const response = await handleImage(imageRequest("poster", { id: "82853", query: "lang=ru" }), env, ctx);
  assert.equal(response.status, 302);
  assert.match(response.headers.get("location"), /\/ru\/poster\.jpg/);
  assert.equal(ctx.pending.length, 1);
});

test("a cover TMDB lacks in Russian comes from the D1 card covers", async () => {
  const kp = "https://avatars.mds.yandex.net/get-ott/cover-ru.jpg";
  const env = {
    ...kvEnv({ "title:kinopub:82852": { built_at: new Date().toISOString(), artwork: {} } }),
    CATALOG: {
      prepare() {
        return { bind() { return { async all() { return { results: [{ lang: "ru", url: kp, width: 1920, height: 1080 }] }; } }; } };
      },
    },
  };
  const response = await handleImage(imageRequest("cover", { query: "w=780&lang=ru" }), env, ctxSpy());
  assert.equal(response.status, 302);
  assert.match(response.headers.get("location"), /\/ru\/cover\.jpg\?w=780/);
  const fetched = [];
  const restore = globalThis.fetch;
  globalThis.fetch = async (target) => {
    fetched.push(String(target));
    return new Response("img", { status: 200, headers: { "content-type": "image/webp" } });
  };
  try {
    const stamped = await handleImage(new Request("https://example.test/img/cover/by/kinopub/82852/ru/cover.jpg?w=780"), env, ctxSpy());
    assert.equal(stamped.status, 200);
    assert.ok(fetched[0].includes(encodeURIComponent(kp)), fetched[0]);
  } finally {
    globalThis.fetch = restore;
  }
});

test("the stamped poster keeps the Kinopoisk hint so its rung comes before kino.pub", async () => {
  const src = encodeURIComponent("https://m.staticpop.net/poster/item/medium/82852.jpg");
  const env = kvEnv({ "title:kinopub:82852": { built_at: new Date().toISOString(), artwork: { poster: [] } } });
  const first = await handleImage(imageRequest("poster", { query: `w=780&lang=ru&kinopoisk=4915923&src=${src}` }), env, ctxSpy());
  const location = first.headers.get("location");
  assert.match(location, /kinopoisk=4915923/);
  const fetched = [];
  const restore = globalThis.fetch;
  globalThis.fetch = async (target) => {
    fetched.push(String(target));
    return new Response("img", { status: 200, headers: { "content-type": "image/webp" } });
  };
  try {
    await handleImage(new Request(location), env, ctxSpy());
    assert.ok(fetched[0].includes("kinopoiskapiunofficial.tech"), fetched[0]);
  } finally {
    globalThis.fetch = restore;
  }
});

test("wide=1 asks the wide-card chain with kino.pub's wide derived from the id", async () => {
  const bare = kvEnv({ "title:kinopub:82852": { built_at: new Date().toISOString(), artwork: {} } });
  const response = await handleImage(imageRequest("cover", { query: "w=780&lang=ru&wide=1" }), bare, ctxSpy());
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "https://example.test/img/cover/by/kinopub/82852/ru/cover.jpg?w=780&wide=1");
  const strict = await handleImage(imageRequest("cover", { query: "w=780&lang=ru" }), bare, ctxSpy());
  assert.equal(strict.status, 404);
  const fetched = [];
  const restore = globalThis.fetch;
  globalThis.fetch = async (target) => {
    fetched.push(String(target));
    return new Response("img", { status: 200, headers: { "content-type": "image/webp" } });
  };
  try {
    await handleImage(new Request(response.headers.get("location")), bare, ctxSpy());
    assert.ok(fetched[0].includes(encodeURIComponent("https://m.staticpop.net/poster/item/wide/82852.jpg")), fetched[0]);
  } finally {
    globalThis.fetch = restore;
  }
});

test("Kinopoisk's no-poster GIF is a missing rung", async () => {
  const restore = globalThis.fetch;
  const hops = {
    "https://kinopoiskapiunofficial.tech/images/posters/kp/14892763.jpg": "https://st.kp.yandex.net/images/film_big/14892763.jpg",
    "https://st.kp.yandex.net/images/film_big/14892763.jpg": "https://st.kp.yandex.net/images/no-poster.gif",
    "https://kinopoiskapiunofficial.tech/images/posters/kp/4915923.jpg": "https://st.kp.yandex.net/images/film_big/4915923.jpg",
    "https://st.kp.yandex.net/images/film_big/4915923.jpg": "https://avatars.mds.yandex.net/get-kinopoisk-image/1/x1000",
  };
  const fetched = [];
  globalThis.fetch = async (target, init) => {
    const url = String(target);
    fetched.push(url);
    assert.equal(init?.redirect, "manual");
    if (hops[url]) return new Response(null, { status: 302, headers: { location: hops[url] } });
    return new Response(null, { status: 200, headers: { "content-type": "image/jpeg" } });
  };
  try {
    assert.equal(await kinopoiskHasPoster("https://kinopoiskapiunofficial.tech/images/posters/kp/14892763.jpg"), false);
    assert.equal(await kinopoiskHasPoster("https://kinopoiskapiunofficial.tech/images/posters/kp/4915923.jpg"), true);
    const count = fetched.length;
    // Remembered: no second walk for the same title.
    assert.equal(await kinopoiskHasPoster("https://kinopoiskapiunofficial.tech/images/posters/kp_small/14892763.jpg"), false);
    assert.equal(fetched.length, count);
  } finally {
    globalThis.fetch = restore;
  }
});

test("a textless TMDB poster comes before an empty Kinopoisk one in Russian", async () => {
  const restore = globalThis.fetch;
  const fetched = [];
  globalThis.fetch = async (target) => {
    const url = String(target);
    fetched.push(url);
    if (url.includes("kinopoiskapiunofficial")) {
      return new Response(null, { status: 302, headers: { location: "https://st.kp.yandex.net/images/no-poster.gif" } });
    }
    return new Response("img", { status: 200, headers: { "content-type": "image/webp" } });
  };
  try {
    const env = kvEnv({
      "title:kinopub:129379": {
        ids: { kinopoisk: { value: "77777001" } },
        artwork: {
          poster: [
            { source: "tmdb", url: "https://image.tmdb.org/t/p/w780/en.jpg", lang: "en", width: 2000, height: 3000 },
            { source: "tmdb", url: "https://image.tmdb.org/t/p/w780/textless.jpg", lang: null, width: 2000, height: 3000 },
            { source: "kinopoisk", url: "https://kinopoiskapiunofficial.tech/images/posters/kp/77777001.jpg", lang: "ru" },
          ],
        },
      },
    });
    const response = await handleImage(
      new Request("https://example.test/img/poster/by/kinopub/129379/ru/poster.jpg?w=300&kinopoisk=77777001"),
      env, ctxSpy(),
    );
    assert.equal(response.status, 200);
    assert.ok(fetched[0].includes("textless.jpg"), fetched[0]);
    assert.ok(!fetched.some((u) => u.includes("kinopoisk")), fetched.join("\n"));
  } finally {
    globalThis.fetch = restore;
  }
});
