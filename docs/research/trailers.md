# Trailers

## How we do it now
The kino.pub `trailerURL` drives an ambient preview in the detail hero (`TrailerPreviewModel`) and appears in the one playable rail. It stops on page `onDisappear` and when real playback starts. TMDB `videos` are parsed but not played (YouTube).

## What others do
| Repo | What | Link |
|---|---|---|
| Plozz | TMDB/YouTube trailers through YouTubeKit (`Sources/ProviderTrailers/`); stops an ambient trailer nobody is watching (it was 21% of steady CPU in network I/O), including on app background; trailers bound to their owning page. | [1ab1b7e](https://github.com/brandomoore/Plozz/commit/1ab1b7e02dc19354555f5d59b0b749c1739b8e58), [5c4a11e](https://github.com/brandomoore/Plozz/commit/5c4a11e0) |
| sashimi / Swiftfin | Local server trailers only. | [sashimi README](https://github.com/bitstorm-labs/sashimi-apple#features) |
| cronica / rippple | YouTubePlayerKit (web player). | — |

## Pros / cons
- Pro: native HLS trailers, no YouTube dependency.
- Con: no stop on app background; titles without a kino.pub trailer have none, even when TMDB has one.

## Proposal
1. Stop/pause the ambient trailer on `scenePhase == .background` (not `.inactive`). S · P2.
2. Optional: TMDB YouTube trailers via YouTubeKit, as Plozz does, behind a flag, only when kino.pub has none. M · P2.
