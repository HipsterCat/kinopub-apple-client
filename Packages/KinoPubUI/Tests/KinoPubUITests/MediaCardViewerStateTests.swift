//
//  MediaCardViewerStateTests.swift
//
//  A cached card painted with the viewer's state of now, not of when it was fetched.
//

import XCTest
import KinoPubBackend
import KinoPubMedia
@testable import KinoPubUI

final class MediaCardViewerStateTests: XCTestCase {

  func testAPosterCardIsTheTitle() {
    XCTAssertEqual(MediaCard(id: 7, posterURL: "", title: "A").ref, .title(7))
    XCTAssertEqual(MediaCard(id: 900, posterURL: "", title: "A", itemID: 7, video: 5, season: 2).ref,
                   .episode(7, season: 2, number: 5))
  }

  /// What the card said when fetched is the reported side.
  func testTheCardReportsWhatItWasFetchedWith() {
    let card = MediaCard(id: 7, posterURL: "", title: "A", progress: 0.5, isWatched: false,
                         isSeries: true, isInWatchlist: true, durationSeconds: 3_000,
                         bookmarkFolderIDs: [3])
    let reported = card.reportedState
    XCTAssertEqual(reported.progress?.position, 1_500)
    XCTAssertEqual(reported.isFollowing, true)
    XCTAssertEqual(reported.bookmarkFolderIDs, [3])
  }

  /// This device's state replaces the cached copy: a film finished here since the row was
  /// fetched reads watched, with no bar.
  func testTheViewersStateReplacesTheCachedCopy() {
    let cached = MediaCard(id: 7, posterURL: "", title: "Film", progress: 0.4,
                           durationSeconds: 6_000)
    let painted = cached.withViewerState(ViewerState(isWatched: true, bookmarkFolderIDs: [1, 2]))
    XCTAssertTrue(painted.isWatched)
    XCTAssertNil(painted.progress)
    XCTAssertEqual(painted.bookmarkFolderIDs, [1, 2])
    XCTAssertTrue(painted.isBookmarked)
    XCTAssertEqual(painted.title, "Film", "words are untouched")
  }

  /// Follow is a series' alone, even if a store says otherwise about a film.
  func testAFilmIsNeverFollowed() {
    let film = MediaCard(id: 7, posterURL: "", title: "Film")
    XCTAssertFalse(film.withViewerState(ViewerState(isFollowing: true)).isInWatchlist)
  }
}
