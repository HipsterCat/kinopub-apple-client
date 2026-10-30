#!/usr/bin/env python3
"""Turn a worker KV archive into a source database, then a fuller card.

    python3 import_kv.py

Reads data/kv-documents-*.jsonl.gz (the newest one) and writes two files
next to it, both gitignored:

  data/kv.db       every field of the archive, one concept per table.
                   People keep their TMDB id, gender and popularity, and every
                   role is its own row. Episodes keep a TMDB id and a rating,
                   plus the IMDb rating when record-v2 already has that episode.
  data/card-2.db   a copy of card.db with the empty cells filled from kv.db

card.db is not modified. A cell that already has a value stays: tvoe's
poster, Kinopoisk's id, a season the warehouse already counted. The archive
fills the holes and adds myshows_id, synopsis_ru, status and tagline_ru.

card-2 also grows the tables the page reads. `person` is only the people
we show. `billing` is Featured: up to three stars, one director, up to
three writers, plus two or three names from the regular cast. `cast_count`
is everyone else (regular, guest, producers) so the rest can be fetched
later. `image` holds the pictures. `top_episode` is the handful worth
surfacing. kv.db keeps the full cast.

Long lists (cast, trailers, facts, every picture) stay in kv.db. That is
the table to open when the question is "what did the worker actually store".
"""

from __future__ import annotations

import argparse
import gzip
import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"

KV_SCHEMA = """
CREATE TABLE document (
  kinopub_id      INTEGER PRIMARY KEY,
  version         INTEGER,
  kind            TEXT,
  title_ru        TEXT,
  title_original  TEXT,
  year            INTEGER,
  pending         INTEGER NOT NULL,
  facts_checked   INTEGER,
  built_at        TEXT,
  logo_checked_at TEXT,
  art_rev         INTEGER,
  expiration      INTEGER,
  status          TEXT
);

CREATE TABLE external_id (
  kinopub_id  INTEGER NOT NULL,
  namespace   TEXT NOT NULL,
  value       TEXT NOT NULL,
  confidence  REAL,
  method      TEXT,
  PRIMARY KEY (kinopub_id, namespace)
);
CREATE INDEX external_id_value ON external_id(namespace, value);

CREATE TABLE artwork (
  kinopub_id INTEGER NOT NULL,
  kind       TEXT NOT NULL,
  position   INTEGER NOT NULL,
  source     TEXT,
  lang       TEXT,
  url        TEXT NOT NULL,
  width      INTEGER,
  height     INTEGER,
  pinned     INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (kinopub_id, kind, position)
);

CREATE TABLE rating (
  kinopub_id INTEGER NOT NULL,
  source     TEXT NOT NULL,
  value      REAL,
  votes      INTEGER,
  scale      REAL,
  PRIMARY KEY (kinopub_id, source)
);

CREATE TABLE synopsis (
  kinopub_id INTEGER NOT NULL,
  position   INTEGER NOT NULL,
  source     TEXT,
  lang       TEXT,
  variant    TEXT,
  text       TEXT,
  PRIMARY KEY (kinopub_id, position)
);

CREATE TABLE genre (
  kinopub_id INTEGER NOT NULL,
  position   INTEGER NOT NULL,
  genre_id   TEXT,
  domain     TEXT,
  name_en    TEXT,
  name_ru    TEXT,
  genre_group TEXT,
  mapped     INTEGER,
  source     TEXT,
  PRIMARY KEY (kinopub_id, position)
);

CREATE TABLE genre_name (
  kinopub_id INTEGER NOT NULL,
  position   INTEGER NOT NULL,
  source     TEXT,
  name       TEXT,
  PRIMARY KEY (kinopub_id, position)
);

CREATE TABLE person (
  tmdb_id               INTEGER PRIMARY KEY,
  name_ru               TEXT,
  name_en               TEXT,
  gender                INTEGER,
  popularity            REAL,
  known_for_department  TEXT,
  adult                 INTEGER,
  profile_url           TEXT
);

CREATE TABLE credit (
  kinopub_id            INTEGER NOT NULL,
  position              INTEGER NOT NULL,
  person_id             INTEGER,
  department            TEXT,
  known_for_department  TEXT,
  gender                INTEGER,
  popularity            REAL,
  character             TEXT,
  episode_count         INTEGER,
  name_ru               TEXT,
  name_en               TEXT,
  sources               TEXT,
  PRIMARY KEY (kinopub_id, position)
);
CREATE INDEX credit_person ON credit(person_id);
CREATE INDEX credit_popularity ON credit(kinopub_id, popularity);

CREATE TABLE credit_role (
  kinopub_id    INTEGER NOT NULL,
  position      INTEGER NOT NULL,
  role_ord      INTEGER NOT NULL,
  credit_id     TEXT,
  character     TEXT,
  job           TEXT,
  episode_count INTEGER,
  PRIMARY KEY (kinopub_id, position, role_ord)
);

CREATE TABLE credit_photo (
  kinopub_id INTEGER NOT NULL,
  position   INTEGER NOT NULL,
  photo_ord  INTEGER NOT NULL,
  url        TEXT NOT NULL,
  PRIMARY KEY (kinopub_id, position, photo_ord)
);

CREATE TABLE season (
  kinopub_id    INTEGER NOT NULL,
  number        INTEGER NOT NULL,
  tmdb_id       INTEGER,
  name_ru       TEXT,
  name_en       TEXT,
  synopsis_ru   TEXT,
  synopsis_en   TEXT,
  air_date      TEXT,
  end_date      TEXT,
  episode_cnt   INTEGER,
  poster_ru     TEXT,
  poster_en     TEXT,
  source        TEXT,
  fetched_langs TEXT,
  tmdb_rating   REAL,
  tmdb_votes    INTEGER,
  PRIMARY KEY (kinopub_id, number)
);

CREATE TABLE episode (
  kinopub_id   INTEGER NOT NULL,
  season       INTEGER NOT NULL,
  number       INTEGER NOT NULL,
  name_ru      TEXT,
  name_en      TEXT,
  overview_ru  TEXT,
  overview_en  TEXT,
  runtime_min  INTEGER,
  air_date     TEXT,
  still          TEXT,
  imdb_id        TEXT,
  tmdb_id        INTEGER,
  season_tmdb_id INTEGER,
  episode_type   TEXT,
  season_finale  INTEGER,
  skip_intro     INTEGER,
  skip_credits   INTEGER,
  PRIMARY KEY (kinopub_id, season, number)
);

CREATE TABLE episode_rating (
  kinopub_id INTEGER NOT NULL,
  season     INTEGER NOT NULL,
  episode    INTEGER NOT NULL,
  source     TEXT NOT NULL,
  value      REAL,
  votes      INTEGER,
  PRIMARY KEY (kinopub_id, season, episode, source)
);

CREATE TABLE trailer (
  kinopub_id INTEGER NOT NULL,
  position   INTEGER NOT NULL,
  source     TEXT,
  source_key TEXT,
  kind       TEXT,
  name       TEXT,
  lang       TEXT,
  official     INTEGER,
  url          TEXT,
  published_at TEXT,
  duration_sec INTEGER,
  PRIMARY KEY (kinopub_id, position)
);

CREATE TABLE network (
  kinopub_id     INTEGER NOT NULL,
  tmdb_id        INTEGER NOT NULL,
  name           TEXT,
  logo_url       TEXT,
  origin_country TEXT,
  PRIMARY KEY (kinopub_id, tmdb_id)
);

CREATE TABLE fact (
  kinopub_id INTEGER NOT NULL,
  position   INTEGER NOT NULL,
  source     TEXT,
  text       TEXT,
  spoiler    INTEGER,
  PRIMARY KEY (kinopub_id, position)
);

CREATE TABLE image_stat (
  key        TEXT PRIMARY KEY,
  missing    INTEGER,
  waited     INTEGER,
  updated_at TEXT
);
"""


