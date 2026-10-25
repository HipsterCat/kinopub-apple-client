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

  /// `-KINOPUBTemplatesHero`: with the templates gallery, its first row is the Home hero
  /// carousel (`TVPageSection.hero`) instead of the banner shelf — for `TVHomeHeroUITests`.
  public static var templatesHero: Bool {
#if DEBUG
    ProcessInfo.processInfo.arguments.contains("-KINOPUBTemplatesHero")
#else
    false
#endif
  }

  /// `-KINOPUBHeroScrollLog`: the Home hero's page logs every focus move and scroll end
  /// (offset, adjusted top inset, hero height, section) to the system log as `HERO-SCROLL`
  /// — to see where the focus engine leaves the page and why.
  public static var heroScrollLog: Bool {
#if DEBUG
    ProcessInfo.processInfo.arguments.contains("-KINOPUBHeroScrollLog")
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

  /// `-KINOPUBTVChannelsFixture YES`: the app root is the real TV tab under a tab bar, on a
  /// stand-in API that lists a set of channels (see `TVChannelsFixture` in the app), and a
  /// stand-in player — the grid, its focus and Select with no session. With
  /// `-KINOPUBFixtureRealArt YES` the logos come from kino.pub's CDN.
  public static var tvChannelsFixture: Bool {
#if DEBUG
    UserDefaults.standard.bool(forKey: "KINOPUBTVChannelsFixture")
#else
    false
#endif
  }

  /// `-KINOPUBFixtureRealPlayer YES`: the TV tab fixture plays in the app's real player, every
  /// channel on Apple's public sample stream — the system player in live mode, under the
  /// remote, with no session.
  public static var fixtureRealPlayer: Bool {
#if DEBUG
    UserDefaults.standard.bool(forKey: "KINOPUBFixtureRealPlayer")
#else
    false
#endif
  }

  /// `-KINOPUBFixtureStream <url>`: the stream the real-player fixtures open instead of
  /// Apple's sample — a local server that holds the playlist back stands in for a slow CDN.
  public static var fixtureStream: String? {
#if DEBUG
    UserDefaults.standard.string(forKey: "KINOPUBFixtureStream")
#else
    nil
#endif
  }

  /// `-KINOPUBFixtureOpensAt <n>`: the `seasonStrip` fixture's second season has ten
  /// episodes and is watched up to `n − 1`, so Play opens S2E`n` with the rest ahead — the
  /// player's Episodes tab opening in the middle of a season.
  public static var fixtureOpensAt: Int? {
#if DEBUG
    let value = UserDefaults.standard.integer(forKey: "KINOPUBFixtureOpensAt")
    return value > 0 ? value : nil
#else
    nil
#endif
  }

  /// `-KINOPUBSlowInfo <seconds>`: the player stamps what it knows about the title that
  /// long after the tabs could first be built — what a thin card (Home's banner) does on a
  /// real connection, where the stream's links are fetched before the item exists. For the
  /// Info tab's arrival.
  public static var slowInfo: TimeInterval? {
#if DEBUG
    UserDefaults.standard.object(forKey: "KINOPUBSlowInfo") == nil
      ? nil : UserDefaults.standard.double(forKey: "KINOPUBSlowInfo")
#else
    nil
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

  /// `-KINOPUBFixtureWatchOutAfter <seconds>`: that long after launch the Library fixture's
  /// stand-in API reports the third followed series caught up and the Library refetches, as
  /// it does back from the player — the series leaves Subscriptions under the remote.
  public static var fixtureWatchOutAfter: TimeInterval? {
#if DEBUG
    UserDefaults.standard.object(forKey: "KINOPUBFixtureWatchOutAfter") == nil
      ? nil : UserDefaults.standard.double(forKey: "KINOPUBFixtureWatchOutAfter")
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

  /// `-KINOPUBSearchFixture`: the app root is the tvOS search screen under a tab bar, with
  /// the templates gallery's posters as results — the system keyboard, suggestions and our
  /// results page with no session. Pair with `-ForceGridKeyboard YES` for the keyboard on
  /// the left (UIKit's own default, read from the argument domain).
  public static var searchFixture: Bool {
#if DEBUG
    ProcessInfo.processInfo.arguments.contains("-KINOPUBSearchFixture")
#else
    false
#endif
  }
}
