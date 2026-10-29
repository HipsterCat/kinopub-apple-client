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
/// link carries a token), and the guide fills the line on the focused tile.
///
/// The list is fetched again when the tab comes back after a while (`refreshIfStale`)
/// rather than once per launch: Select plays the link the latest answer gave.
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
  /// How old the list may get before coming back to the tab fetches it again.
  static let freshness: TimeInterval = 5 * 60

  init(contentService: VideoContentService,
       epgService: EPGService = EPGServiceImpl.shared,
       initialChannels: [TVChannel] = TVChannelCatalog.channels) {
    self.contentService = contentService
    self.epgService = epgService
    self.channels = initialChannels
    self.isLoading = initialChannels.isEmpty
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
      fetchedAt = Date()
      isLoading = false
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
}
