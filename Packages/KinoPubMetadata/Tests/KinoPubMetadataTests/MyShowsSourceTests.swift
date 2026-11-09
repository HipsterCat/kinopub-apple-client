//
//  MyShowsSourceTests.swift
//
//  Payload in the shape `shows.GetByExternalId {id: 903747, source: "imdb"}` answered
//  for Breaking Bad (Sasha's probe, 2026-11-09), trimmed.
//

import XCTest
@testable import KinoPubMetadata

final class MyShowsSourceTests: XCTestCase {

  private let show = """
  {"id": 187, "title": "Во все тяжкие", "titleOriginal": "Breaking Bad", "status": "Canceled/Ended",
   "rating": 4.58, "voted": 151923, "imdbId": 903747, "imdbRating": 9.5, "imdbVoted": 2702569,
   "kinopoiskId": 404900, "kinopoiskRating": 8.923, "kinopoiskVoted": 901619,
   "watching": 317914, "watchingTotal": 1043665, "runtime": 47}
  """

  func testShowMapsScoreAudienceAndIMDb() throws {
    let dto = try JSONDecoder().decode(MyShowsShowDTO.self, from: Data(show.utf8))
    var meta = TitleMetadata()
    MyShowsSource.apply(dto, to: &meta)
    XCTAssertEqual(meta.externalRatings.map(\.kind), [.myShows])
    XCTAssertEqual(meta.externalRatings.first?.value, 4.58)
    XCTAssertEqual(meta.externalRatings.first?.score10, 9.16)
    XCTAssertEqual(meta.externalRatings.first?.votes, 151_923)
    XCTAssertEqual(meta.externalRatings.first?.url?.absoluteString, "https://myshows.me/view/187/")
    XCTAssertEqual(meta.relayedIMDbRating, 9.5)
    XCTAssertEqual(meta.relayedIMDbVotes, 2_702_569)
    XCTAssertEqual(meta.myShowsStats, MyShowsStats(watching: 317_914, watchingTotal: 1_043_665))
    XCTAssertEqual(meta.kinopoiskID, 404_900)
    XCTAssertEqual(meta.externalLinks.map(\.site), [.myShows])
  }

  func testUnratedShowAddsNoScore() throws {
    let dto = try JSONDecoder().decode(MyShowsShowDTO.self, from: Data(#"{"id": 5, "rating": 0, "voted": 0}"#.utf8))
    var meta = TitleMetadata()
    MyShowsSource.apply(dto, to: &meta)
    XCTAssertTrue(meta.externalRatings.isEmpty)
    XCTAssertNil(meta.myShowsStats)
    XCTAssertNil(meta.relayedIMDbVotes)
  }

  func testIMDbNumber() {
    XCTAssertEqual(MyShowsSource.imdbNumber("tt0903747"), 903_747)
    XCTAssertNil(MyShowsSource.imdbNumber("903747"))
    XCTAssertNil(MyShowsSource.imdbNumber("tt"))
  }
}
