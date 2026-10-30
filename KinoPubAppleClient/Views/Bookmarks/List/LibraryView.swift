//
//  LibraryView.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubUI
import KinoPubBackend

/// Combined Watchlist + History + Bookmarks for tvOS / iOS / iPad.
struct LibraryView: View {
  @Environment(NavigationState.self) var navigationState
  @Environment(ErrorHandler.self) var errorHandler
  @EnvironmentObject var authState: AuthState
  @Environment(\.appContext) var appContext
  @Environment(\.openURL) private var openURL
  @StateObject private var cardMenu = MediaCardMenuCoordinator()

  @StateObject private var catalog: PersonalLibraryCatalog

  /// iPhone: Settings behind a gear in the bar, not a tab of its own.
  private let settings: AnyView?
  @State private var showsSettings = false

  init(catalog: @autoclosure @escaping () -> PersonalLibraryCatalog, settings: AnyView? = nil) {
    _catalog = StateObject(wrappedValue: catalog())
    self.settings = settings
  }

  var body: some View {
    @Bindable var errorHandler = errorHandler
    RouteStack(tab: .library) {
      content
        .platformNavigationTitle("Library")
        .background(Color.KinoPub.background)
#if os(macOS)
        .macToolbarSearch()
#endif
        .task {
          cardMenu.bind(errorHandler: errorHandler)
          await catalog.fetch()
        }
        .task { await cardMenu.refreshFolders() }
        .mediaCardNewFolderAlert(cardMenu)
        .handleError(state: $errorHandler.state)
#if os(iOS)
        .toolbar {
          if settings != nil {
            ToolbarItem(placement: .primaryAction) {
              Button {
                showsSettings = true
              } label: {
                Label("Settings", systemImage: "gear")
              }
            }
          }
        }
        .sheet(isPresented: $showsSettings) {
          settings
        }
#endif
    }
  }

  @ViewBuilder
  private var content: some View {
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
    } else if catalog.rows.isEmpty {
      UnavailableView(title: "No Results", systemImage: "bookmark")
    } else {
      MediaRowsView(
        rows: catalog.rows,
        navigationLinkProvider: { card in BookmarksRoutes.detailsById(card.itemID) },
        contextMenuProvider: { card, surface in
          MediaCardContextMenus.entries(
            for: card,
            surface: surface,
            menu: cardMenu,
            pushRoute: { navigationState.push($0) },
            openURL: { openURL($0) }
          )
        }
      )
    }
  }

}
