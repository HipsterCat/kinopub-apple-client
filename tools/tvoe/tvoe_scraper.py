#!/usr/bin/env python3
"""
tvoe.live catalog refresh.

Lists (films, serials, shorts, filters) plus one raw detail file per title.
Image bytes are not downloaded. Absolute CDN URLs are added beside relative paths.

API notes:
  - /catalog (v1) silently ignores `from` — every page is the first 100 items.
  - /v2/catalog paginates with `limit` + `skip`.
  - There is no movie-by-id REST call. Details are Next data for /p/{slug}.
  - A season is an array of episodes, not an object. Season number is the index.
  - Qrator bans an IP after parallel bursts. Two workers, pause between details.
"""

import json
import re
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

try:
    import requests
except ImportError:
    print("pip3 install --break-system-packages requests")
    sys.exit(1)

HERE = Path(__file__).resolve().parent
OUT = HERE / "tvoe_data"
DETAILS = OUT / "details"
PROXIES_FILE = HERE / "proxies.local"

API = "https://api.tvoe.live"
SITE = "https://tvoe.live"
CDN = "https://static.cdn.tvoe.live"
PAGE_SIZE = 100
WORKERS = 2
DETAIL_DELAY = 0.25
MAX_CONSEC_FAILS = 100
ATTEMPTS = 4

_local = threading.local()
_proxy_lock = threading.Lock()
_proxies = []
_proxy_i = 0
_fail_lock = threading.Lock()
_consec_fails = 0


def load_proxies():
    if not PROXIES_FILE.exists():
        return []
    found = []
    for line in PROXIES_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        host, port, user, password = line.split(":", 3)
        found.append(f"http://{user}:{password}@{host}:{port}")
    return found


def next_proxy():
    global _proxy_i
    if not _proxies:
        return None
    with _proxy_lock:
        proxy = _proxies[_proxy_i % len(_proxies)]
        _proxy_i += 1
        return proxy


def session():
    if not hasattr(_local, "ses"):
        _local.ses = requests.Session()
        _local.ses.headers["User-Agent"] = (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
        )
    return _local.ses


def cdn_url(path):
    if not isinstance(path, str) or not path:
        return None
    if path.startswith("http://") or path.startswith("https://"):
        return path
    if path.startswith("/"):
        return f"{CDN}{path}"
    return None


def annotate_image(node):
    if isinstance(node, dict) and isinstance(node.get("src"), str):
        absolute = cdn_url(node["src"])
        if absolute:
            node["cdnUrl"] = absolute


def annotate_videos(node):
    if isinstance(node, dict):
        absolute = cdn_url(node.get("thumbnail"))
        if absolute:
            node["thumbnailUrl"] = absolute
        for value in node.values():
            annotate_videos(value)
    elif isinstance(node, list):
        for value in node:
            annotate_videos(value)


def annotate_detail(data):
    for key in ("poster", "cover", "logo"):
        annotate_image(data.get(key))
    annotate_videos(data.get("videos"))
    similar = data.get("similarItems")
    if isinstance(similar, list):
        data["similarItems"] = [
            item.get("_id") for item in similar
            if isinstance(item, dict) and item.get("_id")
        ]
    return data


def annotate_list_item(item):
    for key in ("poster", "cover", "logo"):
        annotate_image(item.get(key))
    return item


def annotate_short(row):
    for src_key, url_key in (
        ("coverFileSrc", "coverCdnUrl"),
        ("thumbnailSrc", "thumbnailCdnUrl"),
        ("movieLogo", "movieLogoCdnUrl"),
    ):
        absolute = cdn_url(row.get(src_key))
        if absolute:
            row[url_key] = absolute
    return row


def get_json(path, params=None):
    last_error = None
    for _ in range(ATTEMPTS):
        proxy = next_proxy()
        try:
            response = session().get(
                f"{API}{path}" if path.startswith("/") else path,
                params=params,
                timeout=25,
                proxies={"http": proxy, "https": proxy} if proxy else None,
            )
            if response.status_code in (403, 429, 503):
                last_error = f"{response.status_code} {path}"
                time.sleep(1.5)
                continue
            response.raise_for_status()
            return response.json()
        except Exception as error:
            last_error = error
            time.sleep(1.0)
    raise RuntimeError(last_error)


def fetch_catalog(category):
    items, skip, seen = [], 0, set()
    while True:
        data = get_json("/v2/catalog", {
            "categoryAlias": category,
            "limit": PAGE_SIZE,
            "skip": skip,
        })
        batch = data.get("items") or []
        total = data.get("totalSize") or 0
        fresh = [row for row in batch if row.get("_id") not in seen]
        if not fresh:
            break
        for row in fresh:
            seen.add(row.get("_id"))
            items.append(annotate_list_item(row))
        print(f"  skip={skip}: +{len(fresh)} (total={total})", flush=True)
        skip += len(batch)
        if len(fresh) < len(batch) or skip >= total or not batch:
            break
        time.sleep(0.08)
    return items


