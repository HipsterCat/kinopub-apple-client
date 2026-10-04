# Related chain memory (Detail → Related → Detail …)

## How we do it now
The tvOS detail page is SwiftUI (`MediaItemView`) with full-screen artwork, an ambient trailer and shelves. "Related" uses the Home shelf component. Each related tap pushes another full page; there is no depth handling (only the UILab reads `stackDepth`).

## What others do
| Repo | What | Link |
|---|---|---|
| Plozz | Measured about 22 MB per pushed level and stalls up to 1 s at depth 10, with an extrapolated jetsam kill around depth 90. A page covered by ≥2 others now renders `Color.clear` and keeps `.task`/state; the view model stays in an LRU of 4. After: about 2.2 MB per level, flat stalls. | [5432abc](https://github.com/brandomoore/Plozz/commit/5432abc091c81a8fdabd674da636e156cca8c1e0) |

## Pros / cons
- Pro: trivial change; Back to the page directly below stays instant.
- Con: unmeasured for us. Apple TV 4K 1st gen / HD have the least headroom.

## Proposal — S · P1
1. Measure footprint and worst stall at depth 3/10/15 on Apple TV 4K 1st gen (Instruments or a memory sampler).
2. If growth is linear: a `DetailStackDepth` environment; pages ≥2 below the top render a placeholder body but keep `.task` and the model; stop the ambient trailer in covered pages.
