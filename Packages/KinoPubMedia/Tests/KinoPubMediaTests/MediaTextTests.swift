//
//  MediaTextTests.swift
//
//  One wording per fact and length, in both languages — the user's spec of 2026-10-03,
//  line by line.
//

import XCTest
@testable import KinoPubMedia

final class MediaTextTests: XCTestCase {

  // MARK: - Episodes

  private let many = EpisodeText(season: 1, number: 1)
  private let manyNamed = EpisodeText(season: 1, number: 1, name: "Pilot")
  private let sole = EpisodeText(season: 1, number: 1, seasonCount: 1)
  private let soleNamed = EpisodeText(season: 1, number: 1, name: "Pilot", seasonCount: 1)

  func testShort() {
    XCTAssertEqual(many.formatted(.short, language: .en), "S1, E1")
    XCTAssertEqual(many.formatted(.short, language: .ru), "1 сезон, 1 серия")
    XCTAssertEqual(sole.formatted(.short, language: .en), "E1")
    XCTAssertEqual(sole.formatted(.short, language: .ru), "1 серия")
    XCTAssertEqual(manyNamed.formatted(.short, language: .en), "S1, E1", "short never names")
  }

  /// The player's subtitle.
  func testMedium() {
    XCTAssertEqual(many.formatted(.medium, language: .en), "Season 1, Episode 1")
    XCTAssertEqual(manyNamed.formatted(.medium, language: .en), "S1, E1: Pilot")
    XCTAssertEqual(many.formatted(.medium, language: .ru), "1 сезон, 1 серия")
    XCTAssertEqual(manyNamed.formatted(.medium, language: .ru), "1 сезон, 1 серия: Pilot")
    XCTAssertEqual(sole.formatted(.medium, language: .en), "Episode 1")
    XCTAssertEqual(soleNamed.formatted(.medium, language: .en), "Episode 1: Pilot")
    XCTAssertEqual(sole.formatted(.medium, language: .ru), "1 серия")
    XCTAssertEqual(soleNamed.formatted(.medium, language: .ru), "1 серия: Pilot")
  }

  func testLong() {
    XCTAssertEqual(manyNamed.formatted(.long, language: .en), "Season 1, Episode 1: Pilot")
    XCTAssertEqual(soleNamed.formatted(.long, language: .en), "Episode 1: Pilot")
    XCTAssertEqual(many.accessibilityLabel(language: .en), "Season 1, Episode 1")
  }

  /// Only *one* season, and it is the *first*: a show whose only uploaded season is its
  /// third still says so.
  func testTheSeasonDropsOnlyForASoleFirstSeason() {
    XCTAssertEqual(EpisodeText(season: 3, number: 2, seasonCount: 1).formatted(.short, language: .en),
                   "S3, E2")
    XCTAssertEqual(EpisodeText(season: 1, number: 2, seasonCount: 2).formatted(.short, language: .en),
                   "S1, E2")
    XCTAssertEqual(EpisodeText(season: 1, number: 2).formatted(.short, language: .en), "S1, E2",
                   "an unknown count says the season")
    XCTAssertEqual(EpisodeText(season: nil, number: 9).formatted(.long, language: .ru), "9 серия",
                   "a season's own rail: the season goes without saying")
  }

  /// «Эпизод 1» is the number again, not a name.
  func testAPlaceholderIsNoName() {
    XCTAssertNil(EpisodeText(season: 1, number: 1, name: "Эпизод 1").name)
    XCTAssertNil(EpisodeText(season: 1, number: 1, name: "Серія 1").name)
    XCTAssertEqual(EpisodeText(season: 1, number: 1, name: "Эпизод 1").formatted(.medium, language: .ru),
                   "1 сезон, 1 серия")
  }

  func testSurfacesPickTheirLength() {
    XCTAssertEqual(manyNamed.text(for: .playerSubtitle, language: .en), "S1, E1: Pilot")
    XCTAssertEqual(manyNamed.text(for: .continueWatchingCard, language: .en), "S1, E1")
    XCTAssertEqual(EpisodeText(season: nil, number: 9).text(for: .episodeTile, language: .en),
                   "Episode 9")
  }