def fetch_shorts():
    rows, skip, seen = [], 0, set()
    while True:
        data = get_json("/shorts", {"limit": PAGE_SIZE, "skip": skip})
        batch = data.get("rows") or []
        total = data.get("total") or 0
        fresh = [row for row in batch if row.get("id") not in seen]
        if not fresh:
            break
        for row in fresh:
            seen.add(row.get("id"))
            rows.append(annotate_short(row))
        print(f"  skip={skip}: +{len(fresh)} (total={total})", flush=True)
        skip += len(batch)
        if len(fresh) < len(batch) or skip >= total or not batch:
            break
        time.sleep(0.08)
    return rows


def current_build_id():
    proxy = next_proxy()
    response = session().get(
        f"{SITE}/filmy",
        timeout=25,
        proxies={"http": proxy, "https": proxy} if proxy else None,
    )
    response.raise_for_status()
    match = re.search(
        r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
        response.text,
        re.S,
    )
    if not match:
        raise RuntimeError("buildId not found on /filmy")
    build_id = json.loads(match.group(1)).get("buildId")
    if not build_id:
        raise RuntimeError("empty buildId")
    return build_id


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)


def note_failure(slug, error):
    global _consec_fails
    with _fail_lock:
        _consec_fails += 1
        count = _consec_fails
    with (OUT / "detail_failures.jsonl").open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"slug": slug, "error": str(error)}, ensure_ascii=False) + "\n")
    print(f"  x {slug}: {error}", flush=True)
    if count >= MAX_CONSEC_FAILS:
        raise SystemExit(f"{MAX_CONSEC_FAILS} consecutive detail failures — stopping")


def note_success():
    global _consec_fails
    with _fail_lock:
        _consec_fails = 0


def fetch_detail(item, build_id):
    slug = (item.get("url") or "").strip("/").split("/")[-1]
    title_id = item.get("_id")
    dest = DETAILS / f"{title_id}.json"
    if dest.exists() and dest.stat().st_size > 0:
        return "skip"
    if not slug or not title_id:
        note_failure(slug or title_id or "?", "missing slug or id")
        return "fail"
    url = f"{SITE}/_next/data/{build_id}/p/{slug}.json"
    last_error = None
    for _ in range(ATTEMPTS):
        proxy = next_proxy()
        try:
            response = session().get(
                url,
                timeout=30,
                proxies={"http": proxy, "https": proxy} if proxy else None,
            )
            if response.status_code in (403, 429, 503):
                last_error = f"{response.status_code}"
                time.sleep(1.5)
                continue
            response.raise_for_status()
            data = response.json().get("pageProps", {}).get("data") or {}
            if data.get("_id") != title_id:
                last_error = f"id mismatch {data.get('_id')}"
                time.sleep(0.5)
                continue
            write_json(dest, annotate_detail(data))
            note_success()
            time.sleep(DETAIL_DELAY)
            return "ok"
        except SystemExit:
            raise
        except Exception as error:
            last_error = error
            time.sleep(1.0)
    note_failure(slug, last_error)
    return "fail"


def scrape_details(items, build_id, limit):
    pending = items if not limit else items[:limit]
    print(f"  details: {len(pending)}", flush=True)
    counts = {"ok": 0, "skip": 0, "fail": 0}
    started = time.time()
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for done, status in enumerate(pool.map(lambda item: fetch_detail(item, build_id), pending), 1):
            counts[status] = counts.get(status, 0) + 1
            if done % 100 == 0:
                rate = done / max(time.time() - started, 1)
                print(
                    f"    {done}/{len(pending)} ({rate:.1f}/s) "
                    f"ok={counts['ok']} skip={counts['skip']} fail={counts['fail']}",
                    flush=True,
                )
    print(
        f"  details done ok={counts['ok']} skip={counts['skip']} fail={counts['fail']}",
        flush=True,
    )
    return counts


def main():
    global _proxies
    limit = None
    if "--limit" in sys.argv:
        limit = int(sys.argv[sys.argv.index("--limit") + 1])
    lists_only = "--lists-only" in sys.argv

    _proxies = [] if "--direct" in sys.argv else load_proxies()
    OUT.mkdir(parents=True, exist_ok=True)
    DETAILS.mkdir(parents=True, exist_ok=True)
    print(f"proxies: {len(_proxies)}", flush=True)

    print("filters", flush=True)
    write_json(OUT / "filters.json", get_json("/v2/catalog/filters"))

    catalog = {}
    for category in ("films", "serials"):
        print(f"\n=== {category} ===", flush=True)
        rows = fetch_catalog(category)
        write_json(OUT / f"catalog_{category}.json", rows)
        catalog[category] = rows
        print(f"  list: {len(rows)}", flush=True)

    print("\n=== shorts ===", flush=True)
    shorts = fetch_shorts()
    write_json(OUT / "shorts.json", shorts)
    print(f"  shorts: {len(shorts)}", flush=True)

    if lists_only:
        return

    build_id = current_build_id()
    print(f"\nbuildId: {build_id}", flush=True)
    items = catalog["films"] + catalog["serials"]
    counts = scrape_details(items, build_id, limit)
    write_json(OUT / "state.json", {
        "last_run": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "build_id": build_id,
        "films": len(catalog["films"]),
        "serials": len(catalog["serials"]),
        "shorts": len(shorts),
        "details": counts,
    })
    print(f"\nDone: {OUT}/", flush=True)


if __name__ == "__main__":
    main()
