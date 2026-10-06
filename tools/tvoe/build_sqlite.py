#!/usr/bin/env python3
"""Build tvoe_data/tvoe.sqlite from the JSON dump. Replaces the file each run."""

import json
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = HERE / "tvoe_data"
DB = DATA / "tvoe.sqlite"
SCHEMA = HERE / "schema.sql"


def flag(value):
    return 1 if value else 0


def image(node):
    if not isinstance(node, dict):
        return None, None
    return node.get("src"), node.get("cdnUrl")


def dumps(value):
    if value is None:
        return None
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def video_row(title_id, kind, season, position, video):
    return (
        video.get("_id"),
        title_id,
        kind,
        season,
        position,
        video.get("nameForUser"),
        video.get("duration"),
        video.get("version"),
        video.get("src"),
        video.get("thumbnail"),
        video.get("thumbnailUrl"),
        None if video.get("published") is None else flag(video.get("published")),
        None if video.get("hasMP4") is None else flag(video.get("hasMP4")),
        video.get("releaseDate"),
        video.get("previewStartTime"),
        video.get("previewEndTime"),
        video.get("creditsStartTime"),
        video.get("creditsEndTime"),
        video.get("replayStartTime"),
        video.get("replayEndTime"),
        dumps(video.get("qualities")),
        dumps(video.get("audio")),
        dumps(video.get("subtitles")),
    )


