#!/usr/bin/env python3
"""One row per kino.pub id: the card that goes to the worker.

    python3 build_card.py

Writes tools/metadata-ingest/data/card.db. Open that in Beekeeper.
The warehouse databases are read, not modified. Nothing here is uploaded.

No source columns, no ranks, no kino.pub vote counts. Year is the one
kino.pub year. A series does not grow a second "started" year beside it.
Full synopses stay in the warehouse. The short line is Kinopoisk's, and
tvoe's when Kinopoisk has none. Every rating has a count column, filled
or not. Seasons and episodes sit in their own tables.
"""

from __future__ import annotations

import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import genres as genre_table  # noqa: E402

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
RECORD = DATA / "record-v2.db"
SNAPSHOT = ROOT.parent / "kinopub-snapshot" / "data" / "snapshot.db"
KINOPOISK = ROOT.parent / "kinopoisk-metadata" / "data" / "kinopoisk.db"
TVOE = ROOT.parent / "tvoe" / "tvoe_data" / "tvoe.sqlite"
OUT = DATA / "card.db"

# value column, then its count. The count is created even when the feed
# sends no votes yet (tvoe, Rotten Tomatoes, Metacritic).
RATINGS = {
    "imdb": ("imdb", "imdb_votes"),
    "kinopoisk": ("kinopoisk", "kinopoisk_votes"),
    "tvoe": ("tvoe", "tvoe_votes"),
    "tmdb": ("tmdb", "tmdb_votes"),
    "rotten_tomatoes": ("rotten_tomatoes", "rotten_tomatoes_votes"),
    "metacritic": ("metacritic", "metacritic_votes"),
    "good_review": ("good_review", "good_review_votes"),
    "film_critics": ("film_critics", "film_critics_votes"),
    "rf_critics": ("rf_critics", "rf_critics_votes"),
}

# The poster URL the worker already uses. Kinopoisk returns a file for an id
# even when the bulk feed has not stored one, so poster_ru is not half empty.
KP_POSTER = "https://kinopoiskapiunofficial.tech/images/posters/kp/{}.jpg"

SCHEMA = """
CREATE TABLE card (
  kinopub_id         INTEGER PRIMARY KEY,
  type               TEXT,
  title_ru           TEXT,
  title_original     TEXT,
  year               INTEGER,
  release_date       TEXT,
  runtime_min        INTEGER,
  countries          TEXT,
  genres             TEXT,
  short_ru           TEXT,
  slogan             TEXT,

  imdb_id            TEXT,
  tmdb_id            TEXT,
  tvdb_id            TEXT,
  kinopoisk_id       TEXT,
  kinopoisk_hd_id    TEXT,
  tvoe_id            TEXT,
  wikidata_id        TEXT,

  poster_ru          TEXT,
  poster_en          TEXT,
  cover_ru           TEXT,
  cover_en           TEXT,
  backdrop           TEXT,
  logo_ru            TEXT,
  logo_en            TEXT,

  imdb               REAL,
  imdb_votes         INTEGER,
  kinopoisk          REAL,
  kinopoisk_votes    INTEGER,
  tvoe               REAL,
  tvoe_votes         INTEGER,
  tvoe_reviews       INTEGER,
  tmdb               REAL,
  tmdb_votes         INTEGER,
  rotten_tomatoes    REAL,
  rotten_tomatoes_votes INTEGER,
  metacritic         REAL,
  metacritic_votes   INTEGER,
  good_review        REAL,
  good_review_votes  INTEGER,
  film_critics       REAL,
  film_critics_votes INTEGER,
  rf_critics         REAL,
  rf_critics_votes   INTEGER,
  rating_await       REAL,
  rating_await_count INTEGER,
  rating_mpaa        TEXT,
  rating_age_ru      INTEGER,
  reviews_count      INTEGER,
  reviews_positive   INTEGER,
  reviews_negative   INTEGER,
  reviews_neutral    INTEGER,

  updated_at         TEXT NOT NULL
);
CREATE INDEX card_imdb ON card(imdb_id);
CREATE INDEX card_kp ON card(kinopoisk_id);
CREATE INDEX card_tvoe ON card(tvoe_id);

CREATE TABLE season (
  kinopub_id    INTEGER NOT NULL,
  number        INTEGER NOT NULL,
  name          TEXT,
  episodes      INTEGER,
  air_date      TEXT,
  end_date      TEXT,
  poster        TEXT,
  PRIMARY KEY (kinopub_id, number)
);

CREATE TABLE episode (
  kinopub_id    INTEGER NOT NULL,
  season        INTEGER NOT NULL,
  number        INTEGER NOT NULL,
  name_ru       TEXT,
  name_en       TEXT,
  air_date      TEXT,
  runtime_min   INTEGER,
  still         TEXT,
  PRIMARY KEY (kinopub_id, season, number)
);
"""

