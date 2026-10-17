//
//  PlayerLiveModeTests.swift
//  KinoPubAppleClientTests
//
//  A TV channel in the real `PlayerManager`, in `WatchMode.live`: the stream it opens is the
//  channel's own link, untouched; the system player gets no Episodes / Up Next tabs, no Info
//  buttons and no custom menus; the info panel is the channel's name. The grid's UI tests use a stand-in player, so this is where the player's
//  side of live is pinned.
//

#if os(tvOS)
import XCTest
import AVFoundation
import AVKit
import KinoPubBackend
import KinoPubKit
// The app target's module is `KinoPub` — see `PlaybackPreflightTests`.
@testable import KinoPub

@MainActor
final class PlayerLiveModeTests: XCTestCase {

  private let stream = "https://fixture.invalid/live/index.m3u8?token=abc"

  private func liveManager() -> PlayerManager {
    PlayerManager(playItem: TVChannel(id: 1, title: "МАТЧ! ТВ", stream: stream),
                  watchMode: .live,
                  downloadedFilesDatabase: DownloadedFilesDatabase<DownloadMeta>(fileSaver: FileSaver()),
                  actionsService: UserActionsServiceMock(),
                  contentService: VideoContentServiceMock())
  }

  /// The channel's link as `/v1/tv` gave it — token and all — not rewritten through the
  /// master-playlist loader, which is for kino.pub's titles.
  func testOpensTheChannelsStreamAsIs() async throws {
    let manager = liveManager()
    await manager.preparePlayback()
    let asset = try XCTUnwrap(manager.player.currentItem?.asset as? AVURLAsset)
    XCTAssertEqual(asset.url.absoluteString, stream)
  }

  /// The info panel names the channel, and only that: its id is not a title's id.
  func testInfoPanelIsTheChannelName() async throws {
    let manager = liveManager()
    await manager.preparePlayback()
    let metadata = try XCTUnwrap(manager.player.currentItem?.externalMetadata)
    XCTAssertEqual(metadata.count, 1)
    XCTAssertEqual(metadata.first?.identifier, .commonIdentifierTitle)
    XCTAssertEqual(metadata.first?.stringValue, "МАТЧ! ТВ")
  }

  /// No Episodes, no Up Next, no *From Beginning* / *Go to*, no custom menus, no subtitles
  /// picker of ours — the system player as it comes, with its own live chrome.
  func testSystemPlayerGetsNoTitleChrome() async {
    let manager = liveManager()
    let controller = AVPlayerViewController()
    manager.systemInfoActions = [UIAction(title: "From Beginning") { _ in }]
    await manager.preparePlayback()
    manager.attach(to: controller)
    XCTAssertEqual(controller.customInfoViewControllers.count, 0)
    XCTAssertEqual(controller.infoViewActions.count, 0)
    XCTAssertEqual(controller.transportBarCustomMenuItems.count, 0)
    XCTAssertFalse(manager.canChooseSubtitles)
  }
}
#endif
