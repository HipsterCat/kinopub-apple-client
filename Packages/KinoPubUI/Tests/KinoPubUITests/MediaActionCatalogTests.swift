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
      download: .idle,
      showsMore: true
    ))
    XCTAssertEqual(row.map(\.id), [.play, .trailer, .bookmark, .markWatched, .download, .more])
    XCTAssertEqual(row[0].chrome, .playPill)
    XCTAssertEqual(row[0].systemImage, "play.fill")
    XCTAssertEqual(row[0].title, MediaActionCopy.playTitle(kind: .fiction))
    XCTAssertEqual(row.first(where: { $0.id == .markWatched })?.chrome, .circle)
  }

  func testConcertUsesWatchNowTitle() {
    let play = MediaActionCatalog.play(for: MediaActionContext(
      playback: .play(season: nil, episode: nil),
      kind: .concert,
      isSeries: false
    ))
    XCTAssertEqual(play.title, MediaActionCopy.playTitle(kind: .concert))
    XCTAssertEqual(play.title, "Watch Now")
  }

  func testMovieWatchedUsesQuieterReplay() {
    let play = MediaActionCatalog.play(for: MediaActionContext(
      playback: .playAgain(season: nil, episode: nil),
      isSeries: false
    ))
    XCTAssertEqual(play.chrome, .pill)
    XCTAssertEqual(play.systemImage, "arrow.clockwise")
    XCTAssertEqual(play.title, MediaActionCopy.localized("Play Again"))
  }

  func testDownloadedHidesDownloadCircle() {
    let row = MediaActionCatalog.row(for: MediaActionContext(
      playback: .play(season: nil, episode: nil),
      isSeries: false,
      showsTrailer: true,
      download: .downloaded,
      showsMore: true
    ))
    XCTAssertFalse(row.contains { $0.id == .download })
  }

  func testDownloadingShowsCircularProgressAndPause() {
    let appearance = MediaActionCatalog.download(for: MediaActionContext(
      playback: .play(season: nil, episode: nil),
      isSeries: false,
      download: .downloading(progress: 0.4)
    ))
    XCTAssertEqual(appearance?.systemImage, "pause.fill")
    XCTAssertEqual(appearance?.circularProgress, 0.4)
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

  func testInProgressMovieUsesRemainingTimeOnly() {
    let play = MediaActionCatalog.play(for: MediaActionContext(
      playback: .resume(progress: 0.35, season: nil, episode: nil, durationSeconds: 52 * 60),
      isSeries: false
    ))
    XCTAssertEqual(play.progress, 0.35)
    XCTAssertEqual(
      play.title,
      MediaActionCopy.remainingLabel(progress: 0.35, durationSeconds: 52 * 60)
    )
  }

  func testSeriesPlayUsesLocalizedEpisodeLabel() {
    let play = MediaActionCatalog.play(for: MediaActionContext(
      playback: .play(season: 1, episode: 1),
      isSeries: true
    ))
    XCTAssertEqual(play.title, MediaActionCopy.episodeLabel(season: 1, episode: 1))
  }

  func testSeriesReplayKeepsEpisodeOnPlayAgain() {
    let play = MediaActionCatalog.play(for: MediaActionContext(
      playback: .playAgain(season: 1, episode: 1),
      isSeries: true
    ))
    XCTAssertEqual(play.chrome, .pill)
    XCTAssertEqual(play.title, MediaActionCopy.episodeLabel(season: 1, episode: 1))
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

  func testPromoteFollowLeadsWithLabelledBell() {
    let row = MediaActionCatalog.row(for: MediaActionContext(
      playback: .playAgain(season: 1, episode: 1),
      isSeries: true,
      showsTrailer: true,
      showsFollow: false,
      showsMore: true,
      promoteFollow: true
    ))
    XCTAssertEqual(row.map(\.id), [.follow, .trailer, .play, .bookmark, .more])
    XCTAssertEqual(row[0].chrome, .playPill)
    XCTAssertEqual(row[0].title, MediaActionCopy.followTitle(isFollowing: false))
  }

  func testShouldPromoteFollowWithinTwoWeeks() {
    let air = Date().addingTimeInterval(7 * 24 * 60 * 60)
    XCTAssertTrue(MediaActionCatalog.shouldPromoteFollow(
      isSeries: true,
      playback: .playAgain(season: 1, episode: 1),
      seriesFinished: false,
      nextEpisodeAirDate: air
    ))
    let later = Date().addingTimeInterval(30 * 24 * 60 * 60)
    XCTAssertFalse(MediaActionCatalog.shouldPromoteFollow(
      isSeries: true,
      playback: .playAgain(season: 1, episode: 1),
      seriesFinished: false,
      nextEpisodeAirDate: later
    ))
    XCTAssertFalse(MediaActionCatalog.shouldPromoteFollow(
      isSeries: true,
      playback: .playAgain(season: 1, episode: 1),
      seriesFinished: true,
      nextEpisodeAirDate: air
    ))
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
