//
//  PiraticApp.swift
//  Piratic
//
//  Created by Kirill Kunst on 17.07.2023.
//

import SwiftUI
import PiraticKit
import PiraticUI
import PiraticMetadata
import PiraticLogging
import OSLog

enum WindowSize {
  static let macos = CGSize(width: 960, height: 580)

  /// Opening size on launch, scaled up from `macos` (the enforced minimum) toward
  /// roughly a 1280x880 window instead of letting the system pick its own default.
  static let macosDefault = CGSize(width: macos.width * 4 / 3, height: macos.height * 4 / 3)
}

@main
struct PiraticApp: App {
  
  /// Shared on iOS / tvOS (one scene). On macOS each library window owns its own
  /// `NavigationState` via `MacLibraryNavigationHost` so Finder-style tabs stay
  /// independent; this instance is only a fallback for the player window when no
  /// library origin was recorded.
  @State var navigationState = NavigationState()
  @State private var errorHandler = ErrorHandler()
  @State private var appLanguage = AppLanguage.shared
  @StateObject var networkMonitor = NetworkMonitor()
  @StateObject var authState = AuthState(authService: AppContext.shared.authService,
                                         accessTokenService: AppContext.shared.accessTokenService,
                                         handlesAppWideAuthEvents: true)
  
#if os(macOS)
  @State private var windowSettings = WindowSettings()
  /// Finder / Photos style: icon + title in the unified toolbar; user can change
  /// it from View ›. Bound so the choice sticks across launches (KP-105).
  @AppStorage("ToolbarLabelStyle") private var toolbarLabelStyle: ToolbarLabelStyle = .titleAndIcon
#endif
  
#if os(iOS) || os(tvOS)
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
#endif

#if os(macOS)
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
#endif

  init() {
    // Before anything reads a flag: the launch-time ones are pinned here for the session.
    MainActor.assumeIsolated {
      FeatureFlag.applyAtLaunch()
      Artwork.startRememberingDisplayScale()
      // Align AppleLanguages with selectedLanguage before any string lookup.
      _ = AppLanguage.shared
    }
    // First thing: the proxy only records requests made after it is installed, and the
    // launch traffic is the whole reason it exists.
    NetworkDiagnostics.start()
    // Restore streaming if it was left on — but never turn it on by default: enabling it
    // is what triggers the local-network permission prompt.
    if UserDefaults.standard.bool(forKey: DiagnosticsSettings.remoteLoggingKey) {
      MainActor.assumeIsolated { NetworkDiagnostics.setRemoteLoggingEnabled(true) }
    }
    HLSAudioLabeler.removeLegacyTemporaryFiles()
#if os(macOS)
    MainActor.assumeIsolated { SidebarCollapseLock.install() }
#endif
#if os(tvOS)
    // Rejected moves only — not the per-move hierarchy sweep.
    MainActor.assumeIsolated { FocusLog.startRejectionTrace() }
#endif
#if os(tvOS) && DEBUG
    // One observer under both SwiftUI and UIKit — see `FocusLog.startGlobalTrace`.
    MainActor.assumeIsolated { FocusLog.startGlobalTrace() }
#endif
  }

