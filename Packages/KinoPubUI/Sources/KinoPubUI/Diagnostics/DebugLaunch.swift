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

  /// `-KINOPUBLayoutDebug`: every page section, the collection, the page controller's
  /// view and each cell's content get their own translucent colour — the "paint the
  /// boxes" way of seeing which container owns a stray inset without Xcode's view debugger.
  public static var layoutDebug: Bool {
#if DEBUG
    ProcessInfo.processInfo.arguments.contains("-KINOPUBLayoutDebug")
#else
    false
#endif
  }

  /// `-KINOPUBDetailFixture <name>`: the app root is a stack of fixture titles served by
  /// local stand-ins for the API, TMDB and the player, opened at the one named (see
  /// `DetailFixture` in the app). For UI tests of the detail page — focus on return from
  /// the player, episodes kino.pub does not have, film versions — with no session.
  public static var detailFixture: String? {
#if DEBUG
    UserDefaults.standard.string(forKey: "KINOPUBDetailFixture")
#else
    nil
#endif
  }

  /// `-KINOPUBLibraryFixture YES`: the app root is the real Library (sidebar and page) on a
  /// stand-in API that lists a handful of followed series with episodes waiting (see
  /// `LibraryFixture` in the app) — Subscriptions as a signed-in account has them, with
  /// no session, for shots and tests of the grid's captions.
  public static var libraryFixture: Bool {
#if DEBUG
    UserDefaults.standard.bool(forKey: "KINOPUBLibraryFixture")
#else
    false
#endif
  }

  /// `-KINOPUBSlowShelves <seconds>`: the stand-in API (`VideoContentServiceMock`) takes that
  /// long to answer a person's shelf on the detail page, so the page spends the time with
  /// skeleton rows where shelves will land — what a real connection does and a fixture,
  /// which answers at once, never shows. For tests of focus while the page is still filling.
  public static var slowShelves: TimeInterval? {
#if DEBUG
    UserDefaults.standard.object(forKey: "KINOPUBSlowShelves") == nil
      ? nil : UserDefaults.standard.double(forKey: "KINOPUBSlowShelves")
#else
    nil
#endif
  }

  /// `-KINOPUBFixtureRealArt YES`: the detail fixtures' shelves use real posters from the
  /// CDN instead of locally drawn ones — images that arrive over the network, are cached,
  /// and are decoded the way a signed-in session's are.
  public static var fixtureRealArt: Bool {
#if DEBUG
    UserDefaults.standard.bool(forKey: "KINOPUBFixtureRealArt")
#else
    false
#endif
  }

  /// `-KINOPUBFixtureInTabs YES`: the detail fixture's navigation stack lives in production's
  /// `.tabBarOnly` `TabView` — the tab bar above the page, the page pushed from a tab's root —
  /// instead of being the whole screen. The focus environment a signed-in session has.
  public static var fixtureInTabs: Bool {
#if DEBUG
    UserDefaults.standard.bool(forKey: "KINOPUBFixtureInTabs")
#else
    false
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

  /// `-KINOPUBMenuBackProbe`: templates gallery inside a `.tabBarOnly` `TabView`,
  /// matching production chrome, so a UI test can see whether Menu reaches the
  /// page under the system tab bar (Rivulet measured that `.sidebarAdaptable`
  /// never did).
  public static var menuBackProbe: Bool {
#if DEBUG
    ProcessInfo.processInfo.arguments.contains("-KINOPUBMenuBackProbe")
#else
    false
#endif
  }
}
