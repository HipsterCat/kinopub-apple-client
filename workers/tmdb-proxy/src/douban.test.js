import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { genreSlug, handleDouban, project, signature } from "./douban.js";

const originalFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = originalFetch; });

// Frodo's answers for The Shawshank Redemption, as Sasha's probe got them (2026-11-09).
const searchItem = {
  layout: "subject", target_type: "movie", target_id: "1292052",
  target: { id: "1292052", title: "肖申克的救赎", year: "1994",
            rating: { count: 3363365, max: 10, star_count: 5.0, value: 9.7 } },
};
const ratingStats = {
  doing_count: 95, done_count: 5784685, wish_count: 522249,
  stats: [0.0011, 0.001, 0.0136, 0.1303, 0.8539],
  type_ranks: [{ rank: 0.99, type: "犯罪片" }, { rank: 0.99, type: "剧情片" }, { rank: 0.5, type: "未知片" }],
};

function kvEnv(documents = {}) {
  return {
    DOUBAN_API_KEY: "test-key",
    DOUBAN_API_SECRET: "test-secret",
    DOCUMENTS: {
      async get(key) { return documents[key] ?? null; },
      async put(key, value) { documents[key] = JSON.parse(value); },
    },
  };
}

test("signs the way the Python client does", async () => {
  // Python: base64(hmac_sha1("test-secret", "GET&" + quote(path, safe="") + "&1700000000"))
  assert.equal(await signature("test-secret", "GET", "/api/v2/movie/1292052/rating", "1700000000"),
               "+BIXQ/RXx6oD27I1QvRbc+bJ+Wg=");
});

test("the answer keeps numbers and English genres only", () => {
  const title = project(searchItem, ratingStats);
  assert.equal(title.id, "1292052");
  assert.equal(title.url, "https://movie.douban.com/subject/1292052/");
  assert.deepEqual(title.rating, { value: 9.7, votes: 3363365 });
  assert.equal(title.distribution.length, 5);
  assert.equal(title.watched, 5784685);
  assert.equal(title.wantToWatch, 522249);
  assert.deepEqual(title.ranks, [{ genre: "crime", betterThan: 0.99 }, { genre: "drama", betterThan: 0.99 }]);
  assert.equal(JSON.stringify(title).includes("肖申克"), false);
  assert.equal(genreSlug("剧情剧"), "drama");
});

test("a found title is fetched once and then served from KV", async () => {
  const documents = {};
  const calls = [];
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    const body = String(url).includes("/search/") ? { items: [searchItem] } : ratingStats;
    return new Response(JSON.stringify(body), { status: 200 });
  };
  const env = kvEnv(documents);
  const url = new URL("https://example.test/v1/douban/by/imdb/tt0111161");
  const first = await handleDouban(url, env);
  assert.equal(first.status, 200);
  assert.equal((await first.json()).rating.value, 9.7);
  assert.equal(calls.length, 2);
  assert.ok(calls[0].includes("q=tt0111161") && calls[0].includes("_sig="));

  const second = await handleDouban(url, env);
  assert.equal(second.status, 200);
  assert.equal(calls.length, 2);
});

test("an unknown title is a cached miss; a refused key is not", async () => {
  const documents = {};
  globalThis.fetch = async () => new Response(JSON.stringify({ items: [] }), { status: 200 });
  const env = kvEnv(documents);
  const miss = await handleDouban(new URL("https://example.test/v1/douban/by/imdb/tt9999999"), env);
  assert.equal(miss.status, 404);
  assert.equal(documents["douban:imdb:tt9999999"].title, null);

  globalThis.fetch = async () => new Response("{}", { status: 403 });
  const refused = await handleDouban(new URL("https://example.test/v1/douban/by/imdb/tt0111161"), env);
  assert.equal(refused.status, 502);
  assert.equal(documents["douban:imdb:tt0111161"], undefined);
});

test("bad ids and missing secrets", async () => {
  assert.equal((await handleDouban(new URL("https://example.test/v1/douban/by/imdb/123"), kvEnv())).status, 400);
  const env = kvEnv();
  delete env.DOUBAN_API_SECRET;
  assert.equal((await handleDouban(new URL("https://example.test/v1/douban/by/imdb/tt0111161"), env)).status, 500);
});
