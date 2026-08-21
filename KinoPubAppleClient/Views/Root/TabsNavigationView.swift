//
//  TabsNavigationView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 11.08.2023.
//

import Foundation
import SwiftUI
import KinoPubUI
import KinoPubBackend
import KinoPubKit

/// Primary chrome — classic system `TabView` tab bar on every platform.
///
/// The browse destinations live in **one table** (`browseTabs`); each platform only
/// decides how a tab *labels* itself and which utility ends surround them. Before that
/// they were four hand-written trees that had to be edited in parallel every time a tab
/// changed, which is how the iPad bar's comment ended up describing a shape its own code
/// did not build.
///
/// - **tvOS:** `.tabBarOnly` (top); glyph · word · … · glyph. Search is the **first**
///   tab (left of Home) — not `role: .search`, which pins trailing. Settings stays a
///   trailing glyph. Browse tabs: Home · Watching · Bookmarks.
/// - **macOS:** `.tabBarOnly`; no Settings tab (Settings window / ⌘,); no Search tab —
///   compact trailing toolbar search via `macToolbarSearch()` on each `RouteStack`
///   (Finder/Photos). Return opens Search results.
/// - **iPhone / iPad:** Home · Watching · Bookmarks + `Tab(value:role: .search)` trailing
///   (HIG). Do **not** pass a title or systemImage on the search tab — that renders it
///   as a peer chip. Settings is a navigation-bar gear, not a tab.
/// - **Movies / Shows** are gated by `FeatureFlags.catalogBrowseTabsEnabled` until
///   those pages are Home-shaped section feeds.
///
/// Badges are `@available(tvOS, unavailable)` on `TabContent` — verified in the 27.0 SDK
/// interface, not assumed — so only the non-TV bars carry Watching / Bookmarks counts.
///
/// PARKED (do not re-enable until locked properly per docs/WWDC): `.sidebarAdaptable`,
/// `TabViewCustomization`, custom `NavigationSplitView` sidebars, Home segmented
/// Movies/Series. Prototypes remain in `Views/UILab/`.
struct TabsNavigationView: View {

  @Environment(\.appContext) var appContext
  @EnvironmentObject var navigationState: NavigationState
  @Environment(ErrorHandler.self) var errorHandler
  @EnvironmentObject var authState: AuthState
  @EnvironmentObject var networkMonitor: NetworkMonitor

  @State private var sidebarFolders: [Bookmark] = []
  @State private var watchlistBadgeCount = 0
  @State private var sidebarSyncedAt: Date?
  private static let sidebarSyncTTL: TimeInterval = 120
#if os(macOS)
  @Environment(\.openWindow) private var openWindow
#endif

  var body: some View {
    modernTabs
      .environmentObject(navigationState)
      .environment(errorHandler)
      .environment(\.usesTVUIKitPosters, FeatureFlags.tvUIKitPosters)
      .environment(\.mediaNavigation) { value in
        if let route = value as? Route {
          navigationState.push(route)
        }
      }
      .onAppear { remapHiddenTabs() }
      .task(id: authState.phase) {
        guard authState.phase == .signedIn else { return }
        await loadSidebarChrome()
      }
      .onChange(of: navigationState.selectedTab) { _, _ in
        guard authState.phase == .signedIn else { return }
        Task { await syncSidebarFolders() }
      }
      // DESIGN: offline / reachability banner when `networkMonitor.isOnline` flips false.
      .onChange(of: networkMonitor.isOnline) { _, _ in }
  }

  private var tabSelection: Binding<NavigationTabs> {
    Binding(
      get: {
        let tab = navigationState.selectedTab
        if !Self.isVisibleTab(tab) {
          return visibleFallback(for: tab)
        }
        return tab
      },
      set: { newValue in
#if os(macOS)
        if navigationState.selectedTab == .search {
          navigationState.selectBrowseTab(newValue)
          return
        }
#endif
        if newValue == .search {
          if navigationState.selectedTab == .search {
            navigationState.popToRoot(for: .search)
          } else {
            // Remember previous tab so Back can leave Search (toolbar / tab / filter jump).
            navigationState.enterSearch()
          }
          return
        }
        if newValue == navigationState.selectedTab {
          navigationState.popToRoot(for: newValue)
        } else {
          navigationState.selectedTab = newValue // Publishing changes from within view updates is not allowed, this will cause undefined behavior.
        }
      }
    )
  }

