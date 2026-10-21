//
//  MainView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 22.07.2023.
//
import SwiftUI
import KinoPubUI
import KinoPubBackend

struct MainView: View {
  @Environment(NavigationState.self) var navigationState
  @Environment(ErrorHandler.self) var errorHandler
  @EnvironmentObject var authState: AuthState
  @Environment(\.appContext) var appContext
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase

  private let tab: NavigationTabs
  @StateObject private var catalog: HomeCatalog
  @StateObject private var cardMenu = MediaCardMenuCoordinator()
  @ObservedObject private var sectionStore = SectionVisibilityStore.shared

  /// Watch Now, Movies, or Series — same `MediaRowsView` stack of SwiftUI
  /// `Section(title) { rail }` shelves. On tvOS the rail is a TVUIKit representable;
  /// iOS/macOS keep SwiftUI cards. The catalog's `contentType` is what differs:
  /// `nil` is Watch Now (all shortcuts, plus Continue Watching / Collections);
  /// `.movie` / `.serial` are typed shelves.
  init(tab: NavigationTabs = .home,
       catalog: @autoclosure @escaping () -> HomeCatalog) {
    self.tab = tab
    _catalog = StateObject(wrappedValue: catalog())
  }

  private var title: LocalizedStringKey {
    switch tab {
    case .movies: "Movies"
    case .series: "Series"
    default: "Watch Now"
    }
  }

  var body: some View {
    @Bindable var errorHandler = errorHandler
    RouteStack(tab: tab, zoom: true) {
      // No page-level material and no `backgroundExtensionEffect` on any platform.
      //
      // That modifier duplicates the view into *mirrored, blurred copies* laid into
      // whatever safe area is free. It exists for the detail column of a
      // `NavigationSplitView`, so artwork can bleed under an overlaying sidebar or
      // inspector. This app has no split view at all, and our sidebars are meant to
      // displace content, not float over it — so there is nothing for the copies to
      // sit behind. What it produced instead was mirrored rows smeared into the
      // navigation and tab bars, and, on a failed or empty load, a mirrored copy of
      // the error placeholder. The native Apple TV app does not do this.
      //
      // The navigation bar is likewise left to the system: on 26 it is already
      // Liquid Glass with the scroll-edge effect.
      rowsView
        .platformNavigationTitle(title)
#if os(macOS)
        .macToolbarSearch()
#endif
        .handleError(state: $errorHandler.state)
        .task {
          cardMenu.bind(errorHandler: errorHandler)
          await catalog.fetch()
        }
        .onAppear {
          catalog.repaintFromLocalProgress()
        }
        .onChange(of: scenePhase) { _, phase in
          if phase == .active {
            Task { await catalog.refreshContinueWatching() }
          }
        }
        .task {
          await cardMenu.refreshFolders()
        }
        .mediaCardNewFolderAlert(cardMenu)
    }
  }

