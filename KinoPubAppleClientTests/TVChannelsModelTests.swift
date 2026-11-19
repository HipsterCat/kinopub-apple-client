//
//  TVChannelsModelTests.swift
//  KinoPubAppleClientTests
//

import XCTest
import KinoPubBackend
import KinoPubUI
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
    let tile = TVChannelsView.tile(for: Self.channel(1), onAir: model.nowPlaying(channelID: 1, at: now))
    XCTAssertEqual(tile.title, "Now")
    XCTAssertEqual(tile.focusedTitle, "Channel 1")
    XCTAssertEqual(tile.subtitle, "Now")
    XCTAssertTrue(tile.subtitleOnFocus)
#endif
  }

  /// The tab opens on the whole baked grid, in the order the loaded list uses:
  /// Latin titles first, the Russian block at the bottom. No stream yet.
  func testOpensOnTheBakedGrid() {
    let model = TVChannelsModel(contentService: VideoContentServiceMock())
    XCTAssertEqual(model.channels.count, 51)
    XCTAssertEqual(model.channels.first?.title, "CBS Sports")
    XCTAssertEqual(model.channels.last?.title, "Футбол ТВ")
    XCTAssertEqual(model.channels.map(\.title).firstIndex(of: "Бокс ТВ"),
                   model.channels.map(\.title).firstIndex(of: "Беларусь 5").map { $0 + 2 })
    XCTAssertTrue(model.channels.allSatisfy { $0.stream.isEmpty && $0.logo != nil })
    XCTAssertFalse(model.isLoading)
  }

  /// A few sports channels ship logos in the asset catalog; the rest stay on the CDN URL.
  func testBundledLogosUseFullCards() {
    XCTAssertEqual(TVChannelCatalog.bundledLogo(for: 80), .full("cbs-sports"))
    XCTAssertEqual(TVChannelCatalog.bundledLogo(for: 27), .full("espn"))
    XCTAssertEqual(TVChannelCatalog.bundledLogo(for: 145), .full("eleven-sports"))
    XCTAssertNil(TVChannelCatalog.bundledLogo(for: 1), "МАТЧ! ТВ stays on the CDN")
#if os(tvOS)
    let cbs = TVChannelCatalog.channels.first { $0.id == 80 }!
    let match = TVChannelCatalog.channels.first { $0.id == 1 }!
    XCTAssertEqual(TVChannelsView.logo(for: cbs), .bundled("cbs-sports"))
    XCTAssertEqual(TVChannelsView.logo(for: match),
                   .remote(URL(string: "https://m.staticpop.net/channels/150x150/match_new.png")!))
    // Mark+focus-BG remains a supported logo kind even though no channel uses it now.
    XCTAssertEqual(TVPageLogo.bundledMark(logo: "cbs-sports_logo",
                                          focusBackground: "cbs-sports_bg"),
                   .bundledMark(logo: "cbs-sports_logo", focusBackground: "cbs-sports_bg"))
#endif
  }

#if os(tvOS)
  /// Unfocused caption is the programme; focused caption returns to the channel name.
  func testChannelTileShowsProgramWhenUnfocused() {
    let channel = TVChannel(id: 27, title: "ESPN 1",
                            logo: "https://example/espn.png", stream: "https://example/live.m3u8")
    let onAir = EPGProgram(title: "LIVE: COLLEGE BASKETBALL",
                           start: Date().addingTimeInterval(-600),
                           stop: Date().addingTimeInterval(600))
    let withProgram = TVChannelsView.tile(for: channel, onAir: onAir)
    XCTAssertEqual(withProgram.title, "LIVE: COLLEGE BASKETBALL")
    XCTAssertEqual(withProgram.focusedTitle, "ESPN 1")
    XCTAssertEqual(withProgram.subtitle, "LIVE: COLLEGE BASKETBALL")
    XCTAssertTrue(withProgram.subtitleOnFocus)

    let idle = TVChannelsView.tile(for: channel, onAir: nil)
    XCTAssertEqual(idle.title, "ESPN 1")
    XCTAssertNil(idle.focusedTitle)
    XCTAssertNil(idle.subtitle)
    XCTAssertFalse(idle.subtitleOnFocus)
  }
#endif

  /// The guide is asked for the channels already on screen, alongside `/v1/tv`.
  func testGuideUsesTheChannelsAlreadyShown() async {
    let asked = Streams()
    let shown = TVChannel(id: 7, title: "Матч! Футбол 3", stream: "")
    let now = Date()
    let model = TVChannelsModel(
      contentService: VideoContentServiceMock(tvChannels: {
        [TVChannel(id: 7, title: "Матч! Футбол 3", stream: "https://cdn.example/7.m3u8")]
      }),
      epgService: EPGServiceMock { channels in
        asked.record(channels.map(\.stream))
        return [7: [EPGProgram(title: "Now", start: now.addingTimeInterval(-600),
                               stop: now.addingTimeInterval(600))]]
      },
      initialChannels: [shown])
    await model.fetch()
    XCTAssertEqual(asked.value, [[""]])
    XCTAssertEqual(model.channels.first?.stream, "https://cdn.example/7.m3u8")
    XCTAssertEqual(model.nowPlaying(channelID: 7, at: now)?.title, "Now")
  }

  /// The same channels in another order stay in the baked order, so the grid
  /// does not reshuffle when the list arrives.
  func testServerListKeepsTheBakedOrder() async {
    let reversed = TVChannelCatalog.channels.reversed().map {
      TVChannel(id: $0.id, title: $0.title, logo: $0.logo, stream: "https://cdn.example/\($0.id).m3u8")
    }
    let model = TVChannelsModel(contentService: VideoContentServiceMock(tvChannels: { reversed }),
                                initialChannels: TVChannelCatalog.channels)
    await model.fetch()
    XCTAssertEqual(model.channels.map(\.id), TVChannelCatalog.channels.map(\.id))
    XCTAssertEqual(model.channels.first?.stream, "https://cdn.example/80.m3u8")
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

private final class Streams: @unchecked Sendable {
  private let lock = NSLock()
  private var calls: [[String]] = []
  var value: [[String]] { lock.withLock { calls } }
  func record(_ streams: [String]) { lock.withLock { calls.append(streams) } }
}