  // MARK: - The tab table

  /// A browse destination in bar order. Search and Settings are deliberately absent:
  /// they are the utility ends, and every platform places them differently.
  private struct TabSpec: Identifiable {
    let tab: NavigationTabs
    let title: LocalizedStringKey
    let systemImage: String
    var id: NavigationTabs { tab }
  }

  private static var browseTabs: [TabSpec] {
    var tabs = [
      TabSpec(tab: .home, title: "Home", systemImage: "house.fill")
    ]
    if FeatureFlags.catalogBrowseTabsEnabled {
      tabs.append(TabSpec(tab: .movies, title: "Movies", systemImage: "movieclapper"))
      tabs.append(TabSpec(tab: .series, title: "Shows", systemImage: "rectangle.stack"))
    }
    tabs.append(TabSpec(tab: .watchlist, title: "Watching", systemImage: "play.circle.fill"))
    tabs.append(TabSpec(tab: .bookmarks, title: "Bookmarks", systemImage: "bookmark.fill"))
    return tabs
  }

  /// Tabs the current platform's `TabView` actually contains. Hidden catalog tabs
  /// and Settings-as-a-tab on iOS/macOS must not remain the selection — that is
  /// what used to dump Settings into More on iPhone. The old combined Library tab
  /// remaps to Watching.
  private static func isVisibleTab(_ tab: NavigationTabs) -> Bool {
    switch tab {
    case .movies, .series:
      return FeatureFlags.catalogBrowseTabsEnabled
    case .settings:
#if os(tvOS)
      return true
#else
      return false
#endif
    case .search:
#if os(macOS)
      return false
#else
      return true
#endif
    case .home, .watchlist, .bookmarks:
      return true
    case .library, .recentlyWatched, .downloads, .bookmark:
      return false
    }
  }

  private func visibleFallback(for tab: NavigationTabs) -> NavigationTabs {
#if os(macOS)
    if tab == .search || tab == .settings {
      return navigationState.searchReturnTab ?? .home
    }
#endif
    if tab == .library { return .watchlist }
    return .home
  }

  private func remapHiddenTabs() {
    let tab = navigationState.selectedTab
#if os(macOS)
    // Search is not a tab here, but it is a real selectedTab while the results
    // surface is up — do not bounce it back to Home on appear.
    if tab == .search { return }
#endif
    if !Self.isVisibleTab(tab) {
      navigationState.selectedTab = visibleFallback(for: tab)
    }
  }

  @ViewBuilder
  private func content(for tab: NavigationTabs) -> some View {
#if os(macOS)
    // Search is not a tab here (see `macShell`) — it takes over the content of the tab
    // it was entered from, so the bar above it keeps standing. Exactly that one tab:
    // every tab root stays mounted on this shell, and answering "search" for all four
    // would stand up four `SearchView`s, each with its own catalog and its own fetch.
    if navigationState.selectedTab == .search, tab == (navigationState.searchReturnTab ?? .home) {
      searchContent
        .background(Color.KinoPub.background)
    } else {
      browseContent(for: tab)
    }
#else
    browseContent(for: tab)
#endif
  }

  @ViewBuilder
  private func browseContent(for tab: NavigationTabs) -> some View {
    switch tab {
    case .home: homeContent
    case .movies: moviesContent
    case .series: seriesContent
    case .watchlist, .library: watchingContent
    case .bookmarks: bookmarksContent
    default: EmptyView()
    }
  }

#if os(tvOS)
  /// Glyph-only tab label. The title still ships as the accessibility label — dropping
  /// the text is a visual decision, not a reason for VoiceOver to announce nothing.
  private func glyph(_ systemImage: String, label: LocalizedStringKey) -> some View {
    Image(systemName: systemImage)
      .accessibilityLabel(Text(label))
  }
#endif

  // MARK: - TabView

