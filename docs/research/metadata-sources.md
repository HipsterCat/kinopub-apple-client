# Metadata sources

## How we do it now
kino.pub API + TMDB (resolved **only** by `/find/{imdb}`, via the Cloudflare worker, [TMDBSource.swift L84-L138](https://github.com/HipsterCat/kinopub-apple-client/blob/b89d194c6a2f4f08fd2b34e52c75cbc18faf4a06/Packages/KinoPubMetadata/Sources/KinoPubMetadata/TMDB/TMDBSource.swift#L84-L138)) + Kinopoisk (per-user key / keyless proxy), merged into `MediaRecordStore`. The worker also has `/v1/title` and `/img`, which the app doesn't call yet.

## What others do
| Repo | What | Link |
|---|---|---|
| Plozz | Exact-title + year beats TMDB's popularity order ("The Circle" ≠ "Kingsman: The Golden Circle"); stamps the resolved id. | [37870de](https://github.com/brandomoore/Plozz/commit/37870de527baf0eb3d488a230a274dae827038ff) |
| Plozz | Artwork chain TMDb → TheTVDB → gradient; Wikipedia overview fallback; Common Sense Media. | [c6f2bbb](https://github.com/brandomoore/Plozz/commit/c6f2bbbf1a4da74b0c8b91f8b55d4a4733ff5302) |
| Lume | TMDB + MDBList (IMDb, RT, Metacritic, Trakt, Letterboxd) + IntroDB; Trakt/Simkl scrobble. | [README](https://github.com/bilipp/Lume#features) |
| Rivulet | Its own TMDB proxy requires App Attest; episode-credits route. | [68ca015](https://github.com/l984-451/Rivulet/commit/68ca015d759a4595a75d98d2110ac7b5838772e3), [70859c3](https://github.com/l984-451/Rivulet/commit/70859c3) |
| rippple | Trakt + TMDb JustWatch where-to-watch; smart recommendations. | [aff5f5a](https://github.com/trakt/trakt-rippple/commit/aff5f5a0f8cec6987f78ad97dbb0f3ec0e465532) |

## Proposal
1. If a title has no IMDb id: a worker-side search fallback with Plozz's exact-title/year rule; stamp the id. S · P2.
2. Ratings: consider MDBList for RT/Metacritic in the aggregate (ROADMAP stage 6). S · P2.
3. Recommendations (stage 6 open question): Trakt recommendations as a candidate source. M · P2.
4. Worker hygiene: the deployed worker is older than `main` (see [title-logos.md](title-logos.md)); consider App Attest if the owner key is abused.