  var body: some Scene {
    WindowGroup {
#if os(macOS)
      // One NavigationState per library window / tab so Finder-style tabs stay independent.
      MacLibraryNavigationHost { navigation in
        libraryRoot(navigation: navigation)
      }
#else
      libraryRoot(navigation: navigationState)
#endif
    }
#if os(macOS)
    .windowResizability(.contentSize)
    .defaultSize(width: WindowSize.macosDefault.width, height: WindowSize.macosDefault.height)
    // Always present the library on launch. Settings (and any other restorable
    // secondary `Window`) can reopen alone; with the default `.automatic` launch
    // behavior the primary `WindowGroup` then stays closed because "another scene
    // already presented" — closing Settings leaves a running app with no UI until
    // the Dock icon is clicked. `.presented` keeps Settings restoration and still
    // opens the main window beside it (Apple's `defaultLaunchBehavior`).
    .defaultLaunchBehavior(.presented)
    // Unified toolbar with the page's title in it, as the TV app's: large beside Back,
    // inline once the page scrolls (`toolbarTitleDisplayMode(.inlineLarge)` per page).
    .windowToolbarStyle(.unified(showsTitle: true))
    // Icon + title by default (Filters, Sort, …), as Finder; View › can switch to
    // icon-only. Listing Labels always carry a title so this style has something to show.
    .windowToolbarLabelStyle($toolbarLabelStyle)
    // New Window / new tab are system-owned again (each window has its own
    // NavigationState). Open Recent stays under File, as IINA lists its files.
    .commands {
      AboutCommands()
      SettingsCommands()
#if DEBUG
      UILabCommands()
#endif
      CommandGroup(after: .newItem) { OpenRecentMenu() }
      // Keep for when `.sidebarAdaptable` returns — hide View → Hide Sidebar.
      // Harmless with classic `.tabBarOnly` (no sidebar chrome).
      CommandGroup(replacing: .sidebar) { }
      // Into the system View menu — `CommandMenu("View")` would add a second View.
      ListArrangementCommands()
    }
#endif

#if os(macOS)
    // The player is its own window rather than a page inside the library window, the way
    // the stock TV app lifts a film out of the page it was on. That window's title bar is
    // where the film's name and the close button come from — a pushed player screen had
    // neither, and no way out once playback began.
    Window("Player", id: PlaybackWindowState.windowID) {
      PlayerWindowContent(fallbackNavigation: navigationState)
        .listedInWindowMenu(disallowTabbing: true)
        .environment(\.appContext, AppContext.shared)
        .environmentObject(authState)
        .environment(errorHandler)
        .environmentObject(networkMonitor)
//        // .preferredColorScheme(.dark)
    }
    // Off the Window menu: the only way in is pressing Play. A menu item opens the scene
    // with nothing to play, which is just an empty black window.
    .commandsRemoved()
    // And don't let the system reopen it at launch for the same reason — a restored
    // player window has no film in it.
    .restorationBehavior(.disabled)
    // Free resizing: a film is worth as much of the display as the viewer wants to give it.
    .windowResizability(.automatic)
    // Open at the shape of the video, not at whatever the last window happened to be —
    // a 16:9 film in a wide short window is all black bars. Everything kino.pub serves is
    // 16:9; a different aspect just letterboxes inside a correctly-sized window instead of
    // opening wrong.
    .defaultWindowPlacement { _, context in
      let visible = context.defaultDisplay.visibleRect
      let width = min(visible.width * 0.8, visible.height * 0.8 * (16.0 / 9.0))
      return WindowPlacement(.center, size: CGSize(width: width, height: width * 9.0 / 16.0))
    }

    // Custom Settings window (not SwiftUI `Settings` scene) so we own the chrome —
    // System Settings–style sidebar + toolbar. Opened via App menu / ⌘, / profile button.
    Window("Settings", id: SettingsWindow.id) {
      SettingsView()
        .listedInWindowMenu(disallowTabbing: true)
        .environment(\.appContext, AppContext.shared)
        .environment(windowSettings)
        .environmentObject(authState)
        .environment(errorHandler)
//        // .preferredColorScheme(.dark)
    }
    .windowResizability(.contentSize)
    .defaultSize(width: 720, height: 520)
    .commandsRemoved()

    // Window › Activity ⌥⌘L, as the TV app on the Mac has it: what is downloading, with
    // pause and Simultaneous Downloads. The scene lists itself in the Window menu.
    Window("Activity", id: ActivityWindow.id) {
      DownloadsActivityView(center: AppContext.shared.downloadsCenter)
        .listedInWindowMenu(disallowTabbing: true)
    }
    .keyboardShortcut("l", modifiers: [.command, .option])
    .defaultSize(width: 420, height: 420)
    .restorationBehavior(.disabled)

    Window("About Piratic", id: AboutWindow.id) {
      AboutView()
        .listedInWindowMenu(disallowTabbing: true)
//        // .preferredColorScheme(.dark)
    }
    .windowResizability(.contentSize)
    .restorationBehavior(.disabled)
    .commandsRemoved()

#if DEBUG
    // UI labs — A/B chrome (adaptable TabView vs locked NavigationSplitView).
    // Open from Window menu, Advanced Settings, or the in-lab toolbar.
    WindowGroup("UI Lab", id: UILabWindow.id, for: UILabChrome.self) { $chrome in
      UILabRoot(initialChrome: chrome ?? .adaptableSidebar)
        .frame(minWidth: 1100, minHeight: 700)
//        // .preferredColorScheme(.dark)
    }
    .defaultSize(width: 1200, height: 800)
    .windowResizability(.contentSize)
    .restorationBehavior(.disabled)
#endif
#endif
  }