INSERT = """
INSERT INTO card (
  kinopub_id, type, title_ru, title_original, year, release_date, runtime_min,
  countries, genres, short_ru, slogan,
  imdb_id, tmdb_id, tvdb_id, kinopoisk_id, kinopoisk_hd_id, tvoe_id, wikidata_id,
  poster_ru, poster_en, cover_ru, cover_en, backdrop, logo_ru, logo_en,
  imdb, imdb_votes, kinopoisk, kinopoisk_votes, tvoe, tvoe_votes, tvoe_reviews, tmdb, tmdb_votes,
  rotten_tomatoes, rotten_tomatoes_votes, metacritic, metacritic_votes,
  good_review, good_review_votes, film_critics, film_critics_votes,
  rf_critics, rf_critics_votes, rating_await, rating_await_count, rating_mpaa, rating_age_ru,
  reviews_count, reviews_positive, reviews_negative,
  reviews_neutral, updated_at
) VALUES (
  :kinopub_id, :type, :title_ru, :title_original, :year, :release_date, :runtime_min,
  :countries, :genres, :short_ru, :slogan,
  :imdb_id, :tmdb_id, :tvdb_id, :kinopoisk_id, :kinopoisk_hd_id, :tvoe_id, :wikidata_id,
  :poster_ru, :poster_en, :cover_ru, :cover_en, :backdrop, :logo_ru, :logo_en,
  :imdb, :imdb_votes, :kinopoisk, :kinopoisk_votes, :tvoe, :tvoe_votes, :tvoe_reviews, :tmdb, :tmdb_votes,
  :rotten_tomatoes, :rotten_tomatoes_votes, :metacritic, :metacritic_votes,
  :good_review, :good_review_votes, :film_critics, :film_critics_votes,
  :rf_critics, :rf_critics_votes, :rating_await, :rating_await_count, :rating_mpaa, :rating_age_ru,
  :reviews_count, :reviews_positive, :reviews_negative,
  :reviews_neutral, :updated_at
)
"""


def country_text(raw: object) -> str | None:
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None
    if text.startswith("["):
        try:
            names = json.loads(text)
        except json.JSONDecodeError:
            return text
        if isinstance(names, list):
            joined = ", ".join(str(name) for name in names if name)
            return joined or None
    return text


def genre_ids(per_source: dict[str, list[str]], type_name: str | None, rank: tuple[str, ...]) -> str | None:
    """Our genre ids, primary first. Labels stay in genres.json.

    Mirrors KinoPubMediaMapping: a documovie leads with documentary, a concert
    keeps concert after its music, anime leads animation. The snapshot never
    stored kino.pub's genre numbers, so the list is whichever later source we
    have, in that source's order.
    """
    chosen: list[str] = []
    for source in rank:
        if per_source.get(source):
            chosen = list(per_source[source])
            break
    kind = (type_name or "").lower()
    implied = None
    leads = False
    if kind in ("documovie", "docuserial"):
        implied, leads = "documentary", True
    elif kind == "concert":
        implied, leads = "concert", False
    elif kind == "tvshow":
        implied, leads = "tv-show", False
    if implied:
        chosen = [genre for genre in chosen if genre != implied]
        if leads:
            chosen.insert(0, implied)
        else:
            chosen.append(implied)
    for lead in ("anime", "animation"):
        if lead in chosen:
            chosen = [lead] + [genre for genre in chosen if genre != lead]
            break
    if not chosen:
        return None
    return ", ".join(chosen)


def age_number(raw: object) -> int | None:
    """Kinopoisk sends age18, tvoe sends 18. The card keeps the number."""
    if raw is None or raw == "":
        return None
    if isinstance(raw, int):
        return raw
    digits = "".join(ch for ch in str(raw) if ch.isdigit())
    if not digits:
        return None
    return int(digits)


