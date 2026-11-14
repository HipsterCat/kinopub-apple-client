import assert from "node:assert/strict";
import { test } from "node:test";
import { handleCard, publishCard } from "./card.js";
import { handleTitleV2 } from "./title.js";

function catalog(tables) {
  return {
    prepare(sql) {
      const statement = {
        sql,
        bound: [],
        bind(...args) {
          statement.bound = args;
          return statement;
        },
      };
      return statement;
    },
    async batch(statements) {
      return statements.map((statement) => {
        let rows = tables[keyOf(statement.sql)] || [];
        const bound = statement.bound?.[0];
        const sql = statement.sql;
        if (bound != null && sql.includes("c2_card") && sql.includes("WHERE")) {
          if (sql.includes("imdb_id")) {
            rows = rows.filter((row) => String(row.imdb_id) === String(bound));
          } else if (sql.includes("kinopoisk_id")) {
            rows = rows.filter((row) => String(row.kinopoisk_id) === String(bound));
          } else if (sql.includes("kinopub_id")) {
            rows = rows.filter((row) => Number(row.kinopub_id) === Number(bound));
          }
        }
        return { results: rows };
      });
    },
  };
}

function keyOf(sql) {
  if (sql.includes("c2_card")) return "card";
  if (sql.includes("c2_billing_role")) return "roles";
  if (sql.includes("c2_billing")) return "billing";
  if (sql.includes("c2_cast_count")) return "counts";
  if (sql.includes("c2_image")) return "images";
  if (sql.includes("c2_top_episode")) return "episodes";
  if (sql.includes("c2_episode")) return "rows";
  if (sql.includes("c2_network")) return "networks";
  if (sql.includes("c2_season")) return "seasons";
  return "";
}

test("a missing card is a 404", async () => {
  const response = await handleCard(
    new URL("https://example.test/v1/card/by/kinopub/7"),
    { CATALOG: catalog({}) },
  );
  assert.equal(response.status, 404);
});

test("the card returns featured people, counts and a top episode", async () => {
  const response = await handleCard(
    new URL("https://example.test/v1/card/by/kinopub/1"),
    {
      CATALOG: catalog({
        card: [{
          kinopub_id: 1, type: "movie", title_ru: "Трансформеры", title_original: "Transformers",
          year: 2007, status: "Released", tagline_ru: null, synopsis_ru: "Война.",
          imdb_id: "tt0418279", tmdb_id: "movie/1858", tvdb_id: null, kinopoisk_id: "81288",
          kinopoisk_hd_id: null, tvoe_id: null, wikidata_id: null, myshows_id: null,
          imdb: 7.0, imdb_votes: 100, kinopoisk: null, kinopoisk_votes: null,
          tmdb: 6.8, tmdb_votes: 1000, tvoe: null, tvoe_votes: null,
        }],
        billing: [{
          section: "star", position: 0, person_id: 42, name_ru: "Шайа ЛаБаф", name_en: "Shia LaBeouf",
          character: "Sam", job: null, episode_count: null, popularity: 3.3,
          gender: 2, profile_url: "https://image/face.jpg", known_for_department: "Acting",
        }],
        roles: [{
          section: "star", position: 0, role_ord: 0, credit_id: "c1", character: "Sam",
          job: null, episode_count: null,
        }],
        counts: [{ section: "regular", total: 90 }, { section: "guest", total: 0 }],
        images: [{ kind: "poster", lang: "ru", url: "https://image/p.jpg", source: "tmdb", width: 1, height: 2, person_id: null, season: null, episode: null }],
        episodes: [{ rank: 1, season: 1, number: 1, name_ru: null, name_en: null, tmdb_id: null, tmdb_value: null, tmdb_votes: null, imdb_value: null, imdb_votes: null, season_finale: 0 }],
        networks: [],
        seasons: [{ number: 1, name: "Сезон 1", episodes: 9, air_date: "2014-02-28", end_date: null, poster: null }],
        rows: [{ season: 1, number: 1, name_ru: "Выпуск", name_en: null, runtime_min: 90, air_date: "2014-02-28", still: "https://image/still.jpg", imdb_id: null, tmdb_id: 5, tmdb_value: 8, tmdb_votes: 10, imdb_value: null, imdb_votes: null, season_finale: 0 }],
      }),
    },
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.title.ru, "Трансформеры");
  assert.equal(body.billing.star[0].name_ru, "Шайа ЛаБаф");
  assert.equal(body.billing.star[0].roles[0].character, "Sam");
  assert.equal(body.counts.regular, 90);
  assert.equal(body.ratings.tmdb.value, 6.8);
  assert.equal(body.images[0].kind, "poster");
  assert.equal(body.seasons[0].episodes[0].name_ru, "Выпуск");
  assert.equal(body.seasons[0].episodes[0].still, "/img/thumbnail/by/kinopub/1?s=1&e=1");
  assert.equal(body.seasons[0].episode_count, 9);
});

