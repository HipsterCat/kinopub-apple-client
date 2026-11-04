import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { handleSeasons } from "./seasons.js";

const originalFetch = globalThis.fetch;

function kvEnv(documents = {}, extra = {}) {
  const puts = [];
  return {
    puts,
    ...extra,
    DOCUMENTS: {
      async get(key, opts) {
        const raw = documents[key];
        if (raw == null) return null;
        return opts?.type === "json" ? raw : JSON.stringify(raw);
      },
      async put(key, value) {
        puts.push({ key, value: JSON.parse(value) });
        documents[key] = JSON.parse(value);
      },
    },
  };
}

function seasonsRequest(path, lang) {
  const headers = {};
  if (lang) headers["Accept-Language"] = lang;
  return new Request(`https://example.test${path}`, { headers });
}

afterEach(() => {
  globalThis.fetch = originalFetch;
});

test("a range wider than four seasons is rejected", async () => {
  const response = await handleSeasons(
    seasonsRequest("/v1/title/by/kinopub/82852/seasons/1-5"),
    kvEnv(),
  );
  assert.equal(response.status, 400);
});

test("Russian response keeps Russian copy and does not attach the English title", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      seasons: [{
        number: 2,
        name: { ru: "Второй", en: "Second" },
        overview: { ru: "о сезоне", en: "about the season" },
        episodes: [{
          number: 1,
          name: { ru: "Финал", en: "Finale" },
          overview: { ru: "час", en: "an hour" },
          runtime_min: 60,
          air_date: "2026-05-01",
          thumbnail: "https://image.tmdb.org/t/p/original/still.jpg",
          imdb: { value: 8.4, votes: 1200 },
          skip_intro: true,
          skip_credits: true,
          previewStartTime: 12,
          creditsStartTime: 3400,
        }],
      }],
    },
  });
  const response = await handleSeasons(
    seasonsRequest("/v1/title/by/kinopub/82852/seasons/2&3"),
    env,
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.lang, "ru");
  assert.equal(body.seasons.length, 2);
  assert.equal(body.seasons[0].name, "Второй");
  assert.equal(body.seasons[0].overview, "о сезоне");
  assert.equal(JSON.stringify(body).includes("Second"), false);
  assert.equal(JSON.stringify(body).includes("Finale"), false);
  const episode = body.seasons[0].episodes[0];
  assert.deepEqual(episode.imdb, { value: 8.4, votes: 1200 });
  assert.equal(episode.runtime_min, 60);
  assert.equal(episode.skip_intro, true);
  assert.equal(episode.skip_credits, true);
  assert.equal(episode.still, "/img/thumbnail/by/kinopub/82852?s=2&e=1");
  assert.equal("previewStartTime" in episode, false);
  assert.equal("creditsStartTime" in episode, false);
  assert.equal(body.seasons[1].episodes.length, 0);
});

test("English does not receive the Russian title stored as a bare string", async () => {
  const env = kvEnv({
    "title:kinopub:82852": {
      seasons: [{
        number: 1,
        name: "Первый",
        synopsis: "русское описание",
        episodes: [{ number: 1, name: "Серия", runtime_min: 44 }],
      }],
    },
  });
  const response = await handleSeasons(
    seasonsRequest("/v1/title/by/kinopub/82852/seasons/1", "en"),
    env,
  );
  const body = await response.json();
  assert.equal(body.lang, "en");
  assert.equal(body.seasons[0].name, null);
  assert.equal(body.seasons[0].overview, null);
  assert.equal(body.seasons[0].episodes[0].name, null);
  assert.equal(body.seasons[0].episodes[0].runtime_min, 44);
});

test("a missing TMDB season is fetched for the asked language and remembered", async () => {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), auth: init.headers.Authorization });
    return new Response(JSON.stringify({
      name: "Season 2",
      overview: "the season",
      episodes: [{
        episode_number: 4,
        name: "The hour",
        overview: "it runs long",
        runtime: 61,
        air_date: "2026-05-02",
        still_path: "/hour.jpg",
      }],
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  };
  const env = kvEnv({
    "title:kinopub:119662": { ids: { tmdb: { value: "tv/291084" } }, seasons: [] },
  }, { TMDB_READ_TOKEN: "test-token" });

  const response = await handleSeasons(
    seasonsRequest("/v1/title/by/kinopub/119662/seasons/2", "en"),
    env,
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.seasons[0].name, "Season 2");
  assert.equal(body.seasons[0].episodes[0].runtime_min, 61);
  assert.equal(body.seasons[0].episodes[0].imdb, null);
  assert.equal(body.seasons[0].episodes[0].still, "/img/thumbnail/by/kinopub/119662?s=2&e=4");
  assert.equal(calls.length, 1);
  assert.match(calls[0].url, /\/tv\/291084\/season\/2\?language=en-US$/);
  assert.equal(calls[0].auth, "Bearer test-token");

  const again = await handleSeasons(
    seasonsRequest("/v1/title/by/kinopub/119662/seasons/2", "en"),
    env,
  );
  assert.equal(again.status, 200);
  assert.equal(calls.length, 1);
  const stored = env.puts.at(-1).value.seasons[0];
  assert.equal(stored.episodes[0].thumbnail, "https://image.tmdb.org/t/p/original/hour.jpg");
  assert.deepEqual(stored.fetched_langs, ["en"]);
});

test("a fetched episode keeps its TMDB id, rating and finale badge", async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({
    id: 60813,
    name: "Сезон 1",
    overview: "о сезоне",
    poster_path: "/season.jpg",
    vote_average: 8.2,
    episodes: [{
      id: 984889,
      episode_number: 9,
      episode_type: "finale",
      name: "Финал",
      overview: "",
      runtime: 80,
      air_date: "2014-04-25",
      still_path: "/final.jpg",
      vote_average: 9.1,
      vote_count: 12,
    }],
  }), { status: 200, headers: { "Content-Type": "application/json" } });
  const env = kvEnv({
    "title:kinopub:16164": {
      ids: { tmdb: { value: "tv/60823" } },
      seasons: [{ number: 1, name: { ru: "Сезон 1" }, episodes: [] }],
    },
  }, { TMDB_READ_TOKEN: "test-token" });
  const response = await handleSeasons(
    seasonsRequest("/v1/title/by/kinopub/16164/seasons/1"),
    env,
  );
  assert.equal(response.status, 200);
  const episode = (await response.json()).seasons[0].episodes[0];
  assert.equal(episode.tmdb.value, 9.1);
  assert.equal(episode.tmdb.votes, 12);
  assert.equal(episode.season_finale, true);
  const stored = env.puts.at(-1).value.seasons[0];
  assert.equal(stored.id, 60813);
  assert.equal(stored.episodes[0].id, 984889);
  assert.equal(stored.episodes[0].season_id, 60813);
  assert.deepEqual(stored.fetched_langs, ["ru"]);
  assert.equal(stored.poster.ru, "https://image.tmdb.org/t/p/original/season.jpg");
});

test("an unwarmed title 404s without calling TMDB", async () => {
  let called = false;
  globalThis.fetch = async () => { called = true; return new Response("no", { status: 500 }); };
  const response = await handleSeasons(
    seasonsRequest("/v1/title/by/kinopub/1/seasons/1"),
    kvEnv({}, { TMDB_READ_TOKEN: "test-token" }),
  );
  assert.equal(response.status, 404);
  assert.equal(called, false);
});
