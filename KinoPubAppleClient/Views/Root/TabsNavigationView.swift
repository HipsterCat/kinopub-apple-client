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
/// - **tvOS:** `.tabBarOnly` (top); glyph · words (Home … TV, Library) · glyph. Search is
///   the **first** tab (left of Home) — not `role: .search`, which pins trailing.
/// - **macOS:** `.tabBarOnly`; no Settings tab (Settings window / ⌘,); no Search tab —
///   compact trailing toolbar search via `macToolbarSearch()` on each `RouteStack`
///   (Finder/Photos). Return opens Search results.
/// - **iPad:** `.tabBarOnly`; Search glyph **first**, Settings gear last, icon+word in
///   between.
/// - **iPhone:** bottom bar; `Tab(role: .search)` pins Search trailing (HIG).
///
/// Badges are `@available(tvOS, unavailable)` on `TabContent` — verified in the 27.0 SDK
/// interface, not assumed — so only the non-TV bars carry the Library count.
///
/// PARKED (do not re-enable until locked properly per docs/WWDC): `.sidebarAdaptable`,
/// `TabViewCustomization`, custom `NavigationSplitView` sidebars, Home segmented
/// Movies/Series. Prototypes remain in `Views/UILab/`.
struct TabsNavigationView: View {

  @Environment(\.appContext) var appContext
#if os(iOS)
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
  @Environment(NavigationState.self) var navigationState
  @Environment(ErrorHandler.self) var errorHandler
  @EnvironmentObject var authState: AuthState
  @EnvironmentObject var networkMonitor: NetworkMonitor
  @ObservedObject private var sectionStore = SectionVisibilityStore.shared

  @State private var sidebarFolders: [Bookmark] = []
  @State private var watchlistBadgeCount = 0
  @State private var sidebarSyncedAt: Date?
  private static let sidebarSyncTTL: TimeInterval = 120
#if os(macOS)
  @Environment(\.openWindow) private var openWindow
#endif

  /// The sidebar item (Mac) / tab (iPad) the app was on, restored at launch. App storage,
  /// not scene storage: a Mac quit with «Close windows when quitting» on (the default)
  /// restores no scene, and the place was lost every time.
  @AppStorage("selectedNavigationTab") private var storedTab = ""

