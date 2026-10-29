//
//  ShortcutItemsView.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubUI
import KinoPubBackend

/// One Watch Now catalog shelf ("Hot Movies", "Fresh Series", …) opened as its own full,
/// paginated grid — the row header's "see all". Reuses `MediaCatalog` pinned to one
/// shortcut + content type, so paging, retry and context menus come for free. No sort
/// control: the shelf already stands for one specific shortcut, and a picker would make
/// the pushed page's title a lie.
///
/// iOS/macOS only. A tvOS row header never shows a chevron (see `MediaPosterShelf`), so
/// this is never pushed there.
struct ShortcutItemsView: View {
  private let title: String

  @Environment(NavigationState.self) var navigationState
  @Environment(ErrorHandler.self) var errorHandler
  @Environment(\.openURL) private var openURL
  @StateObject private var catalog: MediaCatalog
  @StateObject private var cardMenu = MediaCardMenuCoordinator()

  init(title: String, catalog: @autoclosure @escaping () -> MediaCatalog) {
    self.title = title
    _catalog = StateObject(wrappedValue: catalog())
  }

  var body: some View {
    @Bindable var errorHandler = errorHandler
    content
      .platformNavigationTitle(title)
      .background(Color.KinoPub.background)
      .task {
        cardMenu.bind(errorHandler: errorHandler)
        await catalog.fetchItems()
      }
      .task { await cardMenu.refreshFolders() }
      .mediaCardNewFolderAlert(cardMenu)
      .handleError(state: $errorHandler.state)
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
    ShortcutItemsView(
      title: title,
      catalog: MediaCatalog(itemsService: context.contentService,
                            authState: authState,
                            errorHandler: errorHandler,
                            contentType: contentType,
                            shortcut: shortcut))
  }
}

/// A Home filter shelf (`Новинки`, `Топ недели`, …) as its own paginated grid.
/// iOS and macOS only — tvOS row headers have no chevron.
struct FilteredShelfView: View {
  private let title: String

  @Environment(NavigationState.self) var navigationState
  @Environment(ErrorHandler.self) var errorHandler
  @Environment(\.openURL) private var openURL
  @StateObject private var catalog: FilteredShelfCatalog
  @StateObject private var cardMenu = MediaCardMenuCoordinator()

  init(title: String, catalog: @autoclosure @escaping () -> FilteredShelfCatalog) {
    self.title = title
    _catalog = StateObject(wrappedValue: catalog())
  }

  var body: some View {
    @Bindable var errorHandler = errorHandler
    content
      .platformNavigationTitle(title)
      .background(Color.KinoPub.background)
      .task {
        cardMenu.bind(errorHandler: errorHandler)
        await catalog.fetchItems()
      }
      .task { await cardMenu.refreshFolders() }
      .mediaCardNewFolderAlert(cardMenu)
      .handleError(state: $errorHandler.state)
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
                      onRetry: { catalog.refresh() })
    } else if catalog.items.isEmpty {
      UnavailableView(title: "No Results", systemImage: "rectangle.stack")
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
        pagination: catalog.paginationState,
        onRetryPagination: { catalog.retryPagination() }
      )
    }
  }

  static func make(filter: LibraryFilter,
                   title: String,
                   context: AppContextProtocol,
                   authState: AuthState,
                   errorHandler: ErrorHandler) -> FilteredShelfView {
    FilteredShelfView(
      title: title,
      catalog: FilteredShelfCatalog(filter: filter,
                                    itemsService: context.contentService,
                                    errorHandler: errorHandler))
  }
}

@MainActor
final class FilteredShelfCatalog: ObservableObject {
  @Published var items: [MediaItem] = []
  @Published private(set) var isLoading = false
  @Published private(set) var loadFailed = false
  @Published private(set) var loadError: Error?
  @Published private(set) var paginationFailed = false
  @Published private(set) var isLoadingMore = false
  @Published var pagination: Pagination?

  private let filter: LibraryFilter
  private let itemsService: VideoContentService
  private let errorHandler: ErrorHandler
  private let perPage: Int
  private var isFetching = false

  var paginationState: PaginationState {
    if isLoadingMore { return PaginationState(phase: .loading, loadedCount: items.count) }
    if paginationFailed { return PaginationState(phase: .failed, loadedCount: items.count) }
    guard let pagination, pagination.current >= pagination.total else { return .idle }
    return PaginationState(phase: .complete, loadedCount: items.count)
  }

