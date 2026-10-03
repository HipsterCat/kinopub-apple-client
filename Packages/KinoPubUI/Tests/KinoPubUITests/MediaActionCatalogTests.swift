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

  func testSeriesUnwatchedPlayIncludesVerbInEnglishFallback() {
    let play = MediaActionCatalog.play(for: MediaActionContext(
      playback: .play(season: 1, episode: 1),
      isSeries: true
    ))
    // Package tests resolve via fallback: EN-shaped `Play S1, E1`.
    // Compact `S1, E1` is resume-only (progress bar).
    XCTAssertEqual(play.title, MediaActionCopy.playEpisodeTitle(season: 1, episode: 1))
    XCTAssertEqual(play.title, "Play S1, E1")
    XCTAssertNotEqual(play.title, MediaActionCopy.episodeLabel(season: 1, episode: 1))
  }

  func testSeriesInProgressUsesCompactEpisodeOnly() {
    let play = MediaActionCatalog.play(for: MediaActionContext(
      playback: .resume(progress: 0.4, season: 1, episode: 2, durationSeconds: 2400),
      isSeries: true
    ))
    XCTAssertEqual(play.title, MediaActionCopy.episodeLabel(season: 1, episode: 2))
    XCTAssertEqual(play.progress, 0.4)
  }

  func testSeriesReplayUsesReplayTitle() {
    let play = MediaActionCatalog.play(for: MediaActionContext(
      playback: .playAgain(season: 1, episode: 1),
      isSeries: true
    ))
    XCTAssertEqual(play.chrome, .pill)
    XCTAssertEqual(play.title, MediaActionCopy.replayEpisodeTitle(season: 1, episode: 1))
    XCTAssertEqual(play.title, "Replay S1, E1")
  }

  func testShuffleIsIconCircleBeforeMore() {
    let row = MediaActionCatalog.row(for: MediaActionContext(
      playback: .play(season: 1, episode: 1),
      isSeries: true,
      showsTrailer: true,
      showsFollow: true,
      showsShuffle: true,
      showsMore: true
    ))
    XCTAssertEqual(row.map(\.id),
                   [.play, .trailer, .bookmark, .follow, .shuffle, .more])
    let shuffle = row.first { $0.id == .shuffle }
    XCTAssertEqual(shuffle?.chrome, .circle)
    XCTAssertNil(shuffle?.title)
  }

  func testInProgressSeriesKeepsShuffleAsCircleBeforeMore() {
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
    XCTAssertEqual(row.first(where: { $0.id == .shuffle })?.chrome, .circle)
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

  /// The awaited episode's date is all it takes — a month out, or already aired and not
  /// on kino.pub yet. There used to be a two-week window, which left a series with a
  /// known date further out leading with Replay.
  func testShouldPromoteFollowWheneverTheAwaitedEpisodeHasADate() {
    let dates = [
      Date().addingTimeInterval(7 * 24 * 60 * 60),
      Date().addingTimeInterval(45 * 24 * 60 * 60),
      Date().addingTimeInterval(-2 * 24 * 60 * 60)
    ]
    for date in dates {
      XCTAssertTrue(MediaActionCatalog.shouldPromoteFollow(
        isSeries: true,
        playback: .playAgain(season: 1, episode: 1),
        seriesFinished: false,
        awaitedEpisodeAirDate: date
      ), "\(date)")
    }
  }

  func testShouldNotPromoteFollowWithoutADateOrWithSomethingToPlay() {
    let date = Date().addingTimeInterval(3 * 24 * 60 * 60)
    XCTAssertFalse(MediaActionCatalog.shouldPromoteFollow(
      isSeries: true,
      playback: .playAgain(season: 1, episode: 1),
      seriesFinished: false,
      awaitedEpisodeAirDate: nil
    ), "no date known")
    XCTAssertFalse(MediaActionCatalog.shouldPromoteFollow(
      isSeries: true,
      playback: .play(season: 2, episode: 3),
      seriesFinished: false,
      awaitedEpisodeAirDate: date
    ), "an unwatched episode is still there to play")
    XCTAssertFalse(MediaActionCatalog.shouldPromoteFollow(
      isSeries: true,
      playback: .playAgain(season: 1, episode: 1),
      seriesFinished: true,
      awaitedEpisodeAirDate: date
    ), "finished series")
    XCTAssertFalse(MediaActionCatalog.shouldPromoteFollow(
      isSeries: false,
      playback: .playAgain(season: nil, episode: nil),
      seriesFinished: false,
      awaitedEpisodeAirDate: date
    ), "film")
  }

  // MARK: - Versions of one film

  /// Two named versions: two play pills in place of «Смотреть фильм», each labelled with
  /// its version's name, the first prominent.
  func testTwoVersionsAreTwoNamedPlayPills() {
    let row = MediaActionCatalog.row(for: MediaActionContext(
      playback: .play(season: nil, episode: nil),
      isSeries: false,
      showsMarkWatched: true,
      showsTrailer: true,
      showsMore: true,
      versions: [MediaActionVersion(name: "24 fps", playback: .play(season: nil, episode: nil)),
                 MediaActionVersion(name: "48 fps", playback: .play(season: nil, episode: nil))]
    ))
    XCTAssertEqual(row.map(\.id), [.play, .playAlternate, .trailer, .bookmark, .markWatched, .more])
    XCTAssertEqual(row[0].title, "24 fps")
    XCTAssertEqual(row[1].title, "48 fps")
    XCTAssertEqual(row[0].chrome, .playPill)
    XCTAssertEqual(row[1].chrome, .pill)
    XCTAssertEqual(row[0].systemImage, "play.fill")
    XCTAssertEqual(row[1].systemImage, "play.fill")
    XCTAssertFalse(row.contains { $0.title == MediaActionCopy.playTitle(kind: .fiction) })
  }

  /// No names: «Смотреть» and «Вторая версия» (EN fallbacks in package tests). A third
  /// version is not a button.
  func testUnnamedVersionsFallBackAndAThirdIsNotAButton() {
    let fresh = PlaybackButtonContent.play(season: nil, episode: nil)
    let row = MediaActionCatalog.row(for: MediaActionContext(
      playback: fresh,
      isSeries: false,
      versions: [MediaActionVersion(name: nil, playback: fresh),
                 MediaActionVersion(name: nil, playback: fresh),
                 MediaActionVersion(name: nil, playback: fresh)]
    ))
    XCTAssertEqual(row.map(\.id), [.play, .playAlternate, .bookmark])
    XCTAssertEqual(row[0].title, MediaActionCopy.versionTitle(name: nil, index: 0))
    XCTAssertEqual(row[1].title, MediaActionCopy.versionTitle(name: nil, index: 1))
    XCTAssertEqual(row[0].title, "Watch")
    XCTAssertEqual(row[1].title, "Second Version")
  }

  /// Each pill shows its own version's state: a bar on the started one, Replay on the
  /// watched one. The checkmark stays a circle so the row does not grow a third pill.
  func testVersionPillsCarryTheirOwnState() {
    let row = MediaActionCatalog.row(for: MediaActionContext(
      playback: .resume(progress: 0.3, season: nil, episode: nil, durationSeconds: 6000),
      isSeries: false,
      showsMarkWatched: true,
      versions: [MediaActionVersion(name: "Theatrical",
                                    playback: .resume(progress: 0.3, season: nil, episode: nil,
                                                      durationSeconds: 6000)),
                 MediaActionVersion(name: "Director's Cut",
                                    playback: .playAgain(season: nil, episode: nil))]
    ))
    XCTAssertEqual(row.map(\.id), [.play, .playAlternate, .bookmark, .markWatched])
    XCTAssertEqual(row[0].progress, 0.3)
    XCTAssertEqual(row[0].title, "Theatrical")
    XCTAssertNil(row[1].progress)
    XCTAssertEqual(row[1].systemImage, "arrow.clockwise")
    XCTAssertEqual(row[1].chrome, .pill)
    XCTAssertEqual(row.first { $0.id == .markWatched }?.chrome, .circle)
  }

  /// One version is no choice: the single Play stays exactly as it was.
  func testOneVersionKeepsTheSinglePlay() {
    let row = MediaActionCatalog.row(for: MediaActionContext(
      playback: .play(season: nil, episode: nil),
      isSeries: false,
      versions: [MediaActionVersion(name: "24 fps", playback: .play(season: nil, episode: nil))]
    ))
    XCTAssertEqual(row.map(\.id), [.play, .bookmark])
    XCTAssertEqual(row[0].title, MediaActionCopy.playTitle(kind: .fiction))
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