  var body: some View {
    modernTabs
#if !os(tvOS)
      .onAppear { restoreSelectedTab() }
      .onChange(of: navigationState.selectedTab, initial: true) { _, tab in
        storedTab = Self.storageKey(for: tab) ?? storedTab
      }
      // A remembered folder that is gone falls back to Home once the folders are known.
      .onChange(of: sidebarFolders) { _, folders in
        if case .bookmark(let id) = navigationState.selectedTab,
           !folders.isEmpty, !folders.contains(where: { $0.id == id }) {
          navigationState.selectBrowseTab(.home)
        }
      }
#endif
#if os(tvOS)
      // The one backdrop, behind the tab bar and every stack, and everything over it
      // transparent. The selected tab's path says whose picture is in front; the title's
      // page publishes what that picture is (`pageBackdrop`).
      .pageBackdropStage(front: navigationState.backdropFront,
                         live: navigationState.backdropLiveKeys)
#endif
      .presentsWhatsNew(isSignedIn: authState.phase == .signedIn)
      .environment(navigationState)
      .environment(errorHandler)
      .environment(\.usesTVUIKitPosters, FeatureFlags.tvUIKitPosters)
      .environment(\.mediaNavigation) { value in
        if let route = value as? Route {
          navigationState.push(route)
        }
      }
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

#if !os(tvOS)
  private func restoreSelectedTab() {
#if DEBUG
    guard UserDefaults.standard.string(forKey: "KINOPUBInitialTab") == nil else { return }
#endif
#if os(iOS)
    // iPhone opens on Home; the restored place is the sidebar's (iPad).
    guard horizontalSizeClass == .regular else { return }
#endif
    guard navigationState.selectedTab == .home, let tab = Self.tab(forStorageKey: storedTab) else { return }
    navigationState.selectBrowseTab(tab)
  }

  /// Search and Settings are not places to come back to.
  static func storageKey(for tab: NavigationTabs) -> String? {
    switch tab {
    case .search, .settings: nil
    case .bookmark(let id): "bookmark:\(id)"
    case .home: "home"
    case .catalog: "catalog"
    case .movies: "movies"
    case .series: "series"
    case .collections: "collections"
    case .tv: "tv"
    case .library: "library"
    case .watchlist: "watchlist"
    case .recentlyWatched: "history"
    case .downloads: "downloads"
    case .bookmarks: "bookmarks"
    case .continueWatching: "continue"
    case .genres: "genres"
    }
  }

  static func tab(forStorageKey key: String) -> NavigationTabs? {
    if key.hasPrefix("bookmark:"), let id = Int(key.dropFirst("bookmark:".count)) { return .bookmark(id) }
    let all: [NavigationTabs] = [.home, .catalog, .movies, .series, .collections, .library, .watchlist,
                                 .recentlyWatched, .continueWatching, .genres]
    return all.first { storageKey(for: $0) == key }
  }
#endif

  private var tabSelection: Binding<NavigationTabs> {
    Binding(
      get: {
#if os(macOS)
        // Search is not a tab on macOS — TabView only knows browse destinations.
        let tab = navigationState.selectedTab
        if tab == .search || tab == .settings {
          return navigationState.searchReturnTab ?? .home
        }
        return tab
#else
        navigationState.selectedTab
#endif
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

  private var activeBrowseTabs: [TabSpec] {
    sectionStore.visibleBrowseTabs.map {
      TabSpec(tab: $0.tab, title: $0.titleKey, systemImage: $0.systemImage)
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
    case .catalog: catalogContent
    case .movies: moviesContent
    case .series: seriesContent
    case .collections: collectionsContent
#if os(tvOS)
    case .tv: tvContent
#endif
    case .library: libraryContent
#if os(iOS)
    case .watchlist: WatchlistView()
#endif
    default: EmptyView()
    }
  }

  /// Glyph-only tab label. The title still ships as the accessibility label — dropping
  /// the text is a visual decision, not a reason for VoiceOver to announce nothing.
  private func glyph(_ systemImage: String, label: LocalizedStringKey) -> some View {
    Image(systemName: systemImage)
      .accessibilityLabel(Text(label))
  }

  // MARK: - TabView

  @ViewBuilder
  private var modernTabs: some View {
#if os(macOS)
    if FeatureFlags.macSidebarEnabled {
      macSidebarShell
    } else {
      macShell
    }
#elseif os(tvOS)
    tvTabBar
#elseif os(iOS)
    if horizontalSizeClass == .regular {
      padTabBar
    } else {
      phoneCompactTabBar
    }
#endif
  }

#if os(macOS)
  /// Browse tabs; trailing toolbar search lives on each tab's stack via
  /// `macToolbarSearch()` — never on `TabView` (that yields the giant under-tab field).
  /// Return in the field opens the Search results surface.
  /// Search fills the **content** of the tab it was entered from, rather than covering
  /// the shell. Laying it over the `TabView` also covered the tab bar, so typing in the
  /// toolbar field made Watch Now / Movies / Series / Library disappear — the one piece of
  /// chrome that says where you are, gone exactly when a result is about to take you
  /// somewhere else. The tabs stay drawn, the tab you came from stays selected, and
  /// `searchReturnTab` still owns the way back.
  private var macShell: some View {
    TabView(selection: tabSelection) {
      ForEach(activeBrowseTabs) { spec in
        browseTab(spec)
      }
    }
    .tabViewStyle(.tabBarOnly)
    .onAppear {
      if navigationState.selectedTab == .settings {
        navigationState.selectedTab = .home
      }
    }
  }
#endif

#if os(macOS)
  // MARK: - Mac sidebar

  /// The Apple TV app's shell (Sasha, 2026-10-30): one split view, a source-list sidebar
  /// on the left and the selected destination beside it. `NavigationSplitView` with a
  /// sidebar `List` is what AppKit draws there — `NSSplitView`, then an `NSOutlineView`
  /// named «Sidebar» with a row per item — the same tree the TV app's own sidebar has.
  ///
  /// Search, Home and the catalog without a header; the Library's places under it; every
  /// bookmark folder under Collections, the way the TV app lists playlists; the account
  /// at the foot. Settings is the Settings window (⌘,). Each destination keeps its own
  /// stack for pushes.
  private var macSidebarShell: some View {
    NavigationSplitView {
      VStack(spacing: 0) {
      List(selection: sidebarSelection) {
        Label("Search", systemImage: "magnifyingglass").tag(NavigationTabs.search)
        ForEach(activeBrowseTabs.filter { $0.tab != .library }) { spec in
          Label(spec.title, systemImage: spec.systemImage).tag(spec.tab)
        }

        Section("Library") {
          Label("NewEpisodesTitle".localized, systemImage: "bell")
            .badge(watchlistBadgeCount)
            .tag(NavigationTabs.watchlist)
          Label("Continue Watching", systemImage: "play.circle")
            .tag(NavigationTabs.continueWatching)
          Label("History", systemImage: "clock.arrow.circlepath")
            .tag(NavigationTabs.recentlyWatched)
          Label("SidebarGenres".localized, systemImage: "theatermasks")
            .tag(NavigationTabs.genres)
        }

        if !sidebarFolders.isEmpty {
          Section("BookmarkCollections".localized) {
            ForEach(sidebarFolders, id: \.id) { folder in
              Label(folder.title, systemImage: "bookmark")
                .tag(NavigationTabs.bookmark(folder.id))
            }
          }
        }
      }
      .listStyle(.sidebar)
        // Under the list, not over it: an inset let the last folder scroll beneath it.
        MacSidebarAccount(userService: appContext.userService)
      }
      .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
    } detail: {
      macSidebarDetail
    }
  }

  private var sidebarSelection: Binding<NavigationTabs?> {
    Binding(
      get: { navigationState.selectedTab },
      set: { tab in
        guard let tab else { return }
        if tab == .search {
          navigationState.enterSearch()
        } else {
          navigationState.selectBrowseTab(tab)
        }
      }
    )
  }

  @ViewBuilder
  private var macSidebarDetail: some View {
    switch navigationState.selectedTab {
    case .search:
      searchContent
    case .watchlist:
      WatchlistView()
    case .continueWatching:
      RouteStack(tab: .continueWatching) {
        ContinueWatchingListView.make(context: appContext, authState: authState, errorHandler: errorHandler)
      }
    case .recentlyWatched:
      RouteStack(tab: .recentlyWatched) {
        HistoryView()
      }
    case .genres:
      MacGenresView()
    case .bookmark(let id):
      if let folder = sidebarFolders.first(where: { $0.id == id }) {
        RouteStack(tab: .bookmark(id)) {
          BookmarkView(model: BookmarkModel(bookmark: folder,
                                            itemsService: appContext.contentService,
                                            errorHandler: errorHandler))
        }
        .id(id)
      } else {
        homeContent
      }
    case let tab:
      browseContent(for: tab)
    }
  }
#endif

#if os(tvOS)
  /// Top tab bar — Search is first (left of Home), not `role: .search` (that pins
  /// trailing).
  ///
  /// The browse tabs pass a bare `Text`: `Tab("Title", systemImage:)` gives every tab an
  /// icon+label chip, which is what a 10-foot bar must not be. Only the two utility ends
  /// are glyphs.
  ///
  /// Search chrome (field, keyboard, filters) is stood up when this tab bar is created
  /// — not lazily on first visit of the Search tab. Catalog items load in the
  /// background on the same session (`TVSearchTabModel`).
  private var tvTabBar: some View {
    TVSearchSessionContainer(catalog: makeSearchCatalog()) { session in
      TabView(selection: tabSelection) {
        Tab(value: NavigationTabs.search) {
          SearchView(catalog: session.catalog)
        } label: {
          glyph("magnifyingglass", label: "Search")
        }

        ForEach(activeBrowseTabs) { spec in
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
  }
#endif

#if os(iOS)
  /// iPad top tab bar: Search glyph leads, Settings gear closes, icon+word in between.
  ///
  /// Search deliberately does **not** use `Tab(role: .search)` here — that role pins it
  /// trailing, which put the two utility tabs at the same end and read as an
  /// afterthought. iPhone keeps the role (bottom-bar HIG).
  /// iPad: the system's adaptive sidebar (`.sidebarAdaptable`), as Apple's own iPad apps
  /// build it (Sasha, 2026-10-30) — the top tabs, and the same Library and Collections
  /// sections as the Mac sidebar when it is open. Compact width falls back to the tab bar.
  private var padTabBar: some View {
    TabView(selection: tabSelection) {
      Tab("Search", systemImage: "magnifyingglass", value: NavigationTabs.search, role: .search) {
        searchContent
      }

      ForEach(activeBrowseTabs.filter { $0.tab != .library && $0.tab != .watchlist }) { spec in
        Tab(spec.title, systemImage: spec.systemImage, value: spec.tab) {
          content(for: spec.tab)
        }
      }

      TabSection("Library") {
        Tab("NewEpisodesTitle".localized, systemImage: "bell", value: NavigationTabs.watchlist) {
          WatchlistView()
        }
        .badge(unwatchedEpisodesCount)
        Tab("Continue Watching", systemImage: "play.circle", value: NavigationTabs.continueWatching) {
          RouteStack(tab: .continueWatching) {
            ContinueWatchingListView.make(context: appContext, authState: authState, errorHandler: errorHandler)
          }
        }
        Tab("History", systemImage: "clock.arrow.circlepath", value: NavigationTabs.recentlyWatched) {
          RouteStack(tab: .recentlyWatched) { HistoryView() }
        }
        Tab("SidebarGenres".localized, systemImage: "theatermasks", value: NavigationTabs.genres) {
          MacGenresView()
        }
        Tab("TabLibrary", systemImage: "rectangle.stack", value: NavigationTabs.library) {
          libraryContent
        }
      }

      if !sidebarFolders.isEmpty {
        TabSection("BookmarkCollections".localized) {
          ForEach(sidebarFolders, id: \.id) { folder in
            Tab(folder.title, systemImage: "bookmark", value: NavigationTabs.bookmark(folder.id)) {
              RouteStack(tab: .bookmark(folder.id)) {
                BookmarkView(model: BookmarkModel(bookmark: folder,
                                                  itemsService: appContext.contentService,
                                                  errorHandler: errorHandler))
              }
            }
          }
        }
        .defaultVisibility(.hidden, for: .tabBar)
      }

      Tab("Settings", systemImage: "gear", value: NavigationTabs.settings) {
        settingsContent
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    // Always visible for now (2026-08-09) — the system's scroll-driven minimize was
    // reading as random fade in/out. Revisit once detail-page choreography settles.
    .tabBarMinimizeBehavior(.never)
  }

  /// iPhone bottom bar — content tabs + pinned trailing Search (`Tab(role: .search)`).
  private var phoneCompactTabBar: some View {
    TabView(selection: tabSelection) {
      ForEach(activeBrowseTabs) { spec in
        browseTab(spec)
      }

      // With Library in the bar, Settings is its gear (`LibraryView`), as in Sasha's
      // layout (2026-10-30); a bar without Library keeps the tab.
      if !SectionVisibilityStore.shared.isTabVisible(.library) {
        Tab("Settings", systemImage: "gear", value: NavigationTabs.settings) {
          settingsContent
        }
      }

      Tab(value: NavigationTabs.search, role: .search) {
        searchContent
      } label: {
        Label("Search", systemImage: "magnifyingglass")
      }
    }
    // Always visible for now (2026-08-09) — see `padTabBar`.
    .tabBarMinimizeBehavior(.never)
  }
#endif

#if !os(tvOS)
  /// One browse tab with its badge. Split out because `TabContent.badge` is
  /// `@available(tvOS, unavailable)` — the TV bar builds its tabs without this.
  @TabContentBuilder<NavigationTabs>
  private func browseTab(_ spec: TabSpec) -> some TabContent<NavigationTabs> {
    if spec.tab == .watchlist {
      Tab(spec.title, systemImage: spec.systemImage, value: spec.tab) {
        content(for: spec.tab)
      }
      .badge(unwatchedEpisodesCount)
    } else {
      Tab(spec.title, systemImage: spec.systemImage, value: spec.tab) {
        content(for: spec.tab)
      }
    }
  }
#endif

  // MARK: - Badges

  /// Episodes out and not yet watched, across every followed serial — kino.pub's own
  /// `new` per serial, summed. The Library badge it replaces added the number of followed
  /// serials to the number of titles in every bookmark folder: a sum of two unrelated
  /// counts (Sasha, 2026-10-30). Zero shows no badge.
  private var unwatchedEpisodesCount: Int { watchlistBadgeCount }

  // MARK: - Tab roots

#if !os(tvOS)
  private var searchContent: some View {
    SearchView(catalog: makeSearchCatalog())
  }
#endif

  private func makeSearchCatalog() -> LibraryCatalog {
#if os(tvOS)
    // Results from the third character (the first two only complete the query); the
    // filter row's picks come back after a relaunch, the typed text does not.
    LibraryCatalog(itemsService: appContext.contentService,
                   authState: authState,
                   errorHandler: errorHandler,
                   query: initialSearchQuery,
                   minimumQueryLength: 3,
                   savedFilterKey: "search.filter",
                   searchesEveryField: true)
#else
    LibraryCatalog(itemsService: appContext.contentService,
                   authState: authState,
                   errorHandler: errorHandler,
                   query: initialSearchQuery)
#endif
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
    posterShelves(tab: .home, contentType: nil)
  }

  private var catalogContent: some View {
    FilterCatalogTabView(
      catalog: LibraryCatalog(
        itemsService: appContext.contentService,
        authState: authState,
        errorHandler: errorHandler,
        savedFilterKey: "catalog.tab.filter"
      )
    )
  }

  private var collectionsContent: some View {
    RouteStack(tab: .collections, zoom: true) {
      CollectionsView.make(context: appContext,
                           authState: authState,
                           errorHandler: errorHandler)
    }
  }

  private var moviesContent: some View {
    posterShelves(tab: .movies, contentType: .movie)
  }

  private var seriesContent: some View {
    posterShelves(tab: .series, contentType: .serial)
  }

#if os(tvOS)
  private var tvContent: some View {
    TVChannelsView(model: TVChannelsModel(contentService: appContext.contentService))
  }
#endif

  /// Watch Now / Movies / Series on tvOS — and Watch Now on every platform — share
  /// `MainView` + `HomeCatalog`. Typed catalogs filter Hot / Fresh / Popular to one
  /// `MediaType`; Continue Watching stays on Watch Now only.
  private func posterShelves(tab: NavigationTabs, contentType: MediaType?) -> some View {
    MainView(tab: tab, catalog: HomeCatalog(itemsService: appContext.contentService,
                                            authState: authState,
                                            errorHandler: errorHandler,
                                            contentType: contentType))
  }

  /// macOS and tvOS run the sidebar shell; iOS still gets the shelf-rows Library until
  /// its Podcasts-shaped list lands (`docs/archive/plans/library-sidebar.md`, phase 4).
  @ViewBuilder
  private var libraryContent: some View {
#if os(macOS) || os(tvOS)
    LibraryShellView(
      model: LibraryModel(contentService: appContext.contentService,
                          actionsService: appContext.actionsService,
                          authState: authState,
                          errorHandler: errorHandler),
      catalog: LibrarySectionCatalog(contentService: appContext.contentService,
                                     authState: authState,
                                     errorHandler: errorHandler)
    )
#else
    LibraryView(catalog: PersonalLibraryCatalog(itemsService: appContext.contentService,
                                                authState: authState,
                                                errorHandler: errorHandler),
                bookmarks: LibrarySectionCatalog(contentService: appContext.contentService,
                                                 authState: authState,
                                                 errorHandler: errorHandler),
                settings: horizontalSizeClass == .compact ? AnyView(settingsContent) : nil)
#endif
  }

#if !os(macOS)
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
      return try await appContext.contentService.fetchWatchingSerials(subscribedOnly: true).items
        .reduce(0) { $0 + max($1.new ?? 0, 0) }
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

/// Dedicated Catalog tab (`NavigationTabs.catalog`) separated from Search for genre,
/// type, country, year, rating, and sort browsing without the search keyboard.
struct FilterCatalogTabView: View {
  @Environment(NavigationState.self) var navigationState
  @Environment(ErrorHandler.self) var errorHandler
  @Environment(\.openURL) private var openURL

  @StateObject private var catalog: LibraryCatalog
  @StateObject private var cardMenu = MediaCardMenuCoordinator()

  init(catalog: @autoclosure @escaping () -> LibraryCatalog) {
    _catalog = StateObject(wrappedValue: catalog())
  }

  var body: some View {
    @Bindable var errorHandler = errorHandler
    RouteStack(tab: .catalog, zoom: true) {
      content
        .platformNavigationTitle("Catalog")
#if os(macOS)
        .macToolbarSearch()
#endif
        .handleError(state: $errorHandler.state)
        .task {
          cardMenu.bind(errorHandler: errorHandler)
          if let pending = navigationState.pendingCatalogFilter {
            navigationState.pendingCatalogFilter = nil
            catalog.applyExternalFilter(pending)
          } else if catalog.items.isEmpty {
            await catalog.load()
          } else {
            await catalog.revalidate(force: false)
          }
        }
        .task { await cardMenu.refreshFolders() }
        .mediaCardNewFolderAlert(cardMenu)
        .onChange(of: navigationState.pendingCatalogFilter) { _, pending in
          guard let pending else { return }
          navigationState.pendingCatalogFilter = nil
          catalog.applyExternalFilter(pending)
        }
    }
  }

  @ViewBuilder
  private var content: some View {
#if os(tvOS)
    TVPage(
      sections: tvSections,
      status: tvStatus,
      accessibilityID: "kinopub.page.catalog",
      onSelect: { _, item in
        switch item {
        case .card(let card):
          navigationState.push(.detailsById(card.itemID))
        case .chip(let chip) where chip.id == TVSearchFilters.clear:
          catalog.clearFilters()
        default:
          break
        }
      },
      onChipOption: { chip, option in
        TVSearchFilters.apply(chip: chip, option: option, to: catalog)
      },
      onChipSelection: { chip, selection in
        TVSearchFilters.applySelection(chip: chip, selection: selection, to: catalog)
      },
      onNearEnd: { section in
        guard section.id == "browse", let last = catalog.items.last else { return }
        catalog.loadMoreContent(after: last)
      },
      contextMenuProvider: { card in
        MediaCardContextMenus.entries(for: card,
                                      surface: .shelf,
                                      menu: cardMenu,
                                      pushRoute: { navigationState.push($0) },
                                      openURL: { openURL($0) })
      },
      onRetry: { Task { await catalog.refresh() } },
      returnsToTopOnMenu: true
    )
    .ignoresSafeArea()
#else
    if catalog.loadFailed && catalog.items.isEmpty {
      UnavailableView(title: "Couldn't Load",
                      systemImage: "wifi.exclamationmark",
                      message: catalog.loadError?.userFacingMessage ?? "Check your connection and try again.".localized,
                      retryTitle: "Try Again",
                      onRetry: {
        Task { await catalog.refresh() }
      })
    } else {
      ContentItemsListView(
        items: $catalog.items,
        onLoadMoreContent: { item in
          catalog.loadMoreContent(after: item)
        },
        navigationLinkProvider: { item in
          CatalogRoutesLinkProvider().link(for: item)
        },
        contextMenuProvider: { item in
          MediaCardContextMenus.entries(
            for: item,
            menu: cardMenu,
            pushRoute: { navigationState.push($0) },
            openURL: { openURL($0) }
          )
        },
        placeholderCount: (catalog.items.isEmpty && catalog.isLoading) ? 12 : 0,
        emptyMessage: (catalog.items.isEmpty && !catalog.isLoading) ? "No Results" : nil,
        pagination: catalog.paginationState,
        onRetryPagination: {
          catalog.retryPagination()
        }
      ) {
#if !os(macOS)
        LibraryFiltersBar(catalog: catalog)
#endif
      }
      .environment(\.catalogCaptionOmittedGenreIDs, catalog.filter.captionOmittedGenreIDs)
#if os(macOS)
      .toolbar {
        ToolbarItem(placement: .accessoryBar(id: MacToolbarChrome.accessoryID)) {
          LibraryFiltersBar(catalog: catalog)
            .frame(maxWidth: .infinity)
        }
      }
#endif
    }
#endif
  }

#if os(tvOS)
  private var tvSections: [TVPageSection] {
    let filters = TVSearchFilters.row(catalog: catalog, searching: false)
    let cards = catalog.items.map { MediaCard($0) }
    if cards.isEmpty {
      return catalog.isLoading
        ? [filters, .placeholder(id: "browse", title: nil, kind: .poster, columns: 6, flow: .grid)]
        : [filters]
    }
    return [
      filters,
      .posters(id: "browse", title: nil, flow: .grid, caption: .always,
               loadsMore: catalog.hasMorePages,
               omittedCaptionGenreIDs: catalog.filter.captionOmittedGenreIDs, cards: cards)
    ]
  }

  private var tvStatus: TVPageStatus {
    let empty = catalog.items.isEmpty
    if catalog.loadFailed && empty {
      return .failed(message: catalog.loadError?.userFacingMessage
                       ?? "Check your connection and try again.".localized,
                     retryTitle: "Try Again".localized)
    }
    if empty && !catalog.isLoading, catalog.filter.hasActiveFilters {
      return .message("Nothing Matches These Filters".localized)
    }
    return .content
  }
#endif
}

struct TabsNavigationView_Previews: PreviewProvider {
  static var previews: some View {
    TabsNavigationView()
      .environmentObject(NetworkMonitor())
  }
}

#if os(macOS)
/// The account at the foot of the sidebar, as the TV app has it: the avatar and the name.
/// A click opens the Settings window.
private struct MacSidebarAccount: View {
  let userService: UserService
  @Environment(\.openSettings) private var openSettings
  @State private var name: String?
  @State private var avatarURL: URL?

  var body: some View {
    Button {
      openSettings()
    } label: {
      HStack(spacing: 8) {
        CachedRemoteImage(url: avatarURL, contentMode: .fill,
                          placeholder: { Image(systemName: "person.crop.circle.fill").resizable() },
                          failure: { Image(systemName: "person.crop.circle.fill").resizable() })
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 24)
          .clipShape(Circle())
        Text(name ?? "")
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .task {
      guard let user = try? await userService.fetchUserData() else { return }
      name = user.profile.name.flatMap { $0.isEmpty ? nil : $0 } ?? user.username
      avatarURL = user.profile.avatar.flatMap(URL.init(string:))
    }
  }
}

#endif

#if !os(tvOS)
/// Genres as the TV app has them. Mac: the list in a column of its own beside the
/// sidebar, the selected genre's titles beside it. iPad: the list, each genre pushing its
/// titles.
private struct MacGenresView: View {
  @Environment(\.appContext) private var appContext
  @EnvironmentObject private var authState: AuthState
  @Environment(ErrorHandler.self) private var errorHandler
  @State private var genres: [MediaGenre] = []
  @AppStorage("genreSelection") private var selection: Int?

  var body: some View {
#if os(iOS)
    RouteStack(tab: .genres) {
      List(genres) { genre in
        NavigationLink(value: Route.filteredShelf(LibraryFilter(genreID: genre.id), title: genre.title)) {
          Label(genre.title, systemImage: MacGenreSymbol.name(for: genre.title))
        }
      }
      .platformNavigationTitle("SidebarGenres".localized)
    }
    .task { await loadGenres() }
#else
    HStack(spacing: 0) {
      List(selection: $selection) {
        ForEach(genres) { genre in
          Label(genre.title, systemImage: MacGenreSymbol.name(for: genre.title))
            .tag(Optional(genre.id))
        }
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
      .frame(width: 220)
      Divider()
      RouteStack(tab: .genres) {
        if let selection, let genre = genres.first(where: { $0.id == selection }) {
          FilteredShelfView.make(filter: LibraryFilter(genreID: genre.id),
                                 title: genre.title,
                                 context: appContext,
                                 authState: authState,
                                 errorHandler: errorHandler)
            .id(genre.id)
        } else {
          Color.clear
        }
      }
    }
    .task { await loadGenres() }
#endif
  }

  private func loadGenres() async {
    guard genres.isEmpty, let all = try? await appContext.contentService.fetchGenres(for: nil).items
    else { return }
    var seen = Set<String>()
    genres = all.filter { seen.insert($0.title.lowercased()).inserted }
      .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    // A remembered genre that is gone falls back to the first.
    if selection == nil || !genres.contains(where: { $0.id == selection }) {
      selection = genres.first?.id
    }
  }
}

/// A glyph per genre, by the words its name starts with — kino.pub sends no icons.
enum MacGenreSymbol {
  static func name(for title: String) -> String {
    let lower = title.lowercased()
    let table: [(String, String)] = [
      ("боевик", "flame"), ("комеди", "face.smiling"), ("драм", "theatermasks"),
      ("ужас", "eye"), ("фантаст", "sparkles"), ("фэнтези", "wand.and.stars"),
      ("триллер", "bolt"), ("детектив", "magnifyingglass"), ("мульт", "paintbrush"),
      ("аниме", "sparkle"), ("документ", "doc.text.image"), ("мелодрам", "heart"),
      ("криминал", "lock"), ("приключ", "map"), ("семейн", "figure.2.and.child.holdinghands"),
      ("воен", "shield"), ("истор", "building.columns"), ("музык", "music.note"),
      ("мюзикл", "music.mic"), ("спорт", "sportscourt"), ("вестерн", "sun.dust"),
      ("биограф", "person.text.rectangle"), ("детск", "teddybear"), ("короткометраж", "timer"),
      ("реалити", "video"), ("ток-шоу", "mic"), ("новост", "newspaper"), ("эротик", "flame.fill"),
      ("кулинар", "fork.knife"), ("путешеств", "airplane"), ("природ", "leaf"),
      ("наук", "atom"), ("концерт", "music.quarternote.3"), ("стендап", "music.mic"),
    ]
    return table.first { lower.hasPrefix($0.0) || lower.contains($0.0) }?.1 ?? "film"
  }
}
#endif
