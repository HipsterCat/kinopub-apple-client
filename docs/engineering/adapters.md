# Accepted adapters

Allowed to exist, one place each, the limitation in the type's doc comment. Rule: [AGENTS.md › Constraints are not requirements](../../AGENTS.md#constraints-are-not-requirements). An adapter that stops being needed gets deleted, not kept "in case"; re-probe each one on the next SDK or package major.

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
  Checked by `TVSearchLayoutUITests` (`-KINOPUBSearchFixture -ForceGridKeyboard YES`).

- **`TVSettingKit.swift`** (tvOS Settings) — Settings runs on Apple's private `TVSettingKit`
  (`_TSKSplitViewController`, `TSKViewController`, `TSKSettingItem`, `TSKPreviewViewController`):
  the still preview column, the list-only slide-and-crossfade on push, Apple's cells and value
  pickers have no public API, and a hand-built copy was rejected. Only that file touches private
  API; classes and selectors are checked once (`TVSettingKit.isAvailable`) and the SwiftUI
  `TVProfileSettingsView` is the fallback. Rows bind by KVC through `TSKValueStore` onto the
  existing `@AppStorage` keys and models. Full-screen tools are presented over it, each in its
  own `NavigationStack`, with the environment forwarded. Re-probe every tvOS.

- **`RenditionNames`** (`PlayerManager.swift`) — `AVMetadataItem.stringValue` is deprecated
  (16) for the async `load(.stringValue)`, while `AudioRenditions` reads a rendition's `NAME=`
  synchronously and is tested with no asset. The player awaits the names right after each
  `loadMediaSelectionGroup`; the rules keep their shape. `displayName` is never a substitute —
  it reads «Russian» for every Russian dub.
