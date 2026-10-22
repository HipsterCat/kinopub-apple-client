#!/usr/bin/env python3
"""
Snapshot of the kino.pub library (parent-level items only — movies, series, etc.,
not individual episodes) into a local SQLite file, for later offline matching
against external metadata (awards, etc.).

Auth: reads the live access/refresh token out of the macOS login keychain
(service "com.kunst.kinopub", written there by the Apple client itself),
refreshing via /oauth2/token when it expires. A local copy is cached in
data/token_cache.json so re-runs don't need Keychain access every time.

Usage:
  python3 snapshot.py                       # full sweep, all types
  python3 snapshot.py --types movie,serial  # only these types
  python3 snapshot.py --resume              # continue from last saved page per type
  python3 snapshot.py --db path/to/other.db
  python3 snapshot.py --dev-session --catch-up
      # newest pages of every type, until the local count matches the live catalog
  python3 snapshot.py --dev-session --probe-missing --from-id 1 --to-id 128416
      # one GET per missing id; 404 stays empty. Resumes from data/probe_progress.json

--dev-session reads ~/.kinopub-dev-session.json and keeps the access token only.
It does not call the Keychain and does not refresh: a refresh rotates the token
and can sign the live app out of one of its device slots.
"""
import argparse
import json
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
import sqlite3

BASE_URL = "https://api.service-kp.com"
KEYCHAIN_SERVICE = "com.kunst.kinopub"
KEYCHAIN_ACCOUNT = "com.kunst.kinopub.token"
# Public device-auth client used by every kino.pub client (Kodi addon included) —
# the same pair already baked into KinoPubAppleClient/Info.plist. Only needed here
# to refresh an expired access token via grant_type=refresh_token.
CLIENT_ID = "xbmc"
CLIENT_SECRET = "cgg3gtifu46urtfp2zp1nqtba0k2ezxh"

ALL_TYPES = ["movie", "serial", "docuserial", "documovie", "concert", "tvshow", "3D"]
PER_PAGE = 50
REQUEST_DELAY = 0.4
MAX_RETRIES = 5

DATA_DIR = Path(__file__).parent / "data"
TOKEN_CACHE = DATA_DIR / "token_cache.json"
STATE_FILE = DATA_DIR / "progress.json"
PROBE_STATE = DATA_DIR / "probe_progress.json"
PROBE_FOUND = DATA_DIR / "probe_found.jsonl"
DEFAULT_DB = DATA_DIR / "snapshot.db"
DEV_SESSION = Path.home() / ".kinopub-dev-session.json"

SCHEMA = """
CREATE TABLE IF NOT EXISTS items (
  id INTEGER PRIMARY KEY,
  type TEXT NOT NULL,
  subtype TEXT,
  title TEXT NOT NULL,
  title_ru TEXT,
  title_original TEXT,
  year INTEGER,
  countries TEXT,
  imdb_id INTEGER,
  imdb_rating REAL,
  imdb_votes INTEGER,
  kinopoisk_id INTEGER,
  kinopoisk_rating REAL,
  kinopoisk_votes INTEGER,
  kinopub_rating_votes INTEGER,
  kinopub_rating_percentage REAL,
  views INTEGER,
  poster_thumb TEXT,
  poster_wide TEXT,
  finished INTEGER,
  created_at INTEGER,
  updated_at INTEGER,
  first_synced_at TEXT NOT NULL,
  last_synced_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_items_imdb ON items(imdb_id);
CREATE INDEX IF NOT EXISTS idx_items_kinopoisk ON items(kinopoisk_id);
CREATE INDEX IF NOT EXISTS idx_items_type ON items(type);
CREATE INDEX IF NOT EXISTS idx_items_created ON items(created_at);
"""


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def load_token_cache():
    if TOKEN_CACHE.exists():
        return json.loads(TOKEN_CACHE.read_text())
    return None


def save_token_cache(token):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    TOKEN_CACHE.write_text(json.dumps(token))


