//
//  EpisodeGridMatchTests.swift
//

import XCTest
@testable import KinoPubMetadata

final class EpisodePlayabilityTests: XCTestCase {

  private let now = Date(timeIntervalSince1970: 1_762_000_000)

  private func day(_ offset: Int) -> Date {
    Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: now) ?? now
  }

  /// Dexter S2E1: the file is up, the published premiere says tomorrow. That is a
  /// date lag, not a lock and not a «Премьера» badge.
  func testAPlayableFileStaysPlayableWhenThePremiereIsTomorrow() {
    let decision = EpisodePlayability.decision(onService: true, airDate: day(1), now: now)
    XCTAssertEqual(decision, .playable(premiere: false))
  }

  func testAPlayableFileAWeekOutIsStillADateLag() {
    let decision = EpisodePlayability.decision(onService: true, airDate: day(7), now: now)
    XCTAssertEqual(decision, .playable(premiere: false))
  }

  /// Far enough ahead that the file really did land early.
  func testAnEarlyDropStaysPlayableAndWearsPremiere() {
    let decision = EpisodePlayability.decision(onService: true, airDate: day(8), now: now)
    XCTAssertEqual(decision, .playable(premiere: true))
  }

  func testAnEpisodeKinoPubDoesNotHaveStaysUnavailable() {
    XCTAssertEqual(EpisodePlayability.decision(onService: false, airDate: day(1), now: now),
                   .unavailable)
    XCTAssertEqual(EpisodePlayability.decision(onService: false, airDate: nil, now: now),
                   .unavailable)
  }

  func testAListedFileOrARuntimeCountsAsOnTheService() {
    XCTAssertTrue(EpisodePlayability.onService(fileCount: 1, durationSeconds: 0))
    XCTAssertTrue(EpisodePlayability.onService(fileCount: 0, durationSeconds: 52 * 60))
    XCTAssertFalse(EpisodePlayability.onService(fileCount: 0, durationSeconds: 0))
  }
}

final class EpisodeGridMatchTests: XCTestCase {

  private func kino(block: Int, titled: Int?, number: Int, title: String,
                    runtime: Int, blockNumber: Int? = nil) -> EpisodeGridMatch.KinoEpisode {
    EpisodeGridMatch.KinoEpisode(blockID: block,
                                 blockNumber: blockNumber ?? block,
                                 titledNumber: titled,
                                 number: number,
                                 title: title,
                                 runtimeMinutes: runtime)
  }

  private func official(_ source: EpisodeGridMatch.Source = .tmdb,
                        season: Int, number: Int, title: String,
                        runtime: Int) -> EpisodeGridMatch.OfficialEpisode {
    EpisodeGridMatch.OfficialEpisode(source: source, season: season, number: number,
                                     title: title, runtimeMinutes: runtime)
  }

  /// IMDb's name and runtime win when TMDB's row for the same slot is a different episode.
  func testIMDbBeatsADisagreeingTMDBRow() {
    let grid = [
      official(.tmdb, season: 1, number: 1, title: "Другое", runtime: 40),
      official(.imdb, season: 1, number: 1, title: "Pilot", runtime: 52),
    ]
    let result = EpisodeGridMatch.align(
      kino: [kino(block: 1, titled: 1, number: 1, title: "Pilot", runtime: 52)],
      official: grid)
    let hit = try? XCTUnwrap(result.hits.first)
    XCTAssertEqual(hit?.official.source, .imdb)
    XCTAssertEqual(hit?.official.titles.contains("Pilot"), true)
    XCTAssertTrue(result.unmatchedKino.isEmpty)
  }

  /// Russian and English of one episode are one slot, so the English title does not
  /// become a hole beside the Russian match.
  func testTwoLanguagesOfOneEpisodeAreOneSlot() {
    let grid = [
      official(.tmdb, season: 2, number: 1, title: "Рискованный бизнес", runtime: 52),
      EpisodeGridMatch.OfficialEpisode(source: .tmdb, season: 2, number: 1,
                                       title: "Risky Business", runtimeMinutes: 52),
    ]
    let collapsed = EpisodeGridMatch.collapse(grid)
    XCTAssertEqual(collapsed.count, 1)
    XCTAssertEqual(Set(collapsed[0].titles), ["Рискованный бизнес", "Risky Business"])
    let result = EpisodeGridMatch.align(
      kino: [kino(block: 2, titled: 2, number: 1, title: "Risky Business", runtime: 52)],
      official: grid)
    XCTAssertEqual(result.hits.count, 1)
    XCTAssertEqual(result.rows(for: 2).count, 1)
  }

