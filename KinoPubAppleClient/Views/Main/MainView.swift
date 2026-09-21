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
  @EnvironmentObject var navigationState: NavigationState
  @Environment(ErrorHandler.self) var errorHandler
  @EnvironmentObject var authState: AuthState
  @Environment(\.appContext) var appContext
  @Environment(\.openURL) private var openURL

  private let tab: NavigationTabs
  @StateObject private var catalog: HomeCatalog
  @StateObject private var cardMenu = MediaCardMenuCoordinator()

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
      onSelect: { _, item in
        guard case .card(let card) = item else { return }
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
      prefersFirstPosterFocus: DebugLaunch.focusFirstPoster
    )
    // The page spans the screen — under the tab bar too, the way a UIKit tab's content
    // does: the bar's region comes back to the collection as its top inset, rows scroll
    // beneath the bar, and the bar can hide and reveal from that scroll. Sections apply
    // the 80 pt HIG side insets; a rail's trailing peek runs out to the screen edge.
    .ignoresSafeArea()
  }

  private var pageSections: [TVPageSection] {
    homeRows.map { row in
      if row.cards.first?.isLandscape == true {
        return .stills(id: row.id, title: row.title, count: row.count, cards: row.cards)
      }
      return .posters(id: row.id, title: row.title, count: row.count, cards: row.cards)
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
      bannerCards: (tab == .home && FeatureFlags.homeBannerEnabled) ? catalog.bannerCards : [],
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
                                serverHint: Set(card.bookmarkFolderIDs))
      },
      onCreateBookmarkFolder: { cardMenu.promptNewFolder(for: card.itemID) },
      onToggleWatched: onToggleWatched,
      onHide: isContinueWatching ? { catalog.hide(card) } : nil,
      onOpenImageURL: { openURL($0) }
    )
  }
}

struct MainView_Previews: PreviewProvider {
  @StateObject static var navState = NavigationState()

  static var previews: some View {
    MainView(tab: .home, catalog: HomeCatalog(itemsService: VideoContentServiceMock(),
                                  authState: AuthState(authService: AuthorizationServiceMock(),
                                                       accessTokenService: AccessTokenServiceMock()),
                                  errorHandler: ErrorHandler()))
      .environmentObject(navState)
  }
}