def token_from_keychain():
    """Best-effort only — the Keychain ACL prompt can be denied/cancelled (exit 128),
    in which case callers fall back to a manually supplied token."""
    out = subprocess.run(
        ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE,
         "-a", KEYCHAIN_ACCOUNT, "-w"],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        return None
    return json.loads(out.stdout.strip())


def refresh_token(refresh_token_value):
    data = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "refresh_token": refresh_token_value,
    }).encode()
    req = urllib.request.Request(f"{BASE_URL}/oauth2/token", data=data, method="POST")
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def get_access_token(cli_token):
    if cli_token:
        token = {"access_token": cli_token}
        save_token_cache(token)
        return token
    token = load_token_cache() or token_from_keychain()
    if not token:
        sys.exit(
            "No token available. Either:\n"
            "  - approve the macOS Keychain prompt for 'com.kunst.kinopub' and re-run, or\n"
            "  - pass one from a live app session: --token <access_token>\n"
            "    (grab it from the app's CURLLoggingPlugin console output)"
        )
    save_token_cache(token)
    return token


# Rate limit as observed live: 100 req per short (~7-10s) window via
# X-Rate-Limit-{Limit,Remaining,Reset} response headers. Our request pace stays
# well under that; this is just a safety net if it's ever tighter than observed.
RATE_LIMIT_SAFETY_MARGIN = 15


