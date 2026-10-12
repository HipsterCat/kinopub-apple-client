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
                         isSeries: true,
                         viewerState: ViewerState(isFollowing: true, bookmarkFolderIDs: [3]),
                         durationSeconds: 3_000)
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
    XCTAssertEqual(painted.viewerState.bookmarkFolderIDs, [1, 2])
    XCTAssertTrue(painted.viewerState.isBookmarked)
    XCTAssertEqual(painted.title, "Film", "words are untouched")
  }

  /// Library Following's second line is `unwatchedEpisodes`. The store lays viewer
  /// state over every title card; dropping the count left every cover without a subtitle.
  func testViewerStateKeepsTheUnwatchedEpisodeCount() {
    let followed = MediaCard(id: 1, posterURL: "", title: "Дом Дракона",
                             subtitle: "2 серии", isSeries: true,
                             viewerState: ViewerState(isFollowing: true),
                             unwatchedEpisodes: 2)
    let painted = followed.withViewerState(ViewerState(isFollowing: true))
    XCTAssertEqual(painted.unwatchedEpisodes, 2)
    XCTAssertEqual(painted.subtitle, "2 серии")
  }

  /// Follow is a series' alone, even if a store says otherwise about a film.
  func testAFilmIsNeverFollowed() {
    let film = MediaCard(id: 7, posterURL: "", title: "Film")
    XCTAssertNil(film.withViewerState(ViewerState(isFollowing: true)).viewerState.isFollowing)
  }

  /// A card written before follow and folders became one value still reads them.
  func testACardWrittenBeforeTheViewerStateStillDecodes() throws {
    let json = #"{"id":7,"posterURL":"","title":"Show","isSeries":true,"isInWatchlist":true,"bookmarkFolderIDs":[4],"genreLine":"Драма, Комедия","countryLine":"США","metaLine":"2020"}"#
    let card = try JSONDecoder().decode(MediaCard.self, from: Data(json.utf8))
    XCTAssertEqual(card.viewerState.isFollowing, true)
    XCTAssertEqual(card.viewerState.bookmarkFolderIDs, [4])
    XCTAssertEqual(card.primaryGenre(language: .ru), "Драма", "the primary's name survives")
    XCTAssertEqual(card.country, "США")
    let roundTripped = try JSONDecoder().decode(MediaCard.self, from: JSONEncoder().encode(card))
    XCTAssertEqual(roundTripped, card)
  }
}
