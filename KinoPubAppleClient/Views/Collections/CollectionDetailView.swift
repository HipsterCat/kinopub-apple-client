//
//  CollectionDetailView.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubUI
import KinoPubBackend

/// The grid behind one collection shelf's title / "+N more" — every item the
/// collection has, no pagination (the endpoint returns them all at once).
struct CollectionDetailView: View {
  @Environment(NavigationState.self) var navigationState
  @Environment(ErrorHandler.self) var errorHandler
  @Environment(\.openURL) private var openURL
  @StateObject private var model: CollectionDetailModel
  @StateObject private var cardMenu = MediaCardMenuCoordinator()

  init(model: @autoclosure @escaping () -> CollectionDetailModel) {
    _model = StateObject(wrappedValue: model())
  }

  var body: some View {
    @Bindable var errorHandler = errorHandler
    content
      .platformNavigationTitle(model.title)
      .background(Color.KinoPub.background)
      .task {
        cardMenu.bind(errorHandler: errorHandler)
        await model.fetch()
      }
      .task { await cardMenu.refreshFolders() }
      .mediaCardNewFolderAlert(cardMenu)
      .handleError(state: $errorHandler.state)
  }

  @ViewBuilder
  private var content: some View {
#if os(tvOS)
    // The search results catalog: `TVSearchFilters` chips and the 6-column poster
    // grid, in the one `TVPage` collection search uses. Picks apply on the device.
    tvCatalog
      .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
#else
    if model.items.isEmpty && model.isLoading {
      LoadingIndicatorView()
    } else if model.items.isEmpty && model.loadFailed {
      UnavailableView(title: "Couldn't Load",
                      systemImage: "wifi.exclamationmark",
                      message: model.loadError?.userFacingMessage ?? "Check your connection and try again.".localized,
                      retryTitle: "Try Again",
                      onRetry: {
        Task { await model.fetch() }
      })
    } else if model.items.isEmpty && model.filter.hasActiveFilters {
      VStack(alignment: .leading, spacing: 0) {
        filterBar
        UnavailableView(title: "Nothing Matches These Filters", systemImage: "line.3.horizontal.decrease")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    } else if model.items.isEmpty {
      UnavailableView(title: "No Results", systemImage: "rectangle.stack")
    } else {
      ContentItemsListView(
        items: $model.items,
        onLoadMoreContent: { _ in },
        navigationLinkProvider: { item in Route.details(item) },
        contextMenuProvider: { item in
          MediaCardContextMenus.entries(
            for: item,
            menu: cardMenu,
            pushRoute: { navigationState.push($0) },
            openURL: { openURL($0) }
          )
        }
      ) {
        filterBar
      }
    }
#endif
  }

#if os(tvOS)
  private var tvCatalog: some View {
    TVPage(
      sections: tvSections,
      status: tvStatus,
      accessibilityID: "kinopub.page.collection",
      onSelect: { _, item in
        guard let card = item.card,
              let media = model.items.first(where: { $0.id == card.itemID })
                ?? model.allItems.first(where: { $0.id == card.itemID }) else { return }
        navigationState.push(.details(media))
      },
      onChipOption: { chip, option in
        TVSearchFilters.apply(chip: chip, option: option, to: model)
      },
      onChipSelection: { chip, selection in
        TVSearchFilters.applySelection(chip: chip, selection: selection, to: model)
      },
      contextMenuProvider: { card in
        MediaCardContextMenus.entries(
          for: card,
          surface: .shelf,
          menu: cardMenu,
          pushRoute: { navigationState.push($0) },
          openURL: { openURL($0) }
        )
      },
      onRetry: { Task { await model.fetch() } }
    )
  }

  /// Filters first, then the same untitled poster grid search shows while browsing.
  private var tvSections: [TVPageSection] {
    let filters = TVSearchFilters.row(catalog: model, searching: false)
    if model.allItems.isEmpty && model.isLoading {
      return [filters, .placeholder(id: "collection", title: nil, kind: .poster, columns: 6, flow: .grid)]
    }
    let cards = model.items.map { MediaCard($0) }
    guard !cards.isEmpty else { return [filters] }
    return [filters, .posters(id: "collection", title: nil, flow: .grid, caption: .always, cards: cards)]
  }

  private var tvStatus: TVPageStatus {
    if model.items.isEmpty && model.loadFailed && model.allItems.isEmpty {
      return .failed(message: model.loadError?.userFacingMessage
                       ?? "Check your connection and try again.".localized,
                     retryTitle: "Try Again".localized)
    }
    if model.items.isEmpty && !model.isLoading {
      return .message((model.filter.hasActiveFilters
                       ? "Nothing Matches These Filters"
                       : "No Results").localized)
    }
    return .content
  }
#else
  /// The search catalog's filter controls over the collection's items — applied on
  /// the device, since `/v1/collections/view` takes no parameters.
  private var filterBar: some View {
    LibraryFiltersBar(catalog: model)
  }
#endif

  static func make(collection: Collection,
                   context: AppContextProtocol,
                   errorHandler: ErrorHandler) -> CollectionDetailView {
    CollectionDetailView(model: CollectionDetailModel(collection: collection,
                                                       collectionsService: context.collectionsService,
                                                       errorHandler: errorHandler))
  }
}

struct CollectionDetailView_Previews: PreviewProvider {
  static var previews: some View {
    NavigationStack {
      CollectionDetailView(model: CollectionDetailModel(collection: .mock(id: 1, title: "Mock Collection"),
                                                         collectionsService: CollectionsServiceMock(),
                                                         errorHandler: ErrorHandler()))
    }
  }
}