def api_get(path, params, access_token):
    qs = urllib.parse.urlencode(params)
    req = urllib.request.Request(f"{BASE_URL}{path}?{qs}",
                                  headers={"Authorization": f"Bearer {access_token}"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        body = json.loads(resp.read())
        remaining = resp.headers.get("X-Rate-Limit-Remaining")
        reset = resp.headers.get("X-Rate-Limit-Reset")
        if remaining is not None and int(remaining) < RATE_LIMIT_SAFETY_MARGIN:
            pause = int(reset) + 1 if reset else 5
            print(f"  (rate limit {remaining} left, pausing {pause}s)", flush=True)
            time.sleep(pause)
        return body


def fetch_page(path, params, token_holder):
    """token_holder: mutable dict with 'access_token'/'refresh_token', refreshed in place on 401."""
    last_err = None
    for attempt in range(MAX_RETRIES):
        try:
            return api_get(path, params, token_holder["access_token"])
        except urllib.error.HTTPError as e:
            if e.code == 401:
                if not token_holder.get("refresh_token"):
                    sys.exit("Access token expired and no refresh_token on hand — "
                             "pass a fresh one with --token.")
                refreshed = refresh_token(token_holder["refresh_token"])
                token_holder.update(refreshed)
                save_token_cache(token_holder)
                continue
            if e.code == 429 or e.code >= 500:
                last_err = e
                time.sleep(2 ** attempt)
                continue
            raise
        except (urllib.error.URLError, TimeoutError) as e:
            last_err = e
            time.sleep(2 ** attempt)
    raise RuntimeError(f"giving up on {path} {params}: {last_err}")


def split_title(raw):
    if " / " in raw:
        ru, _, orig = raw.partition(" / ")
        return ru.strip(), orig.strip()
    return raw.strip(), None


def row_from_item(item, synced_at):
    title_ru, title_original = split_title(item.get("title", ""))
    posters = item.get("posters") or {}
    countries = [c.get("title") for c in (item.get("countries") or []) if c.get("title")]
    return {
        "id": item["id"],
        "type": item.get("type"),
        "subtype": item.get("subtype") or None,
        "title": item.get("title", ""),
        "title_ru": title_ru or None,
        "title_original": title_original,
        "year": item.get("year") or None,
        "countries": json.dumps(countries, ensure_ascii=False) if countries else None,
        "imdb_id": item.get("imdb") or None,
        "imdb_rating": item.get("imdb_rating"),
        "imdb_votes": item.get("imdb_votes"),
        "kinopoisk_id": item.get("kinopoisk") or None,
        "kinopoisk_rating": item.get("kinopoisk_rating"),
        "kinopoisk_votes": item.get("kinopoisk_votes"),
        "kinopub_rating_votes": item.get("rating_votes"),
        "kinopub_rating_percentage": item.get("rating_percentage"),
        "views": item.get("views"),
        "poster_thumb": posters.get("medium"),
        "poster_wide": posters.get("wide"),
        "finished": 1 if item.get("finished") else 0,
        "created_at": item.get("created_at"),
        "updated_at": item.get("updated_at"),
        "last_synced_at": synced_at,
    }


def upsert_items(conn, items, synced_at):
    rows = [row_from_item(it, synced_at) for it in items]
    conn.executemany(
        """
        INSERT INTO items (
          id, type, subtype, title, title_ru, title_original, year, countries,
          imdb_id, imdb_rating, imdb_votes, kinopoisk_id, kinopoisk_rating, kinopoisk_votes,
          kinopub_rating_votes, kinopub_rating_percentage, views,
          poster_thumb, poster_wide, finished, created_at, updated_at,
          first_synced_at, last_synced_at
        ) VALUES (
          :id, :type, :subtype, :title, :title_ru, :title_original, :year, :countries,
          :imdb_id, :imdb_rating, :imdb_votes, :kinopoisk_id, :kinopoisk_rating, :kinopoisk_votes,
          :kinopub_rating_votes, :kinopub_rating_percentage, :views,
          :poster_thumb, :poster_wide, :finished, :created_at, :updated_at,
          :last_synced_at, :last_synced_at
        )
        ON CONFLICT(id) DO UPDATE SET
          type=excluded.type, subtype=excluded.subtype, title=excluded.title,
          title_ru=excluded.title_ru, title_original=excluded.title_original,
          year=excluded.year, countries=excluded.countries,
          imdb_id=excluded.imdb_id, imdb_rating=excluded.imdb_rating, imdb_votes=excluded.imdb_votes,
          kinopoisk_id=excluded.kinopoisk_id, kinopoisk_rating=excluded.kinopoisk_rating,
          kinopoisk_votes=excluded.kinopoisk_votes,
          kinopub_rating_votes=excluded.kinopub_rating_votes,
          kinopub_rating_percentage=excluded.kinopub_rating_percentage,
          views=excluded.views, poster_thumb=excluded.poster_thumb, poster_wide=excluded.poster_wide,
          finished=excluded.finished, created_at=excluded.created_at, updated_at=excluded.updated_at,
          last_synced_at=excluded.last_synced_at
        """,
        rows,
    )
    conn.commit()


def load_state():
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {}


def save_state(state):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2))


def access_token_from_dev_session():
    """Access token only. Refreshing rotates the live app session."""
    if not DEV_SESSION.exists():
        sys.exit(f"No dev session at {DEV_SESSION}.")
    raw = json.loads(DEV_SESSION.read_text())
    access = raw.get("access_token")
    if not access:
        sys.exit(f"{DEV_SESSION} has no access_token.")
    token = {"access_token": access}
    save_token_cache(token)
    return token


def count_type(conn, media_type):
    return conn.execute(
        "SELECT COUNT(*) FROM items WHERE type = ? COLLATE NOCASE",
        (media_type,),
    ).fetchone()[0]


def print_summary(conn):
    total, lo, hi = conn.execute(
        "SELECT COUNT(*), MIN(id), MAX(id) FROM items"
    ).fetchone()
    print(f"items {total}  ids {lo}..{hi}", flush=True)
    for kind, count, top in conn.execute(
        "SELECT type, COUNT(*), MAX(id) FROM items GROUP BY type ORDER BY COUNT(*) DESC"
    ):
        print(f"  {kind} {count}  max {top}", flush=True)


