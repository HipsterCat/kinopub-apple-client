# Upcoming: Spoiler protection

**Status:** upcoming. S · P2.

## Prior art
| Repo | What | Link |
|---|---|---|
| Sodalite | Veils detail heroes, shared cards and episode backdrops until started/watched; press to reveal; a per-series override; reveal memory store. | [dad91dd](https://github.com/superuser404notfound/Sodalite/commit/dad91dd118f58439b930ad0fe62ef66a1fd8979e), [df9c1e3](https://github.com/superuser404notfound/Sodalite/commit/df9c1e3) |
| strimr | Episode spoiler protection. | [PR #131](https://github.com/wunax/strimr/pull/131) |
| Silo | Hide spoilers for unwatched episodes, per profile (open). | [PR #559](https://github.com/Silo-Server/silo-apple/pull/559) |

## Proposal
A `FeatureFlag` + a `MediaPresentationProfile` rule (never an `if` in a view, per AGENTS), driven by `EpisodeQueue` viewer state: blur unwatched episode stills and hide descriptions in the episode rail and Up Next. Select on a blurred tile still plays; long-press reveals.
