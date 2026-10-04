# Watch Now banner / home hero

## How we do it now
- tvOS banner on the system full-screen layout: up to 6 cards **sampled at random** from catalog shelves on each cold launch. It keeps picks only within a session ([HomeCatalog.swift L433-L469](https://github.com/HipsterCat/kinopub-apple-client/blob/b89d194c6a2f4f08fd2b34e52c75cbc18faf4a06/KinoPubAppleClient/Views/Main/HomeCatalog.swift#L433-L469)). It shows logos and loops, behind `homeBannerEnabled`.
- Detail + logo tasks are cancelled when the banner set changes (since #39).
- CURRENT parks heroes/banner as non-MVP, and the Netflix focus-preview (`showsFeaturedPreview`) is dead ([AGENTS.md L402](https://github.com/HipsterCat/kinopub-apple-client/blob/b89d194c6a2f4f08fd2b34e52c75cbc18faf4a06/AGENTS.md#L402)).

## What others do
| Repo | What | Link |
|---|---|---|
| Plozz | Persists the curated hero set and paints it on the first frame. Slides with a resume position are never persisted. | [7d00545](https://github.com/brandomoore/Plozz/commit/7d0054506560106436b2e3c5b7c1b683d3cbc335) |
| Plozz | A "cache that refreshes underneath": a fresh curation is folded in, on-screen slots keep their place, and a title retires after 3 curations drop it. | [a6b76a7](https://github.com/brandomoore/Plozz/commit/a6b76a70c0ba59fbae7470358c8c45907b56c7f1) |
| Plozz | Loads details ahead of focus, holding the logo in one fixed box. | [7f4406e](https://github.com/brandomoore/Plozz/commit/7f4406ed6322a1392a332f3247ecb69935cdc241) |
| Plozz | Paging dots moved to Core Animation (no whole-row redraw). | [e0ca302](https://github.com/brandomoore/Plozz/commit/e0ca3020), [5b39ca5](https://github.com/brandomoore/Plozz/commit/5b39ca54) |
| Plozz | A hero that follows focus on tvOS (optional layout). **Noted only**: it's our retired pattern. | [f9a46d7](https://github.com/brandomoore/Plozz/commit/f9a46d75d1c67130630b741b56370cf02a4d3707) |
| Rivulet | TMDB-trending hero with a placeholder cell; a persisted list that washes out stale slides. | [5784707](https://github.com/l984-451/Rivulet/commit/5784707fc4b74b51b1fe98b1496d3a2534ad7ffa), [4444e2d](https://github.com/l984-451/Rivulet/commit/4444e2d) |
| sashimi | Hero rotation including channels; ambient wallpaper hero; a fix for timer stacking on re-appear. | [PR #472](https://github.com/bitstorm-labs/sashimi-apple/pull/472), [PR #383](https://github.com/bitstorm-labs/sashimi-apple/pull/383), [PR #289](https://github.com/bitstorm-labs/sashimi-apple/pull/289) |
| Lume | Immersive tvOS home with a crossfading TMDB hero (README); uses fold snapping, which we ban. | [README](https://github.com/bilipp/Lume#screenshots) |
| Silo | Next Up hero + On Deck row centred on one column. | [PR #535](https://github.com/Silo-Server/silo-apple/pull/535) |

## Pros / cons
- Pro: a system full-screen layout, UIKit `TVPage`, cancellable enrichment tasks.
- Con: the pick reshuffles every launch; logos are resolved again; there's no editorial/trending source (random from shelves is a "v1 hack" per the code comment).

## Proposal — M · P2 (once heroes leave "parked")
1. Persist the banner pick (ids + logo URLs) next to the `ContentStore` rows; paint it on the first frame.
2. Fold refreshes instead of reshuffling.
3. When a banner card takes focus, prefetch its detail backdrop through `Artwork` (see [detail-page.md](detail-page.md)).
4. Logos via [title-logos.md](title-logos.md) A.
