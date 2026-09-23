import Foundation

/// DEBUG scheme arguments for hig shots. Empty in Release.
///
/// `-KINOPUBForceColorScheme light|dark` pins appearance for hig shots.
/// `-KINOPUBFocusFirstPoster` is a best-effort steal onto Hot Movies — local
/// verify at `f59f31b` failed (tab pill kept focus). Do not use it as the
/// evidence path. Pair scheme args by hand; they are not on the shared Debug scheme.
///
/// Continue Watching is skipped by making the landscape rail unfocusable
/// (`collectionView.allowsFocus`, `canFocusItemAt`, cell `canBecomeFocused`).
/// Returning `nil` from `indexPathForPreferredFocusedView` is **not** enough —
/// the system then defaults to the first CW cell. Do not use `UIView.allowsFocus`
/// or `focusGroupPriority` — both are unavailable on tvOS.
///
/// After the Hot Movies cells exist, `UIFocusSystem.requestFocusUpdate(to:)`
/// *tries* to claim the first poster. Local verify at `f59f31b` failed — the
/// SwiftUI tab bar kept focus. Do not treat this flag as a working shot
/// harness. Hig frames: `WatchNowHigShotsUITests` + `XCUIRemote.press(.down)`.
/// `setNeedsFocusUpdate()` on that rail is a no-op while the tab bar holds
/// focus. SwiftUI `defaultFocus` does not reach TVUIKit cells — do not point
/// it at a CardKey the posters never bind (an unbound defaultFocus leaves
/// the Watch Now tab pill as preferred).
public enum DebugLaunch {
  /// `-KINOPUBTemplatesGallery`: the app root is the section-templates page instead of
  /// the tab shell — the one place every `TVPageSection` kind is on screen at once, for
  /// shots and remote-driven tests without a sign-in or a walk through Settings.
  public static var templatesGallery: Bool {
#if DEBUG
    ProcessInfo.processInfo.arguments.contains("-KINOPUBTemplatesGallery")
#else
    false
#endif
  }

  /// `-KINOPUBSearchQuery <text>`: the search field starts with this text. The tvOS
  /// inline keyboard takes no `typeText` from UI tests, so this is how a test searches.
  public static var searchQuery: String? {
#if DEBUG
    UserDefaults.standard.string(forKey: "KINOPUBSearchQuery")
#else
    nil
#endif
  }

  public static var focusFirstPoster: Bool {
#if DEBUG
    ProcessInfo.processInfo.arguments.contains("-KINOPUBFocusFirstPoster")
      || UserDefaults.standard.bool(forKey: "KINOPUBFocusFirstPoster")
#else
    false
#endif
  }
}