def catch_up(conn, types, token_holder):
    """Page each type newest-first until the local count matches the live total.

    Stops early once the stored rows for that type equal pagination.total_items.
    If the table is still short, keeps going through the older pages — that is
    how a type skipped by an earlier run gets filled in.
    """
    added = 0
    for media_type in types:
        print(f"== catch-up {media_type} ==", flush=True)
        page = 1
        type_added = 0
        while True:
            data = fetch_page("/v1/items", {
                "type": media_type, "sort": "-created", "perpage": PER_PAGE, "page": page,
            }, token_holder)
            pagination = data.get("pagination") or {}
            total_pages = pagination.get("total") or page
            live_total = pagination.get("total_items")
            items = data.get("items") or []
            if not items:
                print(f"  [{media_type}] page {page} empty", flush=True)
                break
            ids = [it["id"] for it in items if it.get("id") is not None]
            known = set()
            if ids:
                placeholders = ",".join("?" * len(ids))
                known = {row[0] for row in conn.execute(
                    f"SELECT id FROM items WHERE id IN ({placeholders})", ids
                )}
            fresh = [
                it for it in items
                if it.get("id") is not None and it.get("id") not in known
            ]
            if fresh:
                upsert_items(conn, fresh, now_iso())
                type_added += len(fresh)
                added += len(fresh)
            db_count = count_type(conn, media_type)
            live = "" if live_total is None else f"/{live_total}"
            print(
                f"  [{media_type}] page {page}/{total_pages} "
                f"+{len(fresh)} (type +{type_added}) local {db_count}{live}",
                flush=True,
            )
            if live_total is not None and db_count >= live_total:
                break
            if page >= total_pages:
                if live_total is not None and db_count < live_total:
                    print(
                        f"  [{media_type}] short by {live_total - db_count} "
                        f"after the last page",
                        flush=True,
                    )
                break
            page += 1
            time.sleep(REQUEST_DELAY)
    return added


class RequestPace:
    """Spaces the start of each detail request, and holds when the budget is low."""

    def __init__(self, interval):
        self.interval = interval
        self._cv = threading.Condition()
        self._next_at = 0.0

    def acquire(self):
        with self._cv:
            now = time.time()
            slot = max(now, self._next_at)
            self._next_at = slot + self.interval
            delay = slot - now
        if delay > 0:
            time.sleep(delay)

    def hold(self, seconds):
        if seconds <= 0:
            return
        with self._cv:
            self._next_at = max(self._next_at, time.time() + seconds)


def observe_rate_limit(headers, pace):
    if not headers:
        return
    remaining = headers.get("X-Rate-Limit-Remaining")
    if remaining is None or int(remaining) >= RATE_LIMIT_SAFETY_MARGIN:
        return
    reset = headers.get("X-Rate-Limit-Reset")
    pause = int(reset) + 1 if reset is not None else 5
    if pause < 2:
        pause = 2
    print(f"  (rate limit {remaining} left, pausing {pause}s)", flush=True)
    pace.hold(pause)


def fetch_item(item_id, access_token, pace):
    """Detail read. 404 is an empty id. Does not refresh the token."""
    url = f"{BASE_URL}/v1/items/{item_id}?nolinks=1"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {access_token}"})
    last = None
    for attempt in range(MAX_RETRIES):
        pace.acquire()
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                observe_rate_limit(resp.headers, pace)
                body = json.loads(resp.read())
            item = body.get("item") if isinstance(body, dict) else None
            if not isinstance(item, dict) or item.get("id") is None:
                return item_id, "bad", None
            return item_id, "ok", item
        except urllib.error.HTTPError as e:
            e.read()
            observe_rate_limit(e.headers, pace)
            if e.code == 404:
                return item_id, "absent", None
            if e.code == 401:
                return item_id, "auth", None
            if e.code == 429 or e.code >= 500:
                last = e.code
                time.sleep(2 ** attempt)
                continue
            return item_id, "error", e.code
        except (urllib.error.URLError, TimeoutError) as e:
            last = str(e)
            time.sleep(2 ** attempt)
    return item_id, "error", last


