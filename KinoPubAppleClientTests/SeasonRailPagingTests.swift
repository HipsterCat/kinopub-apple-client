//
//  SeasonRailPagingTests.swift
//  KinoPubAppleClientTests
//
//  Windowed hydration for the continuous seasons rail (KP-70): seed around the
//  opening tab, expand toward a displayed neighbour, never hydrate every season
//  on appear.
//

import XCTest
@testable import KinoPub
@testable import KinoPubBackend

final class SeasonRailPagingTests: XCTestCase {

  private func seasons(_ counts: [Int]) -> [Season] {
    counts.enumerated().map { index, count in
      let number = index + 1
      let episodes = (1...count).map { n in
        Episode(id: number * 100 + n, title: "", thumbnail: "", duration: 2_400, tracks: 1,
                number: n, ac3: 0, audios: [], watched: -1,
                watching: EpisodeWatching(status: -1, time: 0),
                subtitles: [], files: [])
      }
      return Season(id: number * 10, title: "Сезон \(number)", number: number,
                    watching: SeasonWatching(status: 0), episodes: episodes)
    }
  }

  func testSeedWindowIsOpeningSeasonPlusNeighbors() {
    let seasons = seasons([3, 3, 3, 3, 3])
    let seed = seasons[2].id
    let hydrated = SeasonsRailView.effectiveHydratedIDs(
      seasons: seasons, hydrated: [], selectedTabID: seed)
    XCTAssertEqual(hydrated, [seasons[1].id, seasons[2].id, seasons[3].id])
  }

  func testEmptyHydrationFallsBackToPreferredOpeningTab() {
    let seasons = seasons([2, 2, 2])
    // preferredOpeningTabID picks the first season with an unwatched episode → S1.
    let hydrated = SeasonsRailView.effectiveHydratedIDs(
      seasons: seasons, hydrated: [], selectedTabID: nil)
    XCTAssertEqual(hydrated, [seasons[0].id, seasons[1].id])
  }

  func testPersistedHydrationWinsOverSeed() {
    let seasons = seasons([2, 2, 2, 2])
    let hydrated = SeasonsRailView.effectiveHydratedIDs(
      seasons: seasons, hydrated: [seasons[3].id], selectedTabID: seasons[0].id)
    XCTAssertEqual(hydrated, [seasons[3].id])
  }

  func testExpandingTowardEndAddsNextSeasonOnly() {
    let seasons = seasons([2, 2, 2, 2])
    let before: Set<Int> = [seasons[0].id, seasons[1].id]
    let after = SeasonsRailView.expandingHydration(
      displayedSeasonID: seasons[1].id,
      seasons: seasons,
      hydrated: before)
    XCTAssertEqual(after, [seasons[0].id, seasons[1].id, seasons[2].id])
  }

  func testExpandingTowardStartAddsPreviousSeason() {
    let seasons = seasons([2, 2, 2, 2])
    let before: Set<Int> = [seasons[2].id, seasons[3].id]
    let after = SeasonsRailView.expandingHydration(
      displayedSeasonID: seasons[2].id,
      seasons: seasons,
      hydrated: before)
    XCTAssertEqual(after, [seasons[1].id, seasons[2].id, seasons[3].id])
  }

  func testNeighborRadiusAtEdgesDoesNotInventSeasons() {
    let seasons = seasons([1, 1, 1])
    XCTAssertEqual(
      SeasonsRailView.neighborSeasonIDs(around: seasons[0].id, seasons: seasons, radius: 1),
      [seasons[0].id, seasons[1].id])
    XCTAssertEqual(
      SeasonsRailView.neighborSeasonIDs(around: seasons[2].id, seasons: seasons, radius: 1),
      [seasons[1].id, seasons[2].id])
  }
}
