import Foundation

/// DEBUG scheme arguments for hig shots. Empty in Release.
///
/// `-KINOPUBFocusFirstPoster` lands focus on the first **poster** tile (skips
/// Continue Watching landscape) so caption clearance can be captured. Pair with
/// the app’s `-KINOPUBForceColorScheme light|dark`.
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
