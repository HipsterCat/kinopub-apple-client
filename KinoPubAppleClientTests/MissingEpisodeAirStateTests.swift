//
//  MissingEpisodeAirStateTests.swift
//  KinoPubAppleClientTests
//
//  Episodes TMDB lists and kino.pub does not have (Sasha, 2026-10-03): aired in the last
//  three days → «Сегодня», «Вчера», «Позавчера», «3 дня назад» on the card; no date →
//  «Позже»; long aired → the lock alone. And the date Follow waits for: the next episode
//  of the season kino.pub is on, ahead or already aired.
//

import XCTest
import KinoPubMetadata
@testable import KinoPub

@MainActor
final class MissingEpisodeAirStateTests: XCTestCase {

  private let russian = Locale(identifier: "ru_RU")

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
    return calendar
  }

  /// Saturday 3 October 2026, 21:30 Moscow time — late, so "today" and "yesterday" are
  /// calendar days, not 24-hour spans.
  private var now: Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 21, minute: 30))!
  }

  private func day(_ offset: Int, hour: Int = 9) -> Date {
    let start = calendar.startOfDay(for: now)
    let shifted = calendar.date(byAdding: .day, value: offset, to: start)!
    return calendar.date(byAdding: .hour, value: hour, to: shifted)!
  }

  private func state(_ offset: Int?) -> MissingEpisodeAirState {
    MissingEpisodeAirState(airDate: offset.map { day($0) }, now: now, calendar: calendar)
  }

  // MARK: - State

  func testStatesByCalendarDay() {
    XCTAssertEqual(state(2), .upcoming(day(2)))
    XCTAssertEqual(state(1), .upcoming(day(1)))
    XCTAssertEqual(state(0), .justAired(day(0), daysAgo: 0))
    XCTAssertEqual(state(-1), .justAired(day(-1), daysAgo: 1))
    XCTAssertEqual(state(-3), .justAired(day(-3), daysAgo: 3))
    XCTAssertEqual(state(-4), .aired(day(-4)))
    XCTAssertEqual(state(-514), .aired(day(-514)))
    XCTAssertEqual(state(nil), .undated)
  }

  /// Late tonight, an episode dated early this morning aired *today*, not "a day ago".
  func testTodayIsTheCalendarDayNotTwentyFourHours() {
    let early = MissingEpisodeAirState(airDate: day(0, hour: 0), now: now, calendar: calendar)
    XCTAssertEqual(early, .justAired(day(0, hour: 0), daysAgo: 0))
  }

  // MARK: - Badge

  func testJustAiredBadgesInRussian() {
    XCTAssertEqual(state(0).badge(now: now, locale: russian), "Сегодня")
    XCTAssertEqual(state(-1).badge(now: now, locale: russian), "Вчера")
    XCTAssertEqual(state(-2).badge(now: now, locale: russian), "Позавчера")
    XCTAssertEqual(state(-3).badge(now: now, locale: russian), "3 дня назад")
  }

  func testLongAiredEpisodeHasNoBadgeOnlyTheLock() {
    XCTAssertNil(state(-4).badge(now: now, locale: russian))
    XCTAssertNil(state(-514).badge(now: now, locale: russian))
  }

  func testUndatedEpisodeSaysLater() {
    let badge = state(nil).badge(now: now, locale: russian)
    XCTAssertNotNil(badge)
    XCTAssertFalse(badge?.isEmpty ?? true)
  }

  /// Noon to noon, so the day count is the same in whatever time zone the simulator runs.
  func testUpcomingBadgeStartsWithACapital() throws {
    let badge = try XCTUnwrap(MissingEpisodeAirState.upcoming(day(1, hour: 12))
      .badge(now: day(0, hour: 12), locale: russian))
    XCTAssertEqual(badge, "Завтра")
  }

  // MARK: - Select

  func testSelectSaysClockForWhatIsComingAndLockForWhatKinoPubLacks() {
    XCTAssertEqual(state(2).message.systemImage, "clock")
    XCTAssertEqual(state(nil).message.systemImage, "clock")
    XCTAssertEqual(state(0).message.systemImage, "lock")
    XCTAssertEqual(state(-514).message.systemImage, "lock")
  }

  // MARK: - What Follow waits for

  private func schedule(_ days: [Int?], season: Int = 2) -> [EpisodeSchedule] {
    days.enumerated().map { index, offset in
      EpisodeSchedule(episodeNumber: index + 1, seasonNumber: season, airDate: offset.map { day($0) })
    }
  }

  func testAwaitedEpisodeIsTheNextOneInTheSchedule() {
    let date = MediaItemModel.awaitedEpisodeAirDate(kinoEpisodeNumbers: [1, 2, 3],
                                                    schedule: schedule([-30, -23, -16, 9, 16]),
                                                    nextEpisode: nil,
                                                    tmdbSeason: 2)
    XCTAssertEqual(date, day(9))
  }

  /// Aired weeks ago and still not on kino.pub: still the thing to follow.
  func testAwaitedEpisodeMayHaveAiredAlready() {
    let date = MediaItemModel.awaitedEpisodeAirDate(kinoEpisodeNumbers: [1, 2],
                                                    schedule: schedule([-60, -53, -46]),
                                                    nextEpisode: nil,
                                                    tmdbSeason: 2)
    XCTAssertEqual(date, day(-46))
  }

  func testNoDateNoAwaitedEpisode() {
    XCTAssertNil(MediaItemModel.awaitedEpisodeAirDate(kinoEpisodeNumbers: [1, 2, 3],
                                                      schedule: schedule([-30, -23, -16, nil]),
                                                      nextEpisode: nil,
                                                      tmdbSeason: 2))
    XCTAssertNil(MediaItemModel.awaitedEpisodeAirDate(kinoEpisodeNumbers: [1, 2, 3],
                                                      schedule: schedule([-30, -23, -16]),
                                                      nextEpisode: nil,
                                                      tmdbSeason: 2))
  }

  /// Before the season's schedule loads, TMDB's next-to-air episode answers — when it is
  /// in the same season.
  func testNextEpisodeAnswersBeforeTheScheduleLoads() {
    let sameSeason = EpisodeRef(seasonNumber: 2, episodeNumber: 4, airDate: day(5))
    XCTAssertEqual(MediaItemModel.awaitedEpisodeAirDate(kinoEpisodeNumbers: [1, 2, 3],
                                                        schedule: nil,
                                                        nextEpisode: sameSeason,
                                                        tmdbSeason: 2),
                   day(5))
  }

  /// The next episode opens another season: not "within the last watched season".
  func testNextSeasonDoesNotCount() {
    let nextSeason = EpisodeRef(seasonNumber: 3, episodeNumber: 1, airDate: day(5))
    XCTAssertNil(MediaItemModel.awaitedEpisodeAirDate(kinoEpisodeNumbers: [1, 2, 3],
                                                      schedule: schedule([-30, -23, -16]),
                                                      nextEpisode: nextSeason,
                                                      tmdbSeason: 2))
  }
}