def load_archive(path: Path) -> list[dict]:
    rows = []
    with gzip.open(path, "rt", encoding="utf-8") as stream:
        for line in stream:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def write_kv(rows: list[dict], path: Path) -> dict[str, int]:
    if path.exists():
        path.unlink()
    db = sqlite3.connect(path)
    db.executescript(KV_SCHEMA)
    counts = {
        "documents": 0, "ids": 0, "artwork": 0, "ratings": 0, "synopsis": 0,
        "genres": 0, "credits": 0, "roles": 0, "photos": 0, "seasons": 0, "episodes": 0,
        "episode_ratings": 0, "trailers": 0, "facts": 0, "networks": 0,
    }
    for row in rows:
        key = str(row.get("key") or "")
        value = row.get("value")
        if key == "stats:img" and isinstance(value, dict):
            db.execute(
                "INSERT INTO image_stat (key, missing, waited, updated_at) VALUES (?, ?, ?, ?)",
                (key, value.get("missing"), value.get("waited"), value.get("updated_at")),
            )
            continue
        if not key.startswith("title:kinopub:") or not isinstance(value, dict):
            continue
        kinopub_id = _kinopub_id(key)
        if kinopub_id is None:
            continue
        _insert_document(db, kinopub_id, value, row.get("expiration"), counts)
    counts["episode_ratings"] += _attach_imdb_episode_ratings(db)
    db.commit()
    db.close()
    return counts


def write_card2(card_path: Path, kv_path: Path, out_path: Path) -> dict[str, int]:
    if not card_path.exists():
        sys.exit(f"missing {card_path}")
    if out_path.exists():
        out_path.unlink()
    src = sqlite3.connect(f"file:{card_path}?mode=ro", uri=True)
    dst = sqlite3.connect(out_path)
    src.backup(dst)
    src.close()
    dst.row_factory = sqlite3.Row
    dst.execute("ALTER TABLE card ADD COLUMN myshows_id TEXT")
    dst.execute("ALTER TABLE card ADD COLUMN synopsis_ru TEXT")
    dst.execute("CREATE INDEX card_tmdb ON card(tmdb_id)")
    dst.execute("CREATE INDEX card_myshows ON card(myshows_id)")

    kv = sqlite3.connect(f"file:{kv_path}?mode=ro", uri=True)
    kv.row_factory = sqlite3.Row
    filled = {
        "imdb_id": 0, "tmdb_id": 0, "tvdb_id": 0, "kinopoisk_id": 0,
        "wikidata_id": 0, "myshows_id": 0, "poster_ru": 0, "poster_en": 0,
        "backdrop": 0, "logo_ru": 0, "logo_en": 0, "tmdb": 0, "tmdb_votes": 0,
        "genres": 0, "synopsis_ru": 0, "title_ru": 0, "title_original": 0,
        "year": 0,
    }
    added_rows = 0
    seasons_added = 0
    season_fields = 0
    conflicts: list[str] = []
    season_notes: list[str] = []

    for doc in kv.execute("SELECT * FROM document ORDER BY kinopub_id"):
        kinopub_id = doc["kinopub_id"]
        proposed = _card_patch(kv, doc)
        current = dst.execute("SELECT * FROM card WHERE kinopub_id = ?", (kinopub_id,)).fetchone()
        if current is None:
            _insert_card_row(dst, kinopub_id, proposed, doc["built_at"])
            added_rows += 1
        else:
            sets = []
            values = []
            for column, new in proposed.items():
                if column not in filled and column not in current.keys():
                    continue
                old = current[column] if column in current.keys() else None
                if _blank(new):
                    continue
                if _blank(old):
                    sets.append(f"{column} = ?")
                    values.append(new)
                    if column in filled:
                        filled[column] += 1
                elif str(old) != str(new) and column in (
                    "imdb_id", "tmdb_id", "tvdb_id", "kinopoisk_id", "wikidata_id",
                ):
                    if len(conflicts) < 15:
                        conflicts.append(f"{kinopub_id} {column} card={old} kv={new}")
            if sets:
                values.append(kinopub_id)
                dst.execute(
                    f"UPDATE card SET {', '.join(sets)} WHERE kinopub_id = ?",
                    values,
                )
        seasons_added += _merge_seasons(dst, kv, kinopub_id)
        filled_fields, count_kept = _fill_season_fields(dst, kv, kinopub_id)
        season_fields += filled_fields
        if count_kept and len(season_notes) < 12:
            season_notes.append(count_kept)

    presentation = _fill_presentation(dst, kv)
    dst.commit()
    kv.close()
    total = dst.execute("SELECT COUNT(*) FROM card").fetchone()[0]
    dst.close()
    return {
        "rows": total,
        "added_rows": added_rows,
        "seasons_added": seasons_added,
        "season_fields": season_fields,
        "episodes_added": 0,
        "episode_stills": 0,
        **presentation,
        "conflicts": conflicts,
        "season_notes": season_notes,
        **filled,
    }


