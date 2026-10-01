//
//  MediaActionCatalogTests.swift
//  KinoPubUITests
//

import XCTest
import KinoPubBackend
@testable import KinoPubUI

final class MediaActionCatalogTests: XCTestCase {

  func testMovieUnwatchedOrderAndWatchMovieTitle() {
    let row = MediaActionCatalog.row(for: MediaActionContext(
      playback: .play(season: nil, episode: nil),
      kind: .fiction,
      isSeries: false,
      showsMarkWatched: true,
      showsTrailer: true,
      showsDownload: true,
      showsMore: true
    ))
    XCTAssertEqual(row.map(\.id), [.play, .trailer, .bookmark, .markWatched, .download, .more])
    XCTAssertEqual(row[0].chrome, .playPill)
    XCTAssertEqual(row[0].systemImage, "play.fill")
    XCTAssertEqual(row[0].title, MediaActionCopy.playTitle(kind: .fiction))
    XCTAssertEqual(row.first(where: { $0.id == .markWatched })?.chrome, .circle)
  }

  func testConcertUsesConcertPlayTitle() {
    let play = MediaActionCatalog.play(for: MediaActionContext(
      playback: .play(season: nil, episode: nil),
      kind: .concert,
      isSeries: false
    ))
    XCTAssertEqual(play.title, MediaActionCopy.playTitle(kind: .concert))
  }

  func testMovieWatchedUsesQuieterReplay() {
    let play = MediaActionCatalog.play(for: MediaActionContext(
      playback: .playAgain,
      isSeries: false
    ))
    XCTAssertEqual(play.chrome, .pill)
    XCTAssertEqual(play.systemImage, "arrow.clockwise")
    XCTAssertEqual(play.title, MediaActionCopy.localized("Play Again"))
  }

  func testInProgressSeriesUsesEpisodeLabelWithoutTime() {
    let row = MediaActionCatalog.row(for: MediaActionContext(
      playback: .resume(progress: 0.4, season: 1, episode: 2, durationSeconds: 2400),
      isSeries: true,
      showsMarkWatched: true,
      showsTrailer: true,
      showsFollow: true,
      showsShuffle: true,
      showsMore: true
    ))
    XCTAssertEqual(row.map(\.id),
                   [.play, .markWatched, .trailer, .bookmark, .follow, .shuffle, .more])
    let play = row[0]
    XCTAssertEqual(play.title, MediaActionCopy.episodeLabel(season: 1, episode: 2))
    XCTAssertFalse(play.title?.contains("·") == true)
    XCTAssertEqual(play.progress, 0.4)
    XCTAssertEqual(row.first(where: { $0.id == .shuffle })?.chrome, .circle)
  }

  func testInProgressMovieUsesRemainingMinutesOnly() {
    let play = MediaActionCatalog.play(for: MediaActionContext(
      playback: .resume(progress: 0.35, season: nil, episode: nil, durationSeconds: 52 * 60),
      isSeries: false
    ))
    XCTAssertEqual(play.progress, 0.35)
    XCTAssertEqual(
      play.title,
      MediaActionCopy.remainingMinutesLabel(progress: 0.35, durationSeconds: 52 * 60)
    )
  }

  func testSeriesPlayUsesLocalizedEpisodeLabel() {
    let play = MediaActionCatalog.play(for: MediaActionContext(
      playback: .play(season: 1, episode: 1),
      isSeries: true
    ))
    XCTAssertEqual(play.title, MediaActionCopy.episodeLabel(season: 1, episode: 1))
    XCTAssertFalse(play.title?.contains("S1") == true)
    XCTAssertFalse(play.title?.contains("E1") == true)
  }

  func testShuffleIsLabelledPillWhenNotMidTitle() {
    let row = MediaActionCatalog.row(for: MediaActionContext(
      playback: .play(season: 1, episode: 1),
      isSeries: true,
      showsTrailer: true,
      showsFollow: true,
      showsShuffle: true,
      showsMore: true
    ))
    XCTAssertEqual(row.map(\.id),
                   [.play, .trailer, .shuffle, .bookmark, .follow, .more])
    let shuffle = row.first { $0.id == .shuffle }
    XCTAssertEqual(shuffle?.chrome, .pill)
    XCTAssertEqual(shuffle?.title, MediaActionCopy.localized("Shuffle"))
  }

  func testFollowIconReflectsSubscription() {
    let idle = MediaActionCatalog.follow(for: MediaActionContext(
      playback: .play(season: 1, episode: 1),
      isSeries: true,
      isFollowing: false,
      showsFollow: true
    ))
    let active = MediaActionCatalog.follow(for: MediaActionContext(
      playback: .play(season: 1, episode: 1),
      isSeries: true,
      isFollowing: true,
      showsFollow: true
    ))
    XCTAssertEqual(idle.systemImage, "bell")
    XCTAssertEqual(active.systemImage, "bell.and.waves.left.and.right.fill")
  }

  func testLoadingFlagSurfacesOnAppearance() {
    let mark = MediaActionCatalog.markWatched(for: MediaActionContext(
      playback: .resume(progress: 0.2, season: nil, episode: nil, durationSeconds: 600),
      isSeries: false,
      showsMarkWatched: true,
      loading: [.markWatched]
    ))
    XCTAssertTrue(mark.isLoading)
  }
}
