import assert from "node:assert/strict";
import { test } from "node:test";
import { handleCard, publishCard } from "./card.js";

function catalog(tables) {
  return {
    prepare(sql) {
      const statement = {
        sql,
        bind() { return statement; },
      };
      return statement;
    },
    async batch(statements) {
      return statements.map((statement) => ({ results: tables[keyOf(statement.sql)] || [] }));
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
