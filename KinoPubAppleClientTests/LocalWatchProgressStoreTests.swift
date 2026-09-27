//
//  LocalWatchProgressStoreTests.swift
//  KinoPubAppleClientTests
//
//  Persistence of local resume points through SwiftData: what a relaunch reads back,
//  per-episode records, and clearing. A second store on the same container stands in
//  for the relaunch.
//

import XCTest
import SwiftData
import KinoPubBackend
@testable import KinoPub

final class LocalWatchProgressStoreTests: XCTestCase {

  private var container: ModelContainer!

  override func setUpWithError() throws {
    let configuration = ModelConfiguration(schema: WatchLibrary.schema,
                                           isStoredInMemoryOnly: true,
                                           cloudKitDatabase: .none)
    container = try ModelContainer(for: WatchLibrary.schema, configurations: configuration)
  }

  private let seriesID = 4242
  private let filmID = 777

  func testFilmResumePointSurvivesRelaunch() async {
    let store = LocalWatchProgressStore(container: container)
    store.cacheItem(.mock(id: filmID, type: "movie"))
    store.recordProgress(mediaId: filmID, position: 600, duration: 6000, season: nil, episode: 1)
    await store.flush()

    let relaunched = LocalWatchProgressStore(container: container)
    let entry = relaunched.entry(forId: filmID, season: nil, episode: nil)
    XCTAssertEqual(entry?.position, 600)
    XCTAssertEqual(entry?.item.id, filmID, "the payload snapshot comes back with the record")
    XCTAssertNotNil(relaunched.snapshot(for: filmID))
  }

  func testEachEpisodeKeepsItsOwnRecord() async {
    let store = LocalWatchProgressStore(container: container)
    store.cacheItem(.mock(id: seriesID, type: "serial"))
    store.recordFinished(mediaId: seriesID, duration: 2400, season: 1, episode: 3)
    store.recordProgress(mediaId: seriesID, position: 300, duration: 2400, season: 1, episode: 4)
    await store.flush()

    let relaunched = LocalWatchProgressStore(container: container)
    let records = relaunched.records(forItem: seriesID)
    XCTAssertEqual(Set(records.compactMap(\.episode)), [3, 4])
    XCTAssertEqual(relaunched.entry(forId: seriesID, season: 1, episode: 4)?.position, 300)
    // A finished episode is a tombstone, not a resume point.
    XCTAssertNil(relaunched.entry(forId: seriesID, season: 1, episode: 3))
    XCTAssertEqual(relaunched.allEntries().first?.episode, 4, "newest record per title")
  }

  func testNothingIsWrittenWithoutAPayload() async {
    let store = LocalWatchProgressStore(container: container)
    store.recordProgress(mediaId: filmID, position: 600, duration: 6000, season: nil, episode: 1)
    XCTAssertNil(store.entry(forId: filmID, season: nil, episode: nil))
  }

  func testClearRemovesEveryRecordOfTheTitle() async {
    let store = LocalWatchProgressStore(container: container)
    store.cacheItem(.mock(id: seriesID, type: "serial"))
    store.recordProgress(mediaId: seriesID, position: 300, duration: 2400, season: 1, episode: 1)
    store.recordProgress(mediaId: seriesID, position: 300, duration: 2400, season: 1, episode: 2)
    store.clear(id: seriesID)
    await store.flush()

    XCTAssertTrue(store.records(forItem: seriesID).isEmpty)
    let relaunched = LocalWatchProgressStore(container: container)
    XCTAssertTrue(relaunched.records(forItem: seriesID).isEmpty)
    XCTAssertTrue(relaunched.allEntries().isEmpty)
  }
}
