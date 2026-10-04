//
//  MediaCardModelTests.swift
//
//  A poster card worded from the media model and the viewer's state.
//

import XCTest
import KinoPubBackend
import KinoPubMedia
@testable import KinoPubUI

final class MediaCardModelTests: XCTestCase {

  private var film: MediaEntity {
    var entity = MediaEntity(kind: .movie,
                             ids: [ExternalID(.kinopub, "124447"), ExternalID(.imdb, "tt0903747"),
                                   ExternalID(.kinopoisk, "326")],
                             title: "Побег из Шоушенка",
                             originalTitle: "The Shawshank Redemption",
                             synopsis: Synopsis(full: "Банкир готовит побег."),
                             genres: [GenreVocabulary.genre(id: "drama")!],
                             release: .year(1994),
                             runtime: 142 * 60,
                             scores: [Score(.imdb, value: 9.3, votes: 3_000_000)!,
                                      Score(.kinopoisk, value: 9.1)!],
                             countries: ["США"],
                             formats: [.uhd])
    entity.artwork = ArtworkSet(poster: URL(string: "https://kp/big.jpg"),
                                backdrop: URL(string: "https://kp/wide.jpg"),
                                posterPreview: URL(string: "https://kp/medium.jpg"))
    return entity
  }

  func testAFilmCard() {
    let card = MediaCard(ref: .title(124447), entity: film, state: .unknown, language: .ru)
    XCTAssertEqual(card.id, 124447)
    XCTAssertEqual(card.title, "Побег из Шоушенка")
    XCTAssertEqual(card.subtitle, "The Shawshank Redemption")
    XCTAssertEqual(card.posterURL, "https://kp/medium.jpg", "the grid's size first")
    XCTAssertEqual(card.backdropURL, "https://kp/wide.jpg")
    XCTAssertEqual(card.overview, "Банкир готовит побег.")
    XCTAssertEqual(card.year, 1994)
    XCTAssertEqual(card.durationSeconds, 142 * 60)
    XCTAssertTrue(card.is4K)
    XCTAssertFalse(card.isSeries)
    XCTAssertEqual(card.imdbID, 903747)
    XCTAssertEqual(card.kinopoiskID, 326)
    XCTAssertEqual(card.scores.imdb, 9.3)
    XCTAssertEqual(card.scores.kinopoisk, 9.1)
  }

  /// Follow is a series' alone: a film never reads as followed, whatever a store says.
  func testAFilmIsNeverFollowed() {
    let card = MediaCard(ref: .title(1), entity: film,
                         state: ViewerState(isFollowing: nil, bookmarkFolderIDs: [7]))
    XCTAssertEqual(card.isSeries, false)
    XCTAssertEqual(card.bookmarkFolderIDs, [7])
    XCTAssertTrue(card.isBookmarked)
  }

  func testASeriesCard() {
    let show = MediaEntity(kind: .show, title: "Тед Лассо", seasonCount: 3, release: .year(2020),
                           runtime: 99_999)
    let card = MediaCard(ref: .title(87940), entity: show, state: ViewerState(isFollowing: true),
                         language: .ru)
    XCTAssertTrue(card.isSeries)
    XCTAssertNil(card.durationSeconds, "a series has no single runtime")
    XCTAssertEqual(card.seasonCount, 3)
    XCTAssertEqual(card.metaLine, "2020   3 сезона")
  }
}
