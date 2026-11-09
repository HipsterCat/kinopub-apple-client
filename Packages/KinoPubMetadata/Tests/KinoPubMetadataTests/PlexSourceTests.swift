//
//  PlexSourceTests.swift
//
//  Payloads in the shape metadata.provider.plex.tv answered `matches?guid=tmdb://157336`
//  (Interstellar, a cached answer seen 2026-11-09, trimmed) and in the shape Rivulet and
//  Plozz decode for `/commonsensemedia`.
//

import XCTest
@testable import KinoPubMetadata

final class PlexSourceTests: XCTestCase {

  private let matches = """
  {"MediaContainer": {"size": 1, "Metadata": [{
    "ratingKey": "5d7769cefb0d55001f530acd", "type": "movie", "title": "Interstellar",
    "contentRating": "PG-13", "rating": 7.3, "ratingImage": "rottentomatoes://image.rating.ripe",
    "audienceRating": 8.7, "audienceRatingImage": "rottentomatoes://image.rating.upright",
    "imdbRatingCount": 2631416, "publicPagesURL": "https://watch.plex.tv/movie/interstellar",
    "Rating": [{"image": "imdb://image.rating", "type": "audience", "value": 8.7},
               {"image": "rottentomatoes://image.rating.ripe", "type": "critic", "value": 7.3},
               {"image": "rottentomatoes://image.rating.upright", "type": "audience", "value": "8.7"},
               {"image": "themoviedb://image.rating", "type": "audience", "value": 8.5}],
    "CommonSenseMedia": [{"oneLiner": "Epic space adventure.", "AgeRating": [{"age": 11, "rating": 3, "type": "official"}]}]
  }]}}
  """

  private let fullCommonSense = """
  {"MediaContainer": {"CommonSenseMedia": [{
    "oneLiner": "Epic space adventure.", "parentsNeedToKnow": "Some peril and language.",
    "anyGood": "Yes.",
    "AgeRating": [{"age": "11", "rating": 3, "type": "official"}, {"age": 12, "type": "adult"}, {"age": 10, "type": "child"}],
    "ParentalAdvisoryTopic": [{"label": "Violence & Scariness", "positive": false, "rating": 2, "tag": "Peril in space."},
                              {"label": "Positive Messages", "positive": true, "rating": 4}],
    "TalkingPoint": [{"tag": "Why do the astronauts leave?"}]
  }]}}
  """

  func testItemMapsRatingsAgeAndShortCommonSense() throws {
    let item = try XCTUnwrap(JSONDecoder().decode(PlexContainerDTO.self, from: Data(matches.utf8))
      .mediaContainer?.metadata?.first)
    var meta = TitleMetadata()
    PlexSource.apply(item, to: &meta)
    XCTAssertEqual(meta.plexID, "5d7769cefb0d55001f530acd")
    XCTAssertEqual(meta.ageRating, "PG-13")
    XCTAssertEqual(meta.relayedIMDbRating, 8.7)
    XCTAssertEqual(meta.relayedIMDbVotes, 2_631_416)
    XCTAssertEqual(meta.externalRatings.map(\.kind), [.rottenTomatoes, .rottenTomatoesAudience])
    XCTAssertEqual(meta.externalRatings.map(\.value), [73, 87])
    XCTAssertEqual(meta.commonSense?.age, 11)
    XCTAssertEqual(meta.commonSense?.oneLiner, "Epic space adventure.")
    XCTAssertEqual(meta.externalLinks.first?.site, .plex)
  }

  func testFullCommonSenseOutranksTheShortBlock() throws {
    let item = try XCTUnwrap(JSONDecoder().decode(PlexContainerDTO.self, from: Data(matches.utf8))
      .mediaContainer?.metadata?.first)
    var meta = TitleMetadata()
    PlexSource.apply(item, to: &meta)
    let dto = try XCTUnwrap(JSONDecoder().decode(PlexContainerDTO.self, from: Data(fullCommonSense.utf8))
      .mediaContainer?.commonSenseMedia?.first)
    let full = try XCTUnwrap(PlexSource.commonSense(dto))
    let merged = full.richer(than: meta.commonSense)
    XCTAssertEqual(merged.age, 11)
    XCTAssertEqual(merged.parentsAge, 12)
    XCTAssertEqual(merged.kidsAge, 10)
    XCTAssertEqual(merged.topics.map(\.label), ["Violence & Scariness", "Positive Messages"])
    XCTAssertEqual(merged.topics.last?.isPositive, true)
    XCTAssertEqual(merged.talkingPoints, ["Why do the astronauts leave?"])
    // The short block never replaces the full one.
    XCTAssertEqual(meta.commonSense?.richer(than: full).parentsNeedToKnow, "Some peril and language.")
  }
}
