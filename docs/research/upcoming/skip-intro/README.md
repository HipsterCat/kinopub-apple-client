# Upcoming: Skip intro / recap / credits

**Status:** upcoming (ROADMAP stage 7 is blocked on "any marker source"). P1 · M overall.

## Why
kinopub has no marker source, so there is no Skip Intro, Up Next fires on a guessed credits window (`WatchProgress`: 8% of runtime, 60–180 s), and there are no chapters. Five watched apps ship skips. Two keyless community databases cover titles by IMDb/TMDB id, which we already have in `MediaIdentity`.

## Prior art
| Repo | What | Link |
|---|---|---|
| Plozz | Community markers layered under server markers; Off / On / Auto (delay) / Auto (instant) per kind: intros, credits, previews, commercials. | [PR #65](https://github.com/brandomoore/Plozz/pull/65), [`CommunitySkipMarkers.swift`](https://github.com/brandomoore/Plozz/blob/923ee8eff2d84e1e2b30aab1bf4b095c8926cf4d/Sources/MetadataKit/CommunitySkipMarkers.swift), [209e278](https://github.com/brandomoore/Plozz/commit/209e278c) |
| Lume | IntroDB outro arms Next Episode instead of a fixed 90% guess. | [PR #188](https://github.com/bilipp/Lume/pull/188) |
| strimr | Automatic intro and credits skipping. | [PR #134](https://github.com/wunax/strimr/pull/134) |
| Silo | never / ask / always intro modes; credits keep playing when Skip Credits opens Next Up. | [PR #399](https://github.com/Silo-Server/silo-apple/pull/399), [PR #562](https://github.com/Silo-Server/silo-apple/pull/562) |
| sashimi | Skip segments from Jellyfin's MediaSegments API. | [PR #453](https://github.com/bitstorm-labs/sashimi-apple/pull/453) |

## Files
| File | Part |
|---|---|
| [data-sources.md](data-sources.md) | IntroDB, TheIntroDB: endpoints, ids, coverage, caching via the worker |
| [player-contextual-actions.md](player-contextual-actions.md) | Skip Intro / Recap buttons via `AVPlayerViewController.contextualActions` |
| [credits-content-proposal.md](credits-content-proposal.md) | Credits start → `WatchProgress` + `AVContentProposal` Up Next |
| [chapters-navigation-markers.md](chapters-navigation-markers.md) | Intro/recap/credits as `navigationMarkerGroups` |
| [dub-length-validation.md](dub-length-validation.md) | Rejecting markers that don't fit kino.pub's encode |

## Slices (suggested order)
1. Provider doc sheet in `docs/providers/` (AGENTS: document before integrating) + the `SkipMarkerSource` model. S
2. Worker route that proxies and caches both DBs by IMDb/TMDB id + S/E. S
3. Dub-length validation. S
4. Contextual actions (intro/recap). M
5. Credits → `WatchProgress` + content proposal. M
6. Chapters. S
Behind one `FeatureFlag` case with per-kind modes, like Plozz.
