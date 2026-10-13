//
//  PlaybackEndTests.swift
//
//  End-of-playback: dismiss vs play-next, for every Settings combination.
//

import XCTest
@testable import KinoPubBackend

final class PlaybackEndTests: XCTestCase {

  private let defaultPolicy = PlaybackEndPolicy.default
  private let bingeSeasons = PlaybackEndPolicy(autoPlayNextEpisode: true, autoPlayNextSeason: true)
  private let autoPlayOff = PlaybackEndPolicy(autoPlayNextEpisode: false, autoPlayNextSeason: false)
  private let seasonWithoutEpisode = PlaybackEndPolicy(autoPlayNextEpisode: false,
                                                       autoPlayNextSeason: true)

  func testDefaultPolicyIsAutoPlayOnAndNextSeasonOff() {
    XCTAssertEqual(PlaybackEndPolicy.default.autoPlayNextEpisode, true)
    XCTAssertEqual(PlaybackEndPolicy.default.autoPlayNextSeason, false)
  }

  /// Four Settings combinations × mid-season / season finale / series finale / movie.
  func testEverySettingCombination() {
    let series = self.series()
    let s1e1 = episode(in: series, season: 1, number: 1)
    let s1e2 = episode(in: series, season: 1, number: 2)
    let s1e3 = episode(in: series, season: 1, number: 3)
    let s2e1 = episode(in: series, season: 2, number: 1)
    let last = episode(in: series, season: 2, number: 3)
    let movie = MediaItem.mock()

    struct Row {
      let policy: PlaybackEndPolicy
      let midSeason: PlaybackEndAction
      let seasonEnd: PlaybackEndAction
      let seriesEnd: PlaybackEndAction
    }
    let rows: [Row] = [
      Row(policy: defaultPolicy, midSeason: .playNext(s1e2), seasonEnd: .dismiss, seriesEnd: .dismiss),
      Row(policy: bingeSeasons, midSeason: .playNext(s1e2), seasonEnd: .playNext(s2e1), seriesEnd: .dismiss),
      Row(policy: autoPlayOff, midSeason: .dismiss, seasonEnd: .dismiss, seriesEnd: .dismiss),
      Row(policy: seasonWithoutEpisode, midSeason: .dismiss, seasonEnd: .dismiss, seriesEnd: .dismiss),
    ]
    for row in rows {
      XCTAssertEqual(PlaybackEnd.action(playing: s1e1, series: series, policy: row.policy),
                     row.midSeason, "mid-season under \(row.policy)")
      XCTAssertEqual(PlaybackEnd.action(playing: s1e3, series: series, policy: row.policy),
                     row.seasonEnd, "season end under \(row.policy)")
      XCTAssertEqual(PlaybackEnd.action(playing: last, series: series, policy: row.policy),
                     row.seriesEnd, "series end under \(row.policy)")
      XCTAssertEqual(PlaybackEnd.action(playing: movie, series: nil, policy: row.policy),
                     .dismiss, "movie under \(row.policy)")
    }
  }

  // MARK: - Movies

  func testAMovieAlwaysDismisses() {
    for policy in [defaultPolicy, bingeSeasons, autoPlayOff, seasonWithoutEpisode] {
      XCTAssertEqual(PlaybackEnd.action(playing: MediaItem.mock(), series: nil, policy: policy),
                     .dismiss,
                     "movies dismiss under \(policy)")
    }
  }

  // MARK: - Default: auto-play next episode, not the next season

  func testDefaultPlaysTheNextEpisodeInTheSeason() {
    let series = self.series()
    let s1e1 = episode(in: series, season: 1, number: 1)
    XCTAssertEqual(PlaybackEnd.action(playing: s1e1, series: series, policy: defaultPolicy),
                   .playNext(episode(in: series, season: 1, number: 2)))
  }

  func testDefaultDismissesAtTheEndOfTheSeason() {
    let series = self.series()
    let s1e3 = episode(in: series, season: 1, number: 3)
    XCTAssertEqual(PlaybackEnd.action(playing: s1e3, series: series, policy: defaultPolicy),
                   .dismiss)
  }

  func testDefaultDismissesAtTheEndOfTheSeries() {
    let series = self.series()
    let last = episode(in: series, season: 2, number: 3)
    XCTAssertEqual(PlaybackEnd.action(playing: last, series: series, policy: defaultPolicy),
                   .dismiss)
  }

  // MARK: - Auto-play next season on

  func testNextSeasonPlaysTheOpenerWhenTheSeasonEnds() {
    let series = self.series()
    let s1e3 = episode(in: series, season: 1, number: 3)
    XCTAssertEqual(PlaybackEnd.action(playing: s1e3, series: series, policy: bingeSeasons),
                   .playNext(episode(in: series, season: 2, number: 1)))
  }

  func testNextSeasonStillPlaysTheNextEpisodeInTheSeason() {
    let series = self.series()
    let s1e1 = episode(in: series, season: 1, number: 1)
    XCTAssertEqual(PlaybackEnd.action(playing: s1e1, series: series, policy: bingeSeasons),
                   .playNext(episode(in: series, season: 1, number: 2)),
                   "in-season next wins; it does not jump a season")
  }

