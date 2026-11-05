# Accepted adapters

Allowed to exist, one place each, the limitation in the type's doc comment. Rule: [AGENTS.md › Constraints are not requirements](../../AGENTS.md#constraints-are-not-requirements). An adapter that stops being needed gets deleted, not kept "in case"; re-probe each one on the next SDK or package major.

- **`Date.isOnOrAfter` / `isOnOrBefore`** — `Date.>=` and `Date.<=` are weak-linked to a
  Foundation overlay the compiler calls on any OS that reports 27.2. iPad OS 27.2 seed
  24B5089g has no such symbol: the stub is null and the call lands at address 0
  (launch crash in `ContinueWatchingOrder.lastSeenByItemID`, 2026-10-26). Ordering uses
  the reference interval, which is the compiler's own fallback. Re-probe on the next SDK.
- **`TVUIKitMediaItemMetrics`** — `orthogonalLayoutSectionForMediaItems()` exposes neither its group
  nor its item, so it cannot be resized. We measure what it produces per width and rebuild an
  equivalent section at our scale; Apple keeps owning the proportions.
- **The progress bar in the media-item overlay** — `configuration.playbackProgress` only paints on
  the *focused* tile, and "started, not finished" is what an idle rail has to say.
- **`NetworkConsoleView`'s macOS branch** — `PulseUI.ConsoleView` does not exist on macOS in Pulse
  5.2.3 (the module ships `ConsoleView-ios/-tvos/-watchos`, and its public init is fenced
  `#if !os(macOS)`). Capture still runs there, so the Mac gets export-to-`.pulse`, and streaming to
  the Pulse app is the live reader. Re-probe on the next Pulse major.
- **Auto-connect in `setRemoteLoggingEnabled`** — Pulse keeps `RemoteLoggerSettingsView` internal,
  so there is no server picker to present. "First server found, then remembered" is the only
  selection model its public API offers. Re-probe if that view goes public.

- **`UISearchController+GridKeyboard.swift`** (tvOS Search) — the grid keyboard (Settings →
  General → Keyboard) hides while focus is in the results and the results take the full width,
  through UIKit's private `_shouldHideGridKeyboardUnfocused` (NO by default, no public switch;
  probed on tvOS 26.5 and 27.2). Guarded by `responds(to:)`: without it the keyboard just stays.
  Widening the results used to hang the main thread (the collection growing to the window
  fought the search container; losing focus on the rebuild showed the keyboard again).
  The page extends vertically only, and remembers the focused poster while results have it.
  The column count stays the full screen's: the keyboard shifts the collection and the
  last column clips, instead of the pane's width wrapping posters onto the next row.
  While the keyboard narrows the host below a full row, the collection stays that
  wide so the column past the edge remains a cell; the screen clips it. A mask on
  the host clipped the rails short of the screen as well. Pinning the collection to
  the window hung, above. The collection stays the scroll view the search chrome
  follows the whole time: clearing it while the keyboard was up left the keyboard
  on screen after focus moved into the results, and left the suggestions parked in
  the posters, jumping sideways on each swipe.
  On tvOS 26.x, focus coming back to the field's half scrolls that collection to
  `-safeAreaInsets.top`, without the 157 pt window extension's content inset; the tab
  bar and the field follow the offset, so the bar stayed hidden above the screen.
  `TVPageCollectionView` lands that one target on the adjusted top (27.2 already asks
  for it). Re-probe on the next SDK.
  Checked by `TVSearchLayoutUITests` (`-KINOPUBSearchFixture -ForceGridKeyboard YES`).

- **`TVNavigationZoom.swift`** (tvOS push and pop) — tvOS has no public page transition but
  the crossfade: `UIViewController.Transition.zoom` and `.navigationTransition(.zoom)` have no
  effect there (Apple's docs; probed push and present on 27.2). The scale in/out of TVML apps is
  TVMLKit's private `_TVNavigationZoomAnimator`, a plain `UIViewControllerAnimatedTransitioning`.
  SwiftUI's tvOS stack pushes with `animated: false`, so every move swaps the pages at once and
  the animator is driven from a snapshot of the page left, through a proxy in front of SwiftUI's
  navigation delegate (it also hides UIKit's private `animatorForOperation:` question, which
  SwiftUI answers first). The tab bar's hide and show are drawn as a slide up and back down
  alongside (`TabBarSlide`); SwiftUI still decides when it is hidden. No class, or
  `-KINOPUBSystemNavigationTransition YES`: the system crossfade. Re-probe on the next SDK.
- **`TVSettingKit.swift`** (tvOS Settings) — Settings runs on Apple's private `TVSettingKit`
  (`_TSKSplitViewController`, `TSKViewController`, `TSKSettingItem`, `TSKPreviewViewController`):
  the still preview column, the list-only slide-and-crossfade on push, Apple's cells and value
  pickers have no public API, and a hand-built copy was rejected. Only that file touches private
  API; classes and selectors are checked once (`TVSettingKit.isAvailable`) and the SwiftUI
  `TVProfileSettingsView` is the fallback. Rows bind by KVC through `TSKValueStore` onto the
  existing `@AppStorage` keys and models. Full-screen tools are presented over it, each in its
  own `NavigationStack`, with the environment forwarded. Re-probe every tvOS.
  **Editable lists** (`TSKEditing`: languages, tab and section order) are Settings › Apple TV
  Languages' pattern — *Edit* in the bar, the table's own trash and ≡, *Cancel* / *Done* — on
  public `UITableView` editing, since `TSKViewController` is a `UITableViewController`. Traps
  (tvOS 27.2): the table's data source is TVSettingKit's diffable one, which answers no editing
  call and cannot be swapped out (UIKit asserts it on every snapshot apply), so that instance
  is moved to a runtime subclass adding can-edit / can-move / commit / move; no reload after a
  move (it takes focus off the ≡); `primaryAction` bar items never fire, target–action does;
  system Edit/Done/Cancel items draw as ✓/✕, so the buttons are titled. On the simulator a
  lifted row needs two Down presses per row — Apple's own page does the same.

- **`RenditionNames`** (`PlayerManager.swift`) — `AVMetadataItem.stringValue` is deprecated
  (16) for the async `load(.stringValue)`, while `AudioRenditions` reads a rendition's `NAME=`
  synchronously and is tested with no asset. The player awaits the names right after each
  `loadMediaSelectionGroup`; the rules keep their shape. `displayName` is never a substitute —
  it reads «Russian» for every Russian dub.
