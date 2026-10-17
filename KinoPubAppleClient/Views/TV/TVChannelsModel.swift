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
/// A channel's stream link carries a token, so the list is fetched again when the tab
/// comes back after a while (`refreshIfStale`) rather than once per launch: Select plays
/// the link the latest answer gave.
@MainActor
final class TVChannelsModel: ObservableObject {

  @Published private(set) var channels: [TVChannel] = []
  @Published private(set) var isLoading = true
  @Published private(set) var loadError: Error?
  /// Each channel's schedule, by channel id — filled after the list, never blocking it.
  @Published private(set) var schedules: [Int: [EPGProgram]] = [:]

  private let contentService: VideoContentService
  private let epgService: EPGService
  private var fetchedAt: Date?
  /// How old the list may get before coming back to the tab fetches it again.
  static let freshness: TimeInterval = 5 * 60

  init(contentService: VideoContentService, epgService: EPGService = EPGServiceImpl.shared) {
    self.contentService = contentService
    self.epgService = epgService
  }

  func fetch() async {
    isLoading = channels.isEmpty
    do {
      // A channel with no stream cannot be played, so it is not offered.
      channels = try await contentService.fetchTVChannels().filter { !$0.stream.isEmpty }
      loadError = nil
      fetchedAt = Date()
    } catch {
      Logger.app.debug("fetch tv channels error: \(error)")
      // A failed refresh keeps the list it had; only an empty page shows the error.
      if channels.isEmpty { loadError = error }
      isLoading = false
      return
    }
    isLoading = false
    // The guide is a nicety on top of the list: the grid is up before it is asked.
    schedules = await epgService.schedules(for: channels)
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