test("a resolved title writes its episodes into D1", async () => {
  const sql = [];
  const statement = {
    bind() { return statement; },
  };
  const db = {
    prepare(text) {
      sql.push(text);
      return statement;
    },
    async batch() { return []; },
  };
  await publishCard({ CATALOG: db }, "9", {
    built_at: "2026-10-30T00:00:00Z",
    title: { ru: "Шоу", original: "Show" },
    ids: { tmdb: { value: "tv/1" } },
    seasons: [{
      number: 1,
      name: { ru: "Сезон" },
      episode_cnt: 1,
      episodes: [{ number: 1, name: { ru: "Пилот" }, id: 5, tmdb: { value: 8, votes: 10 } }],
    }],
  });
  assert.equal(sql.some((item) => item.includes("INSERT INTO c2_episode")), true);
  assert.equal(sql.some((item) => item.includes("DELETE FROM c2_episode")), true);
});

const TRANSFORMERS = {
  kinopub_id: 1, type: "movie", title_ru: "Трансформеры", title_original: "Transformers",
  year: 2007, status: "Released", tagline_ru: null, synopsis_ru: "Война.",
  imdb_id: "tt0418279", tmdb_id: "movie/1858", tvdb_id: null, kinopoisk_id: "81288",
  kinopoisk_hd_id: null, tvoe_id: null, wikidata_id: null, myshows_id: null,
  imdb: 7.0, imdb_votes: 100, kinopoisk: null, kinopoisk_votes: null,
  tmdb: 6.8, tmdb_votes: 1000, tvoe: null, tvoe_votes: null,
};

function tmdbJson(body) {
  return new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } });
}

function movieDetails() {
  return {
    id: 1858, title: "Трансформеры", original_title: "Transformers",
    overview: "Война.", vote_average: 6.8, vote_count: 1000, status: "Released",
    runtime: 144, images: {}, videos: { results: [] }, external_ids: {},
  };
}

test("GET /v2/title/by/kinopub/{id} without query is still the stored card", async () => {
  const response = await handleTitleV2(
    new URL("https://example.test/v2/title/by/kinopub/1"),
    { CATALOG: catalog({ card: [TRANSFORMERS] }) },
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.kinopub_id, 1);
  assert.equal(body.ids.imdb, "tt0418279");
});

test("GET /v2/title/by/kinopub/{id} without a card and without hints is still 404", async () => {
  const response = await handleTitleV2(
    new URL("https://example.test/v2/title/by/kinopub/7"),
    { CATALOG: catalog({}) },
  );
  assert.equal(response.status, 404);
});

test("GET /v2/title finds a stored card by imdb", async () => {
  const response = await handleTitleV2(
    new URL("https://example.test/v2/title?imdb=tt0418279"),
    { CATALOG: catalog({ card: [TRANSFORMERS] }) },
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.kinopub_id, 1);
  assert.equal(body.title.original, "Transformers");
});

test("GET /v2/title finds a stored card by kinopoisk", async () => {
  const response = await handleTitleV2(
    new URL("https://example.test/v2/title?kinopoisk=81288"),
    { CATALOG: catalog({ card: [TRANSFORMERS] }) },
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.kinopub_id, 1);
});

