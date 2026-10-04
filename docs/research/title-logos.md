# Title logos — source, sizing, legibility

Applies to the Watch Now banner (`TVPageBannerCell`), the detail hero (`MediaItemHeroView`), and later Continue Watching / Top Shelf.

## How we do it now
- **Source:** `HomeCatalog.resolveBannerDetails` makes a kino.pub details call **plus** a full `MetadataService.metadata(for:)` for each banner card (TMDB find + details with every append, plus all Kinopoisk endpoints), and keeps only `titleLogoURL` ([HomeCatalog.swift L471-L497](https://github.com/HipsterCat/kinopub-apple-client/blob/b89d194c6a2f4f08fd2b34e52c75cbc18faf4a06/KinoPubAppleClient/Views/Main/HomeCatalog.swift#L471-L497)). The worker README already names this the expensive path ([workers/tmdb-proxy/README.md L66-L82](https://github.com/HipsterCat/kinopub-apple-client/blob/b89d194c6a2f4f08fd2b34e52c75cbc18faf4a06/workers/tmdb-proxy/README.md#L66-L82)).
- **Language:** TMDB `include_image_language=ru,en,null`, best logo by preferred languages ([TMDBSource.swift](https://github.com/HipsterCat/kinopub-apple-client/blob/b89d194c6a2f4f08fd2b34e52c75cbc18faf4a06/Packages/KinoPubMetadata/Sources/KinoPubMetadata/TMDB/TMDBSource.swift)).
- **Sizing:** a fixed box. On tvOS the hero uses `.frame(maxWidth: 680, maxHeight: 170)` ([MediaItemHeroView.swift L802](https://github.com/HipsterCat/kinopub-apple-client/blob/b89d194c6a2f4f08fd2b34e52c75cbc18faf4a06/KinoPubAppleClient/Views/MediaItem/Subviews/MediaItemHeroView.swift#L802), [L1366-L1367](https://github.com/HipsterCat/kinopub-apple-client/blob/b89d194c6a2f4f08fd2b34e52c75cbc18faf4a06/KinoPubAppleClient/Views/MediaItem/Subviews/MediaItemHeroView.swift#L1366-L1367)); the banner uses 0.2 × card height and 0.4 × width ([TVPageBannerCell.swift L54-L58](https://github.com/HipsterCat/kinopub-apple-client/blob/b89d194c6a2f4f08fd2b34e52c75cbc18faf4a06/Packages/KinoPubUI/Sources/KinoPubUI/Components/TVUIKit/Page/TVPageBannerCell.swift#L54-L58)). A 6:1 wordmark gets about 680×113 and a 1:1 mark 170×170, a ~2.7× spread in area.
- **Legibility:** no logo shadow (removed for cost, 2026-08-09). The hero is forced dark over a black scrim.

## What others do
| Repo | What | Link |
|---|---|---|
| Rivulet | Stopped fetching full metadata per item just to read the clear-logo path: plain response + a dedicated LRU "logo metadata" cache. 28% fewer bytes, half the latency. Sentry had flagged it as an N+1. | [71b34da](https://github.com/l984-451/Rivulet/commit/71b34daf140eb2b1f765877e386847356b7e7db5) |
| Sodalite | Logo sized by **area**: `height = nominal × sqrt(pivot/aspect)`, with a floor and a ceiling; per-tier budget (tvOS 0.42 × column / 165 pt). 6:1, 3:1 and 1:1 carry the same optical weight. | [d05a2b7](https://github.com/superuser404notfound/Sodalite/commit/d05a2b74bbf3a108ddcca4f457b256a83e94e6f9), [8d7ff1f](https://github.com/superuser404notfound/Sodalite/commit/8d7ff1f2308f71cfc50f40c4e56eb3b69f8ae80a) |
| Plozz | A dark soft shadow only when measured contrast needs it, never a white glow; the logo is adopted the moment it decodes (the contrast analysis catches up). | [18c17de](https://github.com/brandomoore/Plozz/commit/18c17de3468dd86eed58672111b126270fa103da), [331cfd1](https://github.com/brandomoore/Plozz/commit/331cfd17387f7a60bfa00eda77f2927fea122333) |
| Plozz | A logo over textless art in Continue Watching; logo caches isolated by title and source. | [e78e1a8](https://github.com/brandomoore/Plozz/commit/e78e1a85) |

## Pros / cons
- Pro: one decoded-image pipeline (`Artwork`); 32-bit tile rendering; the lettered title holds until a logo lands.
- Con: about 6 × (1 + 2 TMDB + n KP) requests on a cold Watch Now just for logos; the logo arrives after details.
- Con: uneven optical weight; fixed pt constants instead of fractions of the container (against CURRENT's adaptive rule).

## Proposal
### A. Logo in one request — **approved by Sasha (2026-10-04)**, S · P1
Banner cards take the logo from the worker `GET /img/logo/{size}/kinopub/{id}` instead of details + the metadata pipeline. This sits behind a new `FeatureFlag` case, so the old path stays switchable.

**Worker check (2026-10-04, read-only GETs against the URL in `Info.plist`): the route is deployed but not usable for logos yet.**
- `/img/logo/md/kinopub/{id}` → `302` to `m.staticpop.net/poster/item/medium/{id}.jpg`, a **kino.pub poster**, for every id tried (1, 82852, 85325, 130168). `handleImage` falls back to a poster for any `kind` ([title.js L135-L154](https://github.com/HipsterCat/kinopub-apple-client/blob/b89d194c6a2f4f08fd2b34e52c75cbc18faf4a06/workers/tmdb-proxy/src/title.js#L135-L154)).
- `/v1/title/by/kinopub/{id}` → `version: 1, pending: true`, with no logo, even on retry. `main` writes `version: 2`, so the deployed worker is older than the repo. Without hints the background resolve never fills the document.

Prerequisites, in order:
1. Worker: `kind=logo` with no stored logo answers `404` (never a poster). Redeploy from `main`.
2. App: send hints on the request (`imdb`, `kinopoisk`, `title`, `original`, `year`, `type`) so a cold miss resolves in the background.
3. App: treat any redirect to `m.staticpop.net/poster` as "no logo". Keep the lettered title.
4. Keep `fetchDetails` only for platter facts, or make it lazy.

### B. Area-normalized sizing, S · P1
One pure `LogoBudget(aspect:container:)` in KinoPubUI, used by both the hero and the banner, with unit tests. Budget as a fraction of the container; Sodalite's curve, floor and ceiling.

### C. Legibility, S · P2
A measured-contrast dark shadow, applied only where needed (Plozz), drawn once (rasterized), not a live `.shadow` per frame.
