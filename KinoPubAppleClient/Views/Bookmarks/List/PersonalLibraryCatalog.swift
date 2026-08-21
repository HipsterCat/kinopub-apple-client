//
//  PersonalLibraryCatalog.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend
import KinoPubUI
import OSLog
import KinoPubLogging
import Combine

/// Watchlist serials + unfinished movies + recently watched as rows — the Watching
/// tab. Bookmark folders live on the Bookmarks tab (`BookmarksCatalog`).
@MainActor
class PersonalLibraryCatalog: ObservableObject {

  private var authState: AuthState
  private var contentService: VideoContentService
  private var errorHandler: ErrorHandler
  private var store: ContentStore
  private var bag = Set<AnyCancellable>()

  @Published public private(set) var rows: [MediaRow] = []
  @Published public private(set) var isLoaded: Bool = false
  /// True when nothing could be loaded and there's no cache to show — the view swaps
  /// the blank screen for a retry state. Cached rows always win over this flag.
  @Published public private(set) var loadFailed: Bool = false
  /// The failure behind `loadFailed`, so the retry state can say what actually went wrong.
  @Published public private(set) var loadError: Error?

  init(itemsService: VideoContentService,
       authState: AuthState,
       errorHandler: ErrorHandler,
       store: ContentStore = AppContext.shared.contentStore) {
    self.contentService = itemsService
    self.authState = authState
    self.errorHandler = errorHandler
    self.store = store
  }

  func fetch() async {
    guard authState.userState == .authorized else {
      subscribeForAuth()
      return
    }

    assembleRows()
    isLoaded = !rows.isEmpty

    await withTaskGroup(of: Void.self) { group in
      group.addTask { [store] in
        await store.refreshIfStale(.watchlist) { [weak self] in
          guard let self else { throw CancellationError() }
          return try await self.fetchWatchlistCards()
        }
      }
      group.addTask { [store] in
        await store.refreshIfStale(.watchingMovies) { [weak self] in
          guard let self else { throw CancellationError() }
          return try await self.fetchWatchingMovieCards()
        }
      }
      group.addTask { [store] in
        await store.refreshIfStale(.history) { [weak self] in
          guard let self else { throw CancellationError() }
          return try await self.fetchHistoryCards()
        }
      }
    }

    assembleRows()
    isLoaded = true
    let firstError = [self.store.lastError(.watchlist),
                      self.store.lastError(.watchingMovies),
                      self.store.lastError(.history)].lazy
      .compactMap { $0 }
      .first
    loadFailed = rows.isEmpty && firstError != nil
    loadError = rows.isEmpty ? firstError : nil
  }

  /// Pull-to-refresh: forces every row to refetch regardless of TTL.
  @Sendable @MainActor
  func refresh() async {
    errorHandler.reset()
    loadFailed = false
    loadError = nil
    store.invalidate(family: .watch)
    await fetch()
  }

  private func assembleRows() {
    var assembled: [MediaRow] = []

    let watchlistCards = store.cards(.watchlist)
    if !watchlistCards.isEmpty {
      assembled.append(MediaRow(id: "watchlist",
                                title: "Watchlist".localized,
                                count: "\(watchlistCards.count)",
                                cards: watchlistCards))
    }

    let watchingMovieCards = store.cards(.watchingMovies)
    if !watchingMovieCards.isEmpty {
      assembled.append(MediaRow(id: "watchingMovies",
                                title: "Movies".localized,
                                count: "\(watchingMovieCards.count)",
                                cards: watchingMovieCards))
    }

    let historyCards = store.cards(.history)
    if !historyCards.isEmpty {
      assembled.append(MediaRow(id: "history",
                                title: "Recently Watched".localized,
                                count: "\(historyCards.count)",
                                cards: historyCards))
    }

    rows = assembled
  }

  private func fetchWatchlistCards() async throws -> [MediaCard] {
    let items = try await contentService.fetchWatchingSerials(subscribedOnly: true).items
    return items.map { Self.card(for: $0, isSeries: true) }
  }

  private func fetchWatchingMovieCards() async throws -> [MediaCard] {
    let items = try await contentService.fetchWatchingMovies().items
    return items.map { Self.card(for: $0, isSeries: false) }
  }

  private func fetchHistoryCards() async throws -> [MediaCard] {
    let history = try await contentService.fetchHistory(page: nil, perPage: 20).history
    // Always collapsed here: this is a preview shelf, and twenty cards of the same
    // series in a row would crowd out every other title the user has watched.
    return HistoryView.cards(from: history, grouping: .byShow)
  }

  /// `/v1/watching/*` sends only enough to draw a card. Serials carry episode counts
  /// (progress + "+N new"); films carry neither.
  private static func card(for item: WatchingItem, isSeries: Bool) -> MediaCard {
    MediaCard(id: item.id,
              posterURL: item.posters.medium,
              title: item.localizedTitle,
              subtitle: item.originalTitle,
              progress: isSeries ? item.progress : nil,
              badge: item.hasNewEpisodes ? "+\(item.new ?? 0)" : nil,
              backdropURL: item.posters.wideURL ?? item.posters.big,
              isSeries: isSeries,
              isInWatchlist: isSeries)
  }

  private func subscribeForAuth() {
    authState.$userState.filter({ $0 == .authorized }).first().sink { [weak self] _ in
      Task { await self?.fetch() }
    }.store(in: &bag)
  }
}
