# tvoe catalog refresh

Observations from 2026-10-06. The last dump is `tvoe_data/state.json` (`2026-07-28`, `buildId` `vNn_WdW65SRZRBOCj4GSP`). Live `buildId` that day was `yJrJVEnmEyHgGReZJbXJk`. Image bytes are not part of this refresh: ids do not expire, and `static.cdn.tvoe.live` paths do not expire. Store absolute CDN URLs only.

Proxies for the geo lock live in `proxies.local` (gitignored, same `host:port:user:password` lines). Do not copy them into this file or into the scraper. On 2026-10-06 all five accepted the TCP connection and then read-timed out (HTTP and SOCKS). Direct access from this machine answered in 0.2 s, and the refresh ran with `python3 tvoe_scraper.py --direct`.

## Landed 2026-10-06

`tvoe_data/state.json`: films 3 019, serials 1 470, shorts 408, details 4 489, failures 0. `buildId` `yJrJVEnmEyHgGReZJbXJk`. Every detail has `fullDesc`. Episode rows across seasons: 42 363, each thumbnail has a `cdnUrl`. `similarItems` is a list of ids. About 16 minutes at two workers.

`catalog_*_detailed.json` is still the 2026-07-28 fold. `ingest_tvoe` reads those files, not `details/`.

`python3 build_sqlite.py` writes `tvoe_data/tvoe.sqlite` (gitignored) from `schema.sql`. 2026-10-06 load: 4 489 titles, 14 529 genre rows, 78 137 credits, 49 660 videos (42 363 episodes, 3 019 features, 4 278 trailers), 50 393 reviews, 408 shorts. `title_raw.body` is the detail file. Season on `video` is the 1-based index into `videos.seasons`.

## What the dump is missing

| | dump (2026-07-28) | live (2026-10-06) |
| --- | --- | --- |
| Films | 2 972 | 3 019 |
| Serials | 1 376 | 1 470 |
| Shorts | none | 407 |

Cartoons and anime are not categories. They are genres inside films and serials, filtered with `genresAliases` (not `genreAlias`):

| `genresAliases` | films | serials |
| --- | --- | --- |
| `multfilmy` | 390 | 243 |
| `anime` | 42 | 140 |

`/v2/catalog/filters` only has `films` and `serials` (years, countries, genres). `categoryAlias` values `cartoons`, `anime`, `multfilms`, `multiki`, `shorts` return `totalSize: 0`.

## How the site actually answers

List: `GET https://api.tvoe.live/v2/catalog?categoryAlias=films|serials&limit=&skip=`. A page is up to 100 items. Fields on a list row: `_id`, `name`, `shortDesc`, `ageLevel`, `dateReleased`, `categoryAlias`, `badge`, `cover.src`, `poster.src`, `rating`, `countries` (one string), `duration`, `seasonsCount`, `url`.

Title: no REST "movie by id". `/v2/movies/{id}`, `/movies/{id}`, `/v2/catalog/{id}`, `/v1/movies/{id}`, `/movie/{id}` are 404. The card is Next data:

`GET https://tvoe.live/_next/data/{buildId}/p/{slug}.json` → `pageProps.data`.

`buildId` comes from `<script id="__NEXT_DATA__">` on `https://tvoe.live/filmy`. It rotates; the scraper already reads it. Detail keys seen on 2026-10-06: `_id`, `name`, `origName`, `shortDesc`, `fullDesc`, `ageLevel`, `dateReleased`, `categoryAlias`, `badge`, `cover`, `poster`, `logo`, `rating`, `countries`, `duration`, `seasonsCount`, `url`, `genreName`, `genreNames`, `genresAliases`, `persons`, `videos`, `reviews`, `similarItems`, `ultraHdQuality`, `inSubscribeSoon`, `isNewSeason`.

`persons[].type` seen: `actor`, `director`, `producer`, `screenwriter`, `operator`. A person is `{name, type}` only.

`videos` is `{trailers, films, seasons}`. A season is not an object. `videos.seasons` is an array of arrays of episodes. Season number is the array index. There is no season poster, season synopsis, or episode number in the payload. Episode fields: `_id`, `movieId`, `nameForUser`, `version`, `src`, `thumbnail`, `duration`, `previewStartTime`, `previewEndTime`, `creditsStartTime`, `creditsEndTime`, `replayStartTime`, `replayEndTime`, `releaseDate`, `published`, `hasMP4`, `qualities`, `audio`, `subtitles`. Thumbnail is a relative `/images/….jpg`.

