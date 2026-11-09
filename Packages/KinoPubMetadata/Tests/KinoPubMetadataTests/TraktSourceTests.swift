//
//  TraktSourceTests.swift
//
//  Payloads are the examples in Trakt's own contract (trakt/trakt-api,
//  `ratingsResponseSchema.ts`, `movieRatingsResponseSchema.ts`, `commentResponseSchema.ts`).
//

import XCTest
@testable import KinoPubMetadata

final class TraktSourceTests: XCTestCase {

  private let movieRatings = """
  {
    "imdb": {"link": "https://www.imdb.com/title/tt37287335", "rating": 7.9, "votes": 269113},
    "letterboxd": {"link": "https://letterboxd.com/film/obsession-2025", "rating": 4.12, "votes": 3633569},
    "mal": {"link": null, "rating": null, "votes": 0},
    "metascore": {"link": "https://www.imdb.com/title/tt37287335/criticreviews", "rating": 77},
    "rotten_tomatoes": {"link": "https://www.rottentomatoes.com/m/obsession_2025", "rating": 94,
                        "state": "fresh", "user_rating": 41, "user_state": "spilled"},
    "tmdb": {"link": "https://www.themoviedb.org/movie/1339713", "rating": 8.251, "votes": 3739},
    "trakt": {"distribution": {"1": 143, "10": 8567}, "rating": 8.29481, "votes": 24789}
  }
  """

  func testExtendedRatingsMapEverySourceThatHasAScore() throws {
    let dto = try JSONDecoder().decode(TraktRatingsDTO.self, from: Data(movieRatings.utf8))
    let traktURL = URL(string: "https://trakt.tv/movies/obsession-2025")
    let ratings = TraktSource.ratings(from: dto, traktURL: traktURL)
    XCTAssertEqual(ratings.map(\.kind), [.trakt, .rottenTomatoes, .rottenTomatoesAudience, .metacritic, .letterboxd])

    let trakt = try XCTUnwrap(ratings.first { $0.kind == .trakt })
    XCTAssertEqual(trakt.votes, 24789)
    XCTAssertEqual(trakt.url, traktURL)

    let critics = try XCTUnwrap(ratings.first { $0.kind == .rottenTomatoes })
    XCTAssertTrue(critics.isPositive)
    XCTAssertEqual(critics.score10, 9.4, accuracy: 0.001)

    let audience = try XCTUnwrap(ratings.first { $0.kind == .rottenTomatoesAudience })
    XCTAssertFalse(audience.isPositive)

    let letterboxd = try XCTUnwrap(ratings.first { $0.kind == .letterboxd })
    XCTAssertEqual(letterboxd.score10, 8.24, accuracy: 0.001)
  }

  func testDistributionAndRelayedIMDb() throws {
    let dto = try JSONDecoder().decode(TraktRatingsDTO.self, from: Data(movieRatings.utf8))
    XCTAssertEqual(TraktSource.distribution(from: dto), [1: 143, 10: 8567])
    XCTAssertEqual(dto.imdb?.votes, 269113)
  }

  func testStatsAndSentimentsDecode() throws {
    let stats = #"{"watchers": 94800, "plays": 105100, "collectors": 20000, "comments": 120, "lists": 34900, "votes": 32556, "favorited": 1100, "recommended": 900}"#
    let decoded = try JSONDecoder().decode(TraktStatsDTO.self, from: Data(stats.utf8))
    XCTAssertEqual(decoded.lists, 34900)
    XCTAssertEqual(decoded.favorited, 1100)
    let sentiments = #"{"good": [{"sentiment": "Strong performances", "comment_ids": [1]}], "bad": [{"sentiment": "Predictable plot"}], "analyzed_at": "2025-03-01T12:00:00.000Z", "comment_count": 42}"#
    let insights = try JSONDecoder().decode(TraktSentimentsDTO.self, from: Data(sentiments.utf8))
    XCTAssertEqual(insights.good?.map(\.sentiment), ["Strong performances"])
    XCTAssertEqual(insights.commentCount, 42)
    XCTAssertNotNil(insights.analyzedAt.flatMap(TraktSource.parseDate))
  }