  /// The detail page: the season switch is beside the tile, so the season goes unsaid
  /// (user's spec, 2026-10-03).
  func testAListItem() {
    let named = EpisodeText(season: 2, number: 7, name: "Rainbow")
    XCTAssertEqual(named.listItem(language: .en), "7. Rainbow")
    XCTAssertEqual(named.text(for: .episodeTile, language: .ru), "7. Rainbow")
    XCTAssertEqual(EpisodeText(season: 2, number: 7).listItem(language: .ru), "Серия 7")
    XCTAssertEqual(EpisodeText(season: 2, number: 7, name: "Эпизод 7").listItem(language: .en),
                   "Episode 7", "a placeholder is no name")
  }

  /// Anywhere else: the season is said, the name after a colon.
  func testTitled() {
    XCTAssertEqual(manyNamed.text(for: .upNextTile, language: .en), "S1, E1: Pilot")
    XCTAssertEqual(manyNamed.text(for: .upNextTile, language: .ru), "1 сезон, 1 серия: Pilot")
    XCTAssertEqual(many.text(for: .upNextTile, language: .en), "S1, E1")
    XCTAssertEqual(soleNamed.text(for: .upNextTile, language: .ru), "1 серия: Pilot")
  }

  func testSeason() {
    XCTAssertEqual(SeasonText(2).formatted(.long, language: .en), "Season 2")
    XCTAssertEqual(SeasonText(2).formatted(.short, language: .en), "S2")
    XCTAssertEqual(SeasonText(2).formatted(.long, language: .ru), "2 сезон")
  }

  // MARK: - Runtime

  private let film = RuntimeText(seconds: (60 + 53) * 60)
  private let episode = RuntimeText(seconds: 53 * 60)

  func testShortRuntime() {
    XCTAssertEqual(film.formatted(.short, language: .ru), "1ч 53м")
    XCTAssertEqual(episode.formatted(.short, language: .ru), "53м")
    XCTAssertEqual(film.formatted(.short, language: .en), "1h 53m")
    XCTAssertEqual(RuntimeText(seconds: 2 * 3600).formatted(.short, language: .ru), "2ч")
  }

  func testMediumRuntime() {
    XCTAssertEqual(film.formatted(.medium, language: .ru), "1ч 53 мин")
    XCTAssertEqual(RuntimeText(seconds: (120 + 53) * 60).formatted(.medium, language: .ru), "2ч 53 мин")
    XCTAssertEqual(episode.formatted(.medium, language: .ru), "53 мин")
    XCTAssertEqual(film.formatted(.medium, language: .en), "1h 53 min")
  }

  /// The system's wording, with its plural forms.
  func testLongRuntimeIsTheSystems() {
    XCTAssertEqual(film.formatted(.long, language: .ru), "1 час 53 минуты")
    XCTAssertEqual(RuntimeText(seconds: 5 * 3600 + 60).formatted(.long, language: .ru), "5 часов 1 минута")
    XCTAssertEqual(film.formatted(.long, language: .en), "1 hour, 53 minutes")
    XCTAssertEqual(film.accessibilityLabel(language: .ru), film.formatted(.long, language: .ru))
  }

  func testRuntimeEdges() {
    XCTAssertNil(RuntimeText(seconds: 0).formatted(.short))
    XCTAssertEqual(RuntimeText(seconds: 20).formatted(.short, language: .en), "1m",
                   "under a minute is a minute")
    XCTAssertEqual(RuntimeText(seconds: (36 * 60 + 4) * 60).formatted(.short, language: .ru),
                   "1д 12ч 4м")
    XCTAssertEqual(RuntimeText(seconds: 105 * 60).minutesOnly(language: .ru), "105 мин")
  }

  func testRemaining() {
    let left = RemainingText(progress: 0.5, durationSeconds: 106 * 60)
    XCTAssertEqual(left.formatted(.medium, language: .ru), "Ещё 53 мин")
    XCTAssertEqual(left.formatted(.short, language: .en), "53m left")
    XCTAssertEqual(RemainingText(progress: 1, durationSeconds: 3600).formatted(.medium, language: .en),
                   "1 min left", "a minute is always left")
  }
}
