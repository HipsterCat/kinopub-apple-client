# Image caching / artwork pipeline

## How we do it now
Nuke behind `Artwork` ([ArtworkPipeline.swift](https://github.com/HipsterCat/kinopub-apple-client/blob/b89d194c6a2f4f08fd2b34e52c75cbc18faf4a06/Packages/KinoPubUI/Sources/KinoPubUI/Components/Content/ArtworkPipeline.swift)): a size-keyed decoded memory cache (64/256 MB), 128/512 MB disk `DataCache`, coalescing, prefetch, 24 in flight / 15 s timeout (after the cast-host stall, CHANGELOG 2026-10-04). At or above every watched repo.

## What others do
| Repo | What | Link |
|---|---|---|
| Plozz | Recovers stalled artwork loads: coalesced loads bounded by the timeout, cancelled queued work released, late results fenced from replacement loads. | [6d2dd14](https://github.com/brandomoore/Plozz/commit/6d2dd14d0410232c0609dff9312ea753f72a37c0) |
| strimr | Artwork stuck empty after a cancelled image load (tvOS). | [PR #187](https://github.com/wunax/strimr/pull/187) |
| Lume | Disk image cache was unbounded; budget + LRU (open PR). We're ahead. | [PR #240](https://github.com/bilipp/Lume/pull/240) |
| sashimi | tvOS only gained a Nuke pipeline in July (was `AsyncImage`) — our old lesson. | [PR #335](https://github.com/bitstorm-labs/sashimi-apple/pull/335) |
| Sodalite | Top Shelf: don't ask the server to resize when the source is ≤ the requested width; downscale in our own decode. | [34131a9](https://github.com/superuser404notfound/Sodalite/commit/34131a9f0e1f252325e71defff7c98ef3a77f2b8) |

## Proposal — S · P2
1. A test: a cell whose load was cancelled (fast scroll) and is then re-shown re-requests and paints; no permanent negative cache.
2. A per-host concurrency cap so one dead host (`m.pushbr.com`) can't starve the others.
