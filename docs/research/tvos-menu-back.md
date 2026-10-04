# tvOS: Menu returns to the top row first

## How we do it now

On Watch Now / Movies / Series / Library (`TVPage` tab roots), Menu is staged like
the Apple TV app:

| Where focus is | Menu does |
|---|---|
| Below the top row | Scrolls to and focuses the top row. Tab bar stays shut. |
| On the top row (including a rail scrolled sideways) | Passes through: system `TabView(.tabBarOnly)` moves focus to the tab bar. |
| Search, a pushed collection / person page, the player | Unchanged — those surfaces never arm the handler. |

Delivery is **only** system hooks on the page that currently owns focus:

- SwiftUI `.onExitCommand(perform:)` — non-nil only while `isBelowTopRow`; `nil`
  restores the tab-bar default (Apple's documented pass-through).
- UIKit `pressesBegan` / `pressesEnded` on `TVPageCollectionViewController` for
  the same decision, because the focused view is a TVUIKit cell. Matching
  `.ended` is swallowed only for a press this controller already consumed.

Landing uses `indexPathForPreferredFocusedView` + `setNeedsFocusUpdate`. Policy
is `StagedMenuBack` (Rivulet `6c5355f`, plus a grid first-row count so Library
wrapping is one section).

**Not used:** `UIWindow.sendEvent` / any window-level press interceptor. Rivulet
needed that because `.sidebarAdaptable` never delivered Menu to the content
responder chain (measured tvOS 26.5). We ship `.tabBarOnly`; if a UI test ever
shows the first Menu jumping straight to the tab bar, that is a stop — do not
add the interceptor (`AGENTS.md`).

## What others do
| Repo | What | Link |
|---|---|---|
| Rivulet | Staged Menu-back as in the Apple TV app. `.sidebarAdaptable` swallows `.menu` before `pressesBegan`, so they intercept at `UIWindow.sendEvent`. Policy (`StagedMenuBack.shouldReturnToTop`) is reused; the interceptor is not. | [PR #251](https://github.com/l984-451/Rivulet/pull/251), [6c5355f](https://github.com/l984-451/Rivulet/commit/6c5355f1f77d90c727aa043333b7bdfdc873dd7d) |

## Pros / cons
- Pro: standard system-app behaviour, one component (`TVPage`), no focus-routing layer.
- Con: `.onExitCommand` with a non-nil action always consumes; it is attached only
  while below the top row so the second Menu can still reach the tab bar.

## Status — implemented (2026-10-04), Sasha approved on device (2026-10-06)

1. Probe: our shell is `.tabBarOnly`, not Rivulet's `.sidebarAdaptable`. CI walks
   `-KINOPUBMenuBackProbe` (templates gallery inside a matching `TabView`) in
   `TVMenuBackUITests`. Menu reaches the page; do not add `sendEvent`.
2. Device: Sasha walked it on Apple TV ("all tolerable, put it in main").