  /// Nothing on screen until the rows arrive, then a spinner if the wait drags on —
  /// the Apple TV app's own loading behaviour. A failed cold start (nothing cached,
  /// every shelf errored) gets a retry state instead of a blank page.
  @ViewBuilder
  var rowsView: some View {
#if os(tvOS)
    if FeatureFlags.tvPageSections {
      page
    } else {
      legacyRowsView
    }
#else
    legacyRowsView
#endif
  }

#if os(tvOS)
  /// One collection for the whole tab. Rows become typed sections; the column count is
  /// the section template's default (posters 6, stills 5) — change it there, once.
  private var page: some View {
    TVPage(
      sections: pageSections,
      status: pageStatus,
      accessibilityID: "kinopub.page.\(tab)",
      onSelect: { section, item in
        if case .chip(let chip) = item {
          handleChipSelection(chip)
          return
        }
        if case .tile(let tile) = item, section.id == HomeCatalog.liveTVRowID {
          if let id = Int(tile.id),
             let channel = catalog.liveChannels.first(where: { $0.id == id }) {
            navigationState.push(.livePlayer(channel, token: UUID()))
          }
          return
        }
        guard let card = item.card, card.id > 0 else { return }
        if card.primaryAction == .play {
          cardMenu.play(card) { navigationState.push($0) }
        } else if card.opensCollection {
          navigationState.push(Route.collection(CollectionMediaCard.routeCollection(from: card)))
        } else {
          navigationState.push(Route.detailsById(card.id))
        }
      },
      onNearEnd: { section in
        catalog.loadMore(rowID: section.id)
      },
      contextMenuProvider: { card in
        guard !card.opensCollection else { return [] }
        return menuEntries(for: card, surface: .shelf, isContinueWatching: card.isLandscape)
      },
      onRetry: {
        Task { await catalog.refresh() }
      },
      prefersFirstPosterFocus: DebugLaunch.focusFirstPoster,
      returnsToTopOnMenu: true
    )
    // The page spans the screen — under the tab bar too, the way a UIKit tab's content
    // does: the bar's region comes back to the collection as its top inset, rows scroll
    // beneath the bar, and the bar can hide and reveal from that scroll. Sections apply
    // the 80 pt HIG side insets; a rail's trailing peek runs out to the screen edge.
    .ignoresSafeArea()
  }

  /// Continue Watching: five 16:9 stills across (HIG 5-column, 320 at 1920). Titles
  /// stay under the tile at rest (`.always`), and focus is the system's — no overlay
  /// scale on top of it.
  static let continueWatchingColumns = 5
  /// Every other still row: the same HIG 5-column (320 at 1920). The detail page's
  /// episode and version rails take it too (Sasha, 2026-10-04).
  static let stillColumns = 4

  /// The Home banner as the page's first row: the same sampled `bannerCards` the
  /// SwiftUI path draws (six at most), with their title logos, each once
  /// (`TVPageSection.banner`).
  private static let bannerSectionID = "home-banner"

  private var pageSections: [TVPageSection] {
    var result: [TVPageSection] = []
    if catalog.supportsHeroBanner && FeatureFlags.homeBannerEnabled {
      let banner = catalog.bannerCards
      if !banner.isEmpty {
        result.append(
          .banner(id: Self.bannerSectionID,
                  features: banner.map {
                    TVPageFeature(card: catalog.bannerDetails[$0.id] ?? $0,
                                  logo: catalog.bannerLogos[$0.id] ?? .pending)
                  })
        )
      } else {
        result.append(
          .banner(id: Self.bannerSectionID,
                  features: (0..<2).map { idx in
                    TVPageFeature(card: MediaCard.placeholder(id: -101 - idx))
                  })
        )
      }
    }

    var insertedQuickPresets = false
    for row in homeRows {
      if row.cards.first?.isLandscape == true {
        let columns = row.id == HomeCatalog.continueWatchingRowID ? Self.continueWatchingColumns : Self.stillColumns
        let caption: TVPageCaption = row.id == HomeCatalog.continueWatchingRowID ? .always : .onFocus
        result.append(.stills(id: row.id, title: row.title, count: row.count, columns: columns,
                              caption: caption, cards: row.cards))
      } else {
        // Poster rails — Watch Now, Movies, Series alike — have no title or year under the art,
        // not even on focus (Sasha, 2026-10-06): that is `TVPageSection.posters`' own caption for
        // a rail. Catalog / collection / profile grids name every cover.
        result.append(.posters(id: row.id, title: row.title, count: row.count, cards: row.cards))
      }

      if tab == .home && row.id == HomeCatalog.continueWatchingRowID {
        result.append(quickPresetsSection)
        insertedQuickPresets = true
      }
    }

    if !insertedQuickPresets && !homeRows.isEmpty {
      let insertIndex = min(result.count, (catalog.supportsHeroBanner && FeatureFlags.homeBannerEnabled) ? 1 : 0)
      result.insert(quickPresetsSection, at: insertIndex)
    }

    if tab == .home,
       catalog.activeHomeSections.contains(where: { $0.id == HomeCatalog.liveTVRowID }),
       !catalog.liveChannels.isEmpty {
      result.append(
        .tiles(
          id: HomeCatalog.liveTVRowID,
          title: "Спортивные и ТВ-каналы",
          count: "\(catalog.liveChannels.count)",
          columns: TVChannelsView.columns,
          flow: .rail,
          tiles: catalog.liveChannels.map { TVChannelsView.tile(for: $0) }
        )
      )
    }

    if !homeRows.isEmpty {
      result.append(footerActionsSection)
    }

    return result
  }