  /// 17262: one year-titled block holds episodes from two official seasons. The chip
  /// stays the year. The official episode between two matches is a hole. An extra
  /// kino.pub episode is not forced onto a row.
  func testAYearBlockKeepsTheYearAndSpansTheSeasonsItMerged() {
    let kino = [
      kino(block: 10, titled: 2012, number: 1, title: "Альфа", runtime: 45, blockNumber: 1),
      kino(block: 10, titled: 2012, number: 2, title: "Дельта", runtime: 45, blockNumber: 1),
      kino(block: 10, titled: 2012, number: 3, title: "Бета", runtime: 45, blockNumber: 1),
      kino(block: 10, titled: 2012, number: 4, title: "Лишний", runtime: 20, blockNumber: 1),
    ]
    let grid = [
      official(season: 4, number: 1, title: "Альфа", runtime: 45),
      official(season: 4, number: 2, title: "Гамма", runtime: 45),
      official(season: 4, number: 3, title: "Дельта", runtime: 45),
      official(season: 5, number: 1, title: "Бета", runtime: 44),
    ]
    let result = EpisodeGridMatch.align(kino: kino, official: grid)
    XCTAssertEqual(result.displaySeason(blockID: 10, titledNumber: 2012), 2012)
    XCTAssertEqual(result.hits.count, 3)
    XCTAssertEqual(result.unmatchedKino.map(\.title), ["Лишний"])
    let rows = result.rows(for: 10)
    let holes = rows.compactMap { row -> String? in
      if case .hole(let episode) = row { return episode.titles.first }
      return nil
    }
    XCTAssertEqual(holes, ["Гамма"])
    XCTAssertEqual(result.hits.map { $0.official.season }.sorted(), [4, 4, 5])
  }

  /// Drag Race UK: eleven kino.pub blocks against nine official seasons, two chips
  /// both parsed as 2, a missing episode in the middle of a season, and one extra
  /// kino.pub episode. Matched blocks show the official season, not the duplicated digit.
  func testDuplicateSeasonTitlesFollowTheEpisodeNotTheChip() {
    var kino: [EpisodeGridMatch.KinoEpisode] = []
    var grid: [EpisodeGridMatch.OfficialEpisode] = []
    for season in 1...9 {
      let titled = season == 6 ? 2 : season
      for number in 1...3 {
        let title = "S\(season)E\(number)"
        if !(season == 4 && number == 2) {
          kino.append(self.kino(block: season, titled: titled, number: number,
                                title: title, runtime: 60, blockNumber: season))
        }
        grid.append(official(season: season, number: number, title: title, runtime: 60))
      }
    }
    kino.append(self.kino(block: 11, titled: nil, number: 1, title: "Unaired Special",
                          runtime: 12, blockNumber: 11))
    let result = EpisodeGridMatch.align(kino: kino, official: grid)
    XCTAssertEqual(result.displaySeason(blockID: 6, titledNumber: 2), 6)
    XCTAssertEqual(result.displaySeason(blockID: 2, titledNumber: 2), 2)
    XCTAssertEqual(result.unmatchedKino.map(\.title), ["Unaired Special"])
    let holes = result.rows(for: 4).compactMap { row -> Int? in
      if case .hole(let episode) = row { return episode.number }
      return nil
    }
    XCTAssertEqual(holes, [2])
    let shown = (1...9).map { result.displaySeason(blockID: $0, titledNumber: $0 == 6 ? 2 : $0) }
    XCTAssertEqual(shown, Array(1...9))
  }

  /// An official episode kino.pub skipped, and a kino.pub episode the grid does not
  /// have, both stay. Neither is slid onto the other's number.
  func testAMissingEpisodeAndAnExtraEpisodeBothStay() {
    let result = EpisodeGridMatch.align(
      kino: [
        kino(block: 1, titled: 1, number: 1, title: "One", runtime: 40),
        kino(block: 1, titled: 1, number: 2, title: "Bonus", runtime: 12),
      ],
      official: [
        official(season: 1, number: 1, title: "One", runtime: 40),
        official(season: 1, number: 2, title: "Two", runtime: 40),
      ])
    let rows = result.rows(for: 1)
    XCTAssertEqual(rows.count, 3)
    guard case .hole(let missing) = rows[1] else {
      return XCTFail("the official second episode stays a hole, got \(rows)")
    }
    XCTAssertEqual(missing.titles, ["Two"])
    guard case .extra(let bonus) = rows[2] else {
      return XCTFail("the extra kino.pub episode stays playable, got \(rows)")
    }
    XCTAssertEqual(bonus.title, "Bonus")
  }

  func testAYearIsNotASeasonIndex() {
    XCTAssertTrue(EpisodeGridMatch.isYear(2012))
    XCTAssertFalse(EpisodeGridMatch.isYear(14))
    XCTAssertNil(TMDBSeasonMatch.tmdbSeason(kinoNumber: 1, titleNumber: 2012,
                                            tmdbSeasons: [1, 2, 3]))
  }
}
