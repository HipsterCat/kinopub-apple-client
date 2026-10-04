# Cloudflare worker — language, freshness TTL, tvoe

Plan for `workers/tmdb-proxy`. **Evidence / proposed contract, not implemented** except
where marked done. `CURRENT.md` / `AGENTS.md` still win. Do not treat numbers below as
shipped until Sasha says so.

**Status 2026-10-04:** `#43` squash-merged (`cd816c4`) — `kind=logo` with nothing stored
is 404 in the repo. Auto-deploy is `.github/workflows/tmdb-proxy.yml` (this PR). Language,
freshness TTLs, and tvoe matching are **docs only**.

Related: [title-logos.md](title-logos.md), [metadata-sources.md](metadata-sources.md),
[workers/tmdb-proxy/README.md](../../workers/tmdb-proxy/README.md).

---

## 1. Kind mismatch is a 404 (Sasha, 2026-10-04)

The worker must **never** return a poster for `logo`, or any other kind mismatch.
Missing = 404. A banner that 302s to `m.staticpop.net/poster/…` paints a poster where
the lettered title should stay.

| Request kind | Warm document has that kind | Else |
| --- | --- | --- |
| `logo` | 302 to that logo | **404** — never kino.pub poster, never backdrop |
| `poster` | 302 to that poster | 302 to kino.pub `/poster/item/{size}/{id}.jpg` (same kind) |
| `backdrop` | 302 to that backdrop | 302 to kino.pub `/poster/item/wide/{id}.jpg` (their wide still; URL says `poster/item` but it is the backdrop asset) |
| anything else | — | **404** |

`pickArtwork` already reads `document.artwork[kind]` only, so a stored logo cannot
answer a poster request. The bug was the **fallback**: any unknown kind, including
`logo`, redirected to a kino.pub poster. `#43` stopped that for `logo`; unknown kinds
404 in the same file.

Not done: the live worker until auto-deploy runs with secrets present.

---

## 2. Language: two variants, `ru` and `en`

### What exists today

The KV document is **one per kino.pub id** (`title:kinopub:{id}`), not per language.

- Titles: `title.ru` / `title.original`.
- Artwork: `capArtwork` keeps at most one of `ru`, `en`, textless (`lang: null`)
  (`ARTWORK_LANG_ORDER` in `title.js`). TMDB fetch uses
  `include_image_language=ru,en,null`.
- `pickArtwork` prefers `ru`, else `list[0]` — the client cannot ask for English.
- Overviews: TMDB is fetched as `language=ru-RU` only, so `synopsis` is Russian when
  TMDB has it.

The app is RU + EN (`Localizable.xcstrings`). Hero chrome is forced dark; UI language
is still the viewer's.

### Proposed API

**Query param, not a path segment.** Hints are already query (`imdb`, `kinopoisk`,
`title`, `original`, `year`, `type`). A path slot would collide with
`/img/{kind}/{size}/kinopub/{id}`.

```
GET /img/{kind}/{size}/kinopub/{id}?lang=ru
GET /img/{kind}/{size}/kinopub/{id}?lang=en&imdb=tt…&year=2024
GET /v1/title/by/kinopub/{id}?lang=en
```

| Rule | Choice |
| --- | --- |
| Values | `ru` \| `en` only |
| Omitted | `ru` (primary audience; matches today's `pickArtwork`) |
| Other value | 400 `bad_request` |
| Cache key | full URL (query included) — edge cache and Artwork already key by URL |

Do **not** key KV by language. One document holds both; `lang` is a pick at read time.

### Fallback (artwork with text: logos, posters, backdrops)

Requested → the other of `{ru, en}` → textless (`null`).

Textless is the international wordmark / unlettered still, which is what you want under
our own title overlay when neither language exists. Never fall through to a **different
kind**.

### Fallback (titles, overviews)

Requested → the other language → `title.original` / original-language overview.
No textless for words.

`/v1/title` can keep returning **both** `ru` and `en` in the document (the app already
merges fragments) and still honour `?lang=` as the default pick / `X-Lang` header so a
dumb client has one string. Prefer: document stays bilingual, `/img` is the place that
must pick because it returns one URL.

### How the app picks

Send `lang` from the viewer's locale (`ru` if the language code is `ru`, else `en` —
we only ship those two). One helper in the backend/metadata package builds the worker
URL (AGENTS.md: URL building is not in a view; Nuke does not leak). Banner / hero
Artwork loads that URL. Switching UI language is a new URL, so the decoded cache does
not mix scripts.

Until this ships, the worker keeps preferring `ru` and the app keeps using
`MetadataService` for logos when the FeatureFlag is off ([title-logos.md](title-logos.md)).

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
almost everything. Local parser + latest dump exist (`tools/tvoe_data/`,
`tools/metadata-ingest/sources.py` `ingest_tvoe`).

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
`cdnUrl` is the **preferred `lang=ru` artwork** (logo, poster, backdrop), TMDB fills
`en` / textless. Copy facts (streams, intro markers) stay off this path — they are
`title_copy` in the ingest, not the work ([tools/metadata-ingest/README.md](../../tools/metadata-ingest/README.md)).

Import path: Sasha's parser → same JSON shape as `tools/tvoe_data/` → ingest (or a
thin worker importer) → write the index. Full dump is a backup, not the hot path.

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

**Recommendation to discuss, not decide:** R2 for the raw dump (only option that holds
the 67 MB file whole); KV or D1 for the **lookup index** the worker hits per card.
Keep using the existing `DOCUMENTS` KV for title documents. Do **not** put the dump in
Supabase: pause + egress + extra RTT from the isolate.

**Storage choice: TBD for Sasha.**

---

## 5. Implementation order (not this PR)

1. Secrets + auto-deploy so `#43`'s 404 is actually live. (Workflow in this change.)
2. `?lang=ru|en` on `/img` and `/v1/title`; bilingual TMDB fetch; tests.
3. Freshness TTL table on `/v1/title` + `/img`; leave `/3/` at 6 h until the app
   stops using it for banners.
4. tvoe index + ru preference, after Sasha picks KV vs D1 vs R2 (dump vs index).
5. App FeatureFlag `heroLogoViaWorker` ([title-logos.md](title-logos.md) A).