  private var quickPresetsSection: TVPageSection {
    let excludeConcerts = sectionStore.excludeConcertsOnHome
    let chips: [TVPageChip]
    switch tab {
    case .movies:
      chips = [
        TVPageChip(id: "preset-movies-catalog", title: "Все фильмы в Каталоге", systemImage: "square.grid.2x2"),
        TVPageChip(id: "preset-4k", title: "4K UHD", systemImage: "4k.tv"),
        TVPageChip(id: "preset-movies-scifi", title: "Фантастика и Фэнтези", systemImage: "sparkles"),
        TVPageChip(id: "preset-movies-thriller", title: "Триллеры и Детективы", systemImage: "eye"),
        TVPageChip(id: "preset-movies-action", title: "Боевики", systemImage: "flame"),
        TVPageChip(id: "preset-movies-comedy", title: "Комедии", systemImage: "face.smiling"),
        TVPageChip(id: "preset-movies-drama", title: "Драмы", systemImage: "theatermasks"),
        TVPageChip(id: "preset-movies-horror", title: "Ужасы", systemImage: "moon.stars"),
        TVPageChip(id: "preset-cartoons", title: "Мультфильмы", systemImage: "paintbrush"),
        TVPageChip(id: "preset-movies-docu", title: "Документальные", systemImage: "globe"),
        TVPageChip(id: "preset-movies-standup", title: "Стендап", systemImage: "music.mic"),
      ]
    case .series:
      chips = [
        TVPageChip(id: "preset-series-catalog", title: "Все сериалы в Каталоге", systemImage: "square.grid.2x2"),
        TVPageChip(id: "preset-series-watchers", title: "По подписчикам", systemImage: "person.2"),
        TVPageChip(id: "preset-series-finished", title: "Завершённые целиком", systemImage: "checkmark.seal"),
        TVPageChip(id: "preset-series-crime", title: "Детективы и Криминал", systemImage: "magnifyingglass"),
        TVPageChip(id: "preset-series-scifi", title: "Фантастика и Фэнтези", systemImage: "sparkles"),
        TVPageChip(id: "preset-series-drama", title: "Драмы", systemImage: "theatermasks"),
        TVPageChip(id: "preset-series-comedy", title: "Комедии и Ситкомы", systemImage: "face.smiling"),
        TVPageChip(id: "preset-anime", title: "Аниме", systemImage: "wand.and.stars"),
        TVPageChip(id: "preset-series-dorama", title: "Дорамы", systemImage: "heart.text.square"),
        TVPageChip(id: "preset-series-docu", title: "Док. сериалы", systemImage: "globe"),
        TVPageChip(id: "preset-series-tvshows", title: "ТВ-шоу и Передачи", systemImage: "tv"),
      ]
    default:
      chips = [
        TVPageChip(id: "preset-catalog", title: "Каталог", systemImage: "square.grid.2x2"),
        TVPageChip(id: "preset-collections", title: "Подборки", systemImage: "rectangle.stack"),
        TVPageChip(id: "preset-anime", title: "Аниме", systemImage: "sparkles"),
        TVPageChip(id: "preset-cartoons", title: "Мультфильмы", systemImage: "face.smiling"),
        TVPageChip(id: "preset-docs", title: "Документалки", systemImage: "globe"),
        TVPageChip(id: "preset-4k", title: "4K UHD", systemImage: "4k.tv"),
        TVPageChip(id: "preset-watchers", title: "По подписчикам", systemImage: "person.2"),
        TVPageChip(id: "preset-imdb", title: "Топ IMDb", systemImage: "star.fill"),
        TVPageChip(
          id: "preset-exclude-concerts",
          title: excludeConcerts ? "Без концертов: Вкл" : "Без концертов",
          systemImage: excludeConcerts ? "checkmark.circle.fill" : "music.mic.slash",
          isActive: excludeConcerts
        ),
      ]
    }
    return .chips(id: "home-quick-presets", title: nil, chips: chips)
  }