  func testNextSeasonDismissesAtTheEndOfTheSeries() {
    let series = self.series()
    let last = episode(in: series, season: 2, number: 3)
    XCTAssertEqual(PlaybackEnd.action(playing: last, series: series, policy: bingeSeasons),
                   .dismiss)
  }

  // MARK: - Auto-play off

  func testAutoPlayOffDismissesMidSeason() {
    let series = self.series()
    let s1e1 = episode(in: series, season: 1, number: 1)
    XCTAssertEqual(PlaybackEnd.action(playing: s1e1, series: series, policy: autoPlayOff),
                   .dismiss)
  }

  func testAutoPlayOffDismissesAtSeasonAndSeriesEnd() {
    let series = self.series()
    XCTAssertEqual(
      PlaybackEnd.action(playing: episode(in: series, season: 1, number: 3),
                         series: series, policy: autoPlayOff),
      .dismiss)
    XCTAssertEqual(
      PlaybackEnd.action(playing: episode(in: series, season: 2, number: 3),
                         series: series, policy: autoPlayOff),
      .dismiss)
  }

  /// The season toggle does nothing when auto-play of the next episode is off.
  func testSeasonToggleWithoutAutoPlayStillDismisses() {
    let series = self.series()
    XCTAssertEqual(
      PlaybackEnd.action(playing: episode(in: series, season: 1, number: 1),
                         series: series, policy: seasonWithoutEpisode),
      .dismiss)
    XCTAssertEqual(
      PlaybackEnd.action(playing: episode(in: series, season: 1, number: 3),
                         series: series, policy: seasonWithoutEpisode),
      .dismiss)
  }

  // MARK: - Missing / unavailable next

  func testAMissingSeriesPayloadDismisses() {
    let series = self.series()
    let s1e1 = episode(in: series, season: 1, number: 1)
    XCTAssertEqual(PlaybackEnd.action(playing: s1e1, series: nil, policy: defaultPolicy),
                   .dismiss)
    XCTAssertEqual(PlaybackEnd.action(playing: s1e1, series: MediaItem.mock(), policy: bingeSeasons),
                   .dismiss)
  }

  func testAnUnknownEpisodeDismisses() {
    let series = self.series()
    let stranger = listedEpisode(id: 99, number: 1)
    XCTAssertEqual(PlaybackEnd.action(playing: stranger, series: series, policy: defaultPolicy),
                   .dismiss)
  }

  func testAnUnavailableNextEpisodeInTheSeasonDismisses() {
    let series = self.series(unlisted: [(season: 1, number: 2)])
    let s1e1 = episode(in: series, season: 1, number: 1)
    XCTAssertEqual(PlaybackEnd.action(playing: s1e1, series: series, policy: defaultPolicy),
                   .dismiss)
    XCTAssertEqual(PlaybackEnd.action(playing: s1e1, series: series, policy: bingeSeasons),
                   .dismiss,
                   "an unlistable in-season next does not skip to the next season")
  }

  func testAnUnavailableNextSeasonOpenerDismisses() {
    let series = self.series(unlisted: [(season: 2, number: 1)])
    let s1e3 = episode(in: series, season: 1, number: 3)
    XCTAssertEqual(PlaybackEnd.action(playing: s1e3, series: series, policy: bingeSeasons),
                   .dismiss)
  }

  // MARK: - Fixtures

  /// Two seasons of three listed episodes. `unlisted` episodes have an empty files ladder.
  private func series(unlisted: [(season: Int, number: Int)] = []) -> MediaItem {
    let blocked = Set(unlisted.map { "\($0.season)-\($0.number)" })
    let seasons = (1...2).map { season -> Season in
      let episodes = (1...3).map { number -> Episode in
        let listed = !blocked.contains("\(season)-\(number)")
        return listed
          ? listedEpisode(id: season * 100 + number, number: number)
          : Episode(id: season * 100 + number, title: "", thumbnail: "", duration: 3_000,
                    tracks: 1, number: number, ac3: 0, audios: [], watched: 0,
                    watching: EpisodeWatching(status: 0, time: 0), subtitles: [], files: [])
      }
      return Season(id: season, title: "", number: season,
                    watching: SeasonWatching(status: 0), episodes: episodes)
    }
    var item = MediaItem.mock(id: 87940, type: "serial")
    item.seasons = seasons
    return item
  }

  private func listedEpisode(id: Int, number: Int) -> Episode {
    Episode(id: id, title: "", thumbnail: "", duration: 3_000, tracks: 1, number: number,
            ac3: 0, audios: [], watched: 0, watching: EpisodeWatching(status: 0, time: 0),
            subtitles: [], files: [listedFile()])
  }

  private func listedFile() -> FileInfo {
    FileInfo(codec: "h264", w: 1920, h: 1080, quality: "1080p", qualityID: 3,
             url: URLInfo(http: "", hls: "", hls4: "", hls2: ""))
  }

  private func episode(in series: MediaItem, season: Int, number: Int) -> Episode {
    series.seasons!.first { $0.number == season }!.episodes.first { $0.number == number }!
  }
}
