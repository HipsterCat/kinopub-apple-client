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
/// - **tvOS:** `.tabBarOnly` (top); glyph · words (Watch Now … TV, Library) · glyph. Search is
///   the **first** tab (left of Watch Now) — not `role: .search`, which pins trailing.
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

  var body: some View {
    modernTabs
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
    macShell
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

#if os(tvOS)
  /// Top tab bar — Search is first (left of Watch Now), not `role: .search` (that pins
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
            // Literals at the call site so String Catalog + TabView cannot drift
            // back to Home / Shows (after shot at 8d0def4).
            switch spec.tab {
            case .home: Text("Watch Now")
            case .catalog: Text("Catalog")
            case .movies: Text("Movies")
            case .series: Text("Series")
            case .collections: Text("Collections")
            case .tv: Text("TV")
            case .library: Text("Library")
            default: Text(spec.title)
            }
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
  private var padTabBar: some View {
    TabView(selection: tabSelection) {
      Tab(value: NavigationTabs.search) {
        searchContent
      } label: {
        glyph("magnifyingglass", label: "Search")
      }

      ForEach(activeBrowseTabs) { spec in
        browseTab(spec)
      }

      Tab(value: NavigationTabs.settings) {
        settingsContent
      } label: {
        glyph("gear", label: "Settings")
      }
    }
    .tabViewStyle(.tabBarOnly)
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

      Tab("Settings", systemImage: "gear", value: NavigationTabs.settings) {
        settingsContent
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
    if spec.tab == .library {
      Tab(spec.title, systemImage: spec.systemImage, value: spec.tab) {
        content(for: spec.tab)
      }
      .badge(libraryBadgeCount)
    } else {
      Tab(spec.title, systemImage: spec.systemImage, value: spec.tab) {
        content(for: spec.tab)
      }
    }
  }
#endif

  // MARK: - Badges

  private var libraryBadgeCount: Int {
    watchlistBadgeCount + bookmarksBadgeCount
  }

  private var bookmarksBadgeCount: Int {
    sidebarFolders.reduce(0) { $0 + (Int($1.count) ?? 0) }
  }

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
#if os(tvOS)
    posterShelves(tab: .movies, contentType: .movie)
#else
    CatalogView(title: "Movies",
                tab: .movies,
                catalog: MediaCatalog(itemsService: appContext.contentService,
                                      authState: authState,
                                      errorHandler: errorHandler,
                                      contentType: .movie))
#endif
  }

  private var seriesContent: some View {
#if os(tvOS)
    posterShelves(tab: .series, contentType: .serial)
#else
    CatalogView(title: "Series",
                tab: .series,
                catalog: MediaCatalog(itemsService: appContext.contentService,
                                      authState: authState,
                                      errorHandler: errorHandler,
                                      contentType: .serial))
#endif
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
                                                errorHandler: errorHandler))
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
               loadsMore: catalog.hasMorePages, cards: cards)
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
