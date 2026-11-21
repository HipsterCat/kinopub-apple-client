# TMDB proxy (Cloudflare Worker)

Transparent forwarder for The Movie Database API v3 **and** image CDN. The app never
sees the read token. Images go through the worker too (`/t/p/…`) so local DNS/proxy
hijacks of `image.tmdb.org` (→ `127.0.0.1`) do not break cast photos and logos.

## Deploy

Push to `main` that touches `workers/tmdb-proxy/**` (or **Actions → TMDB proxy worker →
Run workflow**) runs tests then `cloudflare/wrangler-action` from
`.github/workflows/tmdb-proxy.yml`. Missing GitHub secrets skip the deploy with a
notice; they do not fail the job.

**GitHub Actions secrets** (Settings → Secrets and variables → Actions):

| Name | What |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token. Create Token → **Edit Cloudflare Workers**. Needs Account: **Workers Scripts Edit**, **Workers KV Storage Edit**, **Account Settings Read**, scoped to this account. |
| `CLOUDFLARE_ACCOUNT_ID` | Account id from the Workers overview (the hex in the dashboard URL). Not the API token. |

`TMDB_READ_TOKEN` is **not** a GitHub secret. It is already on the live worker from
`wrangler secret put`; a GitHub deploy does not overwrite Worker secrets. First-time
or a new account still needs that once:

```bash
cd workers/tmdb-proxy
npx wrangler secret put TMDB_READ_TOKEN   # paste the TMDB API Read Access Token
```

Do not put `account_id` or tokens in `wrangler.toml`. The file already has `name`,
`main`, `compatibility_date`, `workers_dev`, `CACHE_TTL_SECONDS`, and the `DOCUMENTS`
KV binding.

Copy the worker URL (e.g. `https://kinopub-tmdb-proxy.<account>.workers.dev`) into the
app's `Info.plist` as `TMDBProxyBaseURL` — no trailing slash.

Local tests: `npm test` in this directory (`node --test`).

Manual `npx wrangler deploy` is for a laptop with Wrangler logged in, not for CI.

## Behaviour

| Client request | Upstream |
| --- | --- |
| `GET {proxy}/3/find/tt0903747?external_source=imdb_id` | `GET https://api.themoviedb.org/3/find/…` with `Authorization: Bearer …` |
| `GET {proxy}/t/p/w185/abc.jpg` | `GET https://image.tmdb.org/t/p/w185/abc.jpg` (no auth) |

Successful GET responses are edge-cached for `CACHE_TTL_SECONDS` (default 6 hours).
4xx/5xx are not cached.

## Local

```bash
npx wrangler dev
```

Set the secret the same way, or put `TMDB_READ_TOKEN` in `.dev.vars` (gitignored).

## What it is for (user's call, 2026-10-03)

There is no backend of integrations. This worker proxies, caches and aggregates **when that
helps**: with a key built into the app or the owner's own key, when a service may be down,
when its requests are limited. A viewer's own connection (their Kinopoisk key, their Trakt
account) is called by the app directly. Whatever answers, it lands in the app as
`MediaFragment`s of the media model (`docs/media-model.md`).

**Two layers, kept apart:**

