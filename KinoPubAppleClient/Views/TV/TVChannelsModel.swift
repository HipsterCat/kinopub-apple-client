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

  private let contentService: VideoContentService
  private var fetchedAt: Date?
  /// How old the list may get before coming back to the tab fetches it again.
  static let freshness: TimeInterval = 5 * 60

  init(contentService: VideoContentService) {
    self.contentService = contentService
  }

  func fetch() async {
    isLoading = channels.isEmpty
    defer { isLoading = false }
    do {
      // A channel with no stream cannot be played, so it is not offered.
      channels = try await contentService.fetchTVChannels().filter { !$0.stream.isEmpty }
      loadError = nil
      fetchedAt = Date()
    } catch {
      Logger.app.debug("fetch tv channels error: \(error)")
      // A failed refresh keeps the list it had; only an empty page shows the error.
      if channels.isEmpty { loadError = error }
    }
  }

  func refreshIfStale(now: Date = Date()) async {
    guard let fetchedAt, now.timeIntervalSince(fetchedAt) > Self.freshness else { return }
    await fetch()
  }

  func channel(id: Int) -> TVChannel? {
    channels.first { $0.id == id }
  }
}
