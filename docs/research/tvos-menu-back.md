# tvOS: Menu returns to the top row first

## How we do it now

Every `TVPage` list (`returnsToTopOnMenu` defaults on) and Search's results
collection stage Menu like the Apple TV app:

| Where focus is | Menu does |
|---|---|
| Below the top row | Scrolls to and focuses the top row. |
| On the top row of a tab root (including a rail scrolled sideways) | Passes through: system `TabView(.tabBarOnly)` moves focus to the tab bar. |
| On the top row of a pushed `TVPage` (collection, person) | Passes through: NavigationStack pops. |
| On the top row of Search results | Passes through: the search field. |
| Detail page (`TVEmbeddedPage` under the hero) | Unchanged — Menu pops. Staging is off so Sasha's one-scroll page keeps its back. |
| Player | Unchanged. |

Delivery is **only** system hooks on the page that currently owns focus:

- SwiftUI `.onExitCommand(perform:)` via `View.stagedMenuBack` — non-nil only
  while `isBelowTopRow`; `nil` restores the system default (Apple's documented
  pass-through).
- UIKit `pressesBegan` / `pressesEnded` on `TVPageCollectionViewController` for
  the same decision, because the focused view is a TVUIKit cell. Search's host
  (`TVSearchPageHostViewController`) repeats that pair because the search
  container can see Menu before the results collection. Matching `.ended` is
  swallowed only for a press this controller already consumed.

Landing uses `indexPathForPreferredFocusedView` + `setNeedsFocusUpdate`. Policy
is `StagedMenuBack` (Rivulet `6c5355f`, plus a grid first-row count so Library
wrapping is one section).

**Not used:** `UIWindow.sendEvent` / any window-level press interceptor. Rivulet
needed that because `.sidebarAdaptable` never delivered Menu to the content
responder chain (measured tvOS 26.5). We ship `.tabBarOnly`; if a UI test ever
shows the first Menu jumping straight to the tab bar, that is a stop — do not
add the interceptor (`AGENTS.md`).

**Still not `TVPage`:** `CollectionsView` (the pushed list of collection *names*)
is a SwiftUI row `ScrollView`. Menu-back waits on that leftover port.

**Embedded detail sections stay off.** `TVPageCollectionViewController.isEmbedded`
plus `returnsToTopOnMenu = false` on `TVEmbeddedPage` — Menu from a shelf under
the hero still pops the title (`985564d`).

## What others do
| Repo | What | Link |
|---|---|---|
| Rivulet | Staged Menu-back as in the Apple TV app. `.sidebarAdaptable` swallows `.menu` before `pressesBegan`, so they intercept at `UIWindow.sendEvent`. Policy (`StagedMenuBack.shouldReturnToTop`) is reused; the interceptor is not. | [PR #251](https://github.com/l984-451/Rivulet/pull/251), [6c5355f](https://github.com/l984-451/Rivulet/commit/6c5355f1f77d90c727aa043333b7bdfdc873dd7d) |

## Pros / cons
- Pro: standard system-app behaviour, one component (`TVPage` / Search's results
  collection), no focus-routing layer.
- Con: `.onExitCommand` with a non-nil action always consumes; it is attached only
  while below the top row so the second Menu can still reach the tab bar / pop /
  search field.

## Status — tab roots in main (`8562dd9`); lists extension pending device (2026-10-06)

1. Probe: our shell is `.tabBarOnly`, not Rivulet's `.sidebarAdaptable`. CI walks
   `-KINOPUBMenuBackProbe` (templates gallery inside a matching `TabView`) in
   `TVMenuBackUITests`. Menu reaches the page; do not add `sendEvent`.
2. Device: Sasha walked tab roots on Apple TV ("all tolerable, put it in main").
   Search / collection / person wait on a device check of this follow-up. After
   rebase onto `985564d`, also confirm Menu from a detail shelf still pops.
