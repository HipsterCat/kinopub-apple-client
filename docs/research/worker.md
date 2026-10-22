# Cloudflare worker — contract

Decided by Sasha, 2026-10-22. This is the contract for `workers/tmdb-proxy`.
The route code on `main` still has an older shape in places (language on the
query string, a kino.pub CDN url as the poster and backdrop fallback). That
older shape is not this contract. `CURRENT.md` / `AGENTS.md` still win on the app.

Related: [title-logos.md](title-logos.md), [metadata-sources.md](metadata-sources.md),
[workers/tmdb-proxy/README.md](../../workers/tmdb-proxy/README.md).

The sqlite files are not on the worker. They live on the Mac, under `tools/`,
and are gitignored. The worker's own store is the KV namespace `DOCUMENTS`
(`title:kinopub:{id}`, one JSON document). See the top of
`workers/tmdb-proxy/wrangler.toml`.

---

## 1. Images by kino.pub id

```
GET /img/{logo|backdrop|poster|thumbnail}/by/kinopub/{id}?w=&s=&e=
```

`w` is the pixel width the picture is drawn at. The worker snaps up to that
CDN's own bucket. Omit `w` for the largest file we will send (3840). `s` on
`poster` is that season's poster. `s` and `e` on `thumbnail` is that episode's
still. A missing or unknown kind is 404. A kind never answers with a different
kind: a logo that redirects to a poster is what the banner would paint instead
of the lettered title.

**Never redirect to a kino.pub CDN** (`staticpop.net` and the same pictures
under another host). The app already holds those files, and the host depends
on the viewer. kino.pub's own posters are English by default. Old clients keep
showing that English art. Sending it back from the worker would put an English
poster under a Russian request and call it a hit.

| Kind | What comes back |
| --- | --- |
| `logo` | Requested language, then the other. An English logo is sent when Russian was asked and only English exists. 404 only when there is no logo at all. |
| `poster` | Requested language only. Russian is tvoe, then the Kinopoisk image when we have that id, then a TMDB `ru` file. A missing Russian poster is a fast 404, never an English poster in its place. |
| `backdrop` | A textless wide frame, or 404. Language is ignored. A titled banner, a portrait, and any kino.pub url are not a backdrop. |
| `thumbnail` | That episode's still. 404 when we do not have one. Needs `s` and `e`. |

We store links, not files. tvoe files go through `tvoe.live/_next/image` at
their widths only, and only for their own CDN. TMDB files use that kind's
ladder. The old path `/img/{kind}/{sm|md|lg|orig}/kinopub/{id}` does not answer.

---

## 2. Language is the viewer's choice, and the caller must say it

Default is Russian. English is what the viewer picked, not a second default
and not what kino.pub's catalogue happens to ship.

Every call that returns words or lettered art tells the worker the language in
the **`Accept-Language` header**. It is not a query parameter. Absent header,
`*`, or a language we do not serve means Russian. `en-US,en;q=0.9` is English.

The app sends the language it is actually running in, including after the
viewer changes that setting. One document per kino.pub id holds both
languages; the header picks at read time. Do not key KV by language.

Why the worker cannot guess: on kino.pub the picture you get with no language
is English, and the old clients will keep asking that way. If we treat silence
as "whatever kino.pub has", a Russian screen gets an English poster. Silence
means Russian. English arrives only when the viewer chose it and the app said
so.

`/v1/title/by/kinopub/{id}/seasons/…` uses the same header, and the body
contains that one language.

Backdrop does not read the header. A backdrop has no language.

---

## 2a. A few seasons, not the show

```
GET /v1/title/by/kinopub/{id}/seasons/2-4
```

Also `2,3` and `2&3`. At most four season numbers.

The page draws a handful of seasons, the ones in view, often the run that is
on now. One request per season is the expensive shape, against kino.pub and
against TMDB. One season is too small for that rail. The whole show is not
the request. So the caller names the range, and the worker returns those
seasons.

Each episode carries `runtime_min`, `imdb: { value, votes }` when we have it,
and `skip_intro` / `skip_credits` as flags. The timestamps stay out of this
payload. A cold range is filled from TMDB for the requested language and kept
on the title document.