  init(filter: LibraryFilter, itemsService: VideoContentService, errorHandler: ErrorHandler) {
    self.filter = filter
    self.itemsService = itemsService
    self.errorHandler = errorHandler
    self.perPage = CatalogPageSize.grid
  }

  func fetchItems() async {
    let isFirstPage = pagination == nil
    if !isFirstPage {
      guard !isFetching else { return }
    }
    isFetching = true
    defer { isFetching = false }
    isLoadingMore = !isFirstPage
    defer { isLoadingMore = false }
    if isFirstPage { isLoading = true }
    defer { isLoading = false }

    do {
      let page = isFirstPage ? nil : pagination!.current + 1
      let data = try await itemsService.fetchItems(filter: filter, page: page, perPage: perPage)
      if isFirstPage {
        items = data.items
      } else {
        items.append(contentsOf: data.items)
      }
      pagination = data.pagination
      loadFailed = false
      loadError = nil
      paginationFailed = false
    } catch {
      if isFirstPage {
        loadFailed = true
        loadError = error
      } else {
        paginationFailed = true
        errorHandler.setError(error)
      }
    }
  }

  func loadMoreContent(after item: MediaItem) {
    guard let pagination,
          CatalogLoadMore.isThresholdItem(item, in: items),
          pagination.current <= pagination.total else { return }
    Task { await fetchItems() }
  }

  func retryPagination() {
    paginationFailed = false
    Task { await fetchItems() }
  }

  func refresh() {
    items = []
    pagination = nil
    loadFailed = false
    loadError = nil
    paginationFailed = false
    Task { await fetchItems() }
  }
}

/// Continue Watching past the sideways cap: the same ranking, on its own page.
struct ContinueWatchingListView: View {
  @Environment(NavigationState.self) var navigationState
  @Environment(ErrorHandler.self) var errorHandler
  @Environment(\.openURL) private var openURL
  @StateObject private var catalog: HomeCatalog
  @StateObject private var cardMenu = MediaCardMenuCoordinator()
  @State private var cards: [MediaCard] = []
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var loadError: Error?

  init(catalog: @autoclosure @escaping () -> HomeCatalog) {
    _catalog = StateObject(wrappedValue: catalog())
  }

  var body: some View {
    content
      .platformNavigationTitle("Continue Watching")
      .background(Color.KinoPub.background)
      .task {
        cardMenu.bind(errorHandler: errorHandler)
        await load()
      }
      .task { await cardMenu.refreshFolders() }
      .mediaCardNewFolderAlert(cardMenu)
  }

  @ViewBuilder
  private var content: some View {
    if cards.isEmpty && isLoading {
      LoadingIndicatorView()
    } else if cards.isEmpty && loadFailed {
      UnavailableView(title: "Couldn't Load",
                      systemImage: "wifi.exclamationmark",
                      message: loadError?.userFacingMessage ?? "Check your connection and try again.".localized,
                      retryTitle: "Try Again",
                      onRetry: { Task { await load() } })
    } else if cards.isEmpty {
      UnavailableView(title: "No Results", systemImage: "rectangle.stack")
    } else {
      MediaCardsListView(
        cards: cards,
        onLoadMoreContent: { _ in },
        navigationLinkProvider: { card in
          Route.detailsById(card.id)
        },
        contextMenuProvider: { card in
          MediaCardContextMenus.entries(
            for: card,
            surface: .shelf,
            menu: cardMenu,
            pushRoute: { navigationState.push($0) },
            openURL: { openURL($0) },
            isContinueWatchingStyle: true,
            includePlay: true
          )
        }
      )
    }
  }

  private func load() async {
    isLoading = cards.isEmpty
    do {
      cards = try await catalog.expandedContinueWatching()
      loadFailed = false
      loadError = nil
      isLoading = false
    } catch {
      loadError = error
      loadFailed = cards.isEmpty
      isLoading = false
    }
  }

  static func make(context: AppContextProtocol,
                   authState: AuthState,
                   errorHandler: ErrorHandler) -> ContinueWatchingListView {
    ContinueWatchingListView(
      catalog: HomeCatalog(itemsService: context.contentService,
                           authState: authState,
                           errorHandler: errorHandler,
                           watchesHome: false))
  }
}