def load_title(conn, item):
    title_id = item["_id"]
    badge = item.get("badge") or {}
    poster_src, poster_cdn = image(item.get("poster"))
    cover_src, cover_cdn = image(item.get("cover"))
    logo_src, logo_cdn = image(item.get("logo"))
    conn.execute(
        """INSERT INTO title (
            id, category, name, orig_name, short_desc, full_desc, age_level,
            date_released, poster_date, rating, duration, seasons_count, url,
            genre_name, badge_type, badge_start, badge_finish,
            poster_src, poster_cdn, cover_src, cover_cdn, logo_src, logo_cdn,
            ultra_hd, in_subscribe_soon, is_new_season, is_favorite
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (
            title_id,
            item.get("categoryAlias"),
            item.get("name"),
            item.get("origName"),
            item.get("shortDesc"),
            item.get("fullDesc"),
            item.get("ageLevel"),
            item.get("dateReleased"),
            item.get("posterDate"),
            item.get("rating"),
            item.get("duration"),
            item.get("seasonsCount"),
            item.get("url"),
            item.get("genreName"),
            badge.get("type"),
            badge.get("startAt"),
            badge.get("finishAt"),
            poster_src, poster_cdn, cover_src, cover_cdn, logo_src, logo_cdn,
            flag(item.get("ultraHdQuality")),
            flag(item.get("inSubscribeSoon")),
            flag(item.get("isNewSeason")),
            flag(item.get("isFavorite")),
        ),
    )

    names = item.get("genreNames") or []
    aliases = item.get("genresAliases") or []
    for ord_, alias in enumerate(aliases):
        name = names[ord_] if ord_ < len(names) else None
        conn.execute(
            "INSERT INTO title_genre (title_id, ord, alias, name) VALUES (?,?,?,?)",
            (title_id, ord_, alias, name),
        )
    for ord_, name in enumerate(item.get("countries") or []):
        if name:
            conn.execute(
                "INSERT INTO title_country (title_id, ord, name) VALUES (?,?,?)",
                (title_id, ord_, name),
            )
    for ord_, similar_id in enumerate(item.get("similarItems") or []):
        if isinstance(similar_id, str):
            conn.execute(
                "INSERT INTO title_similar (title_id, ord, similar_id) VALUES (?,?,?)",
                (title_id, ord_, similar_id),
            )
    for ord_, person in enumerate(item.get("persons") or []):
        conn.execute(
            "INSERT INTO credit (title_id, ord, name, role) VALUES (?,?,?,?)",
            (title_id, ord_, person.get("name"), person.get("type")),
        )

    videos = item.get("videos") or {}
    rows = []
    for position, video in enumerate(videos.get("films") or [], start=1):
        rows.append(video_row(title_id, "feature", None, position, video))
    for position, video in enumerate(videos.get("trailers") or [], start=1):
        rows.append(video_row(title_id, "trailer", None, position, video))
    for season_index, season in enumerate(videos.get("seasons") or [], start=1):
        for position, video in enumerate(season or [], start=1):
            rows.append(video_row(title_id, "episode", season_index, position, video))
    conn.executemany(
        """INSERT INTO video (
            id, title_id, kind, season, position, name, duration, version, src,
            thumbnail, thumbnail_url, published, has_mp4, release_date,
            preview_start, preview_end, credits_start, credits_end,
            replay_start, replay_end, qualities, audio, subtitles
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        rows,
    )

    review_rows = []
    for review in (item.get("reviews") or {}).get("items") or []:
        user = review.get("user") or {}
        review_rows.append((
            review.get("_id"),
            title_id,
            review.get("rating"),
            review.get("review"),
            review.get("updatedAt"),
            user.get("_id"),
            user.get("displayName") or None,
            user.get("firstname") or None,
            user.get("lastname") or None,
            user.get("avatar") or None,
        ))
    conn.executemany(
        """INSERT INTO review (
            id, title_id, rating, body, updated_at, user_id, user_name,
            first_name, last_name, avatar
        ) VALUES (?,?,?,?,?,?,?,?,?,?)""",
        review_rows,
    )
    conn.execute(
        "INSERT INTO title_raw (title_id, body) VALUES (?,?)",
        (title_id, dumps(item)),
    )


def load_shorts(conn):
    rows = []
    for row in json.loads((DATA / "shorts.json").read_text()):
        rows.append((
            row.get("id"),
            row.get("title"),
            row.get("coverFileSrc"),
            row.get("coverCdnUrl"),
            row.get("videoFileSrc"),
            row.get("videoHlsSrc"),
            row.get("thumbnailSrc"),
            row.get("thumbnailCdnUrl"),
            flag(row.get("isPinnedOnMain")),
            row.get("link"),
            row.get("buttonText"),
            row.get("viewsCount"),
            row.get("publishedAt"),
            row.get("viewAt"),
            row.get("movieId"),
            row.get("movieTitle"),
            row.get("movieLogo"),
            row.get("movieLogoCdnUrl"),
            row.get("movieCategory"),
            row.get("movieGenre"),
            row.get("movieAgeLevel"),
        ))
    conn.executemany(
        """INSERT INTO short (
            id, title, cover_src, cover_cdn, video_file_src, video_hls_src,
            thumbnail_src, thumbnail_cdn, is_pinned, link, button_text,
            views_count, published_at, view_at, movie_id, movie_title,
            movie_logo, movie_logo_cdn, movie_category, movie_genre, movie_age_level
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        rows,
    )


def main():
    if DB.exists():
        DB.unlink()
    conn = sqlite3.connect(DB)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.executescript(SCHEMA.read_text())
    files = sorted((DATA / "details").glob("*.json"))
    with conn:
        for path in files:
            load_title(conn, json.loads(path.read_text()))
        load_shorts(conn)
        if (DATA / "filters.json").exists():
            conn.execute(
                "INSERT INTO source_meta (key, value) VALUES ('filters', ?)",
                ((DATA / "filters.json").read_text(),),
            )
        if (DATA / "state.json").exists():
            conn.execute(
                "INSERT INTO source_meta (key, value) VALUES ('state', ?)",
                ((DATA / "state.json").read_text(),),
            )
    counts = {
        name: conn.execute(f"SELECT count(*) FROM {name}").fetchone()[0]
        for name in ("title", "title_genre", "credit", "video", "review", "short", "title_raw")
    }
    by_kind = dict(conn.execute("SELECT kind, count(*) FROM video GROUP BY kind"))
    cartoons = conn.execute(
        """SELECT count(*) FROM title t
           JOIN title_genre g ON g.title_id = t.id
           WHERE g.alias = 'multfilmy'"""
    ).fetchone()[0]
    conn.close()
    print(f"wrote {DB}")
    print(counts)
    print("videos", by_kind)
    print("multfilmy titles", cartoons)


if __name__ == "__main__":
    sys.exit(main())
