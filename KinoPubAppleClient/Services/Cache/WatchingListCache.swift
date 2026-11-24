//
//  WatchingListCache.swift
//  KinoPubAppleClient
//
//  One in-memory cache for the three watching-list GETs that Continue Watching,
// Library Unwatched / Following, and the sidebar badge all used to fire separately.
//
//  TTL is short (a few minutes) so concurrent surfaces share one answer; mutations
// and the end of playback clear it. Progress ticks while the player is active must
// not clear or refresh this — that was the #110 flood.
//

import Foundation
import KinoPubBackend
import Observation

@MainActor
@Observable
final class WatchingListCache {
  static let shared = WatchingListCache()

  /// How long a successful list is reused across CW / Library / sidebar.
  static let ttl: TimeInterval = 3 * 60

  /// Episodes still unwatched across the followed serials (`unwatchedEpisodeTotal`) of
  /// the last followed list stored — the «Новые серии» tab badge and the page's subtitle,
  /// one number from one list. Observed, so both repaint the moment a fetch lands.
  ///
  /// Before 2026-11-24 the badge was the root view's own `@State`, fetched at sign-in and
  /// on a tab switch at most every two minutes: following «12 12 12» and «Reggie Dinkins»
  /// left it at Dexter's 2 while the page under it said 4 (Sasha). `invalidate` keeps it
  /// (the badge does not blink to nothing while the list refetches); `clear` drops it.
  private(set) var followedEpisodeTotal: Int?
  /// Bumped when a fetched followed list differs from the one stored before — pages
  /// showing that list reload from it (no extra request: the cache is warm).
  private(set) var followedListRevision = 0
  @ObservationIgnored private var lastFollowed: [WatchingItem]?

  enum List: Hashable, Sendable {
    case movies
    case serials(subscribed: Bool)
  }

  private struct Entry {
    let items: [WatchingItem]
    let fetchedAt: Date
  }

  /// Told the ids on every followed-serials list fetched from the network, with when the
  /// request left — the app reconciles its local follow marks with them
  /// (`MediaLibraryStore.reconcileWatchlist`). Unset in unit tests and fixture runs.
  @ObservationIgnored var onFollowedSerialsFetched: (([Int], Date) -> Void)?

  @ObservationIgnored private var entries: [List: Entry] = [:]
  /// Continuations waiting on an in-flight fetch for the same list (no `Task` — keeps
  /// non-Sendable `WatchingItem` on the main actor).
  @ObservationIgnored private var waiters: [List: [CheckedContinuation<[WatchingItem], Error>]] = [:]
  @ObservationIgnored private var fetching: Set<List> = []
  /// Bumped on `invalidate` so a fetch that started before the clear cannot write back.
  @ObservationIgnored private var generation = 0

  /// Fresh cached items, or `nil` when missing / past TTL.
  func cached(_ list: List, now: Date = Date()) -> [WatchingItem]? {
    guard let entry = entries[list],
          now.timeIntervalSince(entry.fetchedAt) <= Self.ttl else { return nil }
    return entry.items
  }

  /// One title from a warm watching list — for painting `unwatchedEpisodes` on any
  /// cover that is already known to be followed. Never fetches.
  func cachedItem(id: Int, subscribed: Bool, now: Date = Date()) -> WatchingItem? {
    cached(.serials(subscribed: subscribed), now: now)?.first { $0.id == id }
  }

  /// A title page about to paint from an older copy of the title (the last details this
  /// session or a resume point kept): when a warm watching list counts a different number
  /// of episodes, that copy's seasons are stale — «12 12 12» painted «2 episodes» and
  /// «Replay E1» from the copy kept before episode 3 came out, then swapped to «Play E3»
  /// under the focused button (Sasha, 2026-11-21). The seasons go; the page paints as a
  /// series whose episodes are still coming, and the details fill them in. Never fetches.
  func reconciled(_ item: MediaItem) -> MediaItem {
    guard let listed = cachedItem(id: item.id, subscribed: true) ?? cachedItem(id: item.id, subscribed: false),
          let total = listed.total, total > 0,
          let seasons = item.seasons, !seasons.isEmpty else { return item }
    let known = seasons.reduce(0) { $0 + $1.episodes.count }
    guard known != total else { return item }
    var fresh = item
    fresh.seasons = nil
    return fresh
  }

  func movies(using service: VideoContentService, force: Bool = false) async throws -> [WatchingItem] {
    try await items(.movies, using: service, force: force)
  }

  func serials(subscribedOnly: Bool,
               using service: VideoContentService,
               force: Bool = false) async throws -> [WatchingItem] {
    try await items(.serials(subscribed: subscribedOnly), using: service, force: force)
  }

  func items(_ list: List,
             using service: VideoContentService,
             force: Bool = false) async throws -> [WatchingItem] {
    if !force, let hit = cached(list) { return hit }

    if fetching.contains(list) {
      return try await withCheckedThrowingContinuation { cont in
        waiters[list, default: []].append(cont)
      }
    }

    fetching.insert(list)
    let gen = generation
    let requestedAt = Date()
    do {
      let items: [WatchingItem]
      switch list {
      case .movies:
        items = try await service.fetchWatchingMovies().items
      case .serials(let subscribed):
        items = try await service.fetchWatchingSerials(subscribedOnly: subscribed).items
      }
      // Only the generation that owns `fetching` may clear it — a stale fetch finishing
      // after `invalidate` must not wipe a newer in-flight marker (#123 review nit).
      guard generation == gen else { return items }
      fetching.remove(list)
      entries[list] = Entry(items: items, fetchedAt: Date())
      if list == .serials(subscribed: true) {
        onFollowedSerialsFetched?(items.map(\.id), requestedAt)
        storeFollowed(items)
      }
      let pending = waiters.removeValue(forKey: list) ?? []
      for waiter in pending { waiter.resume(returning: items) }
      return items
    } catch {
      guard generation == gen else { throw error }
      fetching.remove(list)
      let pending = waiters.removeValue(forKey: list) ?? []
      for waiter in pending { waiter.resume(throwing: error) }
      throw error
    }
  }

  /// Drop every list. Next caller refetches. Cancels waiters coalesced on an in-flight
  /// fetch so they do not receive a stale answer from a request that started earlier
  /// (e.g. Home warming the shared cache before a unit test clears it).
  func invalidate() {
    generation += 1
    entries.removeAll()
    fetching.removeAll()
    let pending = waiters
    waiters.removeAll()
    for (_, waiters) in pending {
      for waiter in waiters { waiter.resume(throwing: CancellationError()) }
    }
  }

  /// Fetch the followed list again now — after a follow or unfollow, so the badge and
  /// «Новые серии» show the change without waiting for a tab switch or a relaunch.
  /// Errors keep the last total.
  func refreshFollowed(using service: VideoContentService) async {
    _ = try? await serials(subscribedOnly: true, using: service, force: true)
  }

  private func storeFollowed(_ items: [WatchingItem]) {
    let total = items.unwatchedEpisodeTotal
    if followedEpisodeTotal != total { followedEpisodeTotal = total }
    if lastFollowed != items {
      lastFollowed = items
      followedListRevision += 1
    }
  }

  /// Account switch: drop the lists and the badge's number with them.
  func clear() {
    invalidate()
    followedEpisodeTotal = nil
    lastFollowed = nil
    followedListRevision += 1
  }
}