  @ViewBuilder
  private var modernTabs: some View {
#if os(macOS)
    macShell
#elseif os(tvOS)
    tvTabBar
#elseif os(iOS)
    iosTabBar
#endif
  }

#if os(macOS)
  /// Browse tabs; trailing toolbar search lives on each tab's stack via
  /// `macToolbarSearch()` — never on `TabView` (that yields the giant under-tab field).
  /// Return in the field opens the Search results surface.
  /// Search fills the **content** of the tab it was entered from, rather than covering
  /// the shell. Laying it over the `TabView` also covered the tab bar, so typing in the
  /// toolbar field made Home / Movies / Shows / Library disappear — the one piece of
  /// chrome that says where you are, gone exactly when a result is about to take you
  /// somewhere else. The tabs stay drawn, the tab you came from stays selected, and
  /// `searchReturnTab` still owns the way back.
  private var macShell: some View {
    TabView(selection: tabSelection) {
      ForEach(Self.browseTabs) { spec in
        browseTab(spec)
      }
    }
    .tabViewStyle(.tabBarOnly)
  }
#endif

#if os(tvOS)
  /// Top tab bar — Search is first (left of Home), not `role: .search` (that pins
  /// trailing).
  ///
  /// The browse tabs pass a bare `Text`: `Tab("Title", systemImage:)` gives every tab an
  /// icon+label chip, which is what a 10-foot bar must not be. Only the two utility ends
  /// are glyphs.
  private var tvTabBar: some View {
    TabView(selection: tabSelection) {
      Tab(value: NavigationTabs.search) {
        searchContent
      } label: {
        glyph("magnifyingglass", label: "Search")
      }

      ForEach(Self.browseTabs) { spec in
        Tab(value: spec.tab) {
          content(for: spec.tab)
        } label: {
          Text(spec.title)
        }
      }

      Tab(value: NavigationTabs.settings) {
        settingsContent
      } label: {
        glyph("gear", label: "Settings")
      }
    }
    .tabViewStyle(.tabBarOnly)
  }
#endif

#if os(iOS)
  /// Bottom bar on iPhone, top bar on iPad: Home · Watching · Bookmarks + trailing
  /// Search role. The search tab is unlabeled — a title + systemImage makes it a
  /// third peer chip. Settings is the navigation-bar gear (`tabRootChrome`).
  private var iosTabBar: some View {
    TabView(selection: tabSelection) {
      ForEach(Self.browseTabs) { spec in
        browseTab(spec)
      }

      Tab(value: NavigationTabs.search, role: .search) {
        searchContent
      }
    }
    .tabViewStyle(.tabBarOnly)
    .tabBarMinimizeBehavior(.onScrollDown)
    .tabViewSearchActivation(.searchTabSelection)
  }
#endif

#if !os(tvOS)
  /// One browse tab with its badge. Split out because `TabContent.badge` is
  /// `@available(tvOS, unavailable)` — the TV bar builds its tabs without this.
  @TabContentBuilder<NavigationTabs>
  private func browseTab(_ spec: TabSpec) -> some TabContent<NavigationTabs> {
    switch spec.tab {
    case .watchlist:
      Tab(spec.title, systemImage: spec.systemImage, value: spec.tab) {
        content(for: spec.tab)
      }
      .badge(watchlistBadgeCount)
    case .bookmarks:
      Tab(spec.title, systemImage: spec.systemImage, value: spec.tab) {
        content(for: spec.tab)
      }
      .badge(bookmarksBadgeCount)
    default:
      Tab(spec.title, systemImage: spec.systemImage, value: spec.tab) {
        content(for: spec.tab)
      }
    }
  }
#endif

  // MARK: - Badges

  private var bookmarksBadgeCount: Int {
    sidebarFolders.reduce(0) { $0 + (Int($1.count) ?? 0) }
  }

  // MARK: - Tab roots

  private var searchContent: some View {
    SearchView(catalog: LibraryCatalog(itemsService: appContext.contentService,
                                       authState: authState,
                                       errorHandler: errorHandler,
                                       query: initialSearchQuery))
  }

  /// What the user has already typed by the time the search surface is built. Only
  /// macOS has anywhere to type before it exists — the field is in the window toolbar,
  /// on every tab. Without this the first load runs query-less and answers with the
  /// unfiltered catalogue; `LibraryCatalog`'s doc comment has the whole sequence.
  private var initialSearchQuery: String {
#if os(macOS)
    navigationState.macSearchFieldText
#else
    ""
#endif
  }