1. **Instant, by kino.pub id, no details needed** —
   `GET /img/{logo|backdrop|poster|thumbnail}/by/kinopub/{id}?w=&s=&e=`
   with `Accept-Language` (`ru` by default, `en` when the app is not Russian).
   Language is not a query parameter. The answer is **302** to our own URL
   `…/{ru|en|und}/{kind}.png`, and that URL returns the bytes.
   `Content-Language` is the same tag: `ru`, `en`, or `und` when the file has
   no language. A cold id waits up to 5 seconds. **404** means there is no
   file, or that wait ran out (`Cache-Control: no-store` on the timeout).
   `w` is a pixel width (snap up to that CDN's own bucket; omit it
   for the largest file we will send, 3840). A TMDB logo whose path ends in
   `.svg` is fetched as `.png`. Among TMDB logos, a PNG beats an SVG; the
   taller PNG wins, and the narrower one wins a tie.
   **Backdrop ignores `Accept-Language`.** It is a textless wide frame, or 404.
   A titled banner, a portrait, and any kino.pub CDN url are not a backdrop.
   `s` on `poster` is that season's poster. `s` and `e` on `thumbnail` is that
   episode's still. Optional `src=` on `thumbnail` may seed a
   `*.staticpop.net` catalogue thumb when TMDB has none yet (other hosts are
   rejected). Thumbnail **404s are not edge-cached** (`no-store`); a season
   with only missing/staticpop stills is re-fetched from TMDB after six hours.
   A Russian poster uses tvoe, or the Kinopoisk image when we have that id, or
   a TMDB `ru` file when we don't — never a kino.pub url, and never an English
   poster in its place. A logo falls through to the other language (an English
   logo is sent when Russian was asked and only English exists). We store
   links, not files. **Stamped bytes** go through
   **[wsrv.nl](https://wsrv.nl/)** first (`w=`, `q=80`, `output=webp` by
   default; optional `format=jpeg|png|webp` on the route). Logo / backdrop /
   poster pass the durable original as `url=`. **Thumbnails** pass the TMDB
   ladder URL when the still is from TMDB (face-crop tokens like
   `w454_and_h254_face` stay in that path — weserv only re-encodes), or the
   staticpop URL when the still is a kino.pub catalogue thumb, e.g.
   `https://wsrv.nl/?url=https://m.staticpop.net/thumb/…/1280.jpg&w=584&q=80&output=webp`.
   On weserv failure, or with Worker var `WESERV_DISABLED=1`, we fall back to
   the legacy path: tvoe files through `tvoe.live/_next/image` (their widths
   only, their CDN only); TMDB files on that kind's ladder; `original` only
   when the file is known to be within 3840, except logos, posters and stills
   whose originals are not the multi-thousand-pixel backdrops. Stamped answers
   are edge-cached (`caches.default`, `Cache-Control: max-age=86400`) so
   repeats do not re-tax weserv. Free-tier care: ~2500 *uncached* requests /
   10 min / visitor IP ([FAQ](https://wsrv.nl/faq/)); cached hits do not
   count — see `X-KinoPub-Image-Via: weserv|legacy`.
2. **A few seasons, not the whole show** —
   `GET /v1/title/by/kinopub/{id}/seasons/2-4` (also `2,3` or `2&3`). At most
   four. `Accept-Language` picks the only language in the body. Each episode
   has `runtime_min`, `imdb: { value, votes }` when we have it, and
   `skip_intro` / `skip_credits` as flags. The timestamps are not in this
   payload. A cold range is filled from TMDB for that language and kept on the
   title document.
3. **Details, when they are opened** — `/v1/title/by/kinopub/{id}`: what the detail page
   shows first. Heavy, rarely-seen parts (reviews, facts, full cast, awards) are not worth
   fetching until the viewer scrolls to them or opens them — they belong in a separate,
   lazy call, not in the first answer. The page itself now reads
   [`/v2/title`](v2-title.md), one call, not this document.

## Observations (audit 2026-10-03)

**What the app calls today:**

| Call | From | Through | Used for |
| --- | --- | --- | --- |
| TMDB `/3/…`, images `/t/p/…` | app (`TMDBSource`) | this worker as a **plain forwarder** (holds the token, edge-caches `CACHE_TTL_SECONDS` = 6 h; images 7 days) | find by IMDb id, details with appended credits / images / videos / keywords, seasons, people |
| kpapp.link `/kpapi/films/{id}/{facts,images,staff,reviews}` | app (`KinopoiskProxySource`) | direct | facts, stills, cast character names, reviews |
| kinopoiskapiunofficial.tech | app (`KinopoiskSource`) | direct, viewer's own key | details (names, plot, slogan, ratings), staff, awards, stills, facts |
| `/v1/title/by/kinopub/{id}`, `/img/…` | **nobody** | — | resolves TMDB + kpapp facts into a document (v2) kept 30 days in KV, and artwork by id |

- **The app does not ask twice — it asks the expensive way.** It never reads the worker's
  own document or images; it rebuilds the same thing itself from TMDB (through the forwarder)
  and Kinopoisk.
- **The Home banner fetches everything for a logo.** `HomeCatalog.resolveBannerDetails`
  runs, per banner card, kino.pub details **and** `MetadataService.metadata(for:)` — TMDB
  find + details with every append, plus every Kinopoisk endpoint configured — and keeps
  only `titleLogoURL`. `/img/logo/{size}/kinopub/{id}` is one request.
- **The detail page asks for reviews and facts on open**, though they sit at the bottom.
- **6 hours is short for the forwarder.** Titles, artwork and credits change rarely; the
  KV document already lives 30 days. Proposed freshness buckets (1 h / 6 h / 7 d / 30 d)
  and where today's 6 h is actually set: [docs/research/worker.md](../../docs/research/worker.md).

## Next (to be done separately)

1. The app's banner and cards take artwork from `/img/…` by kino.pub id; the banner stops
   calling `MetadataService` for a logo.
2. `/v1/title` answers in the model's own JSON (document v3, below); the detail page asks it
   once; heavy extras move to a lazy endpoint.
3. The app's direct TMDB and kpapp.link calls switch off behind a `FeatureFlag` — **only
   after** (2), or the enrichment disappears in between. Kinopoisk with a viewer's own key
   stays in the app.
4. Freshness-based caching ([docs/research/worker.md](../../docs/research/worker.md)).

**Document v3 — the media model's own JSON, nothing worker-specific:**

```json
{
  "version": 3,
  "ref": {"itemID": 87940},
  "title":    [{"source": "tmdb", "language": "ru-RU", "entity": {"kind": "show"}},
               {"source": "trakt", "entity": {"kind": "show", "seasonCount": 3}}],
  "seasons":  {"2": [{"source": "tmdb", "entity": {"kind": "season", "seasonNumber": 2}}]},
  "episodes": {"2": {"5": [{"source": "tmdb", "entity": {"kind": "episode"}}]}}
}
```

The app decodes `title` / `seasons` / `episodes` straight into `MediaContextDraft` and merges
as it does now. TODO: give the wire types explicit, flat coding keys first (`release:
"2020-08-14"` rather than Swift's synthesized enum shape; a genre as its id), so this worker
writes plain JSON; decide what of the lazy extras (cast, facts, reviews) become model types.

**Trakt.** Its public data needs only an app key — seasons, episodes and their air dates, a
show's status, ratings, related titles — so it belongs here under the owner's key. What is a
person's (watched history, scrobbling, recommendations) needs their own OAuth and is the app
talking to Trakt directly; not planned. How kino.pub's own Trakt link works (by the owner's
account: it syncs watches, takes ratings, season data and air dates from Trakt) is not
verified — `docs/providers/trakt.md` comes first, before any integration (AGENTS.md).