def load_probe_state():
    if PROBE_STATE.exists():
        return json.loads(PROBE_STATE.read_text())
    return {}


def save_probe_state(state):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    tmp = PROBE_STATE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(state, indent=2))
    tmp.replace(PROBE_STATE)


def probe_missing(conn, access_token, start_id, end_id, concurrency, interval):
    """GET every integer in [start_id, end_id] that is not already a row.

    404 is recorded by advancing the cursor, not by inserting a row. A failed
    read stops before that id so a re-run retries it.
    """
    if end_id < start_id:
        print(f"Nothing to probe ({start_id}..{end_id}).", flush=True)
        return 0
    key = f"{start_id}-{end_id}"
    state = load_probe_state()
    slot = state.get(key) or {"through": start_id - 1, "found": 0, "absent": 0}
    cursor = max(int(slot.get("through", start_id - 1)), start_id - 1)
    found = int(slot.get("found", 0))
    absent = int(slot.get("absent", 0))
    if cursor >= end_id:
        print(f"Probe {key} already finished at {cursor}. found={found} absent={absent}", flush=True)
        return 0
    present = {row[0] for row in conn.execute(
        "SELECT id FROM items WHERE id BETWEEN ? AND ?", (start_id, end_id)
    )}
    print(
        f"== probe {start_id}..{end_id} from {cursor + 1} "
        f"({len(present)} already stored) ==",
        flush=True,
    )
    pace = RequestPace(interval)
    batch_size = max(concurrency * 10, 40)
    added = 0

    def persist(through, found_count, absent_count):
        slot["through"] = through
        slot["found"] = found_count
        slot["absent"] = absent_count
        slot["updated_at"] = now_iso()
        state[key] = slot
        save_probe_state(state)

    with ThreadPoolExecutor(max_workers=concurrency) as pool:
        while cursor < end_id:
            batch = []
            scan = cursor + 1
            while scan <= end_id and len(batch) < batch_size:
                if scan not in present:
                    batch.append(scan)
                scan += 1
            if not batch:
                cursor = end_id
                persist(cursor, found, absent)
                break
            futures = [
                pool.submit(fetch_item, item_id, access_token, pace) for item_id in batch
            ]
            by_id = {}
            for fut in as_completed(futures):
                item_id, status, payload = fut.result()
                by_id[item_id] = (status, payload)
            cut = None
            for item_id in batch:
                status, _payload = by_id[item_id]
                if status not in ("ok", "absent"):
                    cut = item_id
                    break
            fresh = []
            batch_found = 0
            batch_absent = 0
            for item_id in batch:
                if cut is not None and item_id >= cut:
                    break
                status, payload = by_id[item_id]
                if status == "ok":
                    fresh.append(payload)
                    present.add(item_id)
                    batch_found += 1
                    title = payload.get("title")
                    kind = payload.get("type")
                    print(f"  found {item_id} {kind} {title}", flush=True)
                    with PROBE_FOUND.open("a", encoding="utf-8") as fh:
                        fh.write(json.dumps(
                            {"id": item_id, "type": kind, "title": title},
                            ensure_ascii=False,
                        ) + "\n")
                else:
                    batch_absent += 1
            if fresh:
                upsert_items(conn, fresh, now_iso())
            found += batch_found
            absent += batch_absent
            added += batch_found
            if cut is not None:
                cursor = cut - 1
                persist(cursor, found, absent)
                status, detail = by_id[cut]
                if status == "auth":
                    sys.exit(
                        "Access token rejected. Not refreshing. "
                        "Re-run with a live --dev-session."
                    )
                print(
                    f"  stopping at {cursor}; id {cut} came back {status} {detail}",
                    flush=True,
                )
                sys.exit(1)
            cursor = scan - 1
            persist(cursor, found, absent)
            print(
                f"  through {cursor}/{end_id}  found {found}  absent {absent}",
                flush=True,
            )
    print(f"Probe {key} done. found {found}, absent {absent}.", flush=True)
    return added