def latest_archive(directory: Path) -> Path | None:
    found = sorted(directory.glob("kv-documents-*.jsonl.gz"))
    return found[-1] if found else None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--kv", type=Path, default=DATA / "kv.db")
    parser.add_argument("--card", type=Path, default=DATA / "card.db")
    parser.add_argument("--out", type=Path, default=DATA / "card-2.db")
    args = parser.parse_args()
    archive = args.archive or latest_archive(DATA)
    if archive is None or not archive.exists():
        sys.exit(f"missing archive in {DATA} (kv-documents-*.jsonl.gz)")

    rows = load_archive(archive)
    counts = write_kv(rows, args.kv)
    print(f"archive  {archive.name}")
    print(f"kv.db    {args.kv}")
    for name in (
        "documents", "ids", "artwork", "ratings", "synopsis", "genres",
        "credits", "roles", "photos", "seasons", "episodes", "episode_ratings",
        "trailers", "facts", "networks",
    ):
        print(f"  {name:<12} {counts[name]}")

    report = write_card2(args.card, args.kv, args.out)
    print(f"card-2   {args.out}")
    print(f"  rows {report['rows']}   new from the archive {report['added_rows']}")
    print(
        f"  seasons added {report['seasons_added']}"
        f"   season fields filled {report['season_fields']}"
    )
    print(
        f"  people {report['people']}   images {report['images']}"
        f"   featured {report['featured']}   top episodes {report['top_episodes']}"
    )
    print("  filled where the card was empty")
    for name in (
        "tmdb_id", "imdb_id", "kinopoisk_id", "tvdb_id", "wikidata_id", "myshows_id",
        "tmdb", "tmdb_votes", "poster_ru", "poster_en", "backdrop", "logo_ru", "logo_en",
        "genres", "synopsis_ru", "title_ru", "title_original", "year",
    ):
        print(f"    {name:<16} {report[name]}")
    if report["conflicts"]:
        print("  kept the card's id where the archive disagrees")
        for line in report["conflicts"]:
            print(f"    {line}")
    if report["season_notes"]:
        print("  kept the card's episode count where the archive disagrees")
        for line in report["season_notes"]:
            print(f"    {line}")


def _kinopub_id(key: str) -> int | None:
    suffix = key.rsplit(":", 1)[-1]
    if suffix.isdigit():
        return int(suffix)
    return None


