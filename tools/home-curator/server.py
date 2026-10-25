#!/usr/bin/env python3
"""Curate Watch Now / Movies / Series shelves against the live catalog.

The access token is read from ~/.kinopub-dev-session.json — the same file DEBUG
builds mirror (DevSessionMirror). It is attached to proxied API calls and is
never written into the page, the saved draft, or the log. This server does not
refresh the token: a refresh rotates the live app session.

    python3 tools/home-curator/server.py
    open http://127.0.0.1:8765
"""

from __future__ import annotations

import json
import re
import sys
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent
PAGE = ROOT / "index.html"
DRAFT = ROOT / "draft.json"
DEV_SESSION = Path.home() / ".kinopub-dev-session.json"
API = "https://api.service-kp.com"
MAX_DRAFT = 1_000_000
CATALOG_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,40}$")

def access_token() -> str | None:
    if not DEV_SESSION.exists():
        return None
    try:
        raw = json.loads(DEV_SESSION.read_text())
    except json.JSONDecodeError:
        return None
    token = raw.get("access_token")
    if not isinstance(token, str) or not token:
        return None
    return token


def allowed(path: str) -> bool:
    if not path.startswith("/v1/") or ".." in path:
        return False
    return all(ch.isalnum() or ch in "/-_." for ch in path)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        path = urlsplit(self.path).path
        sys.stderr.write("%s %s\n" % (self.command, path))

    def do_GET(self) -> None:
        split = urlsplit(self.path)
        path = unquote(split.path)
        if path in ("/", "/index.html"):
            self._file(PAGE, "text/html; charset=utf-8")
            return
        if path == "/api/session":
            self._json({"ok": access_token() is not None})
            return
        if path == "/api/draft":
            if not DRAFT.exists():
                self._json({"error": "empty"}, 404)
                return
            self._file(DRAFT, "application/json; charset=utf-8")
            return
        if path.startswith("/api/kp/"):
            upstream = path[len("/api/kp"):] + (("?" + split.query) if split.query else "")
            self._proxy(upstream)
            return
        self._json({"error": "not found"}, 404)

    def do_POST(self) -> None:
        path = urlsplit(self.path).path
        if path != "/api/draft":
            self._json({"error": "not found"}, 404)
            return
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0 or length > MAX_DRAFT:
            self._json({"error": "bad length"}, 400)
            return
        raw = self.rfile.read(length)
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            self._json({"error": "not json"}, 400)
            return
        catalog = body.get("catalog") if isinstance(body, dict) else None
        sections = body.get("sections") if isinstance(body, dict) else None
        if not isinstance(catalog, str) or CATALOG_ID.fullmatch(catalog) is None or not isinstance(sections, list):
            self._json({"error": "expected one catalog"}, 400)
            return
        draft = load_draft()
        draft["catalogs"][catalog] = sections
        draft["savedAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        if "excludeConcerts" in body:
            draft["excludeConcerts"] = bool(body["excludeConcerts"])
        limit = body.get("limit")
        if isinstance(limit, int) and not isinstance(limit, bool):
            draft["limit"] = max(1, min(40, limit))
        text = json.dumps(draft, ensure_ascii=False, indent=2) + "\n"
        if len(text.encode()) > MAX_DRAFT:
            self._json({"error": "too big"}, 400)
            return
        DRAFT.write_text(text)
        self._json({"ok": True, "catalog": catalog, "path": str(DRAFT)})

    def _proxy(self, upstream: str) -> None:
        token = access_token()
        if token is None:
            self._json({"error": "no dev session"}, 401)
            return
        split = urlsplit(upstream)
        if ".." in unquote(split.path) or not allowed(split.path):
            self._json({"error": "path not allowed"}, 403)
            return
        request = urllib.request.Request(
            API + upstream,
            headers={
                "Authorization": "Bearer " + token,
                "Accept": "application/json",
                "User-Agent": "kinopub-home-curator",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=25) as response:
                payload = response.read()
                status = response.status
                content_type = response.headers.get("Content-Type", "application/json")
        except urllib.error.HTTPError as error:
            payload = error.read()
            status = error.code
            content_type = error.headers.get("Content-Type", "application/json") if error.headers else "application/json"
        except (urllib.error.URLError, TimeoutError, OSError):
            self._json({"error": "кинопаб не ответил, нажми «Обновить»"}, 502)
            return
        self._bytes(payload, content_type, status)

    def _file(self, path: Path, content_type: str) -> None:
        if not path.exists():
            self._json({"error": "missing file"}, 404)
            return
        self._bytes(path.read_bytes(), content_type, 200)

    def _json(self, body: dict, status: int = 200) -> None:
        self._bytes(json.dumps(body).encode(), "application/json; charset=utf-8", status)

    def _bytes(self, payload: bytes, content_type: str, status: int) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)


def load_draft() -> dict:
    raw: dict = {}
    if DRAFT.exists():
        try:
            loaded = json.loads(DRAFT.read_text())
        except json.JSONDecodeError:
            loaded = {}
        if isinstance(loaded, dict):
            raw = loaded
    catalogs = raw.get("catalogs")
    if not isinstance(catalogs, dict):
        catalogs = {}
    raw["version"] = 1
    raw["catalogs"] = catalogs
    return raw


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"http://127.0.0.1:{port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()


if __name__ == "__main__":
    main()
