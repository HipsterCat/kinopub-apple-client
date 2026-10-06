-- Projection of a tvoe.live dump. The JSON in tvoe_data/ is the source.
-- This is not the merged metadata catalog: tvoe joins kino.pub only later.
--
-- A season is not an object in the API. videos.seasons is an array of arrays.
-- `video.season` is that array index, 1-based. Episode number is `position`
-- inside the season array. The payload has no season poster or synopsis.

CREATE TABLE title (
  id                TEXT PRIMARY KEY,
  category          TEXT NOT NULL,
  name              TEXT,
  orig_name         TEXT,
  short_desc        TEXT,
  full_desc         TEXT,
  age_level         INTEGER,
  date_released     TEXT,
  poster_date       TEXT,
  rating            REAL,
  duration          REAL,
  seasons_count     INTEGER,
  url               TEXT,
  genre_name        TEXT,
  badge_type        TEXT,
  badge_start       TEXT,
  badge_finish      TEXT,
  poster_src        TEXT,
  poster_cdn        TEXT,
  cover_src         TEXT,
  cover_cdn         TEXT,
  logo_src          TEXT,
  logo_cdn          TEXT,
  ultra_hd          INTEGER NOT NULL,
  in_subscribe_soon INTEGER NOT NULL,
  is_new_season     INTEGER NOT NULL,
  is_favorite       INTEGER NOT NULL
);

CREATE TABLE title_genre (
  title_id TEXT NOT NULL REFERENCES title(id),
  ord      INTEGER NOT NULL,
  alias    TEXT,
  name     TEXT,
  PRIMARY KEY (title_id, ord)
);
CREATE INDEX idx_title_genre_alias ON title_genre(alias);

CREATE TABLE title_country (
  title_id TEXT NOT NULL REFERENCES title(id),
  ord      INTEGER NOT NULL,
  name     TEXT NOT NULL,
  PRIMARY KEY (title_id, ord)
);

CREATE TABLE title_similar (
  title_id   TEXT NOT NULL REFERENCES title(id),
  ord        INTEGER NOT NULL,
  similar_id TEXT NOT NULL,
  PRIMARY KEY (title_id, ord)
);

CREATE TABLE credit (
  title_id TEXT NOT NULL REFERENCES title(id),
  ord      INTEGER NOT NULL,
  name     TEXT,
  role     TEXT,
  PRIMARY KEY (title_id, ord)
);

-- One encode: the film file, an episode, or a trailer.
-- audio, subtitles and qualities stay JSON. They are lists of small objects
-- and the raw row in title_raw still has them verbatim.
CREATE TABLE video (
  id              TEXT PRIMARY KEY,
  title_id        TEXT NOT NULL REFERENCES title(id),
  kind            TEXT NOT NULL,          -- feature | episode | trailer
  season          INTEGER,
  position        INTEGER NOT NULL,
  name            TEXT,
  duration        REAL,
  version         INTEGER,
  src             TEXT,
  thumbnail       TEXT,
  thumbnail_url   TEXT,
  published       INTEGER,
  has_mp4         INTEGER,
  release_date    TEXT,
  preview_start   REAL,
  preview_end     REAL,
  credits_start   REAL,
  credits_end     REAL,
  replay_start    REAL,
  replay_end      REAL,
  qualities       TEXT,
  audio           TEXT,
  subtitles       TEXT
);
CREATE INDEX idx_video_title ON video(title_id, kind, season, position);

CREATE TABLE review (
  id           TEXT PRIMARY KEY,
  title_id     TEXT NOT NULL REFERENCES title(id),
  rating       INTEGER,
  body         TEXT,
  updated_at   TEXT,
  user_id      TEXT,
  user_name    TEXT,
  first_name   TEXT,
  last_name    TEXT,
  avatar       TEXT
);
CREATE INDEX idx_review_title ON review(title_id);

CREATE TABLE short (
  id                TEXT PRIMARY KEY,
  title             TEXT,
  cover_src         TEXT,
  cover_cdn         TEXT,
  video_file_src    TEXT,
  video_hls_src     TEXT,
  thumbnail_src     TEXT,
  thumbnail_cdn     TEXT,
  is_pinned         INTEGER NOT NULL,
  link              TEXT,
  button_text       TEXT,
  views_count       INTEGER,
  published_at      TEXT,
  view_at           TEXT,
  movie_id          TEXT,
  movie_title       TEXT,
  movie_logo        TEXT,
  movie_logo_cdn    TEXT,
  movie_category    TEXT,
  movie_genre       TEXT,
  movie_age_level   INTEGER
);
CREATE INDEX idx_short_movie ON short(movie_id);

-- The detail file as stored, so a field the columns do not name is still here.
CREATE TABLE title_raw (
  title_id TEXT PRIMARY KEY REFERENCES title(id),
  body     TEXT NOT NULL
);

CREATE TABLE source_meta (
  key   TEXT PRIMARY KEY,
  value TEXT
);
