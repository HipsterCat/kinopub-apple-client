//
//  LocalWatchProgressStoreTests.swift
//  PiraticTests
//
//  Persistence of local resume points through SwiftData: what a relaunch reads back,
//  per-episode records, and clearing. A second store on the same container stands in
//  for the relaunch.
//

import XCTest
import SwiftData
import KinoPubBackend
@testable import Piratic

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

  @MainActor
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

  @MainActor
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

  /// No payload, no card — but the play keeps its date and position, on disk too:
  /// Continue Watching orders the row by it (2026-11-28, a title watched on the iPad
  /// lost its place hours later).
  @MainActor
  func testAPlayWithoutAPayloadKeepsItsDateButDrawsNoCard() async {
    let store = LocalWatchProgressStore(container: container)
    store.recordProgress(mediaId: filmID, position: 600, duration: 6000, season: nil, episode: 1)
    XCTAssertNil(store.entry(forId: filmID, season: nil, episode: nil))
    XCTAssertTrue(store.allEntries().isEmpty)
    XCTAssertEqual(store.lastPlayedByItemID()[filmID]?.position, 600)
    await store.flush()

    let relaunched = LocalWatchProgressStore(container: container)
    XCTAssertEqual(relaunched.lastPlayedByItemID()[filmID]?.position, 600)
    relaunched.cacheItem(.mock(id: filmID, type: "movie"))
    XCTAssertEqual(relaunched.entry(forId: filmID, season: nil, episode: nil)?.position, 600,
                   "the card appears once the payload is known")
  }

  @MainActor
  func testLastPlayedKeepsTheNewestEpisodePerTitle() async {
    let store = LocalWatchProgressStore(container: container)
    store.cacheItem(.mock(id: seriesID, type: "serial"))
    store.recordProgress(mediaId: seriesID, position: 300, duration: 2400, season: 1, episode: 6)
    store.recordFinished(mediaId: seriesID, duration: 2400, season: 1, episode: 7)
    let played = store.lastPlayedByItemID()
    XCTAssertEqual(played.count, 1)
    XCTAssertEqual(played[seriesID]?.episode, 7, "a finished episode is still the newest play")
  }

  @MainActor
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

  /// Writers on several threads: the disk ends where memory ends. Queued after the lock,
  /// two writes could reach the writer in the other order and a relaunch read an older
  /// position than the one the app had shown.
  @MainActor
  func testConcurrentWritesLandInMemoryOrder() async {
    let store = LocalWatchProgressStore(container: container)
    store.cacheItem(.mock(id: filmID, type: "movie"))
    let id = filmID
    DispatchQueue.concurrentPerform(iterations: 200) { @Sendable step in
      store.recordProgress(mediaId: id, position: Double(600 + step), duration: 6000,
                           season: nil, episode: 1)
    }
    await store.flush()

    let shown = store.entry(forId: filmID, season: nil, episode: nil)?.position
    let relaunched = LocalWatchProgressStore(container: container)
    XCTAssertNotNil(shown)
    XCTAssertEqual(relaunched.entry(forId: filmID, season: nil, episode: nil)?.position, shown)
  }

  private func series() throws -> MediaItem {
    let watching = try JSONDecoder().decode(SeasonWatching.self, from: Data(#"{"status": 0}"#.utf8))
    var item = MediaItem.mock(id: seriesID, type: "serial")
    item.seasons = [Season(id: 1, title: "", number: 1, watching: watching, episodes: (1...3).map {
      Episode(id: 10 + $0, title: "", thumbnail: "", duration: 2_400, tracks: 1, number: $0, ac3: 0,
              audios: [], watched: -1, watching: EpisodeWatching(status: -1, time: 0),
              subtitles: [], files: [])
    })]
    return item
  }

  /// A position the player wrote lands on its episode, starts it, and leaves the others.
  @MainActor
  func testPositionsAreLaidOverTheRightEpisode() throws {
    let store = LocalWatchProgressStore(container: container)
    var item = try series()
    store.cacheItem(item)
    let asked = Date(timeIntervalSinceNow: -60)
    store.recordProgress(mediaId: seriesID, position: 900, duration: 2_400, season: 1, episode: 2)

    XCTAssertTrue(store.layPositions(over: &item, writtenAfter: asked))
    XCTAssertEqual(item.seasons?[0].episodes.map(\.watching.time), [0, 900, 0])
    XCTAssertEqual(item.seasons?[0].episodes.map(\.watched), [-1, 0, -1])
    XCTAssertFalse(store.layPositions(over: &item, writtenAfter: asked), "nothing left to change")
  }

  /// The player's copy of the title is changed where the page says, and only that.
  @MainActor
  func testUpdatingTheSnapshotChangesWhatThePlayerReads() throws {
    let store = LocalWatchProgressStore(container: container)
    let item = try series()
    store.cacheItem(item)
    store.updateSnapshot(for: seriesID) { $0.updateEpisode(id: 12) { $0.watched = 1 } }
    XCTAssertEqual(store.snapshot(for: seriesID)?.seasons?[0].episodes.map(\.watched), [-1, 1, -1])
    XCTAssertEqual(item.seasons?[0].episodes.map(\.watched), [-1, -1, -1])
    store.updateSnapshot(for: 1) { _ in XCTFail("no such title") }
  }
}
