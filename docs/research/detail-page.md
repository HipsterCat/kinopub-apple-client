# Detail page (movie / show)

## How we do it now
One scroll; the artwork is the hero's background (full screen tall), dissolving into an opaque page. InfoPopup for clipped text. Play/Follow is the entry focus. The playable rail comes first, then related, ratings, cast and info. The aggregate rating is IMDb + KP + TMDB + kino.pub. Card → detail carries the snapshot (AGENTS "The detail page", "Continuity beats placeholders").

## What others do
| Repo | What | Link |
|---|---|---|
| Plozz | Starts the backdrop request during navigation; the destination adopts it; controls reveal after the artwork is visible. | [7c4bceb](https://github.com/brandomoore/Plozz/commit/7c4bceb2ec5f77f40a818c8c2bd4099d74145687), [5f98bc9](https://github.com/brandomoore/Plozz/commit/5f98bc938c913cae4aaf4007a3cfbf03719f2f8b) |
| Sodalite | The artwork ends at the fold; the ground below takes the artwork's colour (they tried flat first; the owner chose the tint). Gradient stops never go through `.clear`. | [ab6178d](https://github.com/superuser404notfound/Sodalite/commit/ab6178de1db3de90028152992014118e46e4fadd), [92c627d](https://github.com/superuser404notfound/Sodalite/commit/92c627d1df80976c3b7604ba864ca5c9fc94761a) |
| Sodalite | A Play button that says what it will do (episode, time left, Play Again). | [README](https://github.com/superuser404notfound/Sodalite#-browse--discover) |
| Silo | Stops an older detail load from flipping an optimistic watched toggle back. | [PR #449](https://github.com/Silo-Server/silo-apple/pull/449) |
| Silo | The same external ratings on every title page; one Cast & Crew row (open). | [PR #555](https://github.com/Silo-Server/silo-apple/pull/555), [PR #585](https://github.com/Silo-Server/silo-apple/pull/585) |
| Rivulet | Info popup with focusable sections; season identity on the show page. | [119e0e6](https://github.com/l984-451/Rivulet/commit/119e0e6), [PR #285](https://github.com/l984-451/Rivulet/pull/285) |
| rippple / cronica | Parental guidance on details. | [3437268](https://github.com/trakt/trakt-rippple/commit/3437268), [cronica PR #61](https://github.com/eggerco/cronica/pull/61) |

## Pros / cons
- Pro: one connected focus graph, no page-wide scroll state, fixture-driven UI tests, Follow-first / Continue rules (D17).
- Con: no backdrop pre-warm; a stale details payload could override a local toggle (unverified); a flat black page below the fold.

## Proposal
1. Pre-warm: on focus of a card/banner, `Artwork` prefetches the detail backdrop at its decode size. S · P2.
2. Mutation generation on watched/watchlist/bookmark in `MediaItemModel`/`MediaLibraryStore`; ignore payload fields older than the last local write. S · P2.
3. A/B flag: a below-fold tint sampled once from the decoded hero artwork, at low saturation. Sasha picks on device. S · P2.
4. Memory across Related pushes: see [related-chain-memory.md](related-chain-memory.md).
