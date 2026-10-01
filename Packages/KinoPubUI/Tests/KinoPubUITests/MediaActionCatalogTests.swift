//
//  MediaActionCatalogTests.swift
//  KinoPubUITests
//

import XCTest
import KinoPubBackend
@testable import KinoPubUI

final class MediaActionCatalogTests: XCTestCase {

  func testMovieUnwatchedOrder() {
    let row = MediaActionCatalog.row(for: MediaActionContext(
      playback: .play(episodeLabel: nil),
      isSeries: false,
      showsMarkWatched: true,
      showsTrailer: true,
      showsDownload: true,
      showsMore: true
    ))
    XCTAssertEqual(row.map(\.id), [.play, .trailer, .bookmark, .markWatched, .download, .more])
    XCTAssertEqual(row[0].chrome, .playPill)
    XCTAssertEqual(row[0].systemImage, "play.fill")
    XCTAssertEqual(row[0].title, NSLocalizedString("Play", comment: ""))
    XCTAssertEqual(row.first(where: { $0.id == .markWatched })?.chrome, .circle)
  }

  func testMovieWatchedUsesQuieterReplay() {
    let play = MediaActionCatalog.play(for: MediaActionContext(
      playback: .playAgain,
      isSeries: false
    ))
    XCTAssertEqual(play.chrome, .pill)
    XCTAssertEqual(play.systemImage, "arrow.clockwise")
    XCTAssertEqual(play.title, NSLocalizedString("Play Again", comment: ""))
  }

  func testInProgressPutsMarkWatchedPillBesidePlay() {
    let row = MediaActionCatalog.row(for: MediaActionContext(
      playback: .resume(progress: 0.4, episodeLabel: "S1, E2", durationSeconds: 2400),
      isSeries: true,
      showsMarkWatched: true,
      showsTrailer: true,
      showsFollow: true,
      showsShuffle: true,
      showsMore: true
    ))
    XCTAssertEqual(row.map(\.id),
                   [.play, .markWatched, .trailer, .bookmark, .follow, .shuffle, .more])
    let mark = row[1]
    XCTAssertEqual(mark.chrome, .pill)
    XCTAssertEqual(mark.title, NSLocalizedString("Mark as Watched", comment: ""))
    XCTAssertEqual(row[0].progress, 0.4)
    XCTAssertTrue(row[0].title?.contains("S1, E2") == true)
  }

  func testSeriesPlayUsesEpisodeLabelWithoutPlayPrefix() {
    let play = MediaActionCatalog.play(for: MediaActionContext(
      playback: .play(episodeLabel: "S1, E1"),
      isSeries: true
    ))
    XCTAssertEqual(play.title, "S1, E1")
    XCTAssertTrue(play.accessibilityLabel.contains("S1, E1"))
  }

  func testFollowIconReflectsSubscription() {
    let idle = MediaActionCatalog.follow(for: MediaActionContext(
      playback: .play(episodeLabel: "S1, E1"),
      isSeries: true,
      isFollowing: false,
      showsFollow: true
    ))
    let active = MediaActionCatalog.follow(for: MediaActionContext(
      playback: .play(episodeLabel: "S1, E1"),
      isSeries: true,
      isFollowing: true,
      showsFollow: true
    ))
    XCTAssertEqual(idle.systemImage, "bell")
    XCTAssertEqual(active.systemImage, "bell.and.waves.left.and.right.fill")
  }

  func testLoadingFlagSurfacesOnAppearance() {
    let mark = MediaActionCatalog.markWatched(for: MediaActionContext(
      playback: .resume(progress: 0.2, episodeLabel: nil, durationSeconds: 600),
      isSeries: false,
      showsMarkWatched: true,
      loading: [.markWatched]
    ))
    XCTAssertTrue(mark.isLoading)
  }
}
