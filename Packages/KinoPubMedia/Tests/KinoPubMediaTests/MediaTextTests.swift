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
    // The detail page's info list: short, and the minutes total from an hour on.
    XCTAssertEqual(RuntimeText(seconds: 105 * 60).withMinutesTotal(language: .ru), "1ч 45м (105 мин)")
    XCTAssertEqual(RuntimeText(seconds: 360 * 60).withMinutesTotal(language: .en), "6h (360 min)")
    XCTAssertEqual(RuntimeText(seconds: 39 * 60).withMinutesTotal(language: .en), "39m")
    XCTAssertNil(RuntimeText(seconds: 0).withMinutesTotal())
  }

  func testRemaining() {
    let left = RemainingText(progress: 0.5, durationSeconds: 106 * 60)
    XCTAssertEqual(left.formatted(.medium, language: .ru), "Ещё 53 мин")
    XCTAssertEqual(left.formatted(.short, language: .en), "53m left")
    XCTAssertEqual(RemainingText(progress: 1, durationSeconds: 3600).formatted(.medium, language: .en),
                   "1 min left", "a minute is always left")
  }

  // MARK: - Seasons, a title's line

  func testSeasonCountIsPluralCorrect() {
    let ru = [1: "1 сезон", 3: "3 сезона", 5: "5 сезонов", 11: "11 сезонов", 21: "21 сезон",
              22: "22 сезона", 112: "112 сезонов"]
    for (count, text) in ru {
      XCTAssertEqual(SeasonCountText(count)?.formatted(language: .ru), text)
    }
    XCTAssertEqual(SeasonCountText(1)?.formatted(language: .en), "1 season")
    XCTAssertEqual(SeasonCountText(3)?.formatted(language: .en), "3 seasons")
    XCTAssertNil(SeasonCountText(0))
    XCTAssertNil(SeasonCountText(nil))
  }

  /// A followed series says how many episodes are still unwatched under its cover.
  func testEpisodesLeftArePluralCorrectInBothLanguages() {
    let ru = [1: "1 серия", 2: "2 серии", 4: "4 серии", 5: "5 серий", 11: "11 серий",
              12: "12 серий", 21: "21 серия", 22: "22 серии", 111: "111 серий", 171: "171 серия"]
    for (count, text) in ru {
      XCTAssertEqual(EpisodesLeftText(count)?.formatted(language: .ru), text)
    }
    XCTAssertEqual(EpisodesLeftText(1)?.formatted(language: .en), "1 episode")
    XCTAssertEqual(EpisodesLeftText(3)?.formatted(language: .en), "3 episodes")
    XCTAssertNil(EpisodesLeftText(0), "nothing left says nothing")
    XCTAssertNil(EpisodesLeftText(nil))
  }

  /// The Library header: «156 непросмотренных серий», including the adjective.
  func testUnwatchedEpisodeHeaderCountsAgreeInRussian() {
    let ru = [1: "1 непросмотренная серия", 2: "2 непросмотренные серии",
              4: "4 непросмотренные серии", 5: "5 непросмотренных серий",
              11: "11 непросмотренных серий", 21: "21 непросмотренная серия",
              22: "22 непросмотренные серии", 156: "156 непросмотренных серий"]
    for (count, text) in ru {
      XCTAssertEqual(UnwatchedEpisodesCountText(count).formatted(language: .ru), text)
    }
    XCTAssertEqual(UnwatchedEpisodesCountText(1).formatted(language: .en), "1 unwatched episode")
    XCTAssertEqual(UnwatchedEpisodesCountText(156).formatted(language: .en), "156 unwatched episodes")
  }

  func testAFolderHeaderCountSaysTotal() {
    XCTAssertEqual(TotalCountText(694).formatted(language: .ru), "Всего 694")
    XCTAssertEqual(TotalCountText(694).formatted(language: .en), "Total 694")
    XCTAssertEqual(TotalCountText(1).formatted(language: .ru), "Всего 1")
  }

  func testAContinueHeaderCountSaysUnfinished() {
    XCTAssertEqual(UnfinishedCountText(14).formatted(language: .ru), "14 недосмотрено")
    XCTAssertEqual(UnfinishedCountText(1).formatted(language: .ru), "1 недосмотрено")
    XCTAssertEqual(UnfinishedCountText(14).formatted(language: .en), "14 unfinished")
  }

  func testAFilmsLineIsYearRuntimeGenresCountry() {
    let film = MediaEntity(kind: .movie, release: .year(2025), runtime: 115 * 60,
                           countries: ["Япония"])
    var withGenres = film
    withGenres.genres = [GenreVocabulary.genre(id: "action")!, GenreVocabulary.genre(id: "drama")!,
                         GenreVocabulary.genre(id: "comedy")!]
    XCTAssertEqual(TitleMetaLine(withGenres).formatted(language: .ru),
                   "2025   1ч 55м   Боевик   Япония", "one genre, the primary (D7)")
  }

  /// A series says how many seasons, never every episode summed as a runtime.
  func testASeriesLineCountsSeasons() {
    let show = MediaEntity(kind: .show, seasonCount: 3, release: .year(2020), runtime: 99_999)
    XCTAssertEqual(TitleMetaLine(show).formatted(language: .en), "2020   3 seasons")
    let listed = MediaEntity(kind: .show, release: .year(2020), runtime: 99_999)
    XCTAssertEqual(TitleMetaLine(listed).formatted(language: .en), "2020",
                   "a listing knows no count, and says no runtime")
  }

  func testHistoryEventTimeIsDayMonthAtClock() {
    let timeZone = TimeZone(identifier: "Europe/Moscow")!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 27, hour: 20, minute: 54))!
    XCTAssertEqual(HistoryEventText(date)?.formatted(language: .ru, timeZone: timeZone),
                   "27 января в 20:54")
    XCTAssertNil(HistoryEventText(nil))
  }

  func testHistoryDayTitleIsTodayYesterdayOrTheDate() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 12))!
    let today = calendar.startOfDay(for: now)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
    let older = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
    XCTAssertEqual(HistoryDayText(today).formatted(language: .ru, calendar: calendar, now: now), "Сегодня")
    XCTAssertEqual(HistoryDayText(yesterday).formatted(language: .ru, calendar: calendar, now: now), "Вчера")
    XCTAssertEqual(HistoryDayText(older).formatted(language: .ru, calendar: calendar, now: now),
                   "10 сентября 2026")
    XCTAssertEqual(HistoryDayText(today).formatted(language: .en, calendar: calendar, now: now), "Today")
    XCTAssertEqual(HistoryDayText(yesterday).formatted(language: .en, calendar: calendar, now: now), "Yesterday")
    XCTAssertEqual(HistoryDayText(older).formatted(language: .en, calendar: calendar, now: now),
                   "10 September 2026")
  }
}
