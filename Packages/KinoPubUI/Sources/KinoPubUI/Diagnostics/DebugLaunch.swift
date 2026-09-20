import Foundation

/// DEBUG scheme arguments for hig shots. Empty in Release.
///
/// `-KINOPUBFocusFirstPoster` lands focus on Watch Now’s **Hot Movies** poster
/// (`hot-movie`, else the first non-landscape row) so caption clearance can be
/// captured. Pair with `-KINOPUBForceColorScheme light`.
///
/// Continue Watching is skipped by making the landscape rail unfocusable
/// (`collectionView.allowsFocus`, `canFocusItemAt`, cell `canBecomeFocused`).
/// Returning `nil` from `indexPathForPreferredFocusedView` is **not** enough —
/// the system then defaults to the first CW cell. Do not use `UIView.allowsFocus`
/// or `focusGroupPriority` — both are unavailable on tvOS.
///
/// After the Hot Movies cells exist, `UIFocusSystem.requestFocusUpdate(to:)`
/// claims the first poster and retries until that cell is actually focused.
/// `setNeedsFocusUpdate()` on that rail is a no-op while the tab bar holds
/// focus. SwiftUI `defaultFocus` does not reach TVUIKit cells — do not point
/// it at a CardKey the posters never bind (an unbound defaultFocus leaves
/// the Watch Now tab pill as preferred).
public enum DebugLaunch {
  public static var focusFirstPoster: Bool {
#if DEBUG
    ProcessInfo.processInfo.arguments.contains("-KINOPUBFocusFirstPoster")
      || UserDefaults.standard.bool(forKey: "KINOPUBFocusFirstPoster")
#else
    false
#endif
  }
}