def _insert_document(db, kinopub_id: int, doc: dict, expiration, counts: dict[str, int]) -> None:
    title = doc.get("title") or {}
    db.execute(
        """
        INSERT INTO document (
          kinopub_id, version, kind, title_ru, title_original, year, pending,
          facts_checked, built_at, logo_checked_at, art_rev, expiration, status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            kinopub_id, doc.get("version"), doc.get("kind"),
            _text(title.get("ru") if isinstance(title, dict) else None),
            _text(title.get("original") if isinstance(title, dict) else None),
            doc.get("year"), 1 if doc.get("pending") else 0,
            _flag(doc.get("factsChecked")), doc.get("built_at"),
            doc.get("logo_checked_at"), doc.get("art_rev"), expiration,
            _text(doc.get("status")),
        ),
    )
    counts["documents"] += 1

    for namespace, slot in (doc.get("ids") or {}).items():
        value, confidence, method = _id_slot(slot)
        if not value:
            continue
        db.execute(
            """
            INSERT INTO external_id (kinopub_id, namespace, value, confidence, method)
            VALUES (?, ?, ?, ?, ?)
            """,
            (kinopub_id, namespace, value, confidence, method),
        )
        counts["ids"] += 1

    for kind, items in (doc.get("artwork") or {}).items():
        for position, item in enumerate(items or []):
            url = _text(item.get("url"))
            if not url:
                continue
            db.execute(
                """
                INSERT INTO artwork (
                  kinopub_id, kind, position, source, lang, url, width, height, pinned
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    kinopub_id, kind, position, item.get("source"), _text(item.get("lang")),
                    url, item.get("width"), item.get("height"),
                    1 if item.get("pinned") else 0,
                ),
            )
            counts["artwork"] += 1

    for item in doc.get("ratings") or []:
        source = _text(item.get("source"))
        if not source:
            continue
        db.execute(
            "INSERT OR REPLACE INTO rating (kinopub_id, source, value, votes, scale) VALUES (?, ?, ?, ?, ?)",
            (kinopub_id, source, item.get("value"), item.get("votes"), item.get("scale")),
        )
        counts["ratings"] += 1

    for position, item in enumerate(doc.get("synopsis") or []):
        db.execute(
            """
            INSERT INTO synopsis (kinopub_id, position, source, lang, variant, text)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (kinopub_id, position, item.get("source"), item.get("lang"),
             item.get("variant"), item.get("text")),
        )
        counts["synopsis"] += 1

    for position, item in enumerate(doc.get("genres") or []):
        name = item.get("name") if isinstance(item.get("name"), dict) else {}
        db.execute(
            """
            INSERT INTO genre (
              kinopub_id, position, genre_id, domain, name_en, name_ru,
              genre_group, mapped, source
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                kinopub_id, position, item.get("id"), item.get("domain"),
                name.get("en"), name.get("ru"), item.get("group"),
                1 if item.get("mapped") else 0, item.get("source"),
            ),
        )
        counts["genres"] += 1

    for position, item in enumerate(doc.get("genre_sources") or []):
        db.execute(
            "INSERT INTO genre_name (kinopub_id, position, source, name) VALUES (?, ?, ?, ?)",
            (kinopub_id, position, item.get("source"), item.get("name")),
        )

    for position, person in enumerate(doc.get("credits") or []):
        _insert_credit(db, kinopub_id, position, person, counts)

    for network in doc.get("networks") or []:
        tmdb_id = network.get("id")
        if tmdb_id is None:
            continue
        db.execute(
            """
            INSERT OR REPLACE INTO network (kinopub_id, tmdb_id, name, logo_url, origin_country)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                kinopub_id, tmdb_id, network.get("name"),
                network.get("logo") or network.get("logo_url"), network.get("origin_country"),
            ),
        )
        counts["networks"] += 1

    for season in doc.get("seasons") or []:
        number = season.get("number")
        if number is None:
            continue
        name_ru, name_en = _localized(season.get("name"))
        synopsis_ru, synopsis_en = _localized(season.get("synopsis") or season.get("overview"))
        poster_ru, poster_en = _localized(season.get("poster"))
        langs = season.get("fetched_langs") or []
        if not langs:
            langs = [code for code, text in (("ru", name_ru or synopsis_ru or poster_ru), ("en", name_en or synopsis_en or poster_en)) if text]
        rating_value, rating_votes = _score(season.get("tmdb"), False)
        db.execute(
            """
            INSERT OR REPLACE INTO season (
              kinopub_id, number, tmdb_id, name_ru, name_en, synopsis_ru, synopsis_en,
              air_date, end_date, episode_cnt, poster_ru, poster_en, source,
              fetched_langs, tmdb_rating, tmdb_votes
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                kinopub_id, number, season.get("id"), name_ru, name_en, synopsis_ru, synopsis_en,
                season.get("air_date"), season.get("end_date"), season.get("episode_cnt"),
                poster_ru, poster_en, season.get("source"),
                ", ".join(str(item) for item in langs if item) or None,
                rating_value, rating_votes,
            ),
        )
        counts["seasons"] += 1
        for episode in season.get("episodes") or []:
            ep_number = episode.get("number")
            if ep_number is None:
                continue
            name_ru, name_en = _pair(episode.get("name"))
            overview_ru, overview_en = _pair(episode.get("overview"))
            tmdb_value, tmdb_votes = _score(episode.get("tmdb"))
            imdb_value, imdb_votes = _imdb_score(episode.get("imdb"))
            db.execute(
                """
                INSERT OR REPLACE INTO episode (
                  kinopub_id, season, number, name_ru, name_en, overview_ru, overview_en,
                  runtime_min, air_date, still, imdb_id, tmdb_id, season_tmdb_id,
                  episode_type, season_finale, skip_intro, skip_credits
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    kinopub_id, number, ep_number, name_ru, name_en, overview_ru, overview_en,
                    episode.get("runtime_min"), episode.get("air_date"),
                    _text(episode.get("thumbnail")), _episode_imdb(episode.get("imdb")),
                    episode.get("id"), episode.get("season_id") or season.get("id"),
                    _text(episode.get("episode_type")),
                    1 if episode.get("season_finale") or episode.get("episode_type") == "finale" else 0,
                    _flag(episode.get("skip_intro")), _flag(episode.get("skip_credits")),
                ),
            )
            counts["episodes"] += 1
            if tmdb_value is not None and tmdb_votes:
                _put_episode_rating(db, kinopub_id, number, ep_number, "tmdb", tmdb_value, tmdb_votes)
                counts["episode_ratings"] += 1
            if imdb_value is not None:
                _put_episode_rating(db, kinopub_id, number, ep_number, "imdb", imdb_value, imdb_votes)
                counts["episode_ratings"] += 1

    for position, item in enumerate(doc.get("trailers") or []):
        db.execute(
            """
            INSERT INTO trailer (
              kinopub_id, position, source, source_key, kind, name, lang, official, url,
              published_at, duration_sec
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                kinopub_id, position, item.get("source"), item.get("source_key"),
                item.get("kind"), item.get("name"), item.get("lang"),
                _flag(item.get("official")), item.get("url"),
                item.get("published_at"), item.get("duration_sec"),
            ),
        )
        counts["trailers"] += 1

    for position, item in enumerate(doc.get("facts") or []):
        db.execute(
            "INSERT INTO fact (kinopub_id, position, source, text, spoiler) VALUES (?, ?, ?, ?, ?)",
            (kinopub_id, position, item.get("source"), item.get("text"), _flag(item.get("spoiler"))),
        )
        counts["facts"] += 1


def _insert_credit(db, kinopub_id: int, position: int, person: dict, counts: dict[str, int]) -> None:
    roles = _roles(person)
    character = next((role["character"] for role in roles if role.get("character")), None) or _text(person.get("character"))
    person_id = person.get("id")
    if isinstance(person_id, str) and person_id.isdigit():
        person_id = int(person_id)
    if not isinstance(person_id, int):
        person_id = None
    profile = None
    for url in person.get("photos") or []:
        text = _text(url)
        if text and "image.tmdb.org" in text:
            profile = text
            break
    if person_id is not None:
        db.execute(
            """
            INSERT INTO person (
              tmdb_id, name_ru, name_en, gender, popularity, known_for_department, adult, profile_url
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(tmdb_id) DO UPDATE SET
              popularity = CASE
                WHEN excluded.popularity IS NULL THEN person.popularity
                WHEN person.popularity IS NULL THEN excluded.popularity
                ELSE MAX(person.popularity, excluded.popularity)
              END,
              name_ru = COALESCE(person.name_ru, excluded.name_ru),
              name_en = COALESCE(person.name_en, excluded.name_en),
              gender = COALESCE(person.gender, excluded.gender),
              known_for_department = COALESCE(person.known_for_department, excluded.known_for_department),
              profile_url = COALESCE(person.profile_url, excluded.profile_url)
            """,
            (
                person_id, person.get("name_ru"), person.get("name_en"), person.get("gender"),
                person.get("popularity"), person.get("known_for_department"),
                _flag(person.get("adult")), profile,
            ),
        )
    sources = person.get("sources") or []
    source_text = ", ".join(str(item) for item in sources if item) or None
    db.execute(
        """
        INSERT INTO credit (
          kinopub_id, position, person_id, department, known_for_department, gender,
          popularity, character, episode_count, name_ru, name_en, sources
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            kinopub_id, position, person_id, person.get("department"),
            person.get("known_for_department"), person.get("gender"), person.get("popularity"),
            character, person.get("episode_count"), person.get("name_ru"), person.get("name_en"),
            source_text,
        ),
    )
    counts["credits"] += 1
    for role_ord, role in enumerate(roles):
        db.execute(
            """
            INSERT INTO credit_role (
              kinopub_id, position, role_ord, credit_id, character, job, episode_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                kinopub_id, position, role_ord, role.get("credit_id"), role.get("character"),
                role.get("job"), role.get("episode_count"),
            ),
        )
        counts["roles"] += 1
    for photo_ord, url in enumerate(person.get("photos") or []):
        url = _text(url)
        if not url:
            continue
        db.execute(
            "INSERT INTO credit_photo (kinopub_id, position, photo_ord, url) VALUES (?, ?, ?, ?)",
            (kinopub_id, position, photo_ord, url),
        )
        counts["photos"] += 1


