import Foundation

/// DEBUG scheme arguments for hig shots. Empty in Release.
///
/// `-KINOPUBFocusFirstPoster` lands focus on Watch Now’s **Hot Movies** poster
/// (`hot-movie`, else the first non-landscape row) so caption clearance can be
/// captured. Pair with `-KINOPUBForceColorScheme light`.
///
/// Continue Watching is skipped by making the landscape rail unfocusable
/// (`allowsFocus` / `canFocusItemAt`). Returning `nil` from
/// `indexPathForPreferredFocusedView` is **not** enough — the system then
/// defaults to the first CW cell.
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