---

## 3. Cache TTL vs title freshness

Today **~6 hours is flat**, and only on the TMDB **forwarder**.

| Site | File | Today's number | Applies to |
| --- | --- | --- | --- |
| `CACHE_TTL_SECONDS = "21600"` | `wrangler.toml` `[vars]` | 6 h | Default for `/3/…` |
| `Number(env.CACHE_TTL_SECONDS \|\| 21600)` | `src/index.js` `proxyAPI` | 6 h | Edge `Cache-Control` **and** `caches.default` for TMDB API |
| `proxyImage` / `proxyFile` | `src/index.js` | **7 days** (`604800`) | `/t/p/…` TMDB images |
| `proxyFile` for dumps | `src/index.js` | **12 h** | `/p/exports/…` |
| `DOC_TTL = 60 * 60 * 24 * 30` | `src/title.js` | **30 days** | KV document `expirationTtl` |
| `json()` helper | `src/title.js` | **5 min** (`max-age=300`) | `/v1/title` JSON, including cold `pending: true` |
| logo 404 | `src/title.js` `handleImage` | **30 s** | Cold miss while background resolve may fill a logo |

`/img` 302s currently inherit `Response.redirect` (no `Cache-Control` on the live
HEAD). `/v1/title` does **not** use `CACHE_TTL_SECONDS`.

The README already notes 6 h is short for titles that barely change, while the KV
document lives 30 days.

### Proposed numbers (not shipped)

Classify from `year` / TMDB `release_date` / `first_air_date` / `status` on the
document. Upcoming = date in the future, or `pending: true`.

