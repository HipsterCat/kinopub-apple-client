# Skip markers — data sources

| Source | Endpoint | Key | Ids | Segments |
|---|---|---|---|---|
| **IntroDB** (introdb.app) | `GET https://api.introdb.app/segments?imdb_id=tt…&season=S&episode=E` (movies: `&is_movie=true`) | none | IMDb (series id + S/E for episodes) | intro, recap, outro (credits) |
| **TheIntroDB** (theintrodb.org) | `GET https://api.theintrodb.org/v3/media` | none | TMDB (IMDb fallback), series id + S/E | intro, recap, credits, preview |

Shapes and examples come from Plozz's client + tests: [`CommunitySkipMarkers.swift`](https://github.com/brandomoore/Plozz/blob/923ee8eff2d84e1e2b30aab1bf4b095c8926cf4d/Sources/MetadataKit/CommunitySkipMarkers.swift), [`CommunitySkipMarkersTests.swift`](https://github.com/brandomoore/Plozz/blob/923ee8eff2d84e1e2b30aab1bf4b095c8926cf4d/Tests/MetadataKitTests/CommunitySkipMarkersTests.swift). Lume's IntroDB client: [`IntroDBClient.swift`](https://github.com/bilipp/Lume/blob/ad80603e381446420c2f0a7ec5035d325aa5bdf1/Lume/Services/Network/IntroDBClient.swift).

## Notes
- Both are best-effort: any failure (offline, 404, rate limit, decode) yields no markers.
- Episodes need the **series** IMDb/TMDB id. We have it from the title's `MediaIdentity`; the season/episode numbering must be TMDB's, not kino.pub's block numbering. Reuse the season match from the media model.
- Open-ended segments ("to the end") need the runtime; drop them when it's unknown.
- Coverage for Russian-only titles is likely thin. Measure the hit rate on a sample of kino.pub ids before committing UI.

## Proposal
- Document both APIs fully in `docs/providers/introdb.md` / `theintrodb.md` first (AGENTS rule).
- The worker proxies and caches: `GET /v1/markers/by/kinopub/{id}?s=&e=` → merged segments with provenance, cached in KV (they rarely change). The app gets one call and can't be rate-limited per device.
- In the app: `SkipMarkerSource` → `MediaFragment`s → `MediaRecordStore` per episode.
