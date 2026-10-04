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

1. **Instant, by kino.pub id, no details needed** — `/img/{kind}/{size}/kinopub/{id}`
   (poster, backdrop, logo). Answers with a redirect to whatever is warm **of that kind**.
   Poster and backdrop fall back to kino.pub's own artwork. **A missing or unknown kind
   is 404**, never a different picture (a logo that 302s to a poster is what the banner
   would paint instead of the lettered title). Resolves the title behind the response.
   Language, freshness TTLs, and tvoe as the preferred ru source:
   [docs/research/worker.md](../../docs/research/worker.md) (not implemented yet).
2. **Details, when they are opened** — `/v1/title/by/kinopub/{id}`: what the detail page
   shows first. Heavy, rarely-seen parts (reviews, facts, full cast, awards) are not worth
   fetching until the viewer scrolls to them or opens them — they belong in a separate,
   lazy call, not in the first answer.

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

