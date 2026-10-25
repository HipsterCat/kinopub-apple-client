//
//  ContinueWatchingLocalOverlayTests.swift
//

import XCTest
@testable import KinoPubBackend

final class ContinueWatchingLocalOverlayTests: XCTestCase {

  func testInProgressLocalUpdatesProgressAndLeads() {
    let cards = [
      ContinueWatchingLocalOverlay.Card(itemID: 1, isSeries: false, season: nil, video: 1),
      ContinueWatchingLocalOverlay.Card(itemID: 2, isSeries: false, season: nil, video: 1)
    ]
    let locals = [
      local(id: 2, progress: 0.4, isSeries: false, updatedAt: 20)
    ]
    let plan = ContinueWatchingLocalOverlay.plan(cards: cards, locals: locals)

    XCTAssertEqual(plan.order, [2, 1])
    XCTAssertEqual(plan.mutations[2]?.progress, 0.4)
    XCTAssertTrue(plan.hiddenIDs.isEmpty)
    XCTAssertTrue(plan.insertIDs.isEmpty)
  }

  /// Only a play after the snapshot lifts a title: the fetch already ranked older ones,
  /// and lifting every title ever played here buried new episodes (2026-10-25).
  func testOnlyPlaysAfterTheSnapshotLeadTheRow() {
    let cards = [
      ContinueWatchingLocalOverlay.Card(itemID: 1, isSeries: false, season: nil, video: 1),
      ContinueWatchingLocalOverlay.Card(itemID: 2, isSeries: false, season: nil, video: 1),
      ContinueWatchingLocalOverlay.Card(itemID: 3, isSeries: false, season: nil, video: 1)
    ]
    let locals = [
      local(id: 3, progress: 0.4, isSeries: false, updatedAt: 50),
      local(id: 2, progress: 0.2, isSeries: false, updatedAt: 150)
    ]
    let plan = ContinueWatchingLocalOverlay.plan(cards: cards, locals: locals,
                                                 snapshotTakenAt: Date(timeIntervalSince1970: 100))

    XCTAssertEqual(plan.order, [2, 1, 3])
    XCTAssertEqual(plan.mutations[3]?.progress, 0.4, "an older play still paints its bar")
  }

  func testFinishedFilmIsHidden() {
    let cards = [
      ContinueWatchingLocalOverlay.Card(itemID: 10, isSeries: false, season: nil, video: 1)
    ]
    let locals = [
      local(id: 10, isFinished: true, isSeries: false, updatedAt: 5)
    ]
    let plan = ContinueWatchingLocalOverlay.plan(cards: cards, locals: locals)

    XCTAssertEqual(plan.hiddenIDs, [10])
    XCTAssertTrue(plan.order.isEmpty)
    XCTAssertNil(plan.mutations[10])
  }

  func testFinishedSeriesEpisodeAdvancesAndClearsProgress() {
    let cards = [
      ContinueWatchingLocalOverlay.Card(itemID: 7, isSeries: true, season: 1, video: 4)
    ]
    let locals = [
      local(id: 7, season: 1, episode: 4, isFinished: true, isSeries: true, updatedAt: 9)
    ]
    let plan = ContinueWatchingLocalOverlay.plan(cards: cards, locals: locals)

    XCTAssertTrue(plan.hiddenIDs.isEmpty)
    XCTAssertEqual(plan.mutations[7]?.video, 5)
    XCTAssertEqual(plan.mutations[7]?.season, 1)
    XCTAssertNil(plan.mutations[7]?.progress)
    XCTAssertEqual(plan.mutations[7]?.overlayLabel, "S1, E5")
    XCTAssertEqual(plan.order, [7])
  }

  func testLocalOnlyInsertLeadsTheRow() {
    let cards = [
      ContinueWatchingLocalOverlay.Card(itemID: 1, isSeries: false, season: nil, video: 1)
    ]
    let locals = [
      local(id: 99, progress: 0.2, isSeries: false, updatedAt: 50, canInsert: true)
    ]
    let plan = ContinueWatchingLocalOverlay.plan(cards: cards, locals: locals)

    XCTAssertEqual(plan.insertIDs, [99])
    XCTAssertEqual(plan.order, [99, 1])
    XCTAssertEqual(plan.mutations[99]?.progress, 0.2)
  }

