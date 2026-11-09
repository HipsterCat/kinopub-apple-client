//
//  DoubanSourceTests.swift
//
//  The worker's answer (`workers/tmdb-proxy/src/douban.js`), from Frodo's reply for The
//  Shawshank Redemption as Sasha's probe got it (2026-11-09).
//

import XCTest
@testable import KinoPubMetadata

final class DoubanSourceTests: XCTestCase {
  func testWorkerAnswerBecomesScoreAndStats() throws {
    let json = #"""
    {"id": "1292052", "type": "movie", "url": "https://movie.douban.com/subject/1292052/", "year": 1994,
     "rating": {"value": 9.7, "votes": 3363365},
     "distribution": [0.0011, 0.001, 0.0136, 0.1303, 0.8539],
     "watched": 5784685, "wantToWatch": 522249, "watching": 95,
     "ranks": [{"genre": "crime", "betterThan": 0.99}, {"genre": "drama", "betterThan": 0.99}]}
    """#
    let dto = try JSONDecoder().decode(DoubanTitleDTO.self, from: Data(json.utf8))
    var meta = TitleMetadata()
    DoubanSource.apply(dto, to: &meta)
    let score = try XCTUnwrap(meta.externalRatings.first)
    XCTAssertEqual(score.kind, .douban)
    XCTAssertEqual(score.score10, 9.7)
    XCTAssertEqual(score.votes, 3_363_365)
    XCTAssertEqual(score.url?.absoluteString, "https://movie.douban.com/subject/1292052/")
    let stats = try XCTUnwrap(meta.doubanStats)
    XCTAssertEqual(stats.shares.count, 5)
    XCTAssertEqual(stats.watched, 5_784_685)
    XCTAssertEqual(stats.ranks.map(\.genre), ["crime", "drama"])
    XCTAssertFalse(stats.isSeries)
  }

  func testTooFewRatingsIsNoScore() throws {
    let json = #"{"id": "1", "type": "tv", "rating": null, "distribution": null, "watched": 12, "ranks": []}"#
    let dto = try JSONDecoder().decode(DoubanTitleDTO.self, from: Data(json.utf8))
    var meta = TitleMetadata()
    DoubanSource.apply(dto, to: &meta)
    XCTAssertTrue(meta.externalRatings.isEmpty)
    XCTAssertEqual(meta.doubanStats?.watched, 12)
    XCTAssertEqual(meta.doubanStats?.isSeries, true)
  }
}
