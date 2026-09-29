#!/usr/bin/env python3
"""Our genre ids, the same table the app reads.

The table is `Packages/KinoPubMedia/Sources/KinoPubMedia/Resources/genres.json` —
one file for the Swift package, this pipeline and the worker, so a document and
the app never disagree on what `drama` is. Matching mirrors
`GenreVocabulary.swift`: ids first where a source has them, names otherwise,
case- and diacritic-insensitive, the hinted domain before the other.

A name nobody mapped is not dropped: it comes back as `<source>:<name>` with
`mapped: False`, the same shape the app uses.
"""

from __future__ import annotations

import json
import unicodedata
from functools import lru_cache
from pathlib import Path

TABLE = (Path(__file__).resolve().parents[2]
         / "Packages/KinoPubMedia/Sources/KinoPubMedia/Resources/genres.json")

# Mirrors `MediaPrecedence.standard` for `.genres`: one source's list wins
# whole, never a splice, because its order is the claim — its first genre is
# the primary one. Sources not listed rank after these, alphabetically.
PRECEDENCE = ("apple", "kinopub", "tmdb", "kinopoisk")

# Rows in the record's `genre` table that are not genres at all.
NOT_GENRE_SOURCES = ("tmdb:keyword",)


def normalize(name: str) -> str:
    decomposed = unicodedata.normalize("NFKD", name.casefold())
    folded = "".join(c for c in decomposed if not unicodedata.combining(c))
    return " ".join(folded.split())


@lru_cache(maxsize=1)
def table() -> dict:
    data = json.loads(TABLE.read_text())
    by_id = {row["id"]: row for row in data["genres"]}
    by_alias: dict[str, dict[str, dict]] = {"video": {}, "music": {}}
    for row in data["genres"]:
        for name in [row["en"], row["ru"], *row.get("aliases", [])]:
            by_alias[row["domain"]].setdefault(normalize(name), row)
    by_tmdb: dict[int, list[dict]] = {}
    for row in data["genres"]:
        for tmdb_id in row.get("tmdb", []):
            by_tmdb.setdefault(tmdb_id, []).append(row)
    by_kinopub = {kp: row for row in data["genres"] for kp in row.get("kinopub", [])}
    labels = {kp: label for label in data["labels"] for kp in label.get("kinopub", [])}
    pairs = {int(k): [by_id[g] for g in v] for k, v in data["tmdb_pairs"].items()}
    return {"by_id": by_id, "by_alias": by_alias, "by_tmdb": by_tmdb,
            "by_kinopub": by_kinopub, "labels": labels, "pairs": pairs}


def _genre(row: dict) -> dict:
    return {"id": row["id"], "domain": row["domain"],
            "name": {"en": row["en"], "ru": row["ru"]}, "group": row["group"],
            "mapped": True}


def _unmapped(source: str, key: str, name: str, domain: str) -> dict:
    return {"id": f"{source}:{key}", "domain": domain, "name": {"en": name, "ru": name},
            "group": None, "mapped": False}


def named(name: str, domain: str = "video") -> dict | None:
    key = normalize(name)
    if not key:
        return None
    for candidate in (("music", "video") if domain == "music" else ("video", "music")):
        row = table()["by_alias"][candidate].get(key)
        if row:
            return _genre(row)
    return None


def from_name(name: str, source: str, domain: str = "video") -> dict:
    return named(name, domain) or _unmapped(source, normalize(name), name, domain)


def from_tmdb(tmdb_id: int, name: str | None = None) -> list[dict]:
    t = table()
    if tmdb_id in t["pairs"]:
        return [_genre(row) for row in t["pairs"][tmdb_id]]
    if tmdb_id in t["by_tmdb"]:
        return [_genre(row) for row in t["by_tmdb"][tmdb_id]]
    if name and (hit := named(name)):
        return [hit]
    return [_unmapped("tmdb", str(tmdb_id), name or str(tmdb_id), "video")]


def from_kinopub(kp_id: int, title: str | None = None, domain: str = "video") -> dict | None:
    """None for the ids that are labels, not genres ("Эксклюзив")."""
    t = table()
    if kp_id in t["labels"]:
        return None
    if kp_id in t["by_kinopub"]:
        return _genre(t["by_kinopub"][kp_id])
    if title and (hit := named(title, domain)):
        return hit
    return _unmapped("kinopub", str(kp_id), title or str(kp_id), domain)


def kinopub_label(kp_id: int) -> dict | None:
    label = table()["labels"].get(kp_id)
    if not label:
        return None
    return {"id": label["id"], "name": {"en": label["en"], "ru": label["ru"]},
            "source": "kinopub", "source_key": f"genre:{kp_id}"}


def merge(rows: list[dict]) -> list[dict]:
    """The record's `genre` rows (`source`, `name`) → one ordered list of ours.

    One source's list whole, the best-ranked source that has any. Rows keep
    their insertion order within a source (SQLite rowid), which is the order
    the source gave them in.
    """
    by_source: dict[str, list[dict]] = {}
    for row in rows:
        if row["source"] in NOT_GENRE_SOURCES:
            continue
        genre = from_name(row["name"], row["source"])
        listed = by_source.setdefault(row["source"], [])
        if all(g["id"] != genre["id"] for g in listed):
            listed.append(dict(genre, source=row["source"]))

    def rank(source: str) -> tuple[int, str]:
        return (PRECEDENCE.index(source) if source in PRECEDENCE else len(PRECEDENCE), source)

    for source in sorted(by_source, key=rank):
        if by_source[source]:
            return by_source[source]
    return []
