# Research — kinopub vs other Apple media clients

Competitive research for the kino.pub Apple client, aimed at the best Netflix-like discovery hub
on tvOS. Each file covers one place, feature or page: how 15 watched open-source clients do it,
how we do it, our pros and cons, a proposed solution, effort (S/M/L) and priority (P0–P2).
Features we don't build yet live under `upcoming/`.

**Status:** evidence, not law. `CURRENT.md` / `AGENTS.md` still win (see AGENTS "Authority"). A proposal
that conflicts with a banned pattern is marked **noted only**.
**Code reuse:** allowed from any watched repo, whatever its licence (Sasha, 2026-10-04: personal,
non-commercial, open-source, experimental). Name the source commit in our commit message.
**Baseline:** 2026-10-04, our `main` at `b89d194`; watched repos read since 2026-07-04.

## Places / features
| File | Topic | Top proposal | Effort · Priority |
|---|---|---|---|
| [home-hero-banner.md](home-hero-banner.md) | Watch Now banner / hero | Persist the pick, fold refreshes, pre-warm detail | M · P2 |
| [title-logos.md](title-logos.md) | Title logos: source, sizing, legibility | Logo in one request via the worker (**approved**, worker fix first); area-normalized sizing | S · P1 |
| [worker.md](worker.md) | Worker: kind=404, `?lang=`, freshness TTL, tvoe host | Lang + freshness TTL; tvoe ru source; **storage TBD** | M · P1 |
| [detail-page.md](detail-page.md) | Movie/show page | Pre-warm the backdrop; tinted below-fold A/B; stale-load guard on toggles | S · P2 |
| [related-chain-memory.md](related-chain-memory.md) | Detail → Related → Detail stack | Measure, then shed pages ≥2 below the top | S · P1 |
| [top-shelf.md](top-shelf.md) | tvOS Top Shelf | The app pre-renders cells into the App Group | M · P2 |
| [tvos-menu-back.md](tvos-menu-back.md) | Menu returns to the top row first | Implemented on `TVPage` tab roots via `.onExitCommand` / `pressesBegan`; Sasha approved on device | M · P2 |
| [tvos-focus.md](tvos-focus.md) | Focus sections, swipe tails | Device check of the episode rail | S · P2 |
| [trailers.md](trailers.md) | Ambient and playable trailers | Stop on app background | S · P2 |
| [player.md](player.md) | AVKit player | Skip markers (see upcoming), Insights tab | M · P1 |
| [image-caching.md](image-caching.md) | Artwork pipeline | Cancelled/stalled load recovery test, per-host limit | S · P2 |
| [metadata-sources.md](metadata-sources.md) | TMDB / KP / worker / others | Exact-title fallback rule; MDBList for ratings | S · P2 |
| [architecture-concurrency.md](architecture-concurrency.md) | Stores, observation, Swift 6 | Swift 6 mode in packages, mutation generations | M · P2 |
| [performance.md](performance.md) | Measuring perf | Signposts + XCUITest remote walk harness | M · P2 |
| [liquid-glass-hig.md](liquid-glass-hig.md) | Glass, HIG | Check `kinoGlass` on older Apple TVs | S · P2 |
| [watched-repos.md](watched-repos.md) | The 15 repos, per-topic matrix, update method | — | — |

## Upcoming
| Folder / file | Feature |
|---|---|
| [upcoming/skip-intro/](upcoming/skip-intro/README.md) | Skip intro / credits / recap: data sources, player integration, credits + Up Next, chapters, dub-length validation |
| [upcoming/spoiler-protection/](upcoming/spoiler-protection/README.md) | Hide unwatched episode stills/descriptions |

## How this folder is updated
The scout agent watches the repos daily and keeps working notes outside the repo. Once a week it opens
a docs PR updating these files. One file per place. New future features get their own folder under `upcoming/`.
