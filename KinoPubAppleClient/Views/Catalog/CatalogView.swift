//
//  CatalogView.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubUI
import KinoPubBackend

/// A browse tab pinned to one content type — Movies or Series. Paginated grid;
/// searching and filtering live in the Search tab. The pinned shortcut/sort
/// control is gone: it sat in the navigation bar through scroll and is the
/// reason these tabs are gated off (`FeatureFlags.catalogBrowseTabsEnabled`)
/// until the pages are Home-shaped section feeds.
struct CatalogView: View {
  @EnvironmentObject var navigationState: NavigationState
  @Environment(ErrorHandler.self) var errorHandler
  @EnvironmentObject var authState: AuthState
  @Environment(\.appContext) var appContext
  @Environment(\.openURL) private var openURL

  private let title: LocalizedStringKey
  private let tab: NavigationTabs

  @StateObject private var catalog: MediaCatalog
  @StateObject private var cardMenu = MediaCardMenuCoordinator()

  /// The tab is the whole address: `RouteStack` resolves which array of
  /// `NavigationState` backs it, so there is no separate path key path to keep in step.
  init(title: LocalizedStringKey,
       tab: NavigationTabs,
       catalog: @autoclosure @escaping () -> MediaCatalog) {
    self.title = title
    self.tab = tab
    _catalog = StateObject(wrappedValue: catalog())
  }

  var body: some View {
    @Bindable var errorHandler = errorHandler
    RouteStack(tab: tab, zoom: true) {
      catalogView
        .platformNavigationTitle(title)
        .background(Color.KinoPub.background)
#if os(iOS)
        .browseNavigationChrome()
        .iosSettingsToolbar(for: tab)
#endif
#if os(macOS)
        .macToolbarSearch()
#endif
        .handleError(state: $errorHandler.state)
        .task {
          cardMenu.bind(errorHandler: errorHandler)
          await catalog.fetchItems()
        }
        .task { await cardMenu.refreshFolders() }
        .mediaCardNewFolderAlert(cardMenu)
    }
  }

  @ViewBuilder
  var catalogView: some View {
    if catalog.items.isEmpty && catalog.isLoading {
      LoadingIndicatorView()
    } else if catalog.items.isEmpty && catalog.loadFailed {
      UnavailableView(title: "Couldn't Load",
                      systemImage: "wifi.exclamationmark",
                      message: catalog.loadError?.userFacingMessage ?? "Check your connection and try again.".localized,
                      retryTitle: "Try Again",
                      onRetry: {
        catalog.refresh()
      })
    } else {
      grid
    }
  }

  private var grid: some View {
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
      pagination: catalog.paginationState,
      onRetryPagination: {
        catalog.retryPagination()
      }
    )
  }
}
