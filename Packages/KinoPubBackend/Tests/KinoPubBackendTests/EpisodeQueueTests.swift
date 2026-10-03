//
//  EpisodeQueueTests.swift
//
//  Every "which episode" question, asked of one queue — so the hero's Play, Continue
//  Watching, Up Next and the end-of-episode proposal cannot disagree by accident.
//

import XCTest
import KinoPubMedia
@testable import KinoPubBackend

final class EpisodeQueueTests: XCTestCase {

  private func episode(id: Int, number: Int, watched: Bool = false, time: Int = 0) -> Episode {
    Episode(id: id, title: "", thumbnail: "", duration: 3_000, tracks: 1, number: number,
            ac3: 0, audios: [], watched: watched ? 1 : 0,
            watching: EpisodeWatching(status: 0, time: time), subtitles: [], files: [])
  }

  /// Season 1: E1 E2 E3 E4 E5 E6 — `watched` lists the numbers watched.
  private func series(watched: Set<Int> = [], inProgress: Int? = nil,
                      seasonOrder: [Int] = [1, 2]) -> MediaItem {
    let seasons = seasonOrder.map { number -> Season in
      let episodes = (1...3).map { n -> Episode in
        let absolute = (number - 1) * 3 + n
        return episode(id: number * 100 + n, number: n, watched: watched.contains(absolute),
                       time: absolute == inProgress ? 1_200 : 0)
      }
      return Season(id: number, title: "", number: number, watching: SeasonWatching(status: 0),
                    episodes: episodes.reversed())
    }
    var item = MediaItem.mock(id: 87940)
    item.seasons = seasons
    return item
  }

  private func numbers(_ entry: EpisodeQueue.Entry?) -> String? {
    entry.map { "S\($0.season.number)E\($0.episode.number)" }
  }

  // MARK: - Reading order

  /// Payload order is not trusted: seasons and episodes come back sorted.
  func testReadingOrderIsSeasonThenNumber() {
    let queue = EpisodeQueue(series: series(seasonOrder: [2, 1]))
    XCTAssertEqual(queue.entries.map { numbers($0) },
                   ["S1E1", "S1E2", "S1E3", "S2E1", "S2E2", "S2E3"])
  }

  func testNextIsTheNextOneWatchedOrNot() {
    let item = series(watched: [3, 4])
    let queue = EpisodeQueue(series: item)
    let s1e2 = item.seasons!.first { $0.number == 1 }!.episodes.first { $0.number == 2 }!
    XCTAssertEqual(numbers(queue.next(after: s1e2)), "S1E3")
    XCTAssertEqual(numbers(queue.nextUnwatched(after: s1e2)), "S2E2",
                   "Up Next skips S1E3 and S2E1, both watched")
  }

  func testTheLastEpisodeHasNoNext() {
    let item = series()
    let last = item.seasons!.first { $0.number == 2 }!.episodes.first { $0.number == 3 }!
    XCTAssertNil(EpisodeQueue(series: item).next(after: last))
    XCTAssertNil(EpisodeQueue(series: nil).next(after: last))
  }

  /// An episode handed to the player gets the stamps `/v1/watching` needs.
  func testANextEpisodeIsStamped() {
    let item = series()
    let first = item.seasons!.first { $0.number == 1 }!.episodes.first { $0.number == 3 }!
    let next = EpisodeQueue(series: item).next(after: first)?.episode
    XCTAssertEqual(next?.mediaId, 87940)
    XCTAssertEqual(next?.seasonNumber, 2)
  }

  // MARK: - Where the viewer is

  /// Today's answer (D17 open): the first unwatched, skipped ones included.
  func testContinueIsTheFirstUnwatched() {
    let queue = EpisodeQueue(series: series(watched: [1, 2, 4, 5], inProgress: 6))
    XCTAssertEqual(numbers(queue.continueTarget), "S1E3")
    XCTAssertEqual(numbers(queue.firstUnwatched), "S1E3")
    XCTAssertEqual(numbers(queue.inProgress), "S2E3")
    XCTAssertEqual(numbers(queue.afterFurthestWatched), "S2E3")
  }

  func testEverythingWatchedReplaysFromTheStart() {
    let queue = EpisodeQueue(series: series(watched: Set(1...6)))
    XCTAssertTrue(queue.isFinished)
    XCTAssertEqual(numbers(queue.continueTarget), "S1E1")
    XCTAssertNil(queue.afterFurthestWatched)
  }

  /// The hero reads the same queue through `primaryEpisode`.
  func testThePrimaryEpisodeIsTheQueuesAnswer() {
    let item = series(watched: [1, 2])
    XCTAssertEqual(item.primaryEpisode.map { "S\($0.season.number)E\($0.episode.number)" },
                   numbers(EpisodeQueue(series: item).continueTarget))
  }

  // MARK: - The device's own state

  /// Watched-ness is the caller's `ViewerState`: a local mark hides an episode the payload
  /// still calls unwatched.
  func testALocalMarkCounts() {
    let item = series()
    let first = item.seasons!.first { $0.number == 1 }!.episodes.first { $0.number == 1 }!
    let queue = EpisodeQueue(series: item) { ref, episode in
      var state = ViewerState(reportedBy: episode)
      if ref == .episode(87940, season: 1, number: 2) { state.isWatched = true }
      return state
    }
    XCTAssertEqual(numbers(queue.nextUnwatched(after: first)), "S1E3")
  }
}