  private var footerActionsSection: TVPageSection {
    var chips: [TVPageChip] = []
    if catalog.hasMoreSections {
      chips.append(
        TVPageChip(id: "footer-load-more",
                   title: "Показать ещё секции",
                   systemImage: "plus.circle")
      )
    }
    if tab == .home {
      let excludeConcerts = sectionStore.excludeConcertsOnHome
      chips.append(
        TVPageChip(
          id: "footer-exclude-concerts",
          title: excludeConcerts ? "Без концертов: Вкл" : "Без концертов: Выкл",
          systemImage: excludeConcerts ? "checkmark.circle.fill" : "music.mic.slash",
          isActive: excludeConcerts
        )
      )
    }
    chips.append(
      TVPageChip(
        id: "footer-customize",
        title: "Настроить секции и вкладки",
        systemImage: "slider.horizontal.3"
      )
    )
    return .chips(id: "home-footer-actions", title: nil, chips: chips)
  }

  private func handleChipSelection(_ chip: TVPageChip) {
    switch chip.id {
    case "preset-catalog":
      navigationState.openCatalog(filter: LibraryFilter(sort: .recentlyAdded), title: "Каталог")
    case "preset-movies-catalog":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .movie, sort: .recentlyAdded), title: "Фильмы")
    case "preset-series-catalog":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .serial, sort: .recentlyUpdated), title: "Сериалы")
    case "preset-collections":
      if sectionStore.isTabVisible(.collections) {
        navigationState.selectedTab = .collections
      } else {
        navigationState.push(.collections)
      }
    case "preset-anime":
      var filter = LibraryFilter(sort: .watchers)
      filter.kinds = [.anime]
      navigationState.openCatalog(filter: filter, title: "Аниме")
    case "preset-cartoons":
      var filter = LibraryFilter(sort: .views, period: .month)
      filter.kinds = [.cartoons]
      navigationState.openCatalog(filter: filter, title: "Мультфильмы")
    case "preset-docs":
      var filter = LibraryFilter(sort: .views, period: .year)
      filter.kinds = [.documentaries]
      navigationState.openCatalog(filter: filter, title: "Документалки")
    case "preset-4k":
      var filter = LibraryFilter(contentType: tab == .movies ? .movie : (tab == .series ? .serial : nil), sort: .recentlyAdded)
      filter.minimumQuality = .uhd4K
      navigationState.openCatalog(filter: filter, title: "4K UHD")
    case "preset-watchers":
      navigationState.openCatalog(filter: LibraryFilter(sort: .watchers), title: "По подписчикам")
    case "preset-imdb":
      var filter = LibraryFilter(sort: .imdbRating)
      filter.yearFrom = 2020
      navigationState.openCatalog(filter: filter, title: "Топ IMDb")
    case "preset-movies-scifi":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .movie, sort: .views, genreIDs: [4, 5], period: .year), title: "Фантастика и Фэнтези")
    case "preset-movies-thriller":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .movie, sort: .views, genreIDs: [7, 13, 17], period: .year), title: "Триллеры и Детективы")
    case "preset-movies-action":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .movie, sort: .views, genreIDs: [2, 8], period: .year), title: "Боевики и Приключения")
    case "preset-movies-comedy":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .movie, sort: .views, genreIDs: [1], period: .year), title: "Комедии")
    case "preset-movies-drama":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .movie, sort: .imdbRating, genreIDs: [9, 3]), title: "Драмы и Биографии")
    case "preset-movies-horror":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .movie, sort: .views, genreIDs: [12, 11], period: .year), title: "Хорроры и Мистика")
    case "preset-movies-docu":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .documovie, sort: .views, period: .year), title: "Документальные фильмы")
    case "preset-movies-standup":
      var filter = LibraryFilter(sort: .recentlyAdded)
      filter.kinds = [.standup]
      navigationState.openCatalog(filter: filter, title: "Стендап")
    case "preset-series-watchers":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .serial, sort: .watchers), title: "Сериалы по подписчикам")
    case "preset-series-finished":
      var filter = LibraryFilter(contentType: .serial, sort: .watchers)
      filter.finishedOnly = true
      navigationState.openCatalog(filter: filter, title: "Завершённые сериалы")
    case "preset-series-crime":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .serial, sort: .watchers, genreIDs: [13, 7, 17]), title: "Детективы и Криминал")
    case "preset-series-scifi":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .serial, sort: .watchers, genreIDs: [4, 5]), title: "Фантастика и Фэнтези")
    case "preset-series-drama":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .serial, sort: .watchers, genreIDs: [9]), title: "Престижные драмы")
    case "preset-series-comedy":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .serial, sort: .watchers, genreIDs: [1]), title: "Комедийные сериалы")
    case "preset-series-dorama":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .serial, sort: .watchers, genreIDs: [107]), title: "Дорамы")
    case "preset-series-docu":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .docuserial, sort: .views, period: .year), title: "Документальные сериалы")
    case "preset-series-tvshows":
      navigationState.openCatalog(filter: LibraryFilter(contentType: .tvshow, sort: .recentlyUpdated), title: "Телешоу и Передачи")
    case "preset-exclude-concerts", "footer-exclude-concerts":
      sectionStore.excludeConcertsOnHome.toggle()
    case "footer-load-more":
      catalog.loadMoreSections()
    case "footer-customize":
      UserDefaults.standard.set("tabs", forKey: "KINOPUBOpenSettingsCategoryOnce")
      navigationState.selectedTab = .settings
    default:
      break
    }
  }

  /// Contextual, never a bare spinner: "Loading Movies". Failure keeps a focusable
  /// Retry so the remote has somewhere to land.
  private var pageStatus: TVPageStatus {
    if catalog.rows.isEmpty && !catalog.isLoaded {
      return .loading(String(localized: "Loading \(pageTitle)"))
    }
    if catalog.rows.isEmpty && catalog.loadFailed {
      return .failed(message: catalog.loadError?.userFacingMessage
                       ?? "Check your connection and try again.".localized,
                     retryTitle: "Try Again".localized)
    }
    return .content
  }

  private var pageTitle: String {
    switch tab {
    case .movies: String(localized: "Movies")
    case .series: String(localized: "Series")
    default: String(localized: "Watch Now")
    }
  }
