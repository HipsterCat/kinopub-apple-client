#!/usr/bin/env python3
"""One row per kino.pub id, the card we would actually keep.

    python3 build_card.py

Writes tools/metadata-ingest/data/card.db. Open that in Beekeeper.
The warehouse databases are read, not modified. Nothing here is uploaded.

A row is the kino.pub item, plus the few fields the other sources add:
a short line, one synopsis, a poster, a textless backdrop, a logo, and
the rating numbers (including how many reviews exist, not the reviews).
kino.pub's own wide still is not a backdrop. Staff is not on the card.
"""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
RECORD = DATA / "record-v2.db"
SNAPSHOT = ROOT.parent / "kinopub-snapshot" / "data" / "snapshot.db"
KINOPOISK = ROOT.parent / "kinopoisk-metadata" / "data" / "kinopoisk.db"
OUT = DATA / "card.db"

SCHEMA = """
CREATE TABLE card (
  kinopub_id        INTEGER PRIMARY KEY,
  type              TEXT,
  title_ru          TEXT,
  title_original    TEXT,
  year              INTEGER,
  year_from         TEXT,
  start_year        INTEGER,
  end_year          INTEGER,
  runtime_min       INTEGER,
  countries         TEXT,
  finished          INTEGER,
  views             INTEGER,
  imdb_id           TEXT,
  kinopoisk_id      INTEGER,
  tvoe_id           TEXT,
  short_ru          TEXT,
  short_from        TEXT,
  synopsis_ru       TEXT,
  synopsis_from     TEXT,
  slogan            TEXT,
  poster_url        TEXT,
  poster_from       TEXT,
  backdrop_url      TEXT,
  backdrop_from     TEXT,
  logo_url          TEXT,
  logo_from         TEXT,
  kp_cover_url      TEXT,
  kinopub_percent   REAL,
  kinopub_votes     INTEGER,
  imdb              REAL,
  imdb_votes        INTEGER,
  kinopoisk         REAL,
  kinopoisk_votes   INTEGER,
  tvoe              REAL,
  rotten_tomatoes   REAL,
  metacritic        REAL,
  good_review       REAL,
  good_review_votes INTEGER,
  film_critics      REAL,
  film_critics_votes INTEGER,
  rf_critics        REAL,
  rf_critics_votes  INTEGER,
  reviews_count     INTEGER
);
CREATE INDEX idx_card_title_ru ON card(title_ru);
CREATE INDEX idx_card_year ON card(year);
"""


def connect_ro(path: Path) -> sqlite3.Connection:
    if not path.exists():
        sys.exit(f"missing {path}")
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def imdb_text(raw) -> str | None:
    if raw is None or raw == "":
        return None
    text = str(raw).strip()
    if text.startswith("tt"):
        return text
    if text.isdigit():
        return "tt" + text.zfill(7)
    return text


def kinopub_host(url: str | None) -> bool:
    return bool(url) and "staticpop.net" in url


def load_record(conn: sqlite3.Connection):
    """Maps keyed by the record's title id, plus kinopub id -> title id."""
    by_kinopub = {}
    for row in conn.execute(
        "SELECT title_id, value FROM title_external_id WHERE namespace='kinopub'"
    ):
        by_kinopub[str(row["value"])] = row["title_id"]

    ids = {}
    for row in conn.execute(
        "SELECT title_id, namespace, value FROM title_external_id"
        " WHERE namespace IN ('imdb','kinopoisk','tvoe')"
    ):
        slot = ids.setdefault(row["title_id"], {})
        slot.setdefault(row["namespace"], row["value"])

    text = {}
    for row in conn.execute(
        "SELECT title_id, source, variant, text FROM synopsis"
        " WHERE lang='ru' AND variant IN ('short','full','tagline')"
        " AND text IS NOT NULL AND text != ''"
    ):
        bucket = text.setdefault(row["title_id"], {})
        bucket.setdefault((row["source"], row["variant"]), row["text"])

    images = {}
    for row in conn.execute(
        "SELECT title_id, kind, source, lang, url FROM image"
        " WHERE kind IN ('poster','backdrop','logo')"
    ):
        if kinopub_host(row["url"]) or row["source"] == "kinopub":
            continue
        images.setdefault(row["title_id"], []).append(row)

    ratings = {}
    for row in conn.execute(
        "SELECT title_id, source, value, votes FROM rating"
        " WHERE season IS NULL AND episode IS NULL"
    ):
        ratings.setdefault(row["title_id"], {})[row["source"]] = (
            row["value"], row["votes"],
        )
    return by_kinopub, ids, text, images, ratings


