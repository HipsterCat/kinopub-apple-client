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
    new Request("https://example.test/img/logo/by/kinopub/7"),
    env,
    { waitUntil() {} },
  );
  assert.equal(image.status, 302);
  assert.equal(image.headers.get("location"), "https://example.test/img/logo/by/kinopub/7/en/logo.png?v=1");
  assert.equal(image.headers.get("content-language"), "en");
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
    assert.equal(body.de, undefined);
  } finally {
    globalThis.fetch = original;
  }
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
