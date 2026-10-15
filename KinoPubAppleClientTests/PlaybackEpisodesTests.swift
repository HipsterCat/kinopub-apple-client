//
//  PlaybackEpisodesTests.swift
//  KinoPubAppleClientTests
//
//  The player's Episodes tab lists a series the way the title page does: seasons then
//  episodes in reading order, the season playing selected. Films have no list.
//

import XCTest
@testable import KinoPub
@testable import KinoPubBackend

final class PlaybackEpisodesTests: XCTestCase {

  func testAMovieHasNoEpisodeList() {
    XCTAssertNil(PlaybackEpisodes(playing: MediaItem.mock(), series: MediaItem.mock()))
  }

  func testASeriesWithoutSeasonsHasNoList() {
    let series = MediaItem.mock(id: 50, type: "serial")
    let episode = listedEpisode(id: 101, number: 1)
    XCTAssertNil(PlaybackEpisodes(playing: episode, series: series))
  }

  func testSeasonsAndEpisodesAreInReadingOrder() throws {
    let series = series(seasonOrder: [2, 1])
    let playing = episode(in: series, season: 1, number: 2)
    let list = try XCTUnwrap(PlaybackEpisodes(playing: playing, series: series))
    XCTAssertEqual(list.seasons.map(\.number), [1, 2])
    XCTAssertEqual(list.seasons.map(\.episodeIDs), [[101, 102, 103], [201, 202, 203]])
    XCTAssertEqual(list.seriesID, 50)
  }

  func testThePlayingEpisodeSelectsItsSeason() throws {
    let series = series()
    let playing = episode(in: series, season: 2, number: 1)
    let list = try XCTUnwrap(PlaybackEpisodes(playing: playing, series: series))
    XCTAssertEqual(list.openingEpisodeID, 201)
    XCTAssertEqual(list.selectedSeasonID, 2)
    XCTAssertEqual(list.episodeByID[201]?.seasonNumber, 2)
    XCTAssertEqual(list.episodeByID[201]?.mediaId, 50)
    XCTAssertEqual(list.episodeByID[201]?.seriesTitle, series.localizedTitle)
  }

  func testASingleSeasonIsStillAList() throws {
    let series = series(seasonOrder: [1])
    let playing = episode(in: series, season: 1, number: 3)
    let list = try XCTUnwrap(PlaybackEpisodes(playing: playing, series: series))
    XCTAssertEqual(list.seasons.map(\.id), [1])
    XCTAssertEqual(list.openingEpisodeID, 103)
    XCTAssertEqual(list.selectedSeasonID, 1)
  }

  // MARK: - Fixtures

  private func series(seasonOrder: [Int] = [1, 2]) -> MediaItem {
    let seasons = seasonOrder.map { number -> Season in
      let episodes = (1...3).reversed().map { n in
        listedEpisode(id: number * 100 + n, number: n)
      }
      return Season(id: number, title: "", number: number,
                    watching: SeasonWatching(status: 0), episodes: episodes)
    }
    var item = MediaItem.mock(id: 50, type: "serial")
    item.seasons = seasons
    return item
  }

  private func listedEpisode(id: Int, number: Int) -> Episode {
    Episode(id: id, title: "", thumbnail: "", duration: 3_000, tracks: 1, number: number,
            ac3: 0, audios: [], watched: 0, watching: EpisodeWatching(status: 0, time: 0),
            subtitles: [], files: [])
  }

  private func episode(in series: MediaItem, season: Int, number: Int) -> Episode {
    series.seasons!.first { $0.number == season }!.episodes.first { $0.number == number }!
  }
}
