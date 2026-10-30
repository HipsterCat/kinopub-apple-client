#!/usr/bin/env python3
"""Replace the D1 card tables with the local card-2.db.

    python3 upload_card2.py

Reads tools/metadata-ingest/data/card-2.db and loads kinopub-catalog.
Re-running drops c2_* and writes them again, so a later KV import can
be followed by this without merging by hand. The 99k warehouse episode
rows stay local: the worker serves top_episode.
"""

from __future__ import annotations

import sqlite3
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data" / "card-2.db"
SCHEMA = ROOT.parent.parent / "workers" / "tmdb-proxy" / "schema" / "card2.sql"
WORKER = ROOT.parent.parent / "workers" / "tmdb-proxy"
DB_NAME = "kinopub-catalog"
BATCH = 40

TABLES = {
    "card": "c2_card",
    "person": "c2_person",
    "billing": "c2_billing",
    "billing_role": "c2_billing_role",
    "cast_count": "c2_cast_count",
    "image": "c2_image",
    "top_episode": "c2_top_episode",
    "network": "c2_network",
    "season": "c2_season",
}


def main() -> None:
    if "--episodes" in sys.argv:
        upload_episodes()
        return
    if not DATA.exists():
        sys.exit(f"missing {DATA}")
    src = sqlite3.connect(f"file:{DATA}?mode=ro", uri=True)
    src.row_factory = sqlite3.Row
    execute_sql(SCHEMA.read_text())
    for local, remote in TABLES.items():
        columns = [row[1] for row in src.execute(f"PRAGMA table_info({local})")]
        rows = src.execute(f"SELECT * FROM {local}")
        chunk = []
        total = 0
        while True:
            fetched = rows.fetchmany(BATCH)
            if not fetched:
                break
            chunk.append(insert_sql(remote, columns, fetched))
            total += len(fetched)
            if len(chunk) == 8:
                execute_sql("\n".join(chunk))
                chunk = []
                print(f"  {remote} {total}", flush=True)
        if chunk:
            execute_sql("\n".join(chunk))
        print(f"{remote} {total}", flush=True)
    src.close()


def insert_sql(table: str, columns: list[str], rows) -> str:
    names = ", ".join(columns)
    values = ", ".join("(" + ", ".join(sql_literal(row[name]) for name in columns) + ")" for row in rows)
    return f"INSERT INTO {table} ({names}) VALUES {values};"


def sql_literal(value) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value).replace("'", "''")
    return f"'{text}'"


EPISODE_COLUMNS = [
    "kinopub_id", "season", "number", "name_ru", "name_en", "runtime_min", "air_date",
    "still", "imdb_id", "tmdb_id", "season_tmdb_id", "episode_type", "season_finale",
    "tmdb_value", "tmdb_votes", "imdb_value", "imdb_votes",
]

EPISODE_DDL = """
CREATE TABLE IF NOT EXISTS c2_episode (
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
DELETE FROM c2_episode;
"""


def upload_episodes() -> None:
    """Every episode: the catalogue's own rows, then the KV rows on top."""
    merged: dict[tuple, dict] = {}
    card = sqlite3.connect(f"file:{DATA}?mode=ro", uri=True)
    card.row_factory = sqlite3.Row
    for row in card.execute(
        "SELECT kinopub_id, season, number, name_ru, name_en, air_date, runtime_min, still FROM episode"
    ):
        merged[(row["kinopub_id"], row["season"], row["number"])] = blank_episode(row)
    card.close()
    kv_path = DATA.parent / "kv.db"
    if kv_path.exists():
        kv = sqlite3.connect(f"file:{kv_path}?mode=ro", uri=True)
        kv.row_factory = sqlite3.Row
        ratings: dict[tuple, dict] = {}
        for row in kv.execute(
            "SELECT kinopub_id, season, episode, source, value, votes FROM episode_rating"
        ):
            ratings.setdefault((row["kinopub_id"], row["season"], row["episode"]), {})[row["source"]] = row
        for row in kv.execute("SELECT * FROM episode"):
            key = (row["kinopub_id"], row["season"], row["number"])
            item = blank_episode(row)
            item.update({
                "imdb_id": row["imdb_id"], "tmdb_id": row["tmdb_id"],
                "season_tmdb_id": row["season_tmdb_id"], "episode_type": row["episode_type"],
                "season_finale": row["season_finale"],
            })
            score = ratings.get(key, {})
            if "tmdb" in score:
                item["tmdb_value"] = score["tmdb"]["value"]
                item["tmdb_votes"] = score["tmdb"]["votes"]
            if "imdb" in score:
                item["imdb_value"] = score["imdb"]["value"]
                item["imdb_votes"] = score["imdb"]["votes"]
            merged[key] = item
        kv.close()
    execute_sql(EPISODE_DDL)
    rows = list(merged.values())
    print(f"episodes {len(rows)}", flush=True)
    for start in range(0, len(rows), BATCH * 8):
        part = rows[start:start + BATCH * 8]
        chunk = []
        for offset in range(0, len(part), BATCH):
            chunk.append(insert_sql("c2_episode", EPISODE_COLUMNS, part[offset:offset + BATCH]))
        execute_sql("\n".join(chunk))
        print(f"  c2_episode {min(start + BATCH * 8, len(rows))}", flush=True)
    print(f"c2_episode {len(rows)}", flush=True)


def blank_episode(row) -> dict:
    return {
        "kinopub_id": row["kinopub_id"], "season": row["season"], "number": row["number"],
        "name_ru": row["name_ru"], "name_en": row["name_en"],
        "runtime_min": row["runtime_min"], "air_date": row["air_date"], "still": row["still"],
        "imdb_id": None, "tmdb_id": None, "season_tmdb_id": None, "episode_type": None,
        "season_finale": None, "tmdb_value": None, "tmdb_votes": None,
        "imdb_value": None, "imdb_votes": None,
    }


def execute_sql(sql: str) -> None:
    path = WORKER / ".card2-batch.sql"
    path.write_text(sql)
    try:
        proc = subprocess.run(
            ["npx", "wrangler", "d1", "execute", DB_NAME, "--remote", "--yes", f"--file={path.name}"],
            cwd=WORKER,
            capture_output=True,
            text=True,
        )
    finally:
        path.unlink(missing_ok=True)
    if proc.returncode != 0:
        sys.exit((proc.stderr or proc.stdout)[-1500:])


if __name__ == "__main__":
    main()
