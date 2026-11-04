-- Curated card. The local card-2.db is the source; this is what the worker reads.
-- kv.db stays the full archive. Re-running upload_card2.py replaces these tables.

DROP TABLE IF EXISTS c2_billing_role;
DROP TABLE IF EXISTS c2_billing;
DROP TABLE IF EXISTS c2_cast_count;
DROP TABLE IF EXISTS c2_image;
DROP TABLE IF EXISTS c2_top_episode;
DROP TABLE IF EXISTS c2_network;
DROP TABLE IF EXISTS c2_season;
DROP TABLE IF EXISTS c2_person;
DROP TABLE IF EXISTS c2_card;

CREATE TABLE c2_card (
  kinopub_id INTEGER PRIMARY KEY,
  type TEXT,
  title_ru TEXT,
  title_original TEXT,
  year INTEGER,
  release_date TEXT,
  runtime_min INTEGER,
  countries TEXT,
  genres TEXT,
  short_ru TEXT,
  slogan TEXT,
  imdb_id TEXT,
  tmdb_id TEXT,
  tvdb_id TEXT,
  kinopoisk_id TEXT,
  kinopoisk_hd_id TEXT,
  tvoe_id TEXT,
  wikidata_id TEXT,
  myshows_id TEXT,
  poster_ru TEXT,
  poster_en TEXT,
  cover_ru TEXT,
  cover_en TEXT,
  backdrop TEXT,
  logo_ru TEXT,
  logo_en TEXT,
  imdb REAL,
  imdb_votes INTEGER,
  kinopoisk REAL,
  kinopoisk_votes INTEGER,
  tvoe REAL,
  tvoe_votes INTEGER,
  tvoe_reviews INTEGER,
  tmdb REAL,
  tmdb_votes INTEGER,
  rotten_tomatoes REAL,
  rotten_tomatoes_votes INTEGER,
  metacritic REAL,
  metacritic_votes INTEGER,
  good_review REAL,
  good_review_votes INTEGER,
  film_critics REAL,
  film_critics_votes INTEGER,
  rf_critics REAL,
  rf_critics_votes INTEGER,
  rating_await REAL,
  rating_await_count INTEGER,
  rating_mpaa TEXT,
  rating_age_ru INTEGER,
  reviews_count INTEGER,
  reviews_positive INTEGER,
  reviews_negative INTEGER,
  reviews_neutral INTEGER,
  synopsis_ru TEXT,
  tagline_ru TEXT,
  status TEXT,
  updated_at TEXT
);
CREATE INDEX c2_card_imdb ON c2_card(imdb_id);
CREATE INDEX c2_card_tmdb ON c2_card(tmdb_id);

CREATE TABLE c2_person (
  person_id INTEGER PRIMARY KEY,
  name_ru TEXT,
  name_en TEXT,
  gender INTEGER,
  popularity REAL,
  known_for_department TEXT,
  profile_url TEXT
);

CREATE TABLE c2_billing (
  kinopub_id INTEGER NOT NULL,
  section TEXT NOT NULL,
  position INTEGER NOT NULL,
  person_id INTEGER,
  name_ru TEXT,
  name_en TEXT,
  character TEXT,
  job TEXT,
  episode_count INTEGER,
  popularity REAL,
  PRIMARY KEY (kinopub_id, section, position)
);

CREATE TABLE c2_billing_role (
  kinopub_id INTEGER NOT NULL,
  section TEXT NOT NULL,
  position INTEGER NOT NULL,
  role_ord INTEGER NOT NULL,
  credit_id TEXT,
  character TEXT,
  job TEXT,
  episode_count INTEGER,
  PRIMARY KEY (kinopub_id, section, position, role_ord)
);

CREATE TABLE c2_cast_count (
  kinopub_id INTEGER NOT NULL,
  section TEXT NOT NULL,
  total INTEGER NOT NULL,
  PRIMARY KEY (kinopub_id, section)
);

CREATE TABLE c2_image (
  kinopub_id INTEGER NOT NULL,
  kind TEXT NOT NULL,
  lang TEXT,
  url TEXT NOT NULL,
  source TEXT,
  width INTEGER,
  height INTEGER,
  person_id INTEGER,
  season INTEGER,
  episode INTEGER
);
CREATE INDEX c2_image_title ON c2_image(kinopub_id);

CREATE TABLE c2_top_episode (
  kinopub_id INTEGER NOT NULL,
  rank INTEGER NOT NULL,
  season INTEGER NOT NULL,
  number INTEGER NOT NULL,
  name_ru TEXT,
  name_en TEXT,
  tmdb_id INTEGER,
  tmdb_value REAL,
  tmdb_votes INTEGER,
  imdb_value REAL,
  imdb_votes INTEGER,
  season_finale INTEGER,
  PRIMARY KEY (kinopub_id, rank)
);

CREATE TABLE c2_network (
  kinopub_id INTEGER NOT NULL,
  tmdb_id INTEGER NOT NULL,
  name TEXT,
  logo_url TEXT,
  origin_country TEXT,
  PRIMARY KEY (kinopub_id, tmdb_id)
);

CREATE TABLE c2_season (
  kinopub_id INTEGER NOT NULL,
  number INTEGER NOT NULL,
  name TEXT,
  episodes INTEGER,
  air_date TEXT,
  end_date TEXT,
  poster TEXT,
  PRIMARY KEY (kinopub_id, number)
);

CREATE TABLE c2_episode (
  kinopub_id INTEGER NOT NULL,
  season INTEGER NOT NULL,
  number INTEGER NOT NULL,
  name_ru TEXT,
  name_en TEXT,
  runtime_min INTEGER,
  air_date TEXT,
  still TEXT,
  imdb_id TEXT,
  tmdb_id INTEGER,
  season_tmdb_id INTEGER,
  episode_type TEXT,
  season_finale INTEGER,
  tmdb_value REAL,
  tmdb_votes INTEGER,
  imdb_value REAL,
  imdb_votes INTEGER,
  PRIMARY KEY (kinopub_id, season, number)
);