test("GET /v2/title/by/kinopub/{id} with hints still returns the stored card", async () => {
  const original = globalThis.fetch;
  let fetched = 0;
  globalThis.fetch = async () => {
    fetched += 1;
    return new Response("no", { status: 500 });
  };
  try {
    const response = await handleTitleV2(
      new URL("https://example.test/v2/title/by/kinopub/1?imdb=tt0418279&name_original=Transformers"),
      { CATALOG: catalog({ card: [TRANSFORMERS] }), TMDB_READ_TOKEN: "token" },
    );
    assert.equal(response.status, 200);
    assert.equal(fetched, 0);
  } finally {
    globalThis.fetch = original;
  }
});

test("GET /v2/title without identity hints is 400", async () => {
  const response = await handleTitleV2(
    new URL("https://example.test/v2/title"),
    { CATALOG: catalog({}) },
  );
  assert.equal(response.status, 400);
});

test("a cold /v2/title/by/kinopub/{id} matches TMDB from the imdb hint", async () => {
  const documents = {};
  const original = globalThis.fetch;
  globalThis.fetch = async (url) => {
    const href = String(url);
    if (href.includes("/3/find/tt0418279")) {
      return tmdbJson({ movie_results: [{ id: 1858 }], tv_results: [] });
    }
    if (href.includes("/3/movie/1858")) return tmdbJson(movieDetails());
    return new Response("no", { status: 404 });
  };
  try {
    const response = await handleTitleV2(
      new URL("https://example.test/v2/title/by/kinopub/99?imdb=tt0418279&kinopoisk=81288"),
      {
        TMDB_READ_TOKEN: "token",
        CATALOG: catalog({}),
        DOCUMENTS: {
          async get(key, opts) {
            const raw = documents[key];
            if (raw == null) return null;
            return opts?.type === "json" ? raw : JSON.stringify(raw);
          },
          async put(key, value) { documents[key] = JSON.parse(value); },
        },
      },
    );
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.kinopub_id, 99);
    assert.equal(body.ids.imdb, "tt0418279");
    assert.equal(body.ids.tmdb, "movie/1858");
    assert.equal(body.title.original, "Transformers");
  } finally {
    globalThis.fetch = original;
  }
});

test("a cold title without imdb matches by name, year and runtime", async () => {
  const documents = {};
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url) => {
    const href = String(url);
    calls.push(href);
    if (href.includes("/3/search/movie")) {
      return tmdbJson({
        results: [
          { id: 1, title: "Other", original_title: "Other", release_date: "2007-01-01" },
          { id: 1858, title: "Transformers", original_title: "Transformers", release_date: "2007-07-03" },
        ],
      });
    }
    if (/\/3\/movie\/1(?:\?|$)/.test(href)) {
      return tmdbJson({ id: 1, runtime: 90, title: "Other", original_title: "Other", images: {}, videos: { results: [] }, external_ids: {} });
    }
    if (href.includes("/3/movie/1858")) return tmdbJson(movieDetails());
    if (href.includes("/3/search/tv")) return tmdbJson({ results: [] });
    return new Response("no", { status: 404 });
  };
  try {
    const response = await handleTitleV2(
      new URL("https://example.test/v2/title/by/kinopub/99?name_original=Transformers&name_ru=%D0%A2%D1%80%D0%B0%D0%BD%D1%81%D1%84%D0%BE%D1%80%D0%BC%D0%B5%D1%80%D1%8B&year=2007&runtime=144&type=movie"),
      {
        TMDB_READ_TOKEN: "token",
        CATALOG: catalog({}),
        DOCUMENTS: {
          async get(key, opts) {
            const raw = documents[key];
            if (raw == null) return null;
            return opts?.type === "json" ? raw : JSON.stringify(raw);
          },
          async put(key, value) { documents[key] = JSON.parse(value); },
        },
      },
    );
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.ids.tmdb, "movie/1858");
    assert.equal(body.title.original, "Transformers");
    assert.equal(calls.some((item) => item.includes("/3/search/movie")), true);
  } finally {
    globalThis.fetch = original;
  }
});