def sync_type(conn, media_type, token_holder, state, resume):
    start_page = state.get(media_type, {}).get("last_completed_page", 0) + 1 if resume else 1
    page = start_page
    total_pages = None
    total_items_seen = 0
    while total_pages is None or page <= total_pages:
        data = fetch_page("/v1/items", {
            "type": media_type, "sort": "-created", "page": page,
        }, token_holder)
        pagination = data.get("pagination", {})
        total_pages = pagination.get("total", page)
        items = data.get("items", [])
        if not items:
            break
        upsert_items(conn, items, now_iso())
        total_items_seen += len(items)
        state[media_type] = {"last_completed_page": page, "total_pages": total_pages}
        save_state(state)
        print(f"  [{media_type}] page {page}/{total_pages} ({len(items)} items, "
              f"{total_items_seen} so far)", flush=True)
        page += 1
        time.sleep(REQUEST_DELAY)
    return total_items_seen


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--types", default=",".join(ALL_TYPES),
                         help="comma-separated content types to sync")
    parser.add_argument("--resume", action="store_true",
                         help="continue from the last saved page per type instead of restarting at page 1")
    parser.add_argument("--db", default=str(DEFAULT_DB))
    parser.add_argument("--token", default=None,
                         help="access token from a live app session, if Keychain access isn't available")
    parser.add_argument("--dev-session", action="store_true",
                         help="use the access token in ~/.kinopub-dev-session.json; never refresh it")
    parser.add_argument("--catch-up", action="store_true",
                         help="page each type newest-first until the local count matches the live catalog")
    parser.add_argument("--probe-missing", action="store_true",
                         help="GET each missing id in the range; 404 stays empty")
    parser.add_argument("--from-id", type=int, default=1)
    parser.add_argument("--to-id", type=int, default=0,
                         help="inclusive end id for --probe-missing; 0 means the current max id")
    parser.add_argument("--concurrency", type=int, default=6)
    parser.add_argument("--pace", type=float, default=0.12,
                         help="seconds between detail-request starts (probe only)")
    args = parser.parse_args()

    if args.concurrency < 1:
        sys.exit("--concurrency must be >= 1")
    if args.pace < 0.05:
        sys.exit("--pace must be >= 0.05s")

    types = [t.strip() for t in args.types.split(",") if t.strip()]

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    db_path = Path(args.db)
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=5000")
    conn.executescript(SCHEMA)

    if args.dev_session:
        token_holder = access_token_from_dev_session()
    else:
        token_holder = dict(get_access_token(args.token))

    start = time.time()
    if args.catch_up or args.probe_missing:
        if args.catch_up:
            added = catch_up(conn, types, token_holder)
            print(f"\nCatch-up inserted {added} rows.", flush=True)
            print_summary(conn)
        if args.probe_missing:
            end_id = args.to_id
            if end_id <= 0:
                end_id = conn.execute("SELECT COALESCE(MAX(id), 0) FROM items").fetchone()[0]
            probe_missing(
                conn, token_holder["access_token"], args.from_id, end_id,
                args.concurrency, args.pace,
            )
            print_summary(conn)
        conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        elapsed = time.time() - start
        print(f"\nDone in {elapsed:.0f}s. {db_path}", flush=True)
        conn.close()
        return

    state = load_state()
    grand_total = 0
    for media_type in types:
        print(f"== {media_type} ==")
        grand_total += sync_type(conn, media_type, token_holder, state, args.resume)

    elapsed = time.time() - start
    total_rows = conn.execute("SELECT COUNT(*) FROM items").fetchone()[0]
    conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    print(f"\nDone. {grand_total} items fetched this run, {total_rows} rows total in "
          f"{db_path} ({elapsed:.0f}s).")
    conn.close()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
