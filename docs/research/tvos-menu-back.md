# tvOS: Menu returns to the top row first

## How we do it now
No handler: Menu deep in Watch Now / Series goes straight to the tab bar or sidebar, and the place is lost.

## What others do
| Repo | What | Link |
|---|---|---|
| Rivulet | Staged Menu-back as in the Apple TV app: below the top row, Menu scrolls to and focuses the top row; at the top it passes through. `.sidebarAdaptable` swallows `.menu` before `pressesBegan`, so they intercept at `UIWindow.sendEvent`. | [PR #251](https://github.com/l984-451/Rivulet/pull/251), [6c5355f](https://github.com/l984-451/Rivulet/commit/6c5355f1f77d90c727aa043333b7bdfdc873dd7d) |

## Pros / cons
- Pro: standard system-app behaviour.
- Con: a window-level press interceptor is close to the focus-routing layer AGENTS bans.

## Proposal — M · P2, **needs Sasha**
1. Probe (`swiftc -typecheck` / probe app): does `.onExitCommand` or `pressesBegan` on our `TVPage` host see `.menu` under our `TabView`?
2. If yes: scroll to the top + `indexPathForPreferredFocusedView` + `setNeedsFocusUpdate` (system API).
3. If not: a named adapter with the SDK limitation in its doc comment. Ask Sasha before building.
