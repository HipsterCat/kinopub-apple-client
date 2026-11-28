import assert from "node:assert/strict";
import { test } from "node:test";
import { handleAdmin } from "./admin.js";
import { extraImageFiles, urlKey } from "./sources.js";
import { serveUpload } from "./uploads.js";

function memoryEnv(initial = {}) {
  const documents = { ...initial };
  const blobs = {};
  return {
    ADMIN_TOKEN: "secret",
    documents,
    blobs,
    DOCUMENTS: {
      async get(key, opts) {
        if (blobs[key]) return opts?.type === "stream" ? { cancel() {} } : blobs[key].value;
        const raw = documents[key];
        if (raw == null) return null;
        return opts?.type === "json" ? raw : JSON.stringify(raw);
      },
      async getWithMetadata(key) {
        return blobs[key] ? { value: blobs[key].value, metadata: blobs[key].metadata } : { value: null };
      },
      async put(key, value, options) {
        if (value instanceof Uint8Array) blobs[key] = { value, metadata: options?.metadata };
        else documents[key] = JSON.parse(value);
      },
      async delete(key) { delete documents[key]; },
    },
  };
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function routedFetch(routes) {
  const calls = [];
  const impl = async (input, init) => {
    const url = String(input);
    calls.push(url);
    for (const [prefix, answer] of routes) {
      if (url.startsWith(prefix)) return typeof answer === "function" ? answer(url, init) : jsonResponse(answer);
    }
    return new Response("missing", { status: 404 });
  };
  impl.calls = calls;
  return impl;
}

const movieDoc = {
  kind: "movie",
  ids: { tmdb: { value: "movie/603" }, imdb: { value: "tt0133093" }, wikidata: { value: "Q83495" } },
  artwork: {
    logo: [{ source: "tvoe", url: "https://static.cdn.tvoe.live/logo/matrix.png", lang: "ru" }],
    poster: [], backdrop: [], cover: [],
  },
};

test("fanart, wikidata and our own rows join the logo list with a source each", async () => {
  const fetchImpl = routedFetch([
    ["https://webservice.fanart.tv/v3/movies/603", {
      hdmovielogo: [
        { id: "1", url: "https://assets.fanart.tv/fanart/movies/603/hdmovielogo/a.png", lang: "en", likes: "3" },
        { id: "2", url: "https://assets.fanart.tv/fanart/movies/603/hdmovielogo/b.png", lang: "ru", likes: "9" },
      ],
      movieposter: [{ id: "3", url: "https://assets.fanart.tv/fanart/movies/603/movieposter/c.jpg", lang: "en" }],
    }],
    ["https://www.wikidata.org/wiki/Special:EntityData/Q83495.json", {
      entities: { Q83495: { claims: { P154: [{ mainsnak: { datavalue: { value: "The Matrix logo.svg" } } }] } } },
    }],
  ]);
  const env = memoryEnv();
  const { files, sources } = await extraImageFiles(env, 7, movieDoc, "logo", {
    fetch: fetchImpl, keys: { fanart: "k", tvdb: null },
  });
  assert.deepEqual(files.map((f) => [f.source, f.lang]), [
    ["tvoe", "ru"], ["fanart", "ru"], ["fanart", "en"], ["wikidata", null],
  ]);
  const fanart = files.find((f) => f.source === "fanart");
  assert.equal(fanart.preview, "https://assets.fanart.tv/preview/movies/603/hdmovielogo/b.png");
  assert.equal(fanart.width, 800);
  assert.equal(files.at(-1).url,
    "https://commons.wikimedia.org/wiki/Special:FilePath/The_Matrix_logo.svg?width=1200");
  assert.deepEqual(sources.fanart, { status: "ok", count: 2 });
  assert.deepEqual(sources.tvdb, { status: "no_key", count: 0 });
  assert.equal(sources.tvoe.count, 1);
});

test("TheTVDB logs in once, finds the series and keeps textless backgrounds for backdrops", async () => {
  let logins = 0;
  const fetchImpl = routedFetch([
    ["https://api4.thetvdb.com/v4/login", () => { logins += 1; return jsonResponse({ data: { token: "t" } }); }],
    ["https://api4.thetvdb.com/v4/series/81189/artworks", {
      data: { artworks: [
        { type: 3, image: "https://artworks.thetvdb.com/a.jpg", thumbnail: "https://artworks.thetvdb.com/a_t.jpg",
          language: null, includesText: false, width: 1920, height: 1080, score: 5 },
        { type: 3, image: "https://artworks.thetvdb.com/b.jpg", language: "eng", includesText: true },
        { type: 2, image: "https://artworks.thetvdb.com/p.jpg", language: "rus" },
      ] },
    }],
  ]);
  const env = memoryEnv();
  const doc = { kind: "show", ids: { tvdb: { value: "81189" } }, artwork: {} };
  const backdrops = await extraImageFiles(env, 1, doc, "backdrop", { fetch: fetchImpl, keys: { tvdb: "x" } });
  assert.deepEqual(backdrops.files.map((f) => f.url), ["https://artworks.thetvdb.com/a.jpg"]);
  assert.equal(backdrops.files[0].preview, "https://artworks.thetvdb.com/a_t.jpg");
  const covers = await extraImageFiles(env, 1, doc, "cover", { fetch: fetchImpl, keys: { tvdb: "x" } });
  assert.deepEqual(covers.files.map((f) => [f.url, f.lang]), [["https://artworks.thetvdb.com/b.jpg", "en"]]);
  const posters = await extraImageFiles(env, 1, doc, "poster", { fetch: fetchImpl, keys: { tvdb: "x" } });
  assert.deepEqual(posters.files.map((f) => f.lang), ["ru"]);
  assert.equal(logins, 1);
});

test("a source that fails or has no key does not hold the others", async () => {
  const fetchImpl = routedFetch([
    ["https://webservice.fanart.tv/", () => new Response("down", { status: 503 })],
  ]);
  const { files, sources } = await extraImageFiles(memoryEnv(), 7, movieDoc, "poster", {
    fetch: fetchImpl, keys: { fanart: "k" },
  });
  assert.deepEqual(files, []);
  assert.equal(sources.fanart.status, "failed");
  assert.equal(sources.tvdb.status, "no_key");
});

test("urlKey matches a TMDB file across sizes and extensions", () => {
  assert.equal(urlKey("https://image.tmdb.org/t/p/original/abc.svg"),
    urlKey("https://image.tmdb.org/t/p/w500/abc.png"));
  assert.notEqual(urlKey("https://avatars.mds.yandex.net/get-kinopoisk-image/1/a/orig"),
    urlKey("https://avatars.mds.yandex.net/get-kinopoisk-image/1/b/orig"));
});

function admin(path, { body, raw, type = "application/json" } = {}) {
  return new Request(`https://worker.test${path}`, {
    method: "POST",
    headers: { Authorization: "Bearer secret", "Content-Type": type },
    body: raw ?? (body == null ? undefined : JSON.stringify(body)),
  });
}

test("images?sources=1 answers for a title TMDB does not know", async () => {
  const env = memoryEnv({
    "title:kinopub:9": { kind: "movie", ids: {}, artwork: {
      poster: [{ source: "kinopoisk", url: "https://kinopoiskapiunofficial.tech/images/posters/kp/1.jpg", lang: "ru" }],
    } },
  });
  const saved = globalThis.fetch;
  globalThis.fetch = routedFetch([]);
  try {
    const response = await handleAdmin(admin("/admin/kinopub/9/images?kind=poster&sources=1"), env);
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.tmdb, null);
    assert.equal(body.ru[0].source, "kinopoisk");
    assert.deepEqual(body.sources.find((s) => s.id === "tmdb"), { id: "tmdb", count: 0, status: "no_id" });
    assert.equal(Object.keys(body).at(-1), "sources");
    // Without the flag the old contract stands.
    const old = await handleAdmin(admin("/admin/kinopub/9/images?kind=poster"), env);
    assert.equal(old.status, 400);
  } finally {
    globalThis.fetch = saved;
  }
});

