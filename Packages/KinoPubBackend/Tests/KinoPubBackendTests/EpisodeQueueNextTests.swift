//
//  EpisodeQueueNextTests.swift
//
//  What the tvOS Up Next panel offers — `EpisodeQueue.next(after:)`. The panel itself is
//  AVKit's, but the episode it names is ours — "next in season, else the next season's
//  opener, else nothing".
//

import XCTest
@testable import KinoPubBackend

final class EpisodeQueueNextTests: XCTestCase {

  private func episode(id: Int, number: Int, title: String = "") -> Episode {
    Episode(id: id, title: title, thumbnail: "", duration: 3064, tracks: 1,
            number: number, ac3: 0, audios: [], watched: 0,
            watching: EpisodeWatching(status: 0, time: 0), subtitles: [], files: [])
  }

  private func season(_ number: Int, episodeIDs: [(id: Int, number: Int)]) -> Season {
    Season(id: number, title: "", number: number,
           watching: SeasonWatching(status: 0),
           episodes: episodeIDs.map { episode(id: $0.id, number: $0.number) })
  }

  private func series(seasons: [Season]) -> MediaItem {
    var item = MediaItem.mock(id: 87940)
    item.seasons = seasons
    return item
  }

  // MARK: - Reading order

  func testNextEpisodeInTheSameSeason() {
    let s1 = season(1, episodeIDs: [(id: 10, number: 1), (id: 11, number: 2)])
    let next = EpisodeQueue(series: series(seasons: [s1])).next(after: s1.episodes[0])?.episode
    XCTAssertEqual(next?.id, 11)
  }

  /// A season boundary is not a wall: the season after's first episode is next.
  func testSeasonBoundaryRollsIntoTheNextSeasonsOpener() {
    let s1 = season(1, episodeIDs: [(id: 10, number: 1), (id: 11, number: 2)])
    let s2 = season(2, episodeIDs: [(id: 20, number: 1)])
    let next = EpisodeQueue(series: series(seasons: [s1, s2])).next(after: s1.episodes[1])?.episode
    XCTAssertEqual(next?.id, 20)
  }

  /// Auto-play stays inside the season unless the next-season setting is on.
  func testNextInSeasonStopsAtTheSeasonFinale() {
    let s1 = season(1, episodeIDs: [(id: 10, number: 1), (id: 11, number: 2)])
    let s2 = season(2, episodeIDs: [(id: 20, number: 1)])
    let queue = EpisodeQueue(series: series(seasons: [s1, s2]))
    XCTAssertEqual(queue.nextInSeason(after: s1.episodes[0])?.episode.id, 11)
    XCTAssertNil(queue.nextInSeason(after: s1.episodes[1]))
    XCTAssertEqual(queue.next(after: s1.episodes[1])?.episode.id, 20)
  }

  /// The payload may arrive unordered; watching order is by number, not by position.
  func testUnorderedPayloadIsReadByNumber() {
    let s2 = season(2, episodeIDs: [(id: 21, number: 2), (id: 20, number: 1)])
    let s1 = season(1, episodeIDs: [(id: 11, number: 2), (id: 10, number: 1)])
    // s1.episodes[0] is *number 2* (id 11) — the tail of season 1, so the answer is
    // season 2's opener wherever the arrays put it.
    let next = EpisodeQueue(series: series(seasons: [s2, s1])).next(after: s1.episodes[0])?.episode
    XCTAssertEqual(next?.id, 20)
  }

  // MARK: - Nothing to offer

  func testTheLastEpisodeProposesNothing() {
    let s1 = season(1, episodeIDs: [(id: 10, number: 1)])
    XCTAssertNil(EpisodeQueue(series: series(seasons: [s1])).next(after: s1.episodes[0])?.episode)
  }

  /// A film's snapshot has no seasons — and no proposal, rather than a guess.
  func testNoSeasonsMeansNoProposal() {
    let s1 = season(1, episodeIDs: [(id: 10, number: 1), (id: 11, number: 2)])
    XCTAssertNil(EpisodeQueue(series: MediaItem.mock(id: 1)).next(after: s1.episodes[0])?.episode)
    XCTAssertNil(EpisodeQueue(series: nil).next(after: s1.episodes[0])?.episode)
  }

  /// The episode playing is not in the cached payload (a stale snapshot for another
  /// cut of the series) — nothing to anchor "next" on.
  func testAnUnknownEpisodeProposesNothing() {
    let s1 = season(1, episodeIDs: [(id: 10, number: 1), (id: 11, number: 2)])
    let stranger = episode(id: 99, number: 1)
    XCTAssertNil(EpisodeQueue(series: series(seasons: [s1])).next(after: stranger)?.episode)
  }

  // MARK: - Stamping the hand-off

