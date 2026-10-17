//
//  TVChannelsModelTests.swift
//  KinoPubAppleClientTests
//

import XCTest
import KinoPubBackend
@testable import KinoPub

@MainActor
final class TVChannelsModelTests: XCTestCase {

  private nonisolated static func channel(_ id: Int, stream: String = "https://cdn.example/live.m3u8") -> TVChannel {
    TVChannel(id: id, title: "Channel \(id)", stream: stream)
  }

  /// A channel with no stream cannot be played, so the grid never offers it.
  func testFetchDropsChannelsWithoutAStream() async {
    let model = TVChannelsModel(contentService: VideoContentServiceMock(tvChannels: {
      [Self.channel(1), Self.channel(2, stream: ""), Self.channel(3)]
    }))
    await model.fetch()
    XCTAssertEqual(model.channels.map(\.id), [1, 3])
    XCTAssertFalse(model.isLoading)
    XCTAssertNil(model.loadError)
    XCTAssertEqual(model.channel(id: 3)?.title, "Channel 3")
    XCTAssertNil(model.channel(id: 2))
  }

  /// Stream links carry a token: coming back to the tab after a while fetches again,
  /// coming back sooner keeps what it has.
  func testRefreshOnlyWhenStale() async {
    let calls = Counter()
    let model = TVChannelsModel(contentService: VideoContentServiceMock(tvChannels: {
      calls.increment()
      return [TVChannel(id: 1, title: "One", stream: "https://cdn.example/1.m3u8")]
    }))
    await model.refreshIfStale()
    XCTAssertEqual(calls.value, 0, "nothing fetched yet is not stale — the first fetch is the page's")
    await model.fetch()
    await model.refreshIfStale(now: Date().addingTimeInterval(60))
    XCTAssertEqual(calls.value, 1)
    await model.refreshIfStale(now: Date().addingTimeInterval(TVChannelsModel.freshness + 1))
    XCTAssertEqual(calls.value, 2)
  }

  /// The guide comes after the list and fills the second line: what is on air now, nothing
  /// for a channel the guide does not carry.
  func testScheduleFillsNowPlaying() async {
    let now = Date()
    let model = TVChannelsModel(
      contentService: VideoContentServiceMock(tvChannels: { [Self.channel(1), Self.channel(2)] }),
      epgService: EPGServiceMock { _ in
        [1: [EPGProgram(title: "Earlier", start: now.addingTimeInterval(-7_200), stop: now.addingTimeInterval(-600)),
             EPGProgram(title: "Now", start: now.addingTimeInterval(-600), stop: now.addingTimeInterval(600))]]
      })
    await model.fetch()
    XCTAssertEqual(model.nowPlaying(channelID: 1, at: now)?.title, "Now")
    XCTAssertNil(model.nowPlaying(channelID: 1, at: now.addingTimeInterval(1_200)), "nothing after the schedule ends")
    XCTAssertNil(model.nowPlaying(channelID: 2, at: now))
#if os(tvOS)
    XCTAssertEqual(TVChannelsView.tile(for: Self.channel(1), onAir: model.nowPlaying(channelID: 1, at: now)).subtitle, "Now")
#endif
  }

  /// Live playback reports nothing, and has no Up Next or episodes: every gate in the
  /// player reads `watchMode == .media`, so `.live` must stay a mode of its own.
  func testLiveIsNotMediaPlayback() {
    XCTAssertNotEqual(WatchMode.live, WatchMode.media)
    let route = Route.livePlayer(Self.channel(7), token: UUID())
    XCTAssertTrue(route.isPlayerRoute)
    XCTAssertNotEqual(route, Route.livePlayer(Self.channel(7), token: UUID()), "a fresh Select is a fresh request")
  }
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  var value: Int { lock.withLock { count } }
  func increment() { lock.withLock { count += 1 } }
}
