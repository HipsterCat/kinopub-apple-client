# Watched repos and the per-topic matrix

Baseline 2026-10-04 (activity read since 2026-07-04). Judgement comes from READMEs, code structure, commit/PR history and diffs where topics overlap. **Not verified on device.**

## Repos
| Repo | Branch | SHA at baseline | Notes |
|---|---|---|---|
| [brandomoore/Plozz](https://github.com/brandomoore/Plozz) | `main` | `923ee8eff2` | Works mostly by direct commits to main (~2.9k commits since Jul 4); PRs are rare. Grep commit subjects for hero/logo/artwork/perf. |
| [l984-451/Rivulet](https://github.com/l984-451/Rivulet) | `main` | `1994afe26e` | UIKit tvOS, Plex. Has its own TMDB proxy worker. |
| [superuser404notfound/Sodalite](https://github.com/superuser404notfound/Sodalite) | `main` | `ec10e56f90` | Direct commits, issue refs (#NNN) in subjects. |
| [jellyfin/Swiftfin](https://github.com/jellyfin/Swiftfin) | `main` | `dbe6140d23` | PR-driven; 16 open PRs at baseline. |
| [wunax/strimr](https://github.com/wunax/strimr) | `main` | `7fd15bd0cd` | PR-driven, PR bodies are empty templates; read diffs. |
| [Silo-Server/silo-apple](https://github.com/Silo-Server/silo-apple) | `main` | `d3c31881af` | Very PR-heavy (200+ PRs/3 months); PR bodies are detailed with audit finding ids. |
| [bilipp/Lume](https://github.com/bilipp/Lume) | `main` | `ad80603e38` | IPTV; PR-driven; perf audits are useful. |
| [photangralenphie/MyMedia](https://github.com/photangralenphie/MyMedia) | `main` | `1971467025` | macOS-only local library; low activity (37 commits since Jul 4, no PRs). |
| [samuelhe52/AniShelf](https://github.com/samuelhe52/AniShelf) | `main` | `1b5b5d6c71` | iOS anime tracker; TMDb; low relevance to tvOS. |
| [eutialia/Parallax](https://github.com/eutialia/Parallax) | `main` | `9e3962d187` | Jellyfin/SMB; PR-driven, high-quality PR write-ups. |
| [fer0n/Unwatched](https://github.com/fer0n/Unwatched) | `main` | `e21de2ecbb` | YouTube queue app; direct commits; low relevance (player/perf only). |
| [trakt/trakt-rippple](https://github.com/trakt/trakt-rippple) | `develop` | `1f9526efac` | Watched branch = develop (per Sasha). UIKit + Rx; iOS/Mac only; low relevance. |
| [mensadilabs/Immich-Gallery](https://github.com/mensadilabs/Immich-Gallery) | `dev` | `ada3322570` | Default branch is 'dev' (watched). Photo app; tvOS focus + Top Shelf only. |
| [eggerco/cronica](https://github.com/eggerco/cronica) | `main` | `6f2e2a2657` | TMDb watchlist app; last commit 2026-09-06 (quiet). |
| [bitstorm-labs/sashimi-apple](https://github.com/bitstorm-labs/sashimi-apple) | `main` | `f22c9c0ea8` | Jellyfin; PR-driven (200+ PRs). |

## Matrix
**Legend (always the repo relative to kinopub):** `+` repo is ahead · `=` comparable ·
`−` repo is behind · `·` not applicable / not present in that repo.
"Ahead" on player features means feature-wise. Most of them use custom transport chrome, which
kinopub bans on purpose (`AGENTS.md`).

| Topic | Plozz | Rivulet | Sodalite | Swiftfin | strimr | Silo | Lume | MyMedia | AniShelf | Parallax | Unwatched | rippple | Immich | cronica | sashimi |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Home / hero | + | + | − | − | − | = | + | · | · | = | · | · | · | = | = |
| Trailers | + | = | = | = | · | = | = | · | · | − | · | = | · | = | = |
| Logos / artwork pipeline | + | + | + | = | = | = | = | · | = | = | · | = | · | = | = |
| Info / detail pages | + | = | + | = | = | = | = | − | − | = | · | = | · | = | = |
| tvOS focus / navigation | = | + | = | = | = | = | = | · | · | = | · | · | = | − | = |
| Player (features) | + | + | + | = | + | + | + | − | · | = | = | · | − | · | = |
| Image caching | = | = | = | = | = | = | − | · | = | = | = | = | − | = | = |
| Metadata sources | + | = | = | − | − | − | + | − | = | − | · | = | · | = | − |
| Architecture / concurrency | = | − | = | = | = | + | = | + | = | + | = | − | − | = | = |
| Performance practice | + | = | + | = | = | = | + | · | = | = | = | = | − | · | = |
| Liquid Glass / HIG | = | = | = | + | − | = | = | = | = | = | = | = | − | − | − |
| Top Shelf | + | + | + | − | + | + | − | · | · | − | · | · | + | · | + |

kinopub has no Top Shelf, so every repo that ships one is `+` on that row.


## Update method
Each pass reads only activity after the stored SHA (`git log <sha>..HEAD`, PRs with `updated_at` after the last pass). It triages by topic keyword and reads diffs only where a change overlaps. Plozz and Sodalite commit straight to `main` with descriptive messages (they carry the measurements); Silo, Parallax and Lume put the substance in PR bodies. Daily notes stay with the scout; findings land here in a weekly docs PR.
