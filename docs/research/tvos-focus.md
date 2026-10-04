# tvOS focus and navigation

## How we do it now
Apple's focus engine only; TVUIKit cells; `focusSection` / `defaultFocus`; a banned list (routing layers, delays, hand-rolled chrome). CURRENT focus acceptance #3: every row is reachable.

## What others do
| Repo | What | Link |
|---|---|---|
| Sodalite | Every horizontally scrolling row is its own focus section, measured in a probe app with XCUIRemote. | [bc76071](https://github.com/superuser404notfound/Sodalite/commit/bc760711e41e3e2ddcc08697028fee7a1486ff01) |
| Parallax | Six device-verified focus/scroll defects; a hero focus section narrower than the shelf kills Up; sparse grids are unreachable without a section. | [PR #9](https://github.com/eutialia/Parallax/pull/9), [PR #44](https://github.com/eutialia/Parallax/pull/44) |
| Silo | Siri Remote swipe tails dropped focus out of the episode carousel (57 exits in 2.5 min, 55 onto the first Cast card); native focus for the row plus focus-exit diagnostics. | [PR #522](https://github.com/Silo-Server/silo-apple/pull/522), [#523](https://github.com/Silo-Server/silo-apple/pull/523), [#528](https://github.com/Silo-Server/silo-apple/pull/528), [#517](https://github.com/Silo-Server/silo-apple/pull/517) |
| Plozz | Native TVUIKit card focus, but heavy custom guards around the hero. Our "engine is Apple's" stance is cleaner. | [5ecafc7](https://github.com/brandomoore/Plozz/commit/5ecafc75) |
| Rivulet | Staged Menu-back — see [tvos-menu-back.md](tvos-menu-back.md). | [PR #251](https://github.com/l984-451/Rivulet/pull/251) |

## Proposal — S · P2
A device check of fast horizontal swipes on the rebuilt episode rail (`TVPageLayout.stillRail`, directly above cast). If focus leaks into Cast, fix the section structure (the rail as its own full-width section), not by press filtering.