| Bucket | When | Edge (`Cache-Control` / `caches.default`) | KV revalidate |
| --- | --- | --- | --- |
| **Upcoming / pending** | Unreleased, or document not yet resolved | **1 h** | 1 h |
| **New** | Released (or currently airing) within 90 days | **6 h** (today's number, keep) | 6 h |
| **Catalog** | 90 days – 2 years | **7 d** | 7 d |
| **Old catalog** | Older than 2 years | **30 d** | 30 d (already `DOC_TTL`) |
| **Negative, may fill** | 404 logo/title on a **pending** document | **30 s** (already) | — |
| **Negative, confirmed** | 404 after `pending: false` and that kind is empty | **10 min** | don't hammer TMDB |

`/t/p/` images stay 7 days — pixels don't change when a title is new; the
**document** (which logo/path) does.

The `/3/` forwarder is **not** title-keyed (one TTL for find, details, people). Do not
pretend it can be freshness-aware without parsing every path. Proposal: leave it at
6 h, or bump the default to **24 h** once `/v1/title` + `/img` carry the table above
and the app stops using the forwarder for banners. Separate decision.

---

## 4. tvoe.live as the preferred ru source

Sasha: tvoe IDs **do not expire**; their Russian images are very high quality for
almost everything. Local parser + latest dump exist (`tools/tvoe/tvoe_data/`,
`tools/metadata-ingest/sources.py` `ingest_tvoe`). The 2026-10-22 compile matched
4 069 of those titles onto kino.pub; 279 still have neither an IMDb id nor a
Kinopoisk id.

### What the dump actually is (2026-10-04 files in-repo)

| File | Size | Rows | Logos |
| --- | --- | --- | --- |
| `catalog_films_detailed.json` | 19 MB | 2 972 | 2 972 |
| `catalog_serials_detailed.json` | 67 MB | 1 376 | 1 376 |
| list-only JSON | ~3 MB | — | — |

Every detailed row has `images.poster|cover|logo.cdnUrl` on `static.cdn.tvoe.live`.
`cdnUrl` is the durable original; the sibling `url` is a Next resizer and is **not**
durable (`ingest_tvoe` already stores `cdnUrl` only).

There are **no IMDb / Kinopoisk ids on the dump**. Identity is `_id` (Mongo-style,
stable) plus `name` / `origName` / `dateReleased`. The ingest comment: matching is
original title + year, which is why `resolve_title` records the method.

### Matching strategy (same ladder as `common.resolve_title`)

Offline, against the kino.pub spine (which **does** have imdb/kinopoisk), then upload
an index the worker can read. Do not re-fuzzy-match on every banner request.

1. **External id we already hold** — `id:imdb`, `id:kinopoisk`, `id:tvoe`. (tvoe dump
   never supplies the first two; they appear after a kino.pub or Kinopoisk ingest
   join.)
2. **Normalized original title + year ±1** (`title_year:norm_original`, confidence 0.8).
3. **Normalized Russian title + year ±1**.
4. **Ambiguous = not a match** (two rows → skip). Guessing is worse than no tvoe art.
5. Alphabets stay apart (`match_key` does not fold Cyrillic into Latin).

Worker at request time: kinopub id + client hints → index lookup → if hit, tvoe
`cdnUrl` is the preferred Russian poster and logo, and the textless backdrop
(`cover` has no baked title). TMDB fills English logos and textless frames tvoe
does not have. Intro and credits markers live on the copy (`copy_segment`).
They are flags on the seasons route, not timestamps, and they reach the worker
only when a publish step copies them onto the KV document. The worker does not
read `record-v2.db`.

Import path: Sasha's parser → `tools/tvoe/tvoe_data/` → ingest into `record-v2.db`.
Full dump is a backup, not the hot path. The worker does not ingest that dump.
It does proxy `api.tvoe.live` and `tvoe.live` (`/tvoe/api/…`, `/tvoe/site/…`) so a
caller does not have to leave this machine to reach them.

### Hosting the dump — free options (2026-10-04 public limits)

Hot path is a **join index** (~thousands of small JSON records: kinopub/imdb/kp/tvoe
ids + three `cdnUrl`s), not 86 MB of detailed JSON on every request. Artwork can stay
on `static.cdn.tvoe.live` (redirect, like TMDB) unless we need to freeze bytes.

| | **Cloudflare KV** (already bound `DOCUMENTS`) | **Cloudflare D1** | **Cloudflare R2** | **Supabase free** |
| --- | --- | --- | --- | --- |
| Free storage | 1 GB / namespace | 5 GB account; **500 MB / DB** | 10 GB-month | 500 MB Postgres + 1 GB file |
| Free reads | 100k keys/day | 5M rows/day | 10M Class B / month | “unlimited API”; **5 GB egress** |
| Free writes | **1k keys/day** | 100k rows/day | 1M Class A / month | n/a |
| Value / row | 25 MiB / key | 2 MB / row | object | row |
| Fits 67 MB serials file as **one blob** | **No** (over 25 MiB) | No (over 2 MB row) | **Yes** | Yes as a Storage object |
| Fits **per-title index** | Yes | Yes | Yes (awkward as SQL) | Yes |
| Latency from this worker | in-isolate | in-isolate | in-isolate | extra hop (HTTPS to Supabase) |
| Egress to worker | none | none | none | counts against 5 GB |
| Footguns | 1 write/s/key; 1k writes/day on free | SQL import 5 GB; 10 DBs on free | none for this size | **pauses after ~1 week inactivity** |
| Import | `wrangler kv bulk put` of the index; dump split per title if stored | `wrangler d1 execute` / SQL | `wrangler r2 object put` of the dump + optional index | `psql` / Storage upload |

**Closed 2026-10-22:** the dump stays in the local sqlite. The worker keeps
`DOCUMENTS` for per-title JSON. No D1, and the sqlite is not uploaded.

---

## 5. What is still open

The freshness table in §3 is still a proposal.

The local record and the worker's KV are not the same store. `record-v2.db`
holds the tvoe artwork, the 82 164 skip markers, and the per-episode IMDb
ratings. A cold image or seasons call only knows what is already in KV, and
on a miss it asks TMDB. Until a publish step copies those fields onto
`title:kinopub:{id}`, the live routes miss them. Do not upload the sqlite.
Do not put this on a new D1.

The catalogues refresh on the Mac, not in the worker: kino.pub, Kinopoisk,
tvoe, IMDb dumps weekly, OMDb at 1 000 requests a day. The only secret on the
worker is `TMDB_READ_TOKEN`.
