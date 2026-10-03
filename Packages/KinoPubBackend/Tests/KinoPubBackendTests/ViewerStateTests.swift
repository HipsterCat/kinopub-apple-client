//
//  ViewerStateTests.swift
//
//  What the viewer has done with a thing: the payload's word, then this device's on top —
//  the rules every card, button and list reads through.
//

import XCTest
import KinoPubMedia
@testable import KinoPubBackend

final class ViewerStateTests: XCTestCase {

  private func episode(watched: Int = 0, time: Int = 0) -> Episode {
    Episode(id: 901, title: "", thumbnail: "", duration: 3_000, tracks: 1, number: 5, ac3: 0,
            audios: [], watched: watched, watching: EpisodeWatching(status: 0, time: time),
            subtitles: [], files: [])
  }

  // MARK: - What kino.pub reports

  func testAnEpisodeReportsItsProgressAndItsFlag() {
    let halfway = ViewerState(reportedBy: episode(time: 1_500))
    XCTAssertEqual(halfway.progress, WatchProgress(position: 1_500, duration: 3_000))
    XCTAssertFalse(halfway.isWatched)
    XCTAssertEqual(halfway.resumeFraction ?? 0, 0.5, accuracy: 0.001)
    XCTAssertTrue(ViewerState(reportedBy: episode(watched: 1)).isWatched)
  }

  /// A listing payload says nothing about watchlist or folders — unknown, not "no".
  func testWhatAPayloadDoesNotSayStaysUnknown() {
    let state = ViewerState(reportedBy: episode())
    XCTAssertNil(state.isFollowing)
    XCTAssertNil(state.bookmarkFolderIDs)
    XCTAssertFalse(state.isBookmarked)
  }

  // MARK: - This device on top

  func testEveryLocalValueWins() {
    let reported = ViewerState(progress: WatchProgress(position: 100, duration: 3_000),
                               isWatched: false, isFollowing: true,
                               bookmarkFolderIDs: [1])
    let local = ViewerOverlay(progress: WatchProgress(position: 900, duration: 3_000),
                              isFollowing: false, bookmarkFolderIDs: [2, 3],
                              download: .downloading(0.4), vote: .up)
    let state = reported.overlaid(local)
    XCTAssertEqual(state.progress?.position, 900)
    XCTAssertEqual(state.isFollowing, false)
    XCTAssertEqual(state.bookmarkFolderIDs, [2, 3])
    XCTAssertEqual(state.download, .downloading(0.4))
    XCTAssertEqual(state.vote, .up)
  }

  /// Nothing local: the payload stands as it is.
  func testAnEmptyOverlayChangesNothing() {
    let reported = ViewerState(progress: WatchProgress(position: 100, duration: 3_000),
                               isWatched: true, isFollowing: true, bookmarkFolderIDs: [1])
    XCTAssertEqual(reported.overlaid(ViewerOverlay()), reported)
  }

  /// Played to the credits on this device: watched, as the server will say once it
  /// hears the position — and no resume bar.
  func testALocalFinishMarksItWatched() {
    let state = ViewerState.unknown.overlaid(
      ViewerOverlay(progress: WatchProgress(position: 2_990, duration: 3_000)))
    XCTAssertTrue(state.isWatched)
    XCTAssertNil(state.resumeFraction)
  }

  /// "Mark unwatched" beats a finished resume point still on disk.
  func testALocalUnwatchedMarkBeatsAFinishedResumePoint() {
    let state = ViewerState.unknown.overlaid(
      ViewerOverlay(progress: WatchProgress(position: 2_990, duration: 3_000), isWatched: false))
    XCTAssertFalse(state.isWatched)
  }

  func testHistoryKeepsTheNewestPlay() {
    let earlier = Date(timeIntervalSince1970: 1_000)
    let later = Date(timeIntervalSince1970: 2_000)
    let reported = ViewerState(lastWatchedAt: later)
    XCTAssertEqual(reported.overlaid(ViewerOverlay(progressUpdatedAt: earlier)).lastWatchedAt, later)
    XCTAssertEqual(ViewerState.unknown.overlaid(ViewerOverlay(progressUpdatedAt: earlier)).lastWatchedAt,
                   earlier)
  }

  func testCodable() throws {
    let state = ViewerState(progress: WatchProgress(position: 10, duration: 20), isWatched: true,
                            isFollowing: false, bookmarkFolderIDs: [4],
                            download: .downloading(0.5), vote: .down)
    XCTAssertEqual(try JSONDecoder().decode(ViewerState.self, from: JSONEncoder().encode(state)),
                   state)
  }

  // MARK: - A series, a season

  /// Watched and downloaded are both progress for a container — a ring or a percentage.
  func testASeriesTalliesItsEpisodes() {
    let episodes = [
      ViewerState(isWatched: true, download: .downloaded),
      ViewerState(isWatched: true, download: .downloading(0.5)),
      ViewerState(progress: WatchProgress(position: 600, duration: 3_000)),
      ViewerState(),
    ]
    let series = ViewerState(isFollowing: true).aggregating(episodes: episodes)
    XCTAssertEqual(series.watchedEpisodes, Tally(completed: 2, total: 4))
    XCTAssertEqual(series.watchedEpisodes?.fraction, 0.5)
    XCTAssertEqual(series.downloadedEpisodes?.fraction, 0.375)
    XCTAssertFalse(series.isWatched)
    XCTAssertEqual(series.isFollowing, true, "the title's own facts stay")
    XCTAssertNil(series.progress)
  }

  func testASeriesIsWatchedWhenEveryEpisodeIs() {
    let all = ViewerState().aggregating(episodes: [ViewerState(isWatched: true),
                                                   ViewerState(isWatched: true)])
    XCTAssertTrue(all.isWatched)
    XCTAssertTrue(all.watchedEpisodes?.isComplete ?? false)
    XCTAssertFalse(ViewerState().aggregating(episodes: []).isWatched, "nothing is not all watched")
    XCTAssertNil(ViewerState().aggregating(episodes: []).watchedEpisodes?.fraction)
  }

  // MARK: - kino.pub's names for a thing

  func testWatchingMetadataIsAMediaRef() {
    XCTAssertEqual(WatchingMetadata(id: 7, video: 5, season: 2).mediaRef,
                   .episode(7, season: 2, number: 5))
    XCTAssertEqual(WatchingMetadata(id: 7, video: 1, season: nil).mediaRef, .version(7, number: 1))
    XCTAssertNil(WatchingMetadata(id: 0, video: 5, season: 2).mediaRef,
                 "an unstamped episode is no title's")
    XCTAssertEqual(WatchingMetadata(.episode(7, season: 2, number: 5)),
                   WatchingMetadata(id: 7, video: 5, season: 2))
  }

  func testAStampedEpisodeIsItsOwnRef() {
    let stamped = episode()
    stamped.mediaId = 7
    stamped.seasonNumber = 2
    XCTAssertEqual(stamped.mediaRef, .episode(7, season: 2, number: 5))
  }
}
