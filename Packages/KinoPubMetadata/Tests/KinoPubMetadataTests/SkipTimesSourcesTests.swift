//
//  SkipTimesSourcesTests.swift
//
//  Payloads in the shapes SkipDB's docs (skipdb.tv/docs) and TheIntroDB's npm SDK 4.0.0
//  describe, 2026-11-09. Neither host is reachable from the cloud runner: the live calls
//  are checked on a device through Diagnostics.
//

import XCTest
@testable import KinoPubMetadata

final class SkipTimesSourcesTests: XCTestCase {

  private let breakingBad = MediaIdentity(kinopubId: 1, imdb: "tt0903747", kinopoisk: nil,
                                          title: "Во все тяжкие", originalTitle: "Breaking Bad",
                                          year: 2008, isSeries: true)

  func testSkipDBMapsOutroToCreditsAndDropsNulls() throws {
    let body = """
    {"imdb_id": "tt0903747", "season": 1, "episode": 1, "intro_length_estimate_ms": null,
     "segments": {
       "intro": {"start_ms": 395000, "end_ms": 481000, "match": "duration", "adjusted": true,
                 "offset_ms": 0, "confidence": 0.9},
       "recap": null,
       "outro": {"start_ms": 3450000, "end_ms": 3555000, "match": "duration", "adjusted": false,
                 "offset_ms": 0, "confidence": 0.7},
       "preview": null}}
    """
    let dto = try SkipTimes.decoder.decode(SkipDBResponseDTO.self, from: Data(body.utf8))
    let segments = SkipDBSource.segments(from: dto)
    XCTAssertEqual(segments.intro, .init(startMs: 395_000, endMs: 481_000, source: .skipDB))
    XCTAssertEqual(segments.credits?.startMs, 3_450_000)
    XCTAssertNil(segments.recap)
    XCTAssertNil(segments.preview)
  }

  func testSkipDBURLSendsWholeSeconds() {
    let url = SkipDBSource.url(identity: breakingBad, season: 1, episode: 1, durationMs: 3_499_600)
    XCTAssertEqual(url?.absoluteString,
                   "https://api.skipdb.tv/api/segments?imdb_id=tt0903747&season=1&episode=1&duration=3499")
  }

  func testTheIntroDBNullEdgesAreTheStreamEdges() throws {
    let body = """
    {"tvdb_id": 81189, "type": "tv", "season": 1, "episode": 1,
     "intro": [{"start_ms": null, "end_ms": 62000}],
     "credits": [{"start_ms": 3400000, "end_ms": null, "confidence": 0.4},
                 {"start_ms": 3420000, "end_ms": null, "confidence": 0.8}]}
    """
    let dto = try SkipTimes.decoder.decode(TheIntroDBMediaDTO.self, from: Data(body.utf8))
    let segments = TheIntroDBSource.segments(from: dto)
    XCTAssertEqual(segments.intro, .init(startMs: 0, endMs: 62_000, source: .introdb))
    XCTAssertEqual(segments.credits, .init(startMs: 3_420_000, endMs: nil, source: .introdb))
  }

  func testTheIntroDBFilmTakesNoEpisodeOrRuntime() {
    let film = MediaIdentity(kinopubId: 2, imdb: "tt0133093", kinopoisk: nil, title: "Матрица",
                             originalTitle: "The Matrix", year: 1999, isSeries: false)
    let url = TheIntroDBSource.url(identity: film, season: nil, episode: nil, durationMs: 8_160_000)
    XCTAssertEqual(url?.absoluteString, "https://api.theintrodb.org/v4/media?imdb_id=tt0133093")
  }

  func testFirstSourceWinsAKindTheNextFillsTheRest() {
    var skipDB = SkipSegments()
    skipDB[.intro] = .init(startMs: 10_000, endMs: 70_000, source: .skipDB)
    var introDB = SkipSegments()
    introDB[.intro] = .init(startMs: 12_000, endMs: 71_000, source: .introdb)
    introDB[.recap] = .init(startMs: 0, endMs: 9_000, source: .introdb)
    let merged = skipDB.filling(from: introDB)
    XCTAssertEqual(merged.intro?.source, .skipDB)
    XCTAssertEqual(merged.recap?.source, .introdb)
  }

  func testSegmentsUnderASecondAreDropped() {
    var segments = SkipSegments()
    segments[.intro] = .init(startMs: 5_000, endMs: 5_400, source: .skipDB)
    XCTAssertTrue(segments.isEmpty)
  }
}