  func testFinishedSeriesNotInTheRowIsNotInserted() {
    let plan = ContinueWatchingLocalOverlay.plan(
      cards: [],
      locals: [local(id: 7, season: 1, episode: 10, isFinished: true, isSeries: true, updatedAt: 9, canInsert: true)]
    )
    XCTAssertTrue(plan.insertIDs.isEmpty)
    XCTAssertTrue(plan.order.isEmpty)
  }

  /// Other device moved the series on; this device's playhead is still on E2.
  /// Painting it would put the abandoned episode back on Home after a refetch.
  func testStaleLocalEpisodeBehindTheSnapshotIsNotPainted() {
    let cards = [
      ContinueWatchingLocalOverlay.Card(itemID: 7, isSeries: true, season: 1, video: 5)
    ]
    let locals = [
      local(id: 7, progress: 0.3, season: 1, episode: 2, isSeries: true, updatedAt: 9)
    ]
    let plan = ContinueWatchingLocalOverlay.plan(cards: cards, locals: locals)

    XCTAssertNil(plan.mutations[7])
    XCTAssertEqual(plan.order, [7])
    XCTAssertTrue(plan.hiddenIDs.isEmpty)
  }

  /// Film: this device at 20 %, the snapshot already at 80 % from another device.
  func testStaleLocalFilmProgressBehindTheSnapshotIsNotPainted() {
    let cards = [
      ContinueWatchingLocalOverlay.Card(itemID: 10, isSeries: false, season: nil, video: 1,
                                        progress: 0.8)
    ]
    let locals = [
      local(id: 10, progress: 0.2, isSeries: false, updatedAt: 5)
    ]
    let plan = ContinueWatchingLocalOverlay.plan(cards: cards, locals: locals)

    XCTAssertNil(plan.mutations[10])
    XCTAssertEqual(plan.order, [10])
  }

  /// Local finished E2, so next would be E3, but the snapshot already offers E8.
  func testFinishedLocalThatIsBehindTheSnapshotDoesNotStepBack() {
    let cards = [
      ContinueWatchingLocalOverlay.Card(itemID: 7, isSeries: true, season: 1, video: 8)
    ]
    let locals = [
      local(id: 7, season: 1, episode: 2, isFinished: true, isSeries: true, updatedAt: 9)
    ]
    let plan = ContinueWatchingLocalOverlay.plan(cards: cards, locals: locals)

    XCTAssertNil(plan.mutations[7])
    XCTAssertEqual(plan.order, [7])
  }

  func testNoLocalLeavesCachedOrderAlone() {
    let cards = [
      ContinueWatchingLocalOverlay.Card(itemID: 3, isSeries: true, season: 2, video: 1),
      ContinueWatchingLocalOverlay.Card(itemID: 4, isSeries: true, season: 1, video: 8)
    ]
    let plan = ContinueWatchingLocalOverlay.plan(cards: cards, locals: [])
    XCTAssertEqual(plan.order, [3, 4])
    XCTAssertTrue(plan.mutations.isEmpty)
    XCTAssertTrue(plan.hiddenIDs.isEmpty)
  }

  func testFinishedFilmDoesNotHideADifferentCard() {
    let cards = [
      ContinueWatchingLocalOverlay.Card(itemID: 1, isSeries: false, season: nil, video: 1),
      ContinueWatchingLocalOverlay.Card(itemID: 2, isSeries: false, season: nil, video: 1)
    ]
    let locals = [
      local(id: 1, isFinished: true, isSeries: false, updatedAt: 1)
    ]
    let plan = ContinueWatchingLocalOverlay.plan(cards: cards, locals: locals)
    XCTAssertEqual(plan.order, [2])
    XCTAssertEqual(plan.hiddenIDs, [1])
  }

  // MARK: -

  private func local(id: Int,
                     progress: Double? = nil,
                     season: Int? = nil,
                     episode: Int? = nil,
                     isFinished: Bool = false,
                     isSeries: Bool = false,
                     updatedAt: TimeInterval,
                     canInsert: Bool = false) -> ContinueWatchingLocalOverlay.Local {
    ContinueWatchingLocalOverlay.Local(
      itemID: id,
      isSeries: isSeries,
      season: season,
      episode: episode,
      isFinished: isFinished,
      isResumable: !isFinished && progress != nil,
      progress: isFinished ? nil : progress,
      updatedAt: updatedAt,
      canInsert: canInsert
    )
  }
}