  func testPlainRatingsCarryTraktsScoreAtTheTopLevel() throws {
    let plain = #"{"rating": 8.11, "votes": 15928, "distribution": {"1": 122}}"#
    let dto = try JSONDecoder().decode(TraktRatingsDTO.self, from: Data(plain.utf8))
    XCTAssertEqual(TraktSource.ratings(from: dto, traktURL: nil).map(\.kind), [.trakt])
  }

  func testUnratedTitleHasNoTraktScore() throws {
    let empty = #"{"trakt": {"rating": 0, "votes": 0, "distribution": {}}, "rotten_tomatoes": null}"#
    let dto = try JSONDecoder().decode(TraktRatingsDTO.self, from: Data(empty.utf8))
    XCTAssertTrue(TraktSource.ratings(from: dto, traktURL: nil).isEmpty)
  }

  private func comment(id: Int, text: String, spoiler: Bool = false, language: String = "en",
                       rating: Int? = 8) -> String {
    """
    {"id": \(id), "parent_id": 0, "created_at": "2025-03-01T12:00:00.000Z",
     "updated_at": "2025-03-01T12:00:00.000Z", "comment": "\(text)", "spoiler": \(spoiler),
     "review": false, "replies": 0, "likes": \(id), "language": "\(language)",
     "user_rating": \(rating.map(String.init) ?? "null"),
     "user_stats": {"rating": null, "play_count": 1, "completed_count": 1},
     "user": {"username": "user\(id)", "private": false, "deleted": false, "name": "",
              "ids": {"slug": "user\(id)", "trakt": \(id)}}}
    """
  }

  func testCommentsBecomeReviewsWithoutSpoilersAppLanguageFirst() throws {
    let long = String(repeating: "A thoughtful paragraph about the film. ", count: 3)
    let json = "[" + [
      comment(id: 1, text: long),
      comment(id: 2, text: long, spoiler: true),
      comment(id: 3, text: "[spoiler]He dies[/spoiler] " + long),
      comment(id: 4, text: "Great!"),
      comment(id: 5, text: long, language: "ru", rating: 3),
    ].joined(separator: ",") + "]"
    let dto = try JSONDecoder().decode([TraktCommentDTO].self, from: Data(json.utf8))
    let reviews = TraktSource.reviews(from: dto, preferredLanguage: "ru")
    XCTAssertEqual(reviews.map(\.sourceId), [5, 1])
    XCTAssertEqual(reviews.first?.sentiment, "NEGATIVE")
    XCTAssertEqual(reviews.last?.sentiment, "POSITIVE")
    XCTAssertEqual(reviews.first?.source, .trakt)
    // An empty display name falls back to the username.
    XCTAssertEqual(reviews.first?.author, "user5")
    XCTAssertNotNil(reviews.first?.postedAt)
  }

  func testTraktReviewsFollowKinopoisksAndJoinTheCounts() {
    var kinopoisk = TitleMetadata()
    kinopoisk.reviews = [Review(author: "КП", title: "", body: "Отзыв", sentiment: "POSITIVE")]
    kinopoisk.reviewsSummary = ReviewsSummary(total: 11, positive: 7, negative: 1, neutral: 3)
    var trakt = TitleMetadata()
    trakt.reviews = [Review(author: "t", title: "", body: "Review", sentiment: "NEGATIVE", source: .trakt)]

    var merged = TitleMetadata()
    merged.merge(kinopoisk)
    merged.merge(trakt)
    XCTAssertEqual(merged.reviews.map(\.author), ["КП", "t"])
    XCTAssertEqual(merged.reviewsSummary, ReviewsSummary(total: 12, positive: 7, negative: 2, neutral: 3))

    // Trakt answering first changes nothing about the order.
    var reversed = TitleMetadata()
    reversed.merge(trakt)
    reversed.merge(kinopoisk)
    XCTAssertEqual(reversed.reviews.map(\.author), ["КП", "t"])
    XCTAssertEqual(reversed.reviewsSummary, ReviewsSummary(total: 12, positive: 7, negative: 2, neutral: 3))
  }
}