  /// A snapshot episode can predate stamping, and the player refuses to report progress
  /// for an unresolved `WatchingMetadata` — so the answer arrives ready to play.
  func testTheAnswerIsStampedForThePlayer() {
    let s1 = season(1, episodeIDs: [(id: 10, number: 1), (id: 11, number: 2)])
    let series = series(seasons: [s1])
    let next = EpisodeQueue(series: series).next(after: s1.episodes[0])?.episode
    XCTAssertEqual(next?.mediaId, 87940)
    XCTAssertEqual(next?.seasonNumber, 1)
    XCTAssertEqual(next?.seriesTitle, series.localizedTitle)
    XCTAssertEqual(next?.metadata.isResolved, true)
  }

  /// Stamping fills gaps, it does not overwrite what a caller already knew.
  func testExistingStampsAreKept() {
    var s2 = season(2, episodeIDs: [(id: 20, number: 1)])
    s2.episodes[0].mediaId = 5
    s2.episodes[0].seasonNumber = 7
    s2.episodes[0].seriesTitle = "Already known"
    let s1 = season(1, episodeIDs: [(id: 10, number: 1)])
    let next = EpisodeQueue(series: series(seasons: [s1, s2])).next(after: s1.episodes[0])?.episode
    XCTAssertEqual(next?.mediaId, 5)
    XCTAssertEqual(next?.seasonNumber, 7)
    XCTAssertEqual(next?.seriesTitle, "Already known")
  }

  // MARK: - Values

  /// A copy handed to the player or a rail is its own: stamping it, or giving it links,
  /// changes nothing the page holds.
  func testAHandedOutEpisodeIsItsOwnCopy() {
    let item = series(seasons: [season(1, episodeIDs: [(id: 10, number: 1), (id: 11, number: 2)])])
    let next = EpisodeQueue(series: item).next(after: item.seasons![0].episodes[0])
    XCTAssertEqual(next?.episode.mediaId, 87940)
    XCTAssertNil(item.seasons?[0].episodes[1].mediaId)
  }

  func testStampingAnItemReachesEveryEpisode() {
    var item = series(seasons: [season(1, episodeIDs: [(id: 10, number: 1)]),
                                season(2, episodeIDs: [(id: 20, number: 1), (id: 21, number: 2)])])
    item.stampSeasons()
    XCTAssertEqual(item.seasons?.map(\.mediaId), [87940, 87940])
    XCTAssertEqual(item.seasons?.flatMap(\.episodes).map(\.mediaId), [87940, 87940, 87940])
  }

  /// A seasonless payload stays one: `seasons` nil and empty mean different things.
  func testStampingAFilmLeavesItWithoutSeasons() {
    var item = MediaItem.mock(id: 5)
    item.seasons = nil
    item.stampSeasons()
    XCTAssertNil(item.seasons)
  }

  /// A changed mark is a different value, so SwiftUI redraws what shows it; the hash stays
  /// the id's.
  func testAMarkChangesTheItemAndNotItsHash() {
    let before = series(seasons: [season(1, episodeIDs: [(id: 10, number: 1), (id: 11, number: 2)])])
    var after = before
    XCTAssertTrue(after.updateEpisode(id: 11) { $0.watched = 1 })
    XCTAssertEqual(after.episode(id: 11)?.watched, 1)
    XCTAssertEqual(after.episode(id: 10)?.watched, 0)
    XCTAssertEqual(before.episode(id: 11)?.watched, 0)
    XCTAssertNotEqual(before, after)
    XCTAssertEqual(before.hashValue, after.hashValue)
    XCTAssertFalse(after.updateEpisode(id: 99) { $0.watched = 1 })
  }

  func testASeasonSurvivesCodingWithItsStampAndTitleNumber() throws {
    var season = Season(id: 1, title: "Сезон 14", number: 2, watching: SeasonWatching(status: 0),
                        episodes: [episode(id: 10, number: 1)])
    season.mediaId = 7
    let decoded = try JSONDecoder().decode(Season.self, from: JSONEncoder().encode(season))
    XCTAssertEqual(decoded, season)
    XCTAssertEqual(decoded.titleSeasonNumber, 14)
    XCTAssertEqual(decoded.episodes.first?.mediaId, 7)
  }

  /// The player's copy — stamped, with links — is still found in the page's item.
  func testTheSeasonOfAFilledCopyIsFound() {
    let item = series(seasons: [season(1, episodeIDs: [(id: 10, number: 1)]),
                                season(2, episodeIDs: [(id: 20, number: 1)])])
    let copy = item.seasons![1].episodes[0].stamped(season: 1, mediaId: 1, seriesTitle: "x")
    XCTAssertEqual(KinoPubMediaMapping.seasonContaining(copy, in: item)?.number, 2)
  }
}
