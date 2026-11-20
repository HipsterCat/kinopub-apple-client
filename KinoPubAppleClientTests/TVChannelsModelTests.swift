//
//  TVChannelsModelTests.swift
//  KinoPubAppleClientTests
//

import XCTest
import KinoPubBackend
#if os(tvOS)
import KinoPubUI
#endif
@testable import KinoPub

@MainActor
final class TVChannelsModelTests: XCTestCase {

  private var tempCacheURL: URL!

  override func setUp() async throws {
    try await super.setUp()
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("TVChannelsTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    tempCacheURL = dir.appendingPathComponent("v1-tv.json")
  }

  override func tearDown() async throws {
    if let dir = tempCacheURL?.deletingLastPathComponent() {
      try? FileManager.default.removeItem(at: dir)
    }
    tempCacheURL = nil
    try await super.tearDown()
  }

  private nonisolated static func channel(_ id: Int, stream: String = "https://cdn.example/live.m3u8") -> TVChannel {
    TVChannel(id: id, title: "Channel \(id)", stream: stream)
  }

  private func makeModel(
    tvChannels: @escaping @Sendable () -> [TVChannel] = { [] },
    epgService: EPGService = EPGServiceImpl.shared,
    initialChannels: [TVChannel] = TVChannelCatalog.channels
  ) -> TVChannelsModel {
    TVChannelsModel(
      contentService: VideoContentServiceMock(tvChannels: tvChannels),
      epgService: epgService,
      initialChannels: initialChannels,
      diskCacheURL: tempCacheURL
    )
  }

  /// A channel with no stream cannot be played, so the grid never offers it.
  func testFetchDropsChannelsWithoutAStream() async {
    let model = makeModel(tvChannels: {
      [Self.channel(1), Self.channel(2, stream: ""), Self.channel(3)]
    }, initialChannels: [])
    await model.fetch()
    XCTAssertEqual(model.channels.map(\.id), [1, 3])
    XCTAssertFalse(model.isLoading)
    XCTAssertNil(model.loadError)
    XCTAssertEqual(model.channel(id: 3)?.title, "Channel 3")
    XCTAssertNil(model.channel(id: 2))
  }

  /// Stream links carry a token: coming back to the tab within an hour reuses the list;
  /// after the TTL (or `fetch`) hits the network again.
  func testRefreshOnlyWhenStale() async {
    let calls = Counter()
    let model = makeModel(tvChannels: {
      calls.increment()
      return [TVChannel(id: 1, title: "One", stream: "https://cdn.example/1.m3u8")]
    }, initialChannels: [])
    await model.refreshIfStale()
    XCTAssertEqual(calls.value, 0, "nothing fetched yet is not stale — the first fetch is the page's")
    await model.fetch()
    await model.load(now: Date().addingTimeInterval(60))
    XCTAssertEqual(calls.value, 1, "load within the hour must not hit /v1/tv again")
    await model.refreshIfStale(now: Date().addingTimeInterval(TVChannelsModel.freshness + 1))
    XCTAssertEqual(calls.value, 2)
  }

  func testFreshnessIsOneHour() {
    XCTAssertEqual(TVChannelsModel.freshness, 60 * 60)
  }

  /// Tests write only to the injected temp file — never the app Caches folder.
  func testDiskCacheUsesInjectedURL() async {
    let model = makeModel(tvChannels: {
      [Self.channel(9, stream: "https://cdn.example/9.m3u8")]
    }, initialChannels: [])
    await model.fetch()
    XCTAssertTrue(FileManager.default.fileExists(atPath: tempCacheURL.path))
    if let appCache = TVChannelsModel.defaultDiskCacheURL {
      XCTAssertNotEqual(tempCacheURL.path, appCache.path)
    }
  }

  /// The guide comes after the list and fills the second line: what is on air now, nothing
  /// for a channel the guide does not carry.
  func testScheduleFillsNowPlaying() async {
    let now = Date()
    let model = makeModel(
      tvChannels: { [Self.channel(1), Self.channel(2)] },
      epgService: EPGServiceMock { _ in
        [1: [EPGProgram(title: "Earlier", start: now.addingTimeInterval(-7_200), stop: now.addingTimeInterval(-600)),
             EPGProgram(title: "Now", start: now.addingTimeInterval(-600), stop: now.addingTimeInterval(600))]]
      },
      initialChannels: []
    )
    await model.fetch()
    XCTAssertEqual(model.nowPlaying(channelID: 1, at: now)?.title, "Now")
    XCTAssertNil(model.nowPlaying(channelID: 1, at: now.addingTimeInterval(1_200)), "nothing after the schedule ends")
    XCTAssertNil(model.nowPlaying(channelID: 2, at: now))
#if os(tvOS)
    let tile = TVChannelsView.tile(for: Self.channel(1), onAir: model.nowPlaying(channelID: 1, at: now))
    XCTAssertEqual(tile.title, "Now")
    XCTAssertNil(tile.focusedTitle)
    XCTAssertNil(tile.subtitle)
    XCTAssertFalse(tile.subtitleOnFocus)
#endif
  }

  /// The tab opens on the whole baked grid, in the order the loaded list uses:
  /// Latin titles first, the Russian block at the bottom. No stream yet.
  func testOpensOnTheBakedGrid() {
    let model = makeModel()
    XCTAssertEqual(model.channels.count, 51)
    XCTAssertEqual(model.channels.first?.title, "CBS Sports")
    XCTAssertEqual(model.channels.last?.title, "Футбол ТВ")
    XCTAssertEqual(model.channels.map(\.title).firstIndex(of: "Бокс ТВ"),
                   model.channels.map(\.title).firstIndex(of: "Беларусь 5").map { $0 + 2 })
    XCTAssertTrue(model.channels.allSatisfy { $0.stream.isEmpty && $0.logo != nil })
    XCTAssertFalse(model.isLoading)
  }

  /// Most sports channels ship logos in the asset catalog; a few still stay on the CDN URL.
  func testBundledLogosUseFullCards() {
    XCTAssertEqual(TVChannelCatalog.bundledLogo(for: 80), .full("cbs-sports"))
    XCTAssertEqual(TVChannelCatalog.bundledLogo(for: 27), .full("espn"))
    XCTAssertEqual(TVChannelCatalog.bundledLogo(for: 145), .full("eleven-sports"))
    XCTAssertEqual(TVChannelCatalog.bundledLogo(for: 1), .full("матч"))
    XCTAssertNil(TVChannelCatalog.bundledLogo(for: 13), "Setanta 1 stays on the CDN")
#if os(tvOS)
    let cbs = TVChannelCatalog.channels.first { $0.id == 80 }!
    let setanta = TVChannelCatalog.channels.first { $0.id == 13 }!
    XCTAssertEqual(TVChannelsView.logo(for: cbs), .bundled("cbs-sports"))
    XCTAssertEqual(TVChannelsView.logo(for: setanta),
                   .remote(URL(string: "https://m.staticpop.net/channels/150x150/setanta_1.png")!))
    // Mark+focus-BG remains a supported logo kind even though no channel uses it now.
    XCTAssertEqual(TVPageLogo.bundledMark(logo: "cbs-sports_logo",
                                          focusBackground: "cbs-sports_bg"),
                   .bundledMark(logo: "cbs-sports_logo", focusBackground: "cbs-sports_bg"))
#endif
  }

#if os(tvOS)
  /// Caption stays the programme when focused (no channel-name / logo swap under the tile).
  func testChannelTileKeepsProgramWhenFocused() {
    let channel = TVChannel(id: 27, title: "ESPN 1",
                            logo: "https://example/espn.png", stream: "https://example/live.m3u8")
    let onAir = EPGProgram(title: "LIVE: COLLEGE BASKETBALL",
                           start: Date().addingTimeInterval(-600),
                           stop: Date().addingTimeInterval(600))
    let withProgram = TVChannelsView.tile(for: channel, onAir: onAir)
    XCTAssertEqual(withProgram.title, "LIVE: COLLEGE BASKETBALL")
    XCTAssertNil(withProgram.focusedTitle)
    XCTAssertNil(withProgram.subtitle)
    XCTAssertFalse(withProgram.subtitleOnFocus)

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
    let model = makeModel(
      tvChannels: {
        [TVChannel(id: 7, title: "Матч! Футбол 3", stream: "https://cdn.example/7.m3u8")]
      },
      epgService: EPGServiceMock { channels in
        asked.record(channels.map(\.stream))
        return [7: [EPGProgram(title: "Now", start: now.addingTimeInterval(-600),
                               stop: now.addingTimeInterval(600))]]
      },
      initialChannels: [shown]
    )
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
    let model = makeModel(tvChannels: { reversed },
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
