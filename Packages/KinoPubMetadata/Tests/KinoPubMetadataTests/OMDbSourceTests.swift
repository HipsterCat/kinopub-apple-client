//
//  OMDbSourceTests.swift
//
//  Payload in the shape omdbapi.com answers `?i=tt…` (its own example, The Shawshank
//  Redemption, trimmed).
//

import XCTest
@testable import KinoPubMetadata

final class OMDbSourceTests: XCTestCase {

  private let title = """
  {"Title": "The Shawshank Redemption", "Year": "1994", "Rated": "R",
   "Awards": "Nominated for 7 Oscars. 21 wins & 42 nominations total",
   "Ratings": [{"Source": "Internet Movie Database", "Value": "9.3/10"},
               {"Source": "Rotten Tomatoes", "Value": "89%"},
               {"Source": "Metacritic", "Value": "82/100"}],
   "Metascore": "82", "imdbRating": "9.3", "imdbVotes": "3,057,422", "imdbID": "tt0111161",
   "Type": "movie", "BoxOffice": "$28,767,189", "Response": "True"}
  """

  func testTitleMapsScoresBoxOfficeAndAwards() throws {
    let dto = try JSONDecoder().decode(OMDbTitleDTO.self, from: Data(title.utf8))
    var meta = TitleMetadata()
    OMDbSource.apply(dto, imdb: "tt0111161", to: &meta)
    XCTAssertEqual(meta.externalRatings.map(\.kind), [.rottenTomatoes, .metacritic])
    XCTAssertEqual(meta.externalRatings.first?.value, 89)
    XCTAssertEqual(meta.externalRatings.last?.value, 82)
    XCTAssertEqual(meta.relayedIMDbRating, 9.3)
    XCTAssertEqual(meta.relayedIMDbVotes, 3_057_422)
    XCTAssertEqual(meta.boxOfficeUSD, 28_767_189)
    XCTAssertEqual(meta.awardsSummary, "Nominated for 7 Oscars. 21 wins & 42 nominations total")
  }

  func testNotAvailableIsNothing() throws {
    let empty = #"{"Ratings": [], "Metascore": "N/A", "imdbRating": "N/A", "imdbVotes": "N/A", "BoxOffice": "N/A", "Awards": "N/A", "Response": "True"}"#
    let dto = try JSONDecoder().decode(OMDbTitleDTO.self, from: Data(empty.utf8))
    var meta = TitleMetadata()
    OMDbSource.apply(dto, imdb: "tt1", to: &meta)
    XCTAssertTrue(meta.externalRatings.isEmpty)
    XCTAssertNil(meta.relayedIMDbVotes)
    XCTAssertNil(meta.boxOfficeUSD)
    XCTAssertNil(meta.awardsSummary)
  }

  func testTraktOutranksOMDbAndIMDbTakesTheLargerCount() {
    var trakt = TitleMetadata()
    trakt.externalRatings = [ExternalRating(kind: .rottenTomatoes, value: 91, state: "certified")]
    trakt.relayedIMDbRating = 9.2
    trakt.relayedIMDbVotes = 3_000_000
    var omdb = TitleMetadata()
    omdb.externalRatings = [ExternalRating(kind: .rottenTomatoes, value: 89),
                            ExternalRating(kind: .metacritic, value: 82)]
    omdb.relayedIMDbRating = 9.3
    omdb.relayedIMDbVotes = 3_057_422
    omdb.boxOfficeUSD = 28_767_189

    var merged = TitleMetadata()
    merged.merge(trakt)
    merged.merge(omdb)
    XCTAssertEqual(merged.externalRatings.map(\.kind), [.rottenTomatoes, .metacritic])
    XCTAssertEqual(merged.externalRatings.first?.value, 91)
    XCTAssertEqual(merged.relayedIMDbRating, 9.3)
    XCTAssertEqual(merged.relayedIMDbVotes, 3_057_422)
    XCTAssertEqual(merged.boxOfficeUSD, 28_767_189)

    // Fewer votes from OMDb leave Trakt's IMDb copy alone.
    omdb.relayedIMDbVotes = 10
    var older = TitleMetadata()
    older.merge(trakt)
    older.merge(omdb)
    XCTAssertEqual(older.relayedIMDbVotes, 3_000_000)
  }

  func testNumbers() {
    XCTAssertEqual(OMDbSource.number("75%"), 75)
    XCTAssertEqual(OMDbSource.number("8.5/10"), 8.5)
    XCTAssertNil(OMDbSource.number("N/A"))
    XCTAssertEqual(OMDbSource.count("$1,234"), 1234)
    XCTAssertNil(OMDbSource.count("N/A"))
  }
}
