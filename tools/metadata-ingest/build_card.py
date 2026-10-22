#!/usr/bin/env python3
"""One row per kino.pub id: the card that goes to the worker.

    python3 build_card.py

Writes tools/metadata-ingest/data/card.db. Open that in Beekeeper.
The warehouse databases are read, not modified. Nothing here is uploaded.

No source columns, no ranks, no kino.pub vote counts. Year is the one
kino.pub year. A series does not grow a second "started" year beside it.
Full synopses stay in the warehouse; the card keeps the short line.
"""

from __future__ import annotations

import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
RECORD = DATA / "record-v2.db"
SNAPSHOT = ROOT.parent / "kinopub-snapshot" / "data" / "snapshot.db"
KINOPOISK = ROOT.parent / "kinopoisk-metadata" / "data" / "kinopoisk.db"
OUT = DATA / "card.db"

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
  short_ru           TEXT,

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
  reviews_count      INTEGER,
  rotten_tomatoes    REAL,
  metacritic         REAL,

  updated_at         TEXT NOT NULL
);
CREATE INDEX card_imdb ON card(imdb_id);
CREATE INDEX card_kp ON card(kinopoisk_id);
CREATE INDEX card_tvoe ON card(tvoe_id);
"""

INSERT = """
INSERT INTO card (
  kinopub_id, type, title_ru, title_original, year, short_ru,
  imdb_id, tmdb_id, tvdb_id, kinopoisk_id, kinopoisk_hd_id, tvoe_id, wikidata_id,
  poster_ru, poster_en, cover_ru, cover_en, backdrop, logo_ru, logo_en,
  imdb, imdb_votes, kinopoisk, kinopoisk_votes, reviews_count,
  rotten_tomatoes, metacritic, updated_at
) VALUES (
  :kinopub_id, :type, :title_ru, :title_original, :year, :short_ru,
  :imdb_id, :tmdb_id, :tvdb_id, :kinopoisk_id, :kinopoisk_hd_id, :tvoe_id, :wikidata_id,
  :poster_ru, :poster_en, :cover_ru, :cover_en, :backdrop, :logo_ru, :logo_en,
  :imdb, :imdb_votes, :kinopoisk, :kinopoisk_votes, :reviews_count,
  :rotten_tomatoes, :metacritic, :updated_at
)
"""


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
    film_poster: dict[str, str] = {}
    film_cover: dict[str, str] = {}
    film_logo: dict[str, str] = {}
    for row in kinopoisk.execute(
        """
        SELECT kinopoisk_id, kinopoisk_hd_id, reviews_count,
               poster_url, cover_url, logo_url
          FROM kp_films
        """
    ):
        key = str(row["kinopoisk_id"])
        if row["kinopoisk_hd_id"]:
            hd[key] = row["kinopoisk_hd_id"]
        if row["reviews_count"]:
            reviews[key] = row["reviews_count"]
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

    ratings: dict[int, dict[str, object]] = {}

    def rating(title_id: int) -> dict[str, object] | None:
        kinopub_id = kinopub_of.get(title_id)
        if kinopub_id is None:
            return None
        return ratings.setdefault(kinopub_id, {})

    for row in record.execute(
        """
        SELECT title_id, source, value, votes
          FROM rating
         WHERE season IS NULL AND episode IS NULL
           AND source IN (
             'imdb', 'imdb:omdb', 'kinopoisk', 'rotten_tomatoes', 'metacritic'
           )
        """
    ):
        slot = rating(row["title_id"])
        if slot is None:
            continue
        source = row["source"]
        if source == "imdb":
            slot["imdb"] = row["value"]
            slot["imdb_votes"] = row["votes"]
        elif source == "imdb:omdb":
            slot.setdefault("imdb", row["value"])
            slot.setdefault("imdb_votes", row["votes"])
        elif source == "kinopoisk":
            slot["kinopoisk"] = row["value"]
            slot["kinopoisk_votes"] = row["votes"]
        elif source == "rotten_tomatoes":
            slot["rotten_tomatoes"] = row["value"]
        elif source == "metacritic":
            slot["metacritic"] = row["value"]

    if OUT.exists():
        OUT.unlink()
    out = sqlite3.connect(OUT)
    out.executescript(SCHEMA)

    rows = []
    for item in snapshot.execute(
        """
        SELECT id, type, title_ru, title_original, year, kinopoisk_id, imdb_id,
               last_synced_at
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
        rows.append({
            "kinopub_id": kinopub_id,
            "type": item["type"],
            "title_ru": item["title_ru"],
            "title_original": item["title_original"],
            "year": item["year"],
            "short_ru": short.get(kinopub_id),
            "imdb_id": imdb_text(found.get("imdb") or item["imdb_id"]),
            "tmdb_id": found.get("tmdb"),
            "tvdb_id": found.get("tvdb"),
            "kinopoisk_id": kinopoisk_id,
            "kinopoisk_hd_id": hd.get(kinopoisk_id) if kinopoisk_id else None,
            "tvoe_id": found.get("tvoe"),
            "wikidata_id": found.get("wikidata"),
            "poster_ru": poster,
            "poster_en": poster_en.get(kinopub_id),
            "cover_ru": cover,
            "cover_en": cover_en.get(kinopub_id),
            "backdrop": backdrop.get(kinopub_id),
            "logo_ru": logo,
            "logo_en": logo_en.get(kinopub_id),
            "imdb": numbers.get("imdb"),
            "imdb_votes": numbers.get("imdb_votes"),
            "kinopoisk": numbers.get("kinopoisk"),
            "kinopoisk_votes": numbers.get("kinopoisk_votes"),
            "reviews_count": reviews.get(kinopoisk_id) if kinopoisk_id else None,
            "rotten_tomatoes": numbers.get("rotten_tomatoes"),
            "metacritic": numbers.get("metacritic"),
            "updated_at": item["last_synced_at"] or built_at,
        })

    out.executemany(INSERT, rows)
    out.commit()

    total = out.execute("SELECT COUNT(*) FROM card").fetchone()[0]
    print(f"card.db  {OUT}")
    print(f"rows     {total}")
    filled = [
        "short_ru", "imdb_id", "tmdb_id", "tvdb_id", "kinopoisk_id",
        "kinopoisk_hd_id", "tvoe_id", "wikidata_id",
        "poster_ru", "poster_en", "cover_ru", "cover_en", "backdrop",
        "logo_ru", "logo_en",
        "imdb", "kinopoisk", "reviews_count", "rotten_tomatoes", "metacritic",
    ]
    width = max(len(name) for name in filled)
    for name in filled:
        count = out.execute(
            f"SELECT COUNT(*) FROM card WHERE {name} IS NOT NULL AND {name} != ''"
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


if __name__ == "__main__":
    main()
