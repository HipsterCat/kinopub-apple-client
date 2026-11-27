//
//  WatchlistView.swift
//  Piratic
//

import SwiftUI
import PiraticUI
import KinoPubBackend
import PiraticLogging
import OSLog

/// Serials the user is following for new episodes — vertical poster grid.
/// Reads through `ContentStore`, so a warm cache paints instantly and a failed
/// refresh keeps the last known list instead of blanking the tab.
struct WatchlistView: View {
  @Environment(NavigationState.self) var navigationState
  @Environment(ErrorHandler.self) var errorHandler
  @EnvironmentObject var authState: AuthState
  @Environment(\.appContext) var appContext
  @Environment(\.openURL) private var openURL
  @StateObject private var cardMenu = MediaCardMenuCoordinator()

  /// Pushed onto another tab's stack (`Route.watchlist`) rather than a tab of its own:
  /// no stack of its own then.
  var embedded = false

  @State private var cards: [MediaCard] = []
  @State private var isLoaded = false
  @State private var loadFailed = false
  @State private var loadError: Error?

  var body: some View {
    if embedded {
      page
    } else {
      RouteStack(tab: .watchlist, zoom: true) { page }
    }
  }

  private var page: some View {
    @Bindable var errorHandler = errorHandler
    return content
        // «Новые серии» and how many — the same number as the tab's badge, so it is
        // clear where that comes from (Sasha, 2026-10-30).
        .platformNavigationTitle("NewEpisodesTitle".localized)
#if !os(tvOS)
        .navigationSubtitle(newEpisodesSubtitle)
#endif
        .background(Color.Piratic.background)
        // Every poster here is a subscription — a bookmark ribbon would sit on all of
        // them and mean nothing (Sasha, 2026-11-20).
        .environment(\.hidesMediaCardBookmarkSymbol, true)
        .task {
          cardMenu.bind(errorHandler: errorHandler)
          await load()
        }
        .task { await cardMenu.refreshFolders() }
        // A follow, an unfollow or a fresher list fetched anywhere (the badge, Home):
        // repaint from it. The page used to load once per appearance and keep what it had.
        .onChange(of: WatchingListCache.shared.followedListRevision) { _, _ in
          Task { await load() }
        }
        .mediaCardNewFolderAlert(cardMenu)
        .handleError(state: $errorHandler.state)
  }

  @ViewBuilder
  private var content: some View {
    if cards.isEmpty && !isLoaded {
      LoadingIndicatorView()
    } else if cards.isEmpty && loadFailed {
      UnavailableView(loadError: loadError) {
        Task { await load(force: true) }
      }
    } else if cards.isEmpty {
      UnavailableView(title: "No Results", systemImage: "text.append")
    } else {
      MediaCardsListView(
        cards: cards,
        onLoadMoreContent: { _ in },
        navigationLinkProvider: { card in BookmarksRoutes.detailsById(card.id) },
        contextMenuProvider: { card in
          MediaCardContextMenus.entries(
            for: card,
            surface: .shelf,
            menu: cardMenu,
            pushRoute: { navigationState.push($0) },
            openURL: { openURL($0) }
          )
        }
      )
    }
  }

  private func load(force: Bool = false) async {
    let store = appContext.contentStore
    cards = store.cards(.watchlist)
    isLoaded = !cards.isEmpty
    loadFailed = false
    loadError = nil

    let willFetch = force || store.isStale(.watchlist)
    let service = appContext.contentService
    let fetch: @Sendable () async throws -> [RowItem] = {
      let items = try await WatchingListCache.shared.serials(subscribedOnly: true,
                                                            using: service,
                                                            force: force)
      return items.map { RowItem.card(Self.card(for: $0)) }
    }
    if force {
      await store.refresh(.watchlist, fetch: fetch)
    } else {
      await store.refreshIfStale(.watchlist, fetch: fetch)
    }

    cards = store.cards(.watchlist)
    isLoaded = true
    loadFailed = cards.isEmpty && store.lastError(.watchlist) != nil
    loadError = cards.isEmpty ? store.lastError(.watchlist) : nil
    if willFetch, !cards.isEmpty, let error = store.lastError(.watchlist) {
      errorHandler.setError(error)
    }
  }

  /// Episodes still unwatched across the followed serials — the tab badge's number
  /// (`WatchingListCache.followedEpisodeTotal`); before the list is fetched this launch,
  /// what the covers from disk paint, summed.
  private var newEpisodesSubtitle: String {
    let total = Self.newEpisodesTotal(cached: WatchingListCache.shared.followedEpisodeTotal,
                                      cards: cards)
    return total > 0 ? String.localizedStringWithFormat("NewEpisodesCount".localized, total) : ""
  }

  nonisolated static func newEpisodesTotal(cached: Int?, cards: [MediaCard]) -> Int {
    cached ?? cards.compactMap(\.followedUnwatchedEpisodes).reduce(0, +)
  }

  nonisolated static func card(for item: WatchingItem) -> MediaCard {
    let left = item.unwatchedCount.flatMap { $0 > 0 ? $0 : nil }
    return MediaCard(id: item.id,
              posterURL: item.posters.medium,
              title: item.localizedTitle,
              subtitle: item.originalTitle,
              backdropURL: item.posters.wideURL ?? item.posters.big,
              isSeries: true,
              viewerState: ViewerState(isFollowing: true),
              unwatchedEpisodes: left,
              kinopoiskID: item.kinopoisk)
  }
}
