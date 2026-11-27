//
//  TVChannelsModel.swift
//  Piratic
//

import Foundation
import KinoPubBackend
import PiraticLogging
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
  /// Disk file for the last successful `/v1/tv` answer. Injectable so unit tests use a
  /// temp path and cannot pollute the app container's Caches (review on #123).
  private let diskCacheURL: URL?
  private var fetchedAt: Date?
  /// Bumps when a newer `fetch` starts, so a guide asked for the previous list cannot
  /// land on top of the one this fetch is waiting for.
  private var fetchGeneration = UUID()
  /// How long a successful `/v1/tv` answer is reused before the next network fetch.
  static let freshness: TimeInterval = 60 * 60

  init(contentService: VideoContentService,
       epgService: EPGService = EPGServiceImpl.shared,
       initialChannels: [TVChannel] = TVChannelCatalog.channels,
       diskCacheURL: URL? = TVChannelsModel.defaultDiskCacheURL) {
    self.contentService = contentService
    self.epgService = epgService
    self.diskCacheURL = diskCacheURL
    self.channels = initialChannels
    self.isLoading = initialChannels.isEmpty
  }

  /// Default on-disk path under Caches. Tests pass a temp file instead.
  static var defaultDiskCacheURL: URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("TVChannels", isDirectory: true)
      .appendingPathComponent("v1-tv.json")
  }

  /// Tab entry: reuse a fresh list (memory, then disk); only hit `/v1/tv` when the TTL
  /// has expired. The guide still runs — it has its own cache.
  func load(now: Date = Date()) async {
    if let fetchedAt, now.timeIntervalSince(fetchedAt) <= Self.freshness {
      await refreshGuide(for: channels)
      return
    }
    if let cached = loadDiskCache(),
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
      let fetched = try await contentService.fetchTVChannels().filter { !$0.stream.isEmpty }
      let playable = TVChannelCatalog.matching(fetched) ?? fetched
      guard fetchGeneration == generation else { return }
      let sameIDs = playable.map(\.id) == shown.map(\.id)
      channels = playable
      loadError = nil
      let stamped = Date()
      fetchedAt = stamped
      isLoading = false
      if !playable.isEmpty {
        saveDiskCache(channels: playable, fetchedAt: stamped)
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

  private func loadDiskCache() -> CachedList? {
    guard let url = diskCacheURL, let data = try? Data(contentsOf: url),
          let cached = try? JSONDecoder().decode(CachedList.self, from: data),
          !cached.channels.isEmpty else { return nil }
    // Older XCTest runs wrote `cdn.example` into the shared app Caches. Tests now
    // inject a temp URL; drop only the default path when it still has those hosts.
    if url == Self.defaultDiskCacheURL,
       cached.channels.contains(where: { Self.isLegacyFixtureHost($0.stream) }) {
      try? FileManager.default.removeItem(at: url)
      return nil
    }
    return cached
  }

  private func saveDiskCache(channels: [TVChannel], fetchedAt: Date) {
    guard let url = diskCacheURL else { return }
    let directory = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let payload = CachedList(fetchedAt: fetchedAt, channels: channels)
    guard let data = try? JSONEncoder().encode(payload) else { return }
    try? data.write(to: url, options: .atomic)
  }

  /// Hosts that older unit tests wrote into the shared simulator Caches. Not a Select
  /// denylist — only used to discard a polluted default on-disk file once.
  private static func isLegacyFixtureHost(_ stream: String) -> Bool {
    guard let host = URL(string: stream)?.host?.lowercased() else { return false }
    return host == "cdn.example" || host.hasSuffix(".example") || host.hasSuffix(".invalid")
  }
}
