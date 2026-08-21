//
//  ShortcutItemsView.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubUI
import KinoPubBackend

/// One Home catalog shelf ("Hot Movies", "Fresh Series", …) opened as its own full,
/// paginated grid — the row header's "see all". Reuses `MediaCatalog` pinned to a
/// shortcut + content type. Sort (Hot / Fresh / Popular) and type filter live in
/// the navigation toolbar, the iOS 26/27 practice — not a bar glued to the content.
///
/// iOS/macOS only. A tvOS row header never shows a chevron (see `MediaPosterShelf`), so
/// this is never pushed there.
struct ShortcutItemsView: View {
  @EnvironmentObject var navigationState: NavigationState
  @Environment(ErrorHandler.self) var errorHandler
  @Environment(\.openURL) private var openURL
  @StateObject private var catalog: MediaCatalog
  @StateObject private var cardMenu = MediaCardMenuCoordinator()

  init(catalog: @autoclosure @escaping () -> MediaCatalog) {
    _catalog = StateObject(wrappedValue: catalog())
  }

  var body: some View {
    @Bindable var errorHandler = errorHandler
    content
      .platformNavigationTitle(displayedTitle)
      .toolbar { sortAndFilterToolbar }
      .background(Color.KinoPub.background)
      .task {
        cardMenu.bind(errorHandler: errorHandler)
        await catalog.fetchItems()
      }
      .task { await cardMenu.refreshFolders() }
      .mediaCardNewFolderAlert(cardMenu)
      .handleError(state: $errorHandler.state)
  }

  /// Keep the Home row's localized title when the user hasn't changed sort/type;
  /// otherwise compose from the current shortcut + type.
  private var displayedTitle: String {
    switch (catalog.shortcut, catalog.contentType) {
    case (.hot, .movie): return "Hot Movies".localized
    case (.hot, .serial): return "Hot Series".localized
    case (.fresh, .movie): return "Fresh Movies".localized
    case (.fresh, .serial): return "Fresh Series".localized
    case (.popular, .movie): return "Popular Movies".localized
    case (.popular, .serial): return "Popular Series".localized
    default:
      return "\(catalog.shortcut.title.localized) \(catalog.contentType.title.localized)"
    }
  }

  @ToolbarContentBuilder
  private var sortAndFilterToolbar: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Menu {
        ForEach(MediaShortcut.allCases) { shortcut in
          Button {
            catalog.shortcut = shortcut
          } label: {
            LibraryFiltersBar.checkmarkLabel(LocalizedStringKey(shortcut.title),
                                             selected: catalog.shortcut == shortcut)
          }
        }
      } label: {
        Label("Sort", systemImage: "arrow.up.arrow.down")
      }
    }
    ToolbarItem(placement: .primaryAction) {
      Menu {
        ForEach(MediaType.allCases) { type in
          Button {
            catalog.contentType = type
          } label: {
            LibraryFiltersBar.checkmarkLabel(LocalizedStringKey(type.titleKey),
                                             selected: catalog.contentType == type)
          }
        }
      } label: {
        Label("Filter", systemImage: "line.3.horizontal.decrease")
      }
    }
  }

  @ViewBuilder
  private var content: some View {
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
    } else if catalog.items.isEmpty {
      UnavailableView(title: "No Results", systemImage: "rectangle.stack")
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

  static func make(shortcut: MediaShortcut,
                   contentType: MediaType,
                   title: String,
                   context: AppContextProtocol,
                   authState: AuthState,
                   errorHandler: ErrorHandler) -> ShortcutItemsView {
    // Title is derived from the live shortcut + type; the route still carries
    // the Home row's string for the stack identity.
    _ = title
    return ShortcutItemsView(
      catalog: MediaCatalog(itemsService: context.contentService,
                            authState: authState,
                            errorHandler: errorHandler,
                            contentType: contentType,
                            shortcut: shortcut))
  }
}
