import assert from "node:assert/strict";
import { test } from "node:test";
import { handleAdmin } from "./admin.js";
import { handleImage } from "./title.js";

function memoryEnv(initial = {}) {
  const documents = { ...initial };
  return {
    ADMIN_TOKEN: "secret",
    documents,
    DOCUMENTS: {
      async get(key, opts) {
        const raw = documents[key];
        if (raw == null) return null;
        return opts?.type === "json" ? raw : JSON.stringify(raw);
      },
      async put(key, value) {
        documents[key] = JSON.parse(value);
      },
    },
  };
}

function admin(path, { token = "secret", body } = {}) {
  return new Request(`https://example.test${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: body == null ? undefined : JSON.stringify(body),
  });
}

test("admin routes stay hidden without the token", async () => {
  const env = memoryEnv();
  env.ADMIN_TOKEN = "";
  const response = await handleAdmin(admin("/admin/kinopub/7/forget?kind=logo"), env);
  assert.equal(response.status, 404);
});

test("pick pins a logo and the image route serves that file", async () => {
  const env = memoryEnv({
    "title:kinopub:7": {
      pending: false,
      artwork: {
        logo: [{ source: "tmdb", url: "https://image.tmdb.org/t/p/original/old.png", lang: "ru", width: 100, height: 40 }],
      },
    },
  });
  const picked = await handleAdmin(admin("/admin/kinopub/7/pick", {
    body: { logo: "https://image.tmdb.org/t/p/original/chosen.png", logo_lang: "en" },
  }), env);
  assert.equal(picked.status, 200);
  const image = await handleImage(
    new Request("https://example.test/img/logo/by/kinopub/7", {
      headers: { "Accept-Language": "en-US,en;q=0.9" },
    }),
    env,
    { waitUntil() {} },
  );
  assert.equal(image.status, 302);
  assert.equal(image.headers.get("location"), "https://example.test/img/logo/by/kinopub/7/en/logo.png?v=1");
  assert.equal(image.headers.get("content-language"), "en");
});

test("pick logo merges ru and en pins without dropping the other language", async () => {
  const env = memoryEnv({
    "title:kinopub:7": {
      pending: false,
      artwork: { logo: [] },
    },
  });
  const ru = await handleAdmin(admin("/admin/kinopub/7/pick", {
    body: {
      logo: "https://image.tmdb.org/t/p/original/ru-logo.png",
      logo_lang: "ru",
    },
  }), env);
  assert.equal(ru.status, 200);
  const en = await handleAdmin(admin("/admin/kinopub/7/pick", {
    body: {
      logo: "https://image.tmdb.org/t/p/original/en-logo.png",
      logo_lang: "en",
    },
  }), env);
  assert.equal(en.status, 200);
  const doc = env.documents["title:kinopub:7"];
  assert.equal(doc.artwork.logo.length, 2);
  const langs = doc.artwork.logo.map((item) => item.lang).sort();
  assert.deepEqual(langs, ["en", "ru"]);
});

test("images returns the ru, en and textless files for one title", async () => {
  const env = memoryEnv({
    "title:kinopub:7": {
      kind: "movie",
      ids: { tmdb: { value: "movie/550" }, imdb: { value: "tt0137523" } },
    },
  });
  env.TMDB_READ_TOKEN = "test";
  const original = globalThis.fetch;
  globalThis.fetch = async (url) => {
    assert.equal(String(url), "https://api.themoviedb.org/3/movie/550/images");
    return new Response(JSON.stringify({
      logos: [
        { iso_639_1: "en", file_path: "/wide.svg", width: 2000, height: 280 },
        { iso_639_1: "en", file_path: "/white.png", width: 400, height: 600 },
        { iso_639_1: "ru", file_path: "/ru.png", width: 300, height: 300 },
        { iso_639_1: null, file_path: "/blank.png", width: 100, height: 100 },
        { iso_639_1: "de", file_path: "/de.png", width: 10, height: 10 },
      ],
    }), { status: 200, headers: { "content-type": "application/json" } });
  };
  try {
    const response = await handleAdmin(admin("/admin/kinopub/7/images?kind=logo"), env);
    const body = await response.json();
    assert.equal(body.en[0].url, "https://image.tmdb.org/t/p/original/white.png");
    assert.equal(body.en[0].pick, true);
    assert.equal(body.en[1].url, "https://image.tmdb.org/t/p/original/wide.png");
    assert.equal(body.en[1].from, "svg");
    assert.equal(body.ru[0].url, "https://image.tmdb.org/t/p/original/ru.png");
    assert.equal(body.und[0].url, "https://image.tmdb.org/t/p/original/blank.png");
    assert.equal(body.de[0].url, "https://image.tmdb.org/t/p/original/de.png");
    assert.equal(body.de[0].pick, undefined);
    assert.equal(body.en[0].lang, "en");
  } finally {
    globalThis.fetch = original;
  }
});

test("stats returns the image counters", async () => {
  const env = memoryEnv();
  env.documents["stats:img"] = { timeout: 2, missing: 5, waited: 1 };
  const response = await handleAdmin(admin("/admin/stats"), env);
  const body = await response.json();
  assert.equal(body.timeout, 2);
  assert.equal(body.missing, 5);
  assert.equal(body.waited, 1);
});

test("link pins ids onto a new stub and does not download", async () => {
  const env = memoryEnv();
  const response = await handleAdmin(admin("/admin/kinopub/17262/link", {
    body: {
      kinopoisk: "471002",
      imdb: "tt4573370",
      tmdb: 55165,
      kind: "show",
    },
  }), env);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.created, true);
  assert.equal(body.pending, true);
  assert.equal(body.ids.tmdb, "tv/55165");
  const doc = env.documents["title:kinopub:17262"];
  assert.equal(doc.ids.imdb.method, "manual");
  assert.equal(doc.ids.kinopoisk.value, "471002");
  assert.equal(doc.kind, "show");
  assert.equal(doc.pending, true);
  assert.equal(doc.built_at, undefined);
});

test("link keeps a built document and adds myshows", async () => {
  const env = memoryEnv({
    "title:kinopub:127783": {
      version: 2,
      kind: "show",
      pending: false,
      built_at: "2026-01-01T00:00:00.000Z",
      title: { ru: "Подруга моей девушки", original: "彼女の友達" },
      artwork: { poster: [{ source: "tmdb", url: "https://image.tmdb.org/t/p/original/p.jpg" }] },
      ids: { kinopub: { value: "127783", confidence: 1, method: "client" } },
    },
  });
  const response = await handleAdmin(admin("/admin/kinopub/127783/link", {
    body: { imdb: "tt43650454", tmdb: "tv/336654", myshows: "101353" },
  }), env);
  assert.equal(response.status, 200);
  const doc = env.documents["title:kinopub:127783"];
  assert.equal(doc.pending, false);
  assert.equal(doc.built_at, "2026-01-01T00:00:00.000Z");
  assert.equal(doc.artwork.poster.length, 1);
  assert.equal(doc.ids.tmdb.value, "tv/336654");
  assert.equal(doc.ids.tmdb.method, "manual");
  assert.equal(doc.ids.myshows.value, "101353");
  assert.equal(doc.ids.imdb.value, "tt43650454");
});

test("link rejects a bare tmdb id with no kind", async () => {
  const env = memoryEnv();
  const response = await handleAdmin(admin("/admin/kinopub/1/link", {
    body: { tmdb: "55165" },
  }), env);
  assert.equal(response.status, 400);
  assert.equal(env.documents["title:kinopub:1"], undefined);
});

test("forget clears the logo", async () => {
  const env = memoryEnv({
    "title:kinopub:7": {
      pending: false,
      artwork: { logo: [{ source: "tmdb", url: "https://image.tmdb.org/t/p/original/old.png", lang: "ru" }] },
    },
  });
  const response = await handleAdmin(admin("/admin/kinopub/7/forget?kind=logo"), env);
  assert.equal(response.status, 200);
  assert.equal(env.documents["title:kinopub:7"].artwork.logo.length, 0);
  assert.equal(env.documents["title:kinopub:7"].art_rev, 1);
});