def first_text(bucket, pairs):
    if not bucket:
        return None, None
    for source, variant in pairs:
        value = bucket.get((source, variant))
        if value:
            return value, source
    return None, None


def pick_image(rows, kind, order):
    """order is a list of (source, lang or None meaning any)."""
    if not rows:
        return None, None
    pool = [row for row in rows if row["kind"] == kind]
    for source, lang in order:
        for row in pool:
            if row["source"] != source:
                continue
            if lang is not None and (row["lang"] or None) != lang:
                continue
            if kind == "backdrop" and (row["lang"] or None) is not None:
                continue
            return row["url"], source
    return None, None


def load_kinopoisk(conn: sqlite3.Connection) -> dict:
    films = {}
    query = """
        SELECT kinopoisk_id, year, start_year, end_year, film_length,
               slogan, short_description, description,
               poster_url, cover_url, logo_url, reviews_count
        FROM kp_films
    """
    for row in conn.execute(query):
        films[row["kinopoisk_id"]] = row
    return films


def rating(bag, source):
    if not bag or source not in bag:
        return None, None
    return bag[source]


def main() -> int:
    record = connect_ro(RECORD)
    snapshot = connect_ro(SNAPSHOT)
    kinopoisk = connect_ro(KINOPOISK)
    by_kinopub, ids, text, images, ratings = load_record(record)
    films = load_kinopoisk(kinopoisk)

    if OUT.exists():
        OUT.unlink()
    out = sqlite3.connect(OUT)
    out.executescript(SCHEMA)

    rows = []
    for item in snapshot.execute("SELECT * FROM items"):
        kinopub_id = item["id"]
        title_id = by_kinopub.get(str(kinopub_id))
        external = ids.get(title_id, {})
        kp_id = item["kinopoisk_id"] or _int(external.get("kinopoisk"))
        film = films.get(kp_id)
        bag = ratings.get(title_id)
        pics = images.get(title_id)
        words = text.get(title_id)

        year = item["year"] or (film["year"] if film else None) or (
            film["start_year"] if film else None
        )
        if item["year"]:
            year_from = "kinopub"
        elif film and (film["year"] or film["start_year"]):
            year_from = "kinopoisk"
        else:
            year_from = None

        short, short_from = first_text(words, (
            ("kinopoisk", "short"),
            ("tvoe", "short"),
        ))
        if not short and film and film["short_description"]:
            short, short_from = film["short_description"], "kinopoisk"
        synopsis, synopsis_from = first_text(words, (
            ("kinopoisk", "full"),
            ("tvoe", "full"),
        ))
        if not synopsis and film and film["description"]:
            synopsis, synopsis_from = film["description"], "kinopoisk"
        slogan = None
        if words and words.get(("kinopoisk", "tagline")):
            slogan = words[("kinopoisk", "tagline")]
        elif film and film["slogan"]:
            slogan = film["slogan"]

        poster, poster_from = pick_image(pics, "poster", (
            ("tvoe", "ru"),
            ("kinopoisk", None),
            ("tmdb", "ru"),
        ))
        if not poster and film and film["poster_url"] and not kinopub_host(film["poster_url"]):
            poster, poster_from = film["poster_url"], "kinopoisk"
        backdrop, backdrop_from = pick_image(pics, "backdrop", (
            ("tvoe", None),
            ("tmdb", None),
        ))
        logo, logo_from = pick_image(pics, "logo", (
            ("tvoe", "ru"),
            ("tmdb", "ru"),
            ("tmdb", "en"),
        ))
        if not logo and film and film["logo_url"]:
            logo, logo_from = film["logo_url"], "kinopoisk"

        imdb, imdb_votes = rating(bag, "imdb")
        kp_value, kp_votes = rating(bag, "kinopoisk")
        tvoe, _tvoe_votes = rating(bag, "tvoe")
        rt, _rt_votes = rating(bag, "rotten_tomatoes")
        meta, _meta_votes = rating(bag, "metacritic")
        good, good_votes = rating(bag, "good_review")
        critics, critics_votes = rating(bag, "film_critics")
        rf, rf_votes = rating(bag, "rf_critics")
        kp_pub, kp_pub_votes = rating(bag, "kinopub")

        rows.append((
            kinopub_id,
            item["type"],
            item["title_ru"] or item["title"],
            item["title_original"],
            year,
            year_from,
            film["start_year"] if film else None,
            film["end_year"] if film else None,
            film["film_length"] if film else None,
            item["countries"],
            item["finished"],
            item["views"],
            imdb_text(external.get("imdb") or item["imdb_id"]),
            kp_id,
            external.get("tvoe"),
            short,
            short_from,
            synopsis,
            synopsis_from,
            slogan,
            poster,
            poster_from,
            backdrop,
            backdrop_from,
            logo,
            logo_from,
            film["cover_url"] if film else None,
            kp_pub if kp_pub is not None else item["kinopub_rating_percentage"],
            kp_pub_votes if kp_pub_votes is not None else item["kinopub_rating_votes"],
            imdb if imdb is not None else item["imdb_rating"],
            imdb_votes if imdb_votes is not None else item["imdb_votes"],
            kp_value if kp_value is not None else item["kinopoisk_rating"],
            kp_votes if kp_votes is not None else item["kinopoisk_votes"],
            tvoe,
            rt,
            meta,
            good,
            good_votes,
            critics,
            critics_votes,
            rf,
            rf_votes,
            film["reviews_count"] if film else None,
        ))

    out.executemany(
        "INSERT INTO card VALUES (" + ",".join("?" * 43) + ")",
        rows,
    )
    out.commit()
    out.row_factory = sqlite3.Row

    print(f"{OUT}")
    print(f"rows {len(rows):,}")
    for label, cond in (
        ("year", "year IS NOT NULL"),
        ("short", "short_ru IS NOT NULL"),
        ("synopsis", "synopsis_ru IS NOT NULL"),
        ("poster tvoe", "poster_from='tvoe'"),
        ("poster kinopoisk", "poster_from='kinopoisk'"),
        ("poster none", "poster_url IS NULL"),
        ("backdrop tvoe", "backdrop_from='tvoe'"),
        ("backdrop tmdb textless", "backdrop_from='tmdb'"),
        ("backdrop none", "backdrop_url IS NULL"),
        ("logo", "logo_url IS NOT NULL"),
        ("reviews_count", "reviews_count IS NOT NULL"),
        ("rotten tomatoes", "rotten_tomatoes IS NOT NULL"),
    ):
        n = out.execute(f"SELECT count(*) FROM card WHERE {cond}").fetchone()[0]
        print(f"  {label:<24} {n:>8,}")

    fallout = out.execute(
        "SELECT kinopub_id, type, year, year_from, start_year, end_year,"
        " imdb_id, kinopoisk_id, tvoe_id, short_from, poster_from, backdrop_from,"
        " logo_from, substr(short_ru,1,80) short, reviews_count, imdb, kinopoisk"
        " FROM card WHERE kinopub_id=100564"
    ).fetchone()
    print("fallout", dict(fallout) if fallout else None)
    out.close()
    return 0


def _int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


if __name__ == "__main__":
    raise SystemExit(main())
