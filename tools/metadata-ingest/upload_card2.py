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
