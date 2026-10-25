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

**Save** writes the whole working set, kept and dropped shelves, to
`tools/home-curator/draft.json` (gitignored). Reopen the page and the draft
comes back. **Download kept** saves only shelves left switched on.
