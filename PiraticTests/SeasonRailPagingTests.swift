//
//  SeasonRailPagingTests.swift
//  PiraticTests
//
//  Windowed hydration for the continuous seasons rail (KP-70): seed around the
//  opening tab, expand toward a displayed neighbour, never hydrate every season
//  on appear.
//

import XCTest
@testable import Piratic
@testable import KinoPubBackend

@MainActor
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

  func testFarSeasonJumpDoesNotAnimate() {
    XCTAssertFalse(SeasonsRailView.animatesSeasonJump(
      tabDistance: 6, landingVisible: false, targetSeasonVisible: false))
    XCTAssertFalse(SeasonsRailView.animatesSeasonJump(
      tabDistance: 2, landingVisible: true, targetSeasonVisible: true))
  }

  func testNeighborOffScreenDoesNotAnimate() {
    XCTAssertFalse(SeasonsRailView.animatesSeasonJump(
      tabDistance: 1, landingVisible: false, targetSeasonVisible: false))
  }

  func testNeighborAlreadyOnScreenAnimates() {
    XCTAssertTrue(SeasonsRailView.animatesSeasonJump(
      tabDistance: 1, landingVisible: false, targetSeasonVisible: true))
    XCTAssertTrue(SeasonsRailView.animatesSeasonJump(
      tabDistance: 1, landingVisible: true, targetSeasonVisible: true))
  }

  func testSameSeasonAnimatesOnlyWhenLandingIsVisible() {
    XCTAssertTrue(SeasonsRailView.animatesSeasonJump(
      tabDistance: 0, landingVisible: true, targetSeasonVisible: true))
    XCTAssertFalse(SeasonsRailView.animatesSeasonJump(
      tabDistance: 0, landingVisible: false, targetSeasonVisible: true))
  }

  func testMissingCurrentTabDoesNotAnimate() {
    XCTAssertFalse(SeasonsRailView.animatesSeasonJump(
      tabDistance: nil, landingVisible: true, targetSeasonVisible: true))
  }

  func testTabDistanceCountsStripStops() {
    let tabs = [
      SeasonTab(id: 15, first: 15, last: 15, status: .available),
      SeasonTab(id: 16, first: 16, last: 16, status: .available),
      SeasonTab(id: 21, first: 21, last: 21, status: .available),
    ]
    XCTAssertEqual(SeasonsRailView.tabDistance(from: 15, to: 21, in: tabs), 2)
    XCTAssertEqual(SeasonsRailView.tabDistance(from: 15, to: 16, in: tabs), 1)
    XCTAssertEqual(SeasonsRailView.tabDistance(from: 16, to: 16, in: tabs), 0)
    XCTAssertNil(SeasonsRailView.tabDistance(from: nil, to: 16, in: tabs))
    XCTAssertNil(SeasonsRailView.tabDistance(from: 15, to: 99, in: tabs))
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
