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

@MainActor
final class WatchingListCache {
  static let shared = WatchingListCache()

  /// How long a successful list is reused across CW / Library / sidebar.
  static let ttl: TimeInterval = 3 * 60

  enum List: Hashable, Sendable {
    case movies
    case serials(subscribed: Bool)
  }

  private struct Entry {
    let items: [WatchingItem]
    let fetchedAt: Date
  }

  private var entries: [List: Entry] = [:]
  private var inFlight: [List: Task<[WatchingItem], Error>] = [:]
  /// Bumped on `invalidate` so a fetch that started before the clear cannot write back.
  private var generation = 0

  /// Fresh cached items, or `nil` when missing / past TTL.
  func cached(_ list: List, now: Date = Date()) -> [WatchingItem]? {
    guard let entry = entries[list],
          now.timeIntervalSince(entry.fetchedAt) <= Self.ttl else { return nil }
    return entry.items
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

    if let existing = inFlight[list] {
      return try await existing.value
    }

    let gen = generation
    let task = Task { () throws -> [WatchingItem] in
      switch list {
      case .movies:
        return try await service.fetchWatchingMovies().items
      case .serials(let subscribed):
        return try await service.fetchWatchingSerials(subscribedOnly: subscribed).items
      }
    }
    inFlight[list] = task
    do {
      let items = try await task.value
      inFlight[list] = nil
      if generation == gen {
        entries[list] = Entry(items: items, fetchedAt: Date())
      }
      return items
    } catch {
      inFlight[list] = nil
      throw error
    }
  }

  /// Drop every list. Next caller refetches. In-flight work may still finish but
  /// will not be cached (generation mismatch).
  func invalidate() {
    generation += 1
    entries.removeAll()
  }

  func clear() {
    invalidate()
  }
}
