//
//  TVChannelsModel.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend
import KinoPubLogging
import OSLog

/// kino.pub's live channels (`GET /v1/tv`) — the whole list in one response, no paging.
///
/// The grid opens on `TVChannelCatalog`: every channel, in title order, with a plate
/// colour and a logo URL, so the first frame is the loaded frame. `/v1/tv` and the
/// guide are asked together; the list replaces the baked one when it arrives (a stream
/// link carries a token), and the guide fills the line under each tile.
///
/// `/v1/tv` is fetched at most once an hour (`freshness`): coming back to the tab reuses
/// the last successful answer (in memory, and on disk under Caches so a relaunch within
/// the hour does not hit the API again). Retry and an expired TTL call `fetch`.
@MainActor
final class TVChannelsModel: ObservableObject {

  @Published private(set) var channels: [TVChannel]
  @Published private(set) var isLoading: Bool
  @Published private(set) var loadError: Error?
  /// Each channel's schedule, by channel id — filled alongside the list, never blocking it.
  @Published private(set) var schedules: [Int: [EPGProgram]] = [:]

  private let contentService: VideoContentService
  private let epgService: EPGService
  private var fetchedAt: Date?
  /// Bumps when a newer `fetch` starts, so a guide asked for the previous list cannot
  /// land on top of the one this fetch is waiting for.
  private var fetchGeneration = UUID()
  /// How long a successful `/v1/tv` answer is reused before the next network fetch.
  static let freshness: TimeInterval = 60 * 60

  init(contentService: VideoContentService,
       epgService: EPGService = EPGServiceImpl.shared,
       initialChannels: [TVChannel] = TVChannelCatalog.channels) {
    self.contentService = contentService
    self.epgService = epgService
    self.channels = initialChannels
    self.isLoading = initialChannels.isEmpty
  }

  /// Tab entry: reuse a fresh list (memory, then disk); only hit `/v1/tv` when the TTL
  /// has expired. The guide still runs — it has its own cache.
  func load(now: Date = Date()) async {
    if let fetchedAt, now.timeIntervalSince(fetchedAt) <= Self.freshness,
       channels.contains(where: { Self.isPlayableStream($0.stream) }) {
      await refreshGuide(for: channels)
      return
    }
    if let cached = Self.loadCache(),
       now.timeIntervalSince(cached.fetchedAt) <= Self.freshness,
       !cached.channels.isEmpty {
      channels = cached.channels
      fetchedAt = cached.fetchedAt
      loadError = nil
      isLoading = false
      await refreshGuide(for: channels)
      return
    }
    await fetch()
  }

  /// A stream URL the player can open — not empty, not a unit-test / fixture host.
  /// XCTest writes `cdn.example` into the shared simulator Caches; loading that into the
  /// app opened a live player that could not fail cleanly (Sasha, 2026-11-20).
  static func isPlayableStream(_ stream: String) -> Bool {
    guard let url = URL(string: stream), let host = url.host, !host.isEmpty else { return false }
    let blocked: Set<String> = ["cdn.example", "cdn.example.com", "example.com", "fixture.invalid",
                                "localhost", "127.0.0.1"]
    if blocked.contains(host) { return false }
    if host.hasSuffix(".example") || host.hasSuffix(".invalid") || host.hasSuffix(".test") {
      return false
    }
    return true
  }

  func fetch() async {
    let shown = channels
    let generation = UUID()
    fetchGeneration = generation
    isLoading = shown.isEmpty

    // The guide does not need the fresh list: it is keyed by channel id, and the grid
    // is already showing `shown`. It runs beside `/v1/tv`, and publishes on its own
    // when the ids on screen are still the ones it was asked for.
    let guideTask = Task { @MainActor [weak self] in
      guard let self else { return }
      let guide = await self.epgService.schedules(for: shown)
      guard self.fetchGeneration == generation else { return }
      self.schedules.merge(guide) { _, new in new }
    }

    do {
      // A channel with no stream cannot be played, so it is not offered. The baked
      // list keeps its order when the server sends that same set.
      let fetched = try await contentService.fetchTVChannels()
        .filter { Self.isPlayableStream($0.stream) }
      let playable = TVChannelCatalog.matching(fetched) ?? fetched
      guard fetchGeneration == generation else { return }
      let sameIDs = playable.map(\.id) == shown.map(\.id)
      channels = playable
      loadError = nil
      let stamped = Date()
      fetchedAt = stamped
      isLoading = false
      // Never persist fixture hosts — unit tests share this Caches folder on the simulator.
      if playable.contains(where: { Self.isPlayableStream($0.stream) }) {
        Self.saveCache(channels: playable, fetchedAt: stamped)
      }
      if sameIDs {
        await guideTask.value
      } else {
        // The baked list and the server disagreed. Drop that guide and ask for this one.
        fetchGeneration = UUID()
        schedules = await epgService.schedules(for: playable)
      }
    } catch {
      Logger.app.debug("fetch tv channels error: \(error)")
      // A failed refresh keeps the list it had; only an empty page shows the error.
      if channels.isEmpty { loadError = error }
      isLoading = false
      if fetchGeneration == generation { await guideTask.value }
    }
  }

  /// What `channel` has on air at `date`, when the guide knows.
  func nowPlaying(channelID: Int, at date: Date) -> EPGProgram? {
    schedules[channelID]?.live(at: date)
  }

  func refreshIfStale(now: Date = Date()) async {
    guard let fetchedAt, now.timeIntervalSince(fetchedAt) > Self.freshness else { return }
    await fetch()
  }

  func channel(id: Int) -> TVChannel? {
    channels.first { $0.id == id }
  }

  // MARK: - Guide-only refresh (list still fresh)

  private func refreshGuide(for channels: [TVChannel]) async {
    let generation = fetchGeneration
    let guide = await epgService.schedules(for: channels)
    guard fetchGeneration == generation else { return }
    schedules.merge(guide) { _, new in new }
  }

  // MARK: - Disk cache (Caches/, same shape as EPG)

  private struct CachedList: Codable {
    let fetchedAt: Date
    let channels: [TVChannel]
  }

  private static var cacheURL: URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("TVChannels", isDirectory: true)
      .appendingPathComponent("v1-tv.json")
  }

  private static func loadCache() -> CachedList? {
    guard let url = cacheURL, let data = try? Data(contentsOf: url),
          let cached = try? JSONDecoder().decode(CachedList.self, from: data) else { return nil }
    let playable = cached.channels.filter { isPlayableStream($0.stream) }
    guard !playable.isEmpty else {
      // Drop a polluted file (e.g. XCTest wrote `cdn.example` into the app container).
      try? FileManager.default.removeItem(at: url)
      return nil
    }
    return CachedList(fetchedAt: cached.fetchedAt, channels: playable)
  }

  private static func saveCache(channels: [TVChannel], fetchedAt: Date) {
    // XCTest shares the app container's Caches with the simulator run — never write there.
    guard NSClassFromString("XCTestCase") == nil else { return }
    guard let url = cacheURL else { return }
    let directory = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let payload = CachedList(fetchedAt: fetchedAt, channels: channels)
    guard let data = try? JSONEncoder().encode(payload) else { return }
    try? data.write(to: url, options: .atomic)
  }
}