`reviews` is `{items, totalSize}`. An item is user text (`rating`, `review`, `user`, `updatedAt`), not catalog copy. `similarItems` is a list of list-shaped cards (about 20); keep their `_id`s, not a second copy of each card.

Shorts: `GET https://api.tvoe.live/shorts?limit=&skip=`. `limit=100` works (`total` 407, 5 pages). A row: `id`, `title`, `coverFileSrc`, `videoFileSrc`, `videoHlsSrc`, `thumbnailSrc`, `isPinnedOnMain`, `link`, `buttonText`, `viewsCount`, `publishedAt`, `viewAt`, `movieTitle`, `movieLogo`, `movieCategory`, `movieGenre`, `movieAgeLevel`, `movieId`. `movieId` is the catalog `_id`.

This machine reached the API without a proxy on 2026-10-06. The site is still geo-locked and Qrator bans parallel bursts, so keep `--proxy` and the scraper's cap (2 workers, 0.25 s between detail calls). A full detail pass is about 4 500 requests, on the order of 40 minutes.

## What `tvoe_scraper.py` drops

`build_entry` folds text into one `description` and prefers `shortDesc`, so `fullDesc` never lands in `catalog_*_detailed.json`. Also dropped: `reviews`, `similarItems`, `genresAliases`, `ultraHdQuality`, `inSubscribeSoon`, `isNewSeason`. Episodes, trailers, tracks, and intro/credits markers do land in `videos`. `ingest_tvoe` reads that blob as a tvoe *copy*, not as facts about the work.

`OUT` is hardcoded to `tools/tvoe_data/`. The dump that is actually in the repo is `tools/tvoe/tvoe_data/`. A run without fixing the path creates a second folder.

The scraper also invents `hlsUrl` from `src` + `version`. That is not an API field. The raw file should not contain it.

The list has no `updatedAt`. A new episode inside an existing season does not change `seasonsCount`. Diffing ids is not enough for serials.

## Refresh

One run, no image bytes. Three cheap lists, then every title.

1. Pull films, serials, shorts, and `/v2/catalog/filters` in full. Seconds.
2. Re-fetch every title's Next payload. Ids are stable, but episode lists and both descriptions change without a list-level signal. An occasional full pass is the honest update.
3. Write the raw body, field names unchanged:
   - `tvoe_data/catalog_films.json`
   - `tvoe_data/catalog_serials.json`
   - `tvoe_data/shorts.json`
   - `tvoe_data/filters.json`
   - `tvoe_data/details/{_id}.json` — the whole `pageProps.data`
4. One file per title so a failed response does not rewrite a 67 MB blob, and a run can resume.
5. Add absolute image URLs only (`https://static.cdn.tvoe.live` + `src` / `thumbnail` / shorts paths). Do not download bytes.
6. Store `similarItems` as ids. Keep reviews as returned.

`tvoe_scraper.py` output path must be `tools/tvoe/tvoe_data/` before this run. Do not pass `--images`.

## SQLite, next run

Raw JSON is the source. `tvoe.sqlite` is a projection, not a replacement, and not the merged metadata-ingest database. tvoe joins kino.pub only after that ingest. Tables:

- `title` — `_id`, category, both names, both descriptions, rating, release date, age, duration, season count, url, genres, countries, badge, poster, cover, logo, flags (`ultraHdQuality`, `inSubscribeSoon`, `isNewSeason`)
- `credit` — name, role, order
- `video` — feature, episode, or trailer: id, season index, position in the array, name, duration, thumbnail URL, tracks, intro/credits/replay markers
- `short` — `/shorts` row plus `movie_id`
- `title_raw` — the detail JSON, so a new API field survives until the schema changes

## Worker, later

The worker does not call `tvoe.live`. A rare run from a machine that can reach the site writes this folder (or the sqlite) to R2. The hot path stays the short index "our id → three `cdnUrl`s" in [docs/research/worker.md](../../docs/research/worker.md).
