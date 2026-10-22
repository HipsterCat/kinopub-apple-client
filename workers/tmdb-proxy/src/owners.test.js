import assert from "node:assert/strict";
import { test } from "node:test";
import { handleOwners, kinopoiskKeys } from "./owners.js";

function ctx() {
  return { waitUntil() {} };
}

function installFetch(handler) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    return handler(String(url), init, calls.length);
  };
  return calls;
}

test("kinopoisk keys keep only non-empty owner secrets", () => {
  assert.deepEqual(kinopoiskKeys({
    KINOPOISK_API_KEY: " first ",
    KINOPOISK_API_KEY_2: "",
  }), ["first"]);
  assert.deepEqual(kinopoiskKeys({}), []);
});

test("omdb injects the worker key and drops a caller key", async () => {
  const calls = installFetch(() => new Response(JSON.stringify({ Response: "True", Title: "X" }), {
    status: 200,
    headers: { "content-type": "application/json" },
  }));
  const url = new URL("https://example.test/omdb?i=tt0111161&plot=short&apikey=from-client");
  const response = await handleOwners(url, new Request(url), { OMDB_API_KEY: "server-key" }, ctx());
  assert.equal(response.status, 200);
  assert.equal(calls.length, 1);
  const sent = new URL(calls[0].url);
  assert.equal(sent.origin + sent.pathname, "https://www.omdbapi.com/");
  assert.equal(sent.searchParams.get("apikey"), "server-key");
  assert.equal(sent.searchParams.get("i"), "tt0111161");
  assert.equal(calls[0].init.headers["X-API-KEY"], undefined);
});

test("omdb does not cache a quota error", async () => {
  const stored = [];
  globalThis.caches = {
    default: {
      async match() { return null; },
      async put(key, response) { stored.push({ key: key.url, status: response.status, body: await response.clone().text() }); },
    },
  };
  installFetch(() => new Response(JSON.stringify({
    Response: "False",
    Error: "Request limit reached!",
  }), { status: 200, headers: { "content-type": "application/json" } }));
  const url = new URL("https://example.test/omdb?i=tt1");
  const response = await handleOwners(url, new Request(url), { OMDB_API_KEY: "server-key" }, ctx());
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(stored.length, 0);
  delete globalThis.caches;
});

test("omdb without a secret is a configuration error", async () => {
  const url = new URL("https://example.test/omdb?i=tt1");
  const response = await handleOwners(url, new Request(url), {}, ctx());
  assert.equal(response.status, 500);
  const body = await response.json();
  assert.equal(body.error, "misconfigured");
});

test("kinopoisk retries the second key after a 402", async () => {
  const calls = installFetch((_url, _init, n) => new Response("{}", {
    status: n === 1 ? 402 : 200,
    headers: { "content-type": "application/json" },
  }));
  const url = new URL("https://example.test/kp/api/v2.2/films/326");
  const response = await handleOwners(url, new Request(url), {
    KINOPOISK_API_KEY: "key-a",
    KINOPOISK_API_KEY_2: "key-b",
  }, ctx());
  assert.equal(response.status, 200);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].url, "https://kinopoiskapiunofficial.tech/api/v2.2/films/326");
  assert.equal(calls[0].init.headers["X-API-KEY"], "key-a");
  assert.equal(calls[1].init.headers["X-API-KEY"], "key-b");
});

test("tvoe api and site stay on their own hosts", async () => {
  const calls = installFetch(() => new Response("{}", {
    status: 200,
    headers: { "content-type": "application/json" },
  }));
  const api = new URL("https://example.test/tvoe/api/v2/catalog?categoryAlias=films&limit=1");
  const apiResponse = await handleOwners(api, new Request(api), {}, ctx());
  assert.equal(apiResponse.status, 200);
  assert.equal(calls[0].url, "https://api.tvoe.live/v2/catalog?categoryAlias=films&limit=1");

  const site = new URL("https://example.test/tvoe/site/_next/data/build/p/slug.json");
  await handleOwners(site, new Request(site), {}, ctx());
  assert.equal(calls[1].url, "https://tvoe.live/_next/data/build/p/slug.json");
  assert.match(calls[1].init.headers["User-Agent"], /Chrome/);
});

test("a foreign redirect is not forwarded", async () => {
  installFetch(() => new Response("", {
    status: 302,
    headers: { location: "https://evil.example/steal" },
  }));
  const url = new URL("https://example.test/tvoe/api/v2/catalog");
  const response = await handleOwners(url, new Request(url), {}, ctx());
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), null);
});

test("other paths are not this proxy", async () => {
  const url = new URL("https://example.test/3/movie/1");
  assert.equal(await handleOwners(url, new Request(url), {}, ctx()), null);
});