  /// Shared chrome around `RootView` for every library window. `navigation` is
  /// per-window on macOS and the single app-owned instance elsewhere.
  @ViewBuilder
  private func libraryRoot(navigation: NavigationState) -> some View {
    RootView()
      .capturesPageColorScheme()
#if !os(tvOS)
      // Monochrome accent for now (Sasha, 2026-10-30): black in light, white in dark —
      // the selected tab, list glyphs, links — instead of the system blue.
      .tint(.primary)
#endif
      .environment(\.appContext, AppContext.shared)
      // Hover pictures on cards come from the worker the title page uses.
      .environment(\.titleImageRoute, AppContext.shared.metadataService.images)
      .environment(navigation)
      .environmentObject(authState)
      .environment(errorHandler)
      .environmentObject(networkMonitor)
#if os(macOS)
      .environment(windowSettings)
#endif
      .piraticLaunchColorScheme()
      .piraticAppearancePreference()
      .piraticAppLanguage(appLanguage)
      .onAppear { ShellRemount.shared.navigation = navigation }
      // Piratic OAuth redirects (`piratic://myanimelist`, `piratic://shikimori`) and
      // Top Shelf (`piratic://…` on tvOS). Account token exchange is not wired yet.
      .onOpenURL { url in
        if let redirect = PiraticOAuthRedirect(url: url) {
          Logger.app.info("OAuth redirect reserved: \(String(describing: redirect))")
          return
        }
#if os(tvOS)
        guard let link = TopShelfLink(url: url) else { return }
        TopShelfRouter.open(link, navigation: navigation)
#endif
      }
#if DEBUG
      // `-PIRATICOpenItem <id>`: open on a title's page, for screenshots of a live
      // detail page without walking there.
      .task(id: authState.userState) {
        guard authState.userState == .authorized,
              let id = Int(UserDefaults.standard.string(forKey: "PIRATICOpenItem") ?? "")
        else { return }
        navigation.selectBrowseTab(.home)
        navigation.mainRoutes = [.detailsById(id)]
      }
      // `-PIRATICPlayEpisode <item>:<season>:<episode>`: straight into the player on one
      // episode, the way a Continue Watching card resolves it — for checking what the
      // player decides (the `tracks ·` log lines) without walking there.
      .task(id: authState.userState) {
        guard authState.userState == .authorized,
              let raw = UserDefaults.standard.string(forKey: "PIRATICPlayEpisode") else { return }
        let parts = raw.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return }
        do {
          var item = try await AppContext.shared.contentService.fetchDetails(for: "\(parts[0])").item
          item.stampSeasons()
          AppContext.shared.localProgressStore.cacheItem(item)
          guard let season = item.seasons?.first(where: { $0.number == parts[1] }),
                let episode = season.episodes.first(where: { $0.number == parts[2] }) else { return }
          let stamped = episode.stamped(season: season.number, mediaId: item.id,
                                        seriesTitle: episode.seriesTitle)
          navigation.push(.player(stamped, token: UUID()))
        } catch {
          Logger.app.error("PIRATICPlayEpisode: \(error)")
        }
      }
#endif
      // Register a readable device identity + advertise HEVC/4K/HDR at activation, so
      // the kino.pub Devices list isn't "unknown / unknown" and streams match what
      // AVPlayer can open. A launch that only revived a Keychain token sends nothing
      // unless the profile itself changed (see DeviceProfileRegistry).
      .task(id: authState.userState) {
        guard authState.userState == .authorized else { return }
        await AppContext.shared.deviceService.syncDeviceProfile(
          activated: authState.didActivateDevice
        )
      }
#if os(iOS)
      .task {
        await AppContext.shared.downloadNotificationManager.requestPermission()
      }
#endif
#if os(macOS)
      .sizeIndependentOfContent(minimum: WindowSize.macos)
      .listedInWindowMenu()
#endif
  }
}

#if os(macOS)
/// Owns one `NavigationState` per library `WindowGroup` instance (window or tab).
private struct MacLibraryNavigationHost<Content: View>: View {
  @State private var navigationState = NavigationState()
  @ViewBuilder var content: (NavigationState) -> Content

  var body: some View {
    content(navigationState)
  }
}

enum SettingsWindow {
  static let id = "settings"
}

enum AboutWindow {
  static let id = "about"
}

private struct AboutCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("About Piratic") {
        openWindow(id: AboutWindow.id)
      }
    }
  }
}

/// The View menu's list-arrangement items, shaped the way Finder and Notes shape
/// theirs: named submenus holding a checked list, not a stack of pickers spilled
/// straight into View. Disabled — not hidden — when the front screen has no list to
/// arrange, which is what tells a user the items exist at all.
private struct ListArrangementCommands: Commands {
  @AppStorage(HistoryGrouping.storageKey) private var grouping: String = HistoryGrouping.none.rawValue
  @AppStorage(HistorySectioning.storageKey) private var sectioning: String = HistorySectioning.day.rawValue
  @FocusedValue(\.showsListArrangement) private var showsArrangement: Bool?

  private var isEnabled: Bool { showsArrangement == true }