#endif

  @ViewBuilder
  private var legacyRowsView: some View {
    if catalog.rows.isEmpty && !catalog.isLoaded {
      LoadingIndicatorView()
    } else if catalog.rows.isEmpty && catalog.loadFailed {
      UnavailableView(title: "Couldn't Load",
                      systemImage: "wifi.exclamationmark",
                      message: catalog.loadError?.userFacingMessage ?? "Check your connection and try again.".localized,
                      retryTitle: "Try Again",
                      onRetry: {
        Task { await catalog.refresh() }
      })
    } else {
      rows
    }
  }

  @ViewBuilder
  private var rows: some View {
    MediaRowsView(
      rows: homeRows,
      // Gated by `FeatureFlags.homeBannerEnabled`. When off, HomeCatalog also
      // skips sampling so wide-poster artwork is never requested.
      bannerCards: (catalog.supportsHeroBanner && FeatureFlags.homeBannerEnabled) ? catalog.bannerCards : [],
      navigationLinkProvider: { card in
        if card.opensCollection {
          Route.collection(CollectionMediaCard.routeCollection(from: card))
        } else {
          Route.detailsById(card.id)
        }
      },
      onPlay: { card in
        cardMenu.play(card) { navigationState.push($0) }
      },
      // Horizontal paging: the shelf reports its last card, the catalog decides whether
      // a next page exists. Continue Watching declines inside `loadMore`.
      onLoadMore: { row, _ in
        catalog.loadMore(rowID: row.id)
      },
      paginationProvider: { row in
        catalog.paginationState(rowID: row.id, loadedCount: row.cards.count)
      },
      onRetryPagination: { row in
        catalog.retryPagination(rowID: row.id)
      },
      contextMenuProvider: { card, surface in
        guard !card.opensCollection else { return [] }
        return menuEntries(for: card, surface: surface, isContinueWatching: card.isLandscape)
      }
    )
  }

  /// Continue Watching's "see all" is the Library tab, not a push: what the row shows
  /// is the head of three lists that live there — series being watched, films being
  /// watched, and history. Every other row's chevron still pushes its own grid, so the
  /// destination stays on the row and only this one is attached here, where navigation
  /// belongs. `HomeCatalog` keeps knowing nothing about tabs.
  private var homeRows: [MediaRow] {
    catalog.rows.map { row in
      guard row.id == HomeCatalog.continueWatchingRowID else { return row }
      return row.opening { navigationState.selectedTab = .library }
    }
  }

  private func menuEntries(for card: MediaCard,
                           surface: MediaCardContextSurface,
                           isContinueWatching: Bool) -> [MediaCardContextEntry] {
    let containing = cardMenu.containingFolders(for: card)
    let folders = cardMenu.folders.map {
      MediaCardContextMenus.BookmarkFolderOption(
        id: $0.id,
        title: $0.title,
        isContaining: containing.contains($0.id)
      )
    }

    let onToggleWatched: (() -> Void)? = {
      if isContinueWatching {
        return card.canToggleWatched ? { catalog.toggleWatched(card) } : nil
      }
      return card.isSeries ? nil : {
        cardMenu.toggleWatched(card, removeFromContinueWatching: false)
      }
    }()

    return MediaCardContextMenus.entries(
      for: card,
      surface: surface,
      bookmarkFolders: folders,
      onPlay: { cardMenu.play(card) { navigationState.push($0) } },
      onGoToTitle: { navigationState.push(.detailsById(card.itemID)) },
      onToggleWatchlist: card.isSeries ? { cardMenu.toggleWatchlist(card) } : nil,
      onToggleBookmarkFolder: { folderID in
        guard let folder = cardMenu.folders.first(where: { $0.id == folderID }) else { return }
        cardMenu.toggleBookmark(itemID: card.itemID,
                                folder: folder,
                                serverHint: card.viewerState.bookmarkFolderIDs ?? [])
      },
      onCreateBookmarkFolder: { cardMenu.promptNewFolder(for: card.itemID) },
      onToggleWatched: onToggleWatched,
      onHide: isContinueWatching ? { catalog.hide(card) } : nil,
      onOpenImageURL: { openURL($0) }
    )
  }
}

struct MainView_Previews: PreviewProvider {
  static let navState = NavigationState()

  static var previews: some View {
    MainView(tab: .home, catalog: HomeCatalog(itemsService: VideoContentServiceMock(),
                                  authState: AuthState(authService: AuthorizationServiceMock(),
                                                       accessTokenService: AccessTokenServiceMock()),
                                  errorHandler: ErrorHandler()))
      .environment(navState)
  }
}
