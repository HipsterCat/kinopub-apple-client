# Home shelf curator

Local page for picking Watch Now, Movies and Series shelves against the live
kino.pub catalog. The seed is `HomeCatalog.homeSectionSpecsByID` as of
2026-10-25: the request the app actually sends, including filters the Settings
subtitles leave out.

```bash
python3 tools/home-curator/server.py
open http://127.0.0.1:8765
```

The first argument is the port, if 8765 is already taken.

The access token is read from `~/.kinopub-dev-session.json` on each request
(the DEBUG `DevSessionMirror` file). It is not copied into the page or the
draft. The server does not refresh it — a refresh rotates the live app session.

**Save** writes only the open tab, kept and dropped shelves, into
`tools/home-curator/draft.json` (gitignored). The other tabs in that file stay
as they were. Reopen the page and each saved tab comes back on its own.
**Download kept** saves the open tab's shelves that are still switched on.