  var body: some Commands {
    CommandGroup(after: .toolbar) {
      Divider()
      Menu("Group By") {
        Picker("Group By", selection: $grouping) {
          ForEach(HistoryGrouping.allCases) { option in
            Text(LocalizedStringKey(option.titleKey)).tag(option.rawValue)
          }
        }
      .pickerStyle(.inline)
      .labelsHidden()
      }
      .disabled(!isEnabled)

      // Apple's own wording for this shape — Notes calls it "Group By Date".
      Menu("Group By Date") {
        Picker("Group By Date", selection: $sectioning) {
          ForEach(HistorySectioning.allCases) { option in
            Text(LocalizedStringKey(option.titleKey)).tag(option.rawValue)
          }
        }
        .pickerStyle(.inline)
        .labelsHidden()
      }
      .disabled(!isEnabled)
    }
  }
}

private struct SettingsCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .appSettings) {
      Button("Settings…") {
        openWindow(id: SettingsWindow.id)
      }
      .keyboardShortcut(",", modifiers: .command)
    }
  }
}

#if DEBUG
private struct UILabCommands: Commands {
  @Environment(\.openWindow) private var openWindow
  @AppStorage(HistoryCardLayout.storageKey) private var historyCardLayout: String = HistoryCardLayout.landscape.rawValue

  var body: some Commands {
    // Window menu — next to Settings / About style utility windows.
    CommandGroup(after: .windowArrangement) {
      Divider()
      Button("UI Lab — Navigation Split") {
        openWindow(id: UILabWindow.id, value: UILabChrome.navigationSplit)
      }
      Button("UI Lab — Adaptable Sidebar") {
        openWindow(id: UILabWindow.id, value: UILabChrome.adaptableSidebar)
      }
      Divider()
      // Landscape vs poster tiles in history. An experiment, not a shipped option: it
      // is named after one screen and there is no general list/cards choice behind it
      // yet, so it stays out of the View menu until there is.
      Picker("History Tiles (experiment)", selection: $historyCardLayout) {
        ForEach(HistoryCardLayout.allCases) { layout in
          Text(LocalizedStringKey(layout.titleKey)).tag(layout.rawValue)
        }
      }
      .pickerStyle(.inline)
    }
  }
}
#endif
#endif

/// Appearance at the app root.
///
/// User Theme (Settings › Appearance) is applied by `piraticAppearancePreference()`.
/// tvOS must **not** get `.preferredColorScheme(nil)` for System — that still pinned
/// Dark on the simulator (hig could not get Light); System means omitting the
/// modifier. DEBUG `-PIRATICForceColorScheme light|dark` still wins over the
/// preference (`simctl ui appearance` unsupported). What is drawn over a picture
/// forces itself dark, the way the Apple TV app does.
enum LaunchAppearance {
#if DEBUG
  static var forcedColorScheme: ColorScheme? {
    let raw = UserDefaults.standard.string(forKey: "PIRATICForceColorScheme")
      ?? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-PIRATICForceColorScheme"),
              args.index(after: i) < args.endIndex else { return nil }
        return args[args.index(after: i)]
      }()
    switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "light": return .light
    case "dark": return .dark
    default: return nil
    }
  }
#endif
}

private extension View {
  @ViewBuilder
  func piraticLaunchColorScheme() -> some View {
#if DEBUG
    if let scheme = LaunchAppearance.forcedColorScheme {
      preferredColorScheme(scheme)
    } else {
      self
    }
#else
    self
#endif
  }
}

#if os(macOS)
/// A window's — or a tab's, or a split view column's — size limits are a fixed minimum,
/// never a measurement of the page.
///
/// Performance limitation (Instruments, 2026-11-28, macOS 27.3): with a scene's
/// `windowResizability` the window's `NSHostingView` recomputes its min / max size on every
/// layout pass — `NSHostingView.minSize()` from `layout()` and `updateConstraints()` — and a
/// `.frame(minWidth:minHeight:)` passes that zero-size proposal down to the whole page, scroll
/// content included. Scrolling a title page spent ~20% of the main thread there. The tabs of
/// the Mac `TabView` and the sidebar shell's detail column are hosting views of their own
/// and ask the same question (10% in a trace taken after the window root was wrapped), so
/// each of those roots carries this too.
/// This layout answers the window's size questions itself (the minimum, or whatever the
/// window offers above it) and lays the content out only at the size it really gets.
private struct SizeIndependentOfContent: Layout {
  var minimum: CGSize

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    CGSize(width: max(proposal.width ?? minimum.width, minimum.width),
           height: max(proposal.height ?? minimum.height, minimum.height))
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for subview in subviews {
      subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
  }
}

extension View {
  func sizeIndependentOfContent(minimum: CGSize = .zero) -> some View {
    SizeIndependentOfContent(minimum: minimum) { self }
  }
}
#endif