def _roles(person: dict) -> list[dict]:
    raw = person.get("roles")
    if isinstance(raw, list) and raw:
        return [
            {
                "character": item.get("character"),
                "job": item.get("job"),
                "credit_id": item.get("credit_id"),
                "episode_count": item.get("episode_count"),
            }
            for item in raw if isinstance(item, dict)
        ]
    if person.get("character") or person.get("job"):
        return [{
            "character": person.get("character"),
            "job": person.get("job"),
            "credit_id": person.get("credit_id"),
            "episode_count": person.get("episode_count"),
        }]
    return []


def _put_episode_rating(db, kinopub_id, season, episode, source, value, votes) -> None:
    db.execute(
        """
        INSERT OR REPLACE INTO episode_rating (kinopub_id, season, episode, source, value, votes)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (kinopub_id, season, episode, source, value, votes),
    )


def _card_patch(kv: sqlite3.Connection, doc: sqlite3.Row) -> dict[str, object]:
    kinopub_id = doc["kinopub_id"]
    ids = {
        row["namespace"]: row["value"]
        for row in kv.execute(
            "SELECT namespace, value FROM external_id WHERE kinopub_id = ?",
            (kinopub_id,),
        )
    }
    art = list(kv.execute(
        "SELECT kind, lang, url FROM artwork WHERE kinopub_id = ? ORDER BY position",
        (kinopub_id,),
    ))
    rating = kv.execute(
        "SELECT value, votes FROM rating WHERE kinopub_id = ? AND source = 'tmdb'",
        (kinopub_id,),
    ).fetchone()
    synopsis = kv.execute(
        """
        SELECT text FROM synopsis
         WHERE kinopub_id = ? AND lang = 'ru' AND variant = 'full'
           AND text IS NOT NULL AND text != ''
         ORDER BY position LIMIT 1
        """,
        (kinopub_id,),
    ).fetchone()
    genres = [
        row["genre_id"]
        for row in kv.execute(
            """
            SELECT genre_id FROM genre
             WHERE kinopub_id = ? AND mapped = 1 AND genre_id IS NOT NULL AND genre_id != ''
             ORDER BY position
            """,
            (kinopub_id,),
        )
    ]
    return {
        "title_ru": doc["title_ru"],
        "title_original": doc["title_original"],
        "year": doc["year"],
        "imdb_id": _imdb(ids.get("imdb")),
        "tmdb_id": ids.get("tmdb"),
        "tvdb_id": ids.get("tvdb"),
        "kinopoisk_id": ids.get("kinopoisk"),
        "wikidata_id": ids.get("wikidata"),
        "myshows_id": ids.get("myshows"),
        "poster_ru": _art(art, "poster", "ru") or _art(art, "poster", None),
        "poster_en": _art(art, "poster", "en"),
        "backdrop": _art(art, "backdrop", None),
        "logo_ru": _art(art, "logo", "ru"),
        "logo_en": _art(art, "logo", "en"),
        "tmdb": rating["value"] if rating else None,
        "tmdb_votes": rating["votes"] if rating else None,
        "genres": ", ".join(genres) or None,
        "synopsis_ru": synopsis["text"] if synopsis else None,
    }


def _insert_card_row(db, kinopub_id: int, proposed: dict, built_at: str | None) -> None:
    columns = ["kinopub_id", "updated_at", *proposed.keys()]
    values = [kinopub_id, built_at or "", *proposed.values()]
    placeholders = ", ".join("?" for _ in columns)
    db.execute(
        f"INSERT INTO card ({', '.join(columns)}) VALUES ({placeholders})",
        values,
    )


STAR_CAP = 3
WRITER_CAP = 3
PREVIEW_CAP = 3
TOP_EPISODES = 5
# Below this, a billed actor is a bit part when the title already has a
# recognisable face. The lead stays even when everyone is this quiet.
POP_FLOOR = 1.0
WRITER_JOBS = ("Writer", "Screenplay", "Story", "Teleplay", "Comic Book")
COUNT_JOBS = (
    "Director", "Writer", "Screenplay", "Story", "Teleplay",
    "Producer", "Executive Producer", "Co-Producer",
    "Creator", "Original Series Creator",
)

PRESENTATION = """
CREATE TABLE person (
  person_id INTEGER PRIMARY KEY,
  name_ru TEXT,
  name_en TEXT,
  gender INTEGER,
  popularity REAL,
  known_for_department TEXT,
  profile_url TEXT
);

CREATE TABLE image (
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
CREATE UNIQUE INDEX image_key ON image (
  kinopub_id, kind, IFNULL(lang, ''), url,
  IFNULL(person_id, 0), IFNULL(season, -1), IFNULL(episode, -1)
);

CREATE TABLE billing (
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

CREATE TABLE billing_role (
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

CREATE TABLE cast_count (
  kinopub_id INTEGER NOT NULL,
  section TEXT NOT NULL,
  total INTEGER NOT NULL,
  PRIMARY KEY (kinopub_id, section)
);

CREATE TABLE top_episode (
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

CREATE TABLE network (
  kinopub_id INTEGER NOT NULL,
  tmdb_id INTEGER NOT NULL,
  name TEXT,
  logo_url TEXT,
  origin_country TEXT,
  PRIMARY KEY (kinopub_id, tmdb_id)
);
"""


def _fill_presentation(dst, kv) -> dict[str, int]:
    """The page's cast, the pictures, and the episodes worth keeping.

    Featured people are stored in full. Regular cast keeps three names and a
    count. Guest cast and the crew we do not show are counts only, so a later
    request can ask TMDB or Kinopoisk for the rest. kv.db still has everyone.
    """
    dst.executescript(PRESENTATION)
    _add_column(dst, "card", "status", "TEXT")
    _add_column(dst, "card", "tagline_ru", "TEXT")

    for row in kv.execute("SELECT kinopub_id, status FROM document WHERE status IS NOT NULL AND status != ''"):
        dst.execute(
            "UPDATE card SET status = ? WHERE kinopub_id = ? AND status IS NULL",
            (row["status"], row["kinopub_id"]),
        )
    for row in kv.execute(
        """
        SELECT kinopub_id, text FROM synopsis
         WHERE variant = 'tagline' AND lang = 'ru' AND text IS NOT NULL AND text != ''
        """
    ):
        dst.execute(
            "UPDATE card SET tagline_ru = ? WHERE kinopub_id = ? AND tagline_ru IS NULL",
            (row["text"], row["kinopub_id"]),
        )

    by_title: dict[int, list[dict]] = {}
    for row in kv.execute(
        """
        SELECT c.kinopub_id, c.position, c.person_id, c.department, c.name_ru, c.name_en,
               c.gender, c.popularity, c.known_for_department, c.episode_count, c.character,
               p.profile_url
          FROM credit c
          LEFT JOIN person p ON p.tmdb_id = c.person_id
         ORDER BY c.kinopub_id, c.position
        """
    ):
        person = dict(row)
        person["roles"] = []
        by_title.setdefault(person["kinopub_id"], []).append(person)
    for row in kv.execute(
        "SELECT * FROM credit_role ORDER BY kinopub_id, position, role_ord"
    ):
        for person in by_title.get(row["kinopub_id"], []):
            if person["position"] == row["position"]:
                person["roles"].append(dict(row))
                break

    photo_of: dict[tuple, str] = {}
    for row in kv.execute(
        "SELECT kinopub_id, position, url FROM credit_photo ORDER BY photo_ord"
    ):
        photo_of.setdefault((row["kinopub_id"], row["position"]), row["url"])

    people: dict[int, dict] = {}
    images: list[tuple] = []
    billing: list[tuple] = []
    billing_roles: list[tuple] = []
    cast_counts: list[tuple] = []
    featured = 0

    for kinopub_id, group in by_title.items():
        chosen = _choose_billing(group)
        featured += chosen["featured"]
        for section, members in chosen["stored"].items():
            for position, person in enumerate(members):
                billing.append((
                    kinopub_id, section, position, person["person_id"], person["name_ru"],
                    person["name_en"], _first_character(person), _section_job(section, person),
                    person["episode_count"], person["popularity"],
                ))
                roles = person["roles"] or [{
                    "credit_id": None, "character": person["character"], "job": None,
                    "episode_count": person["episode_count"],
                }]
                for role_ord, role in enumerate(roles):
                    billing_roles.append((
                        kinopub_id, section, position, role_ord, role.get("credit_id"),
                        role.get("character"), role.get("job"), role.get("episode_count"),
                    ))
                if person["person_id"] is not None:
                    people[person["person_id"]] = person
                photo = person.get("profile_url") or photo_of.get((kinopub_id, person["position"]))
                if photo:
                    images.append((
                        kinopub_id, "photo", None, photo, "tmdb",
                        None, None, person["person_id"], None, None,
                    ))
        for section, total in chosen["counts"].items():
            if total:
                cast_counts.append((kinopub_id, section, total))

    for row in kv.execute("SELECT * FROM artwork"):
        images.append((
            row["kinopub_id"], row["kind"], row["lang"], row["url"], row["source"],
            row["width"], row["height"], None, None, None,
        ))
    for row in kv.execute("SELECT kinopub_id, number, poster_ru, poster_en, source FROM season"):
        for lang, url in (("ru", row["poster_ru"]), ("en", row["poster_en"])):
            if url:
                images.append((row["kinopub_id"], "poster", lang, url, row["source"], None, None, None, row["number"], None))
    known = {row[0] for row in kv.execute("SELECT kinopub_id FROM document")}
    for row in dst.execute(
        """
        SELECT kinopub_id, poster_ru, poster_en, cover_ru, cover_en, backdrop, logo_ru, logo_en
          FROM card
        """
    ):
        if row["kinopub_id"] not in known:
            continue
        for kind, lang, url in (
            ("poster", "ru", row["poster_ru"]), ("poster", "en", row["poster_en"]),
            ("cover", "ru", row["cover_ru"]), ("cover", "en", row["cover_en"]),
            ("backdrop", None, row["backdrop"]),
            ("logo", "ru", row["logo_ru"]), ("logo", "en", row["logo_en"]),
        ):
            if url:
                images.append((row["kinopub_id"], kind, lang, url, "card", None, None, None, None, None))

    networks = [
        (row["kinopub_id"], row["tmdb_id"], row["name"], row["logo_url"], row["origin_country"])
        for row in kv.execute("SELECT * FROM network")
    ]
    for kinopub_id, _tmdb_id, _name, logo, _country in networks:
        if logo:
            images.append((kinopub_id, "network", None, logo, "tmdb", None, None, None, None, None))

    top_rows, stills = _top_episodes(kv)
    images.extend(stills)

    dst.executemany(
        """
        INSERT INTO person (
          person_id, name_ru, name_en, gender, popularity, known_for_department, profile_url
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        [
            (person["person_id"], person["name_ru"], person["name_en"], person["gender"],
             person["popularity"], person["known_for_department"], person["profile_url"])
            for person in people.values()
        ],
    )
    dst.executemany(
        """
        INSERT OR IGNORE INTO image (
          kinopub_id, kind, lang, url, source, width, height, person_id, season, episode
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        images,
    )
    dst.executemany(
        """
        INSERT INTO billing (
          kinopub_id, section, position, person_id, name_ru, name_en, character, job,
          episode_count, popularity
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        billing,
    )
    dst.executemany(
        """
        INSERT INTO billing_role (
          kinopub_id, section, position, role_ord, credit_id, character, job, episode_count
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        billing_roles,
    )
    dst.executemany(
        "INSERT INTO cast_count (kinopub_id, section, total) VALUES (?, ?, ?)",
        cast_counts,
    )
    dst.executemany(
        """
        INSERT INTO top_episode (
          kinopub_id, rank, season, number, name_ru, name_en, tmdb_id,
          tmdb_value, tmdb_votes, imdb_value, imdb_votes, season_finale
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        top_rows,
    )
    dst.executemany(
        """
        INSERT INTO network (kinopub_id, tmdb_id, name, logo_url, origin_country)
        VALUES (?, ?, ?, ?, ?)
        """,
        networks,
    )
    return {
        "people": len(people),
        "images": dst.execute("SELECT COUNT(*) FROM image").fetchone()[0],
        "featured": featured,
        "top_episodes": len(top_rows),
    }


def _choose_billing(people: list[dict]) -> dict:
    actors = [person for person in people if person["department"] == "actor"]
    actors.sort(key=lambda person: person["position"] if person["position"] is not None else 9999)
    recognisable = [person for person in actors[:8] if not _obscure(person)]
    stars = []
    seen = set()
    for person in actors:
        if len(stars) >= STAR_CAP:
            break
        if _obscure(person) and recognisable:
            continue
        key = _person_key(person)
        if key in seen:
            continue
        seen.add(key)
        stars.append(person)
    if not stars:
        stars = actors[:STAR_CAP]

    director_pool = _people_with_jobs(people, ("Director",))
    if not director_pool:
        director_pool = _people_with_jobs(people, ("Creator", "Original Series Creator"))
    directors = director_pool[:1]
    writer_pool = _people_with_jobs(people, WRITER_JOBS)
    writers = writer_pool[:WRITER_CAP]

    star_keys = {_person_key(person) for person in stars}
    has_episodes = any(person["episode_count"] for person in actors)
    if has_episodes:
        peak = max(person["episode_count"] or 0 for person in actors)
        line = max(3, int(peak * 0.25))
        regular_pool = [
            person for person in actors
            if (person["episode_count"] or 0) >= line and _person_key(person) not in star_keys
        ]
        guest_pool = [
            person for person in actors
            if (person["episode_count"] or 0) < line and _person_key(person) not in star_keys
        ]
        preview = _preview(sorted(
            regular_pool,
            key=lambda person: (-(person["episode_count"] or 0), -(person["popularity"] or 0)),
        ))
    else:
        regular_pool = [person for person in actors if _person_key(person) not in star_keys]
        guest_pool = []
        preview = _preview(regular_pool)

    stored = {
        section: members
        for section, members in (
            ("star", stars), ("director", directors), ("writer", writers), ("regular", preview),
        )
        if members
    }
    featured_keys = {
        _person_key(person)
        for section in ("star", "director", "writer")
        for person in stored.get(section, [])
    }
    counts = {
        "featured": len(featured_keys),
        "star": len(stars),
        "director": len(director_pool),
        "writer": len(writer_pool),
        "regular": len(regular_pool),
        "guest": len(guest_pool),
    }
    for job in ("Producer", "Executive Producer", "Co-Producer"):
        total = len(_people_with_jobs(people, (job,)))
        if total:
            counts[job.lower().replace(" ", "_")] = total
    return {"stored": stored, "counts": counts, "featured": len(featured_keys)}


def _people_with_jobs(people: list[dict], jobs: tuple[str, ...]) -> list[dict]:
    found = []
    seen = set()
    ranked = {job: index for index, job in enumerate(jobs)}
    candidates = []
    for person in people:
        for role in person["roles"]:
            job = role.get("job")
            if job in ranked:
                candidates.append((ranked[job], person["position"] or 0, -(person["popularity"] or 0), person))
                break
    for _rank, _position, _pop, person in sorted(candidates, key=lambda item: item[:3]):
        key = _person_key(person)
        if key in seen:
            continue
        seen.add(key)
        found.append(person)
    return found


def _top_episodes(kv) -> tuple[list[tuple], list[tuple]]:
    scores: dict[tuple, dict] = {}
    for row in kv.execute(
        "SELECT kinopub_id, season, episode, source, value, votes FROM episode_rating"
    ):
        slot = scores.setdefault((row["kinopub_id"], row["season"], row["episode"]), {})
        slot[row["source"]] = (row["value"], row["votes"])
    grouped: dict[int, list] = {}
    for row in kv.execute("SELECT * FROM episode"):
        key = (row["kinopub_id"], row["season"], row["number"])
        rating = scores.get(key)
        if not rating:
            continue
        mark = _episode_mark(rating)
        if mark is None:
            continue
        grouped.setdefault(row["kinopub_id"], []).append((mark, row, rating))
    rows = []
    stills = []
    for kinopub_id, episodes in grouped.items():
        episodes.sort(key=lambda item: item[0], reverse=True)
        for rank, (_mark, episode, rating) in enumerate(episodes[:TOP_EPISODES], start=1):
            tmdb = rating.get("tmdb") or (None, None)
            imdb = rating.get("imdb") or (None, None)
            rows.append((
                kinopub_id, rank, episode["season"], episode["number"], episode["name_ru"],
                episode["name_en"], episode["tmdb_id"], tmdb[0], tmdb[1], imdb[0], imdb[1],
                episode["season_finale"],
            ))
            if episode["still"]:
                stills.append((
                    kinopub_id, "still", None, episode["still"], "tmdb", None, None, None,
                    episode["season"], episode["number"],
                ))
    return rows, stills


def _episode_mark(rating: dict) -> tuple | None:
    imdb = rating.get("imdb")
    tmdb = rating.get("tmdb")
    if imdb and imdb[1] and imdb[1] >= 50:
        return (imdb[0] or 0, imdb[1])
    if tmdb and tmdb[1] and tmdb[1] >= 10:
        return (tmdb[0] or 0, tmdb[1])
    if imdb and imdb[1]:
        return (imdb[0] or 0, imdb[1])
    return None


def _preview(pool: list[dict]) -> list[dict]:
    """Two or three names under the count. Skip a bit part when a face is available."""
    picked = []
    for person in pool:
        if len(picked) >= PREVIEW_CAP:
            break
        if _obscure(person) and any(not _obscure(other) for other in pool):
            continue
        picked.append(person)
    if len(picked) < min(PREVIEW_CAP, len(pool)):
        for person in pool:
            if person in picked:
                continue
            picked.append(person)
            if len(picked) >= PREVIEW_CAP:
                break
    return picked


def _obscure(person: dict) -> bool:
    popularity = person["popularity"]
    return popularity is not None and popularity < POP_FLOOR


def _person_key(person: dict):
    if person["person_id"] is not None:
        return ("id", person["person_id"])
    return ("pos", person["position"], person["name_ru"])


def _first_character(person: dict):
    for role in person["roles"]:
        if role.get("character"):
            return role["character"]
    return person["character"]


def _section_job(section: str, person: dict):
    if section == "director":
        for role in person["roles"]:
            if role.get("job") in ("Director", "Creator", "Original Series Creator"):
                return role["job"]
    if section == "writer":
        for role in person["roles"]:
            if role.get("job") in WRITER_JOBS:
                return role["job"]
    return None


def _add_column(db, table: str, name: str, decl: str) -> None:
    have = {row[1] for row in db.execute(f"PRAGMA table_info({table})")}
    if name not in have:
        db.execute(f"ALTER TABLE {table} ADD COLUMN {name} {decl}")


def _merge_seasons(db, kv, kinopub_id: int) -> int:
    added = 0
    have = {
        row["number"]
        for row in db.execute("SELECT number FROM season WHERE kinopub_id = ?", (kinopub_id,))
    }
    for season in kv.execute("SELECT * FROM season WHERE kinopub_id = ?", (kinopub_id,)):
        if season["number"] in have:
            continue
        db.execute(
            """
            INSERT INTO season (kinopub_id, number, name, episodes, air_date, end_date, poster)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                kinopub_id, season["number"], season["name_ru"], season["episode_cnt"],
                season["air_date"], season["end_date"], season["poster_ru"],
            ),
        )
        added += 1
    return added


def _fill_season_fields(db, kv, kinopub_id: int) -> tuple[int, str | None]:
    """Fill a blank name, date, or poster. Leave an episode count that is already set."""
    filled = 0
    count_kept = None
    kv_seasons = {
        row["number"]: row
        for row in kv.execute("SELECT * FROM season WHERE kinopub_id = ?", (kinopub_id,))
    }
    for current in db.execute("SELECT * FROM season WHERE kinopub_id = ?", (kinopub_id,)):
        incoming = kv_seasons.get(current["number"])
        if incoming is None:
            continue
        # A different episode count means this row is not that season.
        # Copying the archive's name onto it would label the wrong run.
        if (
            current["episodes"] and incoming["episode_cnt"]
            and current["episodes"] != incoming["episode_cnt"]
        ):
            if count_kept is None:
                count_kept = (
                    f"{kinopub_id} season {current['number']} episodes"
                    f" card={current['episodes']} kv={incoming['episode_cnt']}"
                )
            continue
        sets = []
        values = []
        for column, new in (
            ("name", incoming["name_ru"]),
            ("air_date", incoming["air_date"]),
            ("end_date", incoming["end_date"]),
            ("poster", incoming["poster_ru"]),
        ):
            if _blank(current[column]) and not _blank(new):
                sets.append(f"{column} = ?")
                values.append(new)
        if (not current["episodes"]) and incoming["episode_cnt"]:
            sets.append("episodes = ?")
            values.append(incoming["episode_cnt"])
        if not sets:
            continue
        values.extend((kinopub_id, current["number"]))
        db.execute(
            f"UPDATE season SET {', '.join(sets)} WHERE kinopub_id = ? AND number = ?",
            values,
        )
        filled += 1
    return filled, count_kept


def _art(rows, kind: str, lang: str | None) -> str | None:
    for row in rows:
        if row["kind"] == kind and row["lang"] == lang:
            return row["url"]
    return None


def _id_slot(slot) -> tuple[str | None, float | None, str | None]:
    if isinstance(slot, dict):
        return _text(slot.get("value")), slot.get("confidence"), slot.get("method")
    return _text(slot), None, None


def _pair(value) -> tuple[str | None, str | None]:
    return _localized(value)


def _localized(value) -> tuple[str | None, str | None]:
    if isinstance(value, dict):
        return _text(value.get("ru")), _text(value.get("en"))
    return _text(value), None


def _score(value, require_votes: bool = True) -> tuple[float | None, int | None]:
    if not isinstance(value, dict):
        return None, None
    raw = value.get("value")
    votes = value.get("votes")
    if raw is None or (require_votes and not votes):
        return None, None
    return raw, votes


def _imdb_score(value) -> tuple[float | None, int | None]:
    if isinstance(value, dict) and isinstance(value.get("value"), (int, float)):
        return _score(value)
    return None, None


def _episode_imdb(value) -> str | None:
    if isinstance(value, dict):
        raw = value.get("id") or value.get("tconst")
        if raw is None and isinstance(value.get("value"), str):
            raw = value.get("value")
        return _imdb(_text(raw))
    return _imdb(_text(value))


def _attach_imdb_episode_ratings(db) -> int:
    """IMDb's per-episode ratings already live in record-v2. Copy the ones
    whose season and episode number match a row we just stored."""
    record = DATA / "record-v2.db"
    if not record.exists():
        return 0
    db.execute("ATTACH DATABASE ? AS record", (str(record),))
    before = db.execute("SELECT COUNT(*) FROM episode_rating WHERE source = 'imdb'").fetchone()[0]
    db.execute(
        """
        INSERT OR REPLACE INTO episode_rating (kinopub_id, season, episode, source, value, votes)
        SELECT CAST(ext.value AS INTEGER), r.season, r.episode, 'imdb', r.value, r.votes
          FROM record.rating r
          JOIN record.title_external_id ext
            ON ext.title_id = r.title_id AND ext.namespace = 'kinopub'
          JOIN episode e
            ON e.kinopub_id = CAST(ext.value AS INTEGER)
           AND e.season = r.season
           AND e.number = r.episode
         WHERE r.source = 'imdb'
           AND r.season IS NOT NULL
           AND r.episode IS NOT NULL
           AND r.value IS NOT NULL
        """
    )
    after = db.execute("SELECT COUNT(*) FROM episode_rating WHERE source = 'imdb'").fetchone()[0]
    db.commit()
    db.execute("DETACH DATABASE record")
    return after - before


def _imdb(value: str | None) -> str | None:
    if not value:
        return None
    if value.startswith("tt"):
        return value
    if value.isdigit():
        return "tt" + value.zfill(7)
    return value


def _label(value) -> str | None:
    if isinstance(value, dict):
        return _text(value.get("ru")) or _text(value.get("en"))
    return _text(value)


def _text(value) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _blank(value) -> bool:
    return value is None or value == ""


def _flag(value) -> int | None:
    if value is None:
        return None
    return 1 if value else 0


if __name__ == "__main__":
    main()