def imdb_text(raw: object) -> str | None:
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None
    if text.startswith("tt"):
        return text
    if text.isdigit():
        return "tt" + text.zfill(7)
    return text


def connect(path: Path) -> sqlite3.Connection:
    if not path.exists():
        sys.exit(f"missing {path}")
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    return db


def main() -> None:
    record = connect(RECORD)
    snapshot = connect(SNAPSHOT)
    kinopoisk = connect(KINOPOISK)
    built_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # title.id in the warehouse is not the kino.pub id. 134 rows happen
    # to share a number; the rest would land on the wrong card.
    kinopub_of: dict[int, int] = {}
    for row in record.execute(
        "SELECT title_id, value FROM title_external_id WHERE namespace = 'kinopub'"
    ):
        kinopub_of[row["title_id"]] = int(row["value"])

    ids: dict[int, dict[str, str]] = {}
    for row in record.execute(
        """
        SELECT title_id, namespace, value
          FROM title_external_id
         WHERE namespace IN ('imdb', 'tmdb', 'tvdb', 'kinopoisk', 'tvoe', 'wikidata')
        """
    ):
        kinopub_id = kinopub_of.get(row["title_id"])
        if kinopub_id is None:
            continue
        ids.setdefault(kinopub_id, {})[row["namespace"]] = row["value"]

    hd: dict[str, str] = {}
    reviews: dict[str, int] = {}
    runtime: dict[str, int] = {}
    slogan: dict[str, str] = {}
    mpaa: dict[str, str] = {}
    kp_age: dict[str, int] = {}
    await_score: dict[str, float] = {}
    await_count: dict[str, int] = {}
    film_poster: dict[str, str] = {}
    film_cover: dict[str, str] = {}
    film_logo: dict[str, str] = {}
    for row in kinopoisk.execute(
        """
        SELECT kinopoisk_id, kinopoisk_hd_id, reviews_count, film_length,
               slogan, rating_mpaa, rating_age_limits,
               rating_await, rating_await_count,
               poster_url, cover_url, logo_url
          FROM kp_films
        """
    ):
        key = str(row["kinopoisk_id"])
        if row["kinopoisk_hd_id"]:
            hd[key] = row["kinopoisk_hd_id"]
        if row["reviews_count"]:
            reviews[key] = row["reviews_count"]
        if row["film_length"]:
            runtime[key] = row["film_length"]
        if row["slogan"]:
            slogan[key] = row["slogan"]
        if row["rating_mpaa"]:
            mpaa[key] = row["rating_mpaa"]
        age = age_number(row["rating_age_limits"])
        if age is not None:
            kp_age[key] = age
        if row["rating_await"] is not None:
            await_score[key] = row["rating_await"]
        if row["rating_await_count"] is not None:
            await_count[key] = row["rating_await_count"]
        if row["poster_url"]:
            film_poster[key] = row["poster_url"]
        if row["cover_url"]:
            film_cover[key] = row["cover_url"]
        if row["logo_url"]:
            film_logo[key] = row["logo_url"]

    # tvoe beats kinopoisk on the russian slots, because tvoe was checked.
    # Kinopoisk fills the same slot when tvoe has nothing.
    # Kinopoisk "backdrop" is their cover, so it lands in cover_ru.
    poster_ru: dict[int, str] = {}
    poster_en: dict[int, str] = {}
    cover_ru: dict[int, str] = {}
    cover_en: dict[int, str] = {}
    backdrop: dict[int, str] = {}
    logo_ru: dict[int, str] = {}
    logo_en: dict[int, str] = {}
    for row in record.execute(
        """
        SELECT title_id, kind, source, lang, url
          FROM image
         WHERE source IN ('tvoe', 'kinopoisk', 'tmdb')
           AND kind IN ('poster', 'backdrop', 'logo')
           AND url IS NOT NULL AND url != ''
         ORDER BY
           CASE source WHEN 'tvoe' THEN 0 WHEN 'kinopoisk' THEN 1 ELSE 2 END,
           rowid
        """
    ):
        title_id = kinopub_of.get(row["title_id"])
        if title_id is None:
            continue
        kind, source, lang, url = row["kind"], row["source"], row["lang"], row["url"]
        if kind == "poster" and lang == "ru" and source == "tvoe":
            poster_ru.setdefault(title_id, url)
        elif kind == "poster" and source == "kinopoisk":
            poster_ru.setdefault(title_id, url)
        elif kind == "poster" and lang == "en" and source == "tmdb":
            poster_en.setdefault(title_id, url)
        elif kind == "backdrop" and source == "kinopoisk":
            cover_ru.setdefault(title_id, url)
        elif kind == "backdrop" and lang == "en" and source == "tmdb":
            cover_en.setdefault(title_id, url)
        elif kind == "backdrop" and source == "tvoe":
            backdrop.setdefault(title_id, url)
        elif kind == "backdrop" and source == "tmdb" and not lang:
            backdrop.setdefault(title_id, url)
        elif kind == "logo" and lang == "ru" and source in ("tvoe", "kinopoisk"):
            logo_ru.setdefault(title_id, url)
        elif kind == "logo" and lang == "en" and source == "tmdb":
            logo_en.setdefault(title_id, url)

    short: dict[int, str] = {}
    for row in record.execute(
        """
        SELECT title_id, text
          FROM synopsis
         WHERE variant = 'short' AND lang = 'ru'
           AND text IS NOT NULL AND text != ''
         ORDER BY rowid
        """
    ):
        kinopub_id = kinopub_of.get(row["title_id"])
        if kinopub_id is not None:
            short.setdefault(kinopub_id, row["text"])

    # tvoe's catalog has a real short line. The warehouse stored their
    # `description` as a full synopsis and never kept `shortDesc`, so the
    # short is read from tvoe's own sqlite. Kinopoisk still wins.
    tvoe_short: dict[str, str] = {}
    tvoe_age: dict[str, int] = {}
    tvoe_released: dict[str, str] = {}
    tvoe_review_count: dict[str, int] = {}
    if TVOE.exists():
        tvoe = sqlite3.connect(f"file:{TVOE}?mode=ro", uri=True)
        tvoe.row_factory = sqlite3.Row
        for row in tvoe.execute("SELECT id, short_desc, age_level, date_released FROM title"):
            if row["short_desc"]:
                tvoe_short[row["id"]] = row["short_desc"]
            if row["age_level"] is not None:
                tvoe_age[row["id"]] = row["age_level"]
            if row["date_released"]:
                tvoe_released[row["id"]] = row["date_released"]
        for row in tvoe.execute("SELECT title_id, COUNT(*) FROM review GROUP BY title_id"):
            tvoe_review_count[row[0]] = row[1]
        tvoe.close()

    # One source's list, in that source's order, as our ids. Kinopoisk before
    # tvoe: tvoe writes "Мультфильмы", Kinopoisk writes "мультфильм", and the
    # card is not a splice of the two. kino.pub's own genre ids were not kept
    # on the snapshot, so they cannot lead this list yet.
    genre_rank = ("kinopub", "tmdb", "kinopoisk", "tvoe")
    genres_by_source: dict[int, dict[str, list[str]]] = {}
    for row in record.execute(
        """
        SELECT title_id, source, name
          FROM genre
         WHERE source IN ('kinopub', 'tmdb', 'kinopoisk', 'tvoe')
           AND name IS NOT NULL AND name != ''
         ORDER BY rowid
        """
    ):
        kinopub_id = kinopub_of.get(row["title_id"])
        if kinopub_id is None:
            continue
        mapped = genre_table.from_name(row["name"], row["source"])
        if not mapped["mapped"]:
            continue
        per_source = genres_by_source.setdefault(kinopub_id, {})
        names = per_source.setdefault(row["source"], [])
        if mapped["id"] not in names:
            names.append(mapped["id"])

    ratings: dict[int, dict[str, object]] = {}

    def rating(title_id: int) -> dict[str, object] | None:
        kinopub_id = kinopub_of.get(title_id)
        if kinopub_id is None:
            return None
        return ratings.setdefault(kinopub_id, {})

    source_list = ", ".join(f"'{name}'" for name in (*RATINGS, "imdb:omdb"))
    for row in record.execute(
        f"""
        SELECT title_id, source, value, votes
          FROM rating
         WHERE season IS NULL AND episode IS NULL
           AND source IN ({source_list})
        """
    ):
        slot = rating(row["title_id"])
        if slot is None:
            continue
        source = row["source"]
        if source == "imdb:omdb":
            slot.setdefault("imdb", row["value"])
            slot.setdefault("imdb_votes", row["votes"])
            continue
        value_column, votes_column = RATINGS[source]
        slot[value_column] = row["value"]
        slot[votes_column] = row["votes"]

    if OUT.exists():
        OUT.unlink()
    out = sqlite3.connect(OUT)
    out.executescript(SCHEMA)

    rows = []
    short_from_tvoe = 0
    for item in snapshot.execute(
        """
        SELECT id, type, title_ru, title_original, year, countries, kinopoisk_id,
               imdb_id, last_synced_at
          FROM items
         ORDER BY id
        """
    ):
        kinopub_id = item["id"]
        found = ids.get(kinopub_id, {})
        kinopoisk_id = found.get("kinopoisk") or (
            str(item["kinopoisk_id"]) if item["kinopoisk_id"] else None
        )
        poster = poster_ru.get(kinopub_id)
        if poster is None and kinopoisk_id:
            poster = film_poster.get(kinopoisk_id) or KP_POSTER.format(kinopoisk_id)
        cover = cover_ru.get(kinopub_id)
        if cover is None and kinopoisk_id:
            cover = film_cover.get(kinopoisk_id)
        logo = logo_ru.get(kinopub_id)
        if logo is None and kinopoisk_id:
            logo = film_logo.get(kinopoisk_id)
        numbers = ratings.get(kinopub_id, {})
        tvoe_id = found.get("tvoe")
        line = short.get(kinopub_id)
        if not line and tvoe_id:
            line = tvoe_short.get(tvoe_id)
            if line:
                short_from_tvoe += 1
        genre_names = genre_ids(genres_by_source.get(kinopub_id, {}), item["type"], genre_rank)
        age_ru = kp_age.get(kinopoisk_id) if kinopoisk_id else None
        if age_ru is None and tvoe_id:
            age_ru = tvoe_age.get(tvoe_id)
        rows.append({
            "kinopub_id": kinopub_id,
            "type": item["type"],
            "title_ru": item["title_ru"],
            "title_original": item["title_original"],
            "year": item["year"],
            "release_date": tvoe_released.get(tvoe_id) if tvoe_id else None,
            "runtime_min": runtime.get(kinopoisk_id) if kinopoisk_id else None,
            "countries": country_text(item["countries"]),
            "genres": genre_names,
            "short_ru": line,
            "slogan": slogan.get(kinopoisk_id) if kinopoisk_id else None,
            "imdb_id": imdb_text(found.get("imdb") or item["imdb_id"]),
            "tmdb_id": found.get("tmdb"),
            "tvdb_id": found.get("tvdb"),
            "kinopoisk_id": kinopoisk_id,
            "kinopoisk_hd_id": hd.get(kinopoisk_id) if kinopoisk_id else None,
            "tvoe_id": tvoe_id,
            "wikidata_id": found.get("wikidata"),
            "poster_ru": poster,
            "poster_en": poster_en.get(kinopub_id),
            "cover_ru": cover,
            "cover_en": cover_en.get(kinopub_id),
            "backdrop": backdrop.get(kinopub_id),
            "logo_ru": logo,
            "logo_en": logo_en.get(kinopub_id),
            "tvoe_reviews": tvoe_review_count.get(tvoe_id) if tvoe_id else None,
            "rating_await": await_score.get(kinopoisk_id) if kinopoisk_id else None,
            "rating_await_count": await_count.get(kinopoisk_id) if kinopoisk_id else None,
            "rating_mpaa": mpaa.get(kinopoisk_id) if kinopoisk_id else None,
            "rating_age_ru": age_ru,
            "reviews_count": reviews.get(kinopoisk_id) if kinopoisk_id else None,
            # Film row has reviews_count and rating_good_review, not the
            # three tone totals. Those arrive on the reviews response
            # (totalPositiveReviews and the two beside it) and were not stored.
            "reviews_positive": None,
            "reviews_negative": None,
            "reviews_neutral": None,
            "updated_at": item["last_synced_at"] or built_at,
            **{column: numbers.get(column) for pair in RATINGS.values() for column in pair},
        })

    out.executemany(INSERT, rows)

    seasons: dict[tuple[int, int], dict[str, object]] = {}
    episodes = []
    for row in record.execute(
        """
        SELECT title_id, season, number, name_ru, name_en, air_date, runtime, still
          FROM episode
         ORDER BY (name_ru IS NULL OR name_ru = ''), rowid
        """
    ):
        kinopub_id = kinopub_of.get(row["title_id"])
        if kinopub_id is None:
            continue
        episodes.append((
            kinopub_id, row["season"], row["number"], row["name_ru"], row["name_en"],
            row["air_date"], row["runtime"], row["still"],
        ))
        slot = seasons.setdefault((kinopub_id, row["season"]), {
            "episodes": 0, "air_date": None, "name": None, "end_date": None, "poster": None,
        })
        slot["episodes"] += 1
        air_date = row["air_date"]
        if air_date and (slot["air_date"] is None or air_date < slot["air_date"]):
            slot["air_date"] = air_date

    for row in record.execute(
        """
        SELECT title_id, number, name, air_date, end_date, episode_cnt, poster
          FROM season
        """
    ):
        kinopub_id = kinopub_of.get(row["title_id"])
        if kinopub_id is None:
            continue
        slot = seasons.setdefault((kinopub_id, row["number"]), {
            "episodes": 0, "air_date": None, "name": None, "end_date": None, "poster": None,
        })
        if row["name"]:
            slot["name"] = row["name"]
        if row["end_date"]:
            slot["end_date"] = row["end_date"]
        if row["poster"]:
            slot["poster"] = row["poster"]
        if row["air_date"]:
            slot["air_date"] = row["air_date"]
        if row["episode_cnt"] and not slot["episodes"]:
            slot["episodes"] = row["episode_cnt"]

    out.executemany(
        """
        INSERT OR IGNORE INTO episode
          (kinopub_id, season, number, name_ru, name_en, air_date, runtime_min, still)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        episodes,
    )
    out.executemany(
        """
        INSERT INTO season (kinopub_id, number, name, episodes, air_date, end_date, poster)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        [
            (kinopub_id, number, slot["name"], slot["episodes"], slot["air_date"],
             slot["end_date"], slot["poster"])
            for (kinopub_id, number), slot in seasons.items()
        ],
    )
    out.commit()

    total = out.execute("SELECT COUNT(*) FROM card").fetchone()[0]
    print(f"card.db  {OUT}")
    print(f"rows     {total}")
    print(f"seasons  {out.execute('SELECT COUNT(*) FROM season').fetchone()[0]}")
    print(f"episodes {out.execute('SELECT COUNT(*) FROM episode').fetchone()[0]}")
    print(f"short from tvoe, no kinopoisk short  {short_from_tvoe}")
    filled = [
        "genres", "countries", "runtime_min", "short_ru", "slogan",
        "release_date", "rating_mpaa", "rating_age_ru", "rating_await", "tvoe_reviews",
        "imdb_id", "tmdb_id", "tvdb_id", "kinopoisk_id",
        "kinopoisk_hd_id", "tvoe_id", "wikidata_id",
        "poster_ru", "poster_en", "cover_ru", "cover_en", "backdrop",
        "logo_ru", "logo_en",
        "imdb", "kinopoisk", "tvoe", "tmdb", "good_review", "film_critics",
        "rf_critics", "reviews_count", "rotten_tomatoes", "metacritic",
    ]
    width = max(len(name) for name in filled)
    for name in filled:
        count = out.execute(
            f"SELECT COUNT(*) FROM card WHERE {name} IS NOT NULL AND CAST({name} AS TEXT) != ''"
        ).fetchone()[0]
        print(f"  {name:<{width}}  {count:>6}   {count / total:.0%}")

    out.row_factory = sqlite3.Row
    print("\nFallout")
    row = out.execute("SELECT * FROM card WHERE kinopub_id = 100564").fetchone()
    if row is not None:
        for key in row.keys():
            value = row[key]
            if value is None or value == "":
                continue
            text = str(value).replace("\n", " ")
            if len(text) > 90:
                text = text[:87] + "..."
            print(f"  {key:<18} {text}")
        season_count = out.execute(
            "SELECT COUNT(*) FROM season WHERE kinopub_id = 100564"
        ).fetchone()[0]
        episode_count = out.execute(
            "SELECT COUNT(*) FROM episode WHERE kinopub_id = 100564"
        ).fetchone()[0]
        print(f"  {'seasons':<18} {season_count}")
        print(f"  {'episodes':<18} {episode_count}")


if __name__ == "__main__":
    main()