test("an upload is stored once, served immutable and pinned for its language", async () => {
  const env = memoryEnv();
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);
  const response = await handleAdmin(
    admin("/admin/kinopub/5/upload?kind=poster&lang=ru&width=1000&height=1500", { raw: png, type: "image/png" }), env);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.match(body.url, /^https:\/\/worker\.test\/img\/upload\/[0-9a-f]{64}\.png$/);
  const doc = env.documents["title:kinopub:5"];
  assert.deepEqual(doc.artwork.poster.map((a) => [a.source, a.lang, a.pinned, a.width]), [["upload", "ru", true, 1000]]);
  assert.equal(doc.uploads[0].url, body.url);

  const served = await serveUpload(new Request(body.url), env);
  assert.equal(served.status, 200);
  assert.equal(served.headers.get("Content-Type"), "image/png");
  assert.match(served.headers.get("Cache-Control"), /immutable/);
  assert.deepEqual(new Uint8Array(await served.arrayBuffer()), png);

  const text = await handleAdmin(admin("/admin/kinopub/5/upload?kind=poster", { raw: "hello", type: "text/plain" }), env);
  assert.equal(text.status, 415);
});

test("keys are saved in KV, reported by name and removed with an empty string", async () => {
  const env = memoryEnv();
  const saved = await (await handleAdmin(admin("/admin/keys", { body: { fanart: " abc ", tvdb: "def" } }), env)).json();
  assert.deepEqual(saved.configured.sort(), ["fanart", "tvdb"]);
  assert.equal(env.documents["config:source-keys"].fanart, "abc");
  const removed = await (await handleAdmin(admin("/admin/keys", { body: { tvdb: "" } }), env)).json();
  assert.deepEqual(removed.configured, ["fanart"]);
});