  private var homeContent: some View {
    MainView(catalog: HomeCatalog(itemsService: appContext.contentService,
                                  authState: authState,
                                  errorHandler: errorHandler))
  }

  private var moviesContent: some View {
    CatalogView(title: "Movies",
                tab: .movies,
                catalog: MediaCatalog(itemsService: appContext.contentService,
                                      authState: authState,
                                      errorHandler: errorHandler,
                                      contentType: .movie))
  }

  private var seriesContent: some View {
    CatalogView(title: "Shows",
                tab: .series,
                catalog: MediaCatalog(itemsService: appContext.contentService,
                                      authState: authState,
                                      errorHandler: errorHandler,
                                      contentType: .serial))
  }

  /// Watching: watchlist serials, unfinished movies, recently watched — Home-shaped
  /// rows. The macOS/tvOS Library sidebar (`LibraryShellView`) is parked.
  private var watchingContent: some View {
    LibraryView(catalog: PersonalLibraryCatalog(itemsService: appContext.contentService,
                                                authState: authState,
                                                errorHandler: errorHandler))
  }

  private var bookmarksContent: some View {
    BookmarksView(catalog: BookmarksCatalog(itemsService: appContext.contentService,
                                            authState: authState,
                                            errorHandler: errorHandler))
  }

#if os(tvOS)
  private var settingsContent: some View {
    ProfileView(model: ProfileModel(userService: appContext.userService,
                                    errorHandler: errorHandler,
                                    authState: authState))
  }
#endif

  // MARK: - Badge data

  /// Only the badge counts are fetched here. The profile avatar deliberately is **not**:
  /// `SettingsRootView` already loads and caches it for the one screen that draws it,
  /// and this view's copy fed a `@State` no branch of the body ever rendered — a network
  /// fetch per sign-in for nothing. Left over from the parked sidebar shell.
  private func loadSidebarChrome() async {
    async let foldersTask = fetchFolders()
    async let watchlistTask = fetchWatchlistCount()
    sidebarFolders = await foldersTask
    watchlistBadgeCount = await watchlistTask
    sidebarSyncedAt = Date()
  }

  private func syncSidebarFolders() async {
    if let sidebarSyncedAt, Date().timeIntervalSince(sidebarSyncedAt) < Self.sidebarSyncTTL { return }
    async let foldersTask = fetchFolders()
    async let watchlistTask = fetchWatchlistCount()
    let folders = await foldersTask
    let watchlist = await watchlistTask
    if folders != sidebarFolders { sidebarFolders = folders }
    if watchlist != watchlistBadgeCount { watchlistBadgeCount = watchlist }
    sidebarSyncedAt = Date()
  }

  private func fetchFolders() async -> [Bookmark] {
    do {
      let fetched = try await appContext.contentService.fetchBookmarks().items
      // The sidebar refresh doubles as the app's folder-list refresh — see
      // `BookmarkFoldersStore`, which every card menu reads instead of fetching.
      BookmarkFoldersStore.shared.adopt(fetched)
      return fetched
        .filter { $0.count != "0" }
        .recentlyUpdatedFirst()
    } catch {
      return sidebarFolders
    }
  }

  private func fetchWatchlistCount() async -> Int {
    do {
      return try await appContext.contentService.fetchWatchingSerials(subscribedOnly: true).items.count
    } catch {
      return watchlistBadgeCount
    }
  }
}

/*
 PARKED — sidebarAdaptable / locked-sidebar experiments (revisit with docs + device checks)

 Do not re-enable until sidebar toggle / hide / edit are solved the system way:
 - TabView(.sidebarAdaptable) + TabSection + tabViewSidebarBottomBar / Header
 - TabViewCustomization (macOS hide/reorder) — intentionally omitted before; still open
 - .toolbar(removing: .sidebarToggle) + CommandGroup(replacing: .sidebar)
 - NavigationSplitView + List(selection:) / custom Button rows — rejected vs apple-native-design
 - Home segmented For You/Movies/Series instead of separate tabs

 Working prototypes: Views/UILab/UILabRoot.swift (adaptable vs split).
*/

struct TabsNavigationView_Previews: PreviewProvider {
  static var previews: some View {
    TabsNavigationView()
      .environmentObject(NetworkMonitor())
  }
}
