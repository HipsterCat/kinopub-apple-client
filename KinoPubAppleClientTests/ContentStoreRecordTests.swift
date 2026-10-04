//
//  ContentStoreRecordTests.swift
//  KinoPubAppleClientTests
//
//  Rows keep refs, titles live in one record store, and a card is worded when the row
//  is read (docs/media-model.md, step 4).
//

import XCTest
import KinoPubBackend
import KinoPubMedia
import KinoPubUI
@testable import KinoPub

@MainActor
final class ContentStoreRecordTests: XCTestCase {

  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ContentStoreRecordTests-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func makeStore(viewer: ViewerStateReading? = nil) -> ContentStore {
    ContentStore(disk: RowSnapshotStore(directory: directory),
                 records: MediaRecordStore(disk: MediaRecordDisk(directory: directory)),
                 viewer: viewer)
  }

  func testATitleRowPaintsTheSameCardTheCatalogueBuilds() {
    let store = makeStore()
    let film = MediaItem.mock(id: 10, type: "movie")
    store.setItems([.title(film)], for: .folder(1))

    XCTAssertEqual(store.cards(.folder(1)), [MediaCard(film)])
    XCTAssertEqual(store.rows[.folder(1)]?.entries, [.title(.title(10))], "the row keeps the ref only")
  }

  func testATitleOnTwoRowsIsOneRecordAndPaintsTheNewestPayload() throws {
    let store = makeStore()
    store.setItems([.title(.mock(id: 10, type: "movie"))], for: .folder(1))
    let newer = try XCTUnwrap(Self.mock(id: 10, year: 1999))
    store.setItems([.title(newer)], for: .folder(2))

    XCTAssertEqual(store.records.records.count, 1)
    XCTAssertEqual(store.cards(.folder(1)).first?.year, 1999, "the older row reads the newer record")
    XCTAssertEqual(store.cards(.folder(2)).first?.year, 1999)
  }

  func testTheViewersStateIsLaidOverAtReadTime() {
    let viewer = ViewerStateReaderMock()
    let store = makeStore(viewer: viewer)
    store.setItems([.title(.mock(id: 10, type: "movie"))], for: .folder(1))
    XCTAssertEqual(store.cards(.folder(1)).first?.isWatched, false)

    viewer.overlays[.title(10)] = ViewerOverlay(isWatched: true)
    XCTAssertEqual(store.cards(.folder(1)).first?.isWatched, true, "no refetch needed")
  }

  func testRowsAndRecordsSurviveARelaunchAndOrphansAreDropped() {
    let store = makeStore()
    store.setItems([.title(.mock(id: 10, type: "movie")), .title(.mock(id: 11, type: "movie"))],
                   for: .folder(1))
    store.removeCard(id: 11, from: .folder(1))

    let relaunched = makeStore()
    XCTAssertEqual(relaunched.cards(.folder(1)).map(\.id), [10])
    XCTAssertEqual(Set(relaunched.records.records.keys), [.title(10)], "no row refers to 11 any more")
  }

  func testTheDetailPagesPayloadRefreshesATitleARowShows() throws {
    let store = makeStore()
    store.setItems([.title(.mock(id: 10, type: "movie"))], for: .folder(1))
    store.refreshRecord(with: try XCTUnwrap(Self.mock(id: 10, year: 1999)))
    XCTAssertEqual(store.cards(.folder(1)).first?.year, 1999)

    store.refreshRecord(with: .mock(id: 12, type: "movie"))
    XCTAssertNil(store.records.record(for: .title(12)), "a title no row shows is not kept")
    XCTAssertEqual(makeStore().cards(.folder(1)).first?.year, 1999, "and the refresh is on disk")
  }

  func testCardsThatAreNotOnTheModelStayCards() {
    let store = makeStore()
    let card = MediaCard(id: 5, posterURL: "", title: "Collection", opensCollection: true)
    store.setItems([.card(card)], for: .collections)

    XCTAssertEqual(store.cards(.collections), [card])
    XCTAssertTrue(store.records.records.isEmpty)
  }

  /// The same title as another payload would send it — a different year.
  private static func mock(id: Int, year: Int) -> MediaItem? {
    guard let data = try? JSONEncoder().encode(MediaItem.mock(id: id, type: "movie")),
          var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    json["year"] = year
    guard let edited = try? JSONSerialization.data(withJSONObject: json) else { return nil }
    return try? JSONDecoder().decode(MediaItem.self, from: edited)
  }

  func testRowsWrittenBeforeRefsStillPaint() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let card = MediaCard(id: 7, posterURL: "", title: "Yesterday")
    struct LegacyState: Encodable { let cards: [MediaCard]; let fetchedAt: Date }
    struct LegacyRow: Encodable { let key: RowKey; let state: LegacyState }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode([LegacyRow(key: .folder(1), state: LegacyState(cards: [card], fetchedAt: Date()))])
      .write(to: directory.appendingPathComponent("rows-v2.json"))

    XCTAssertEqual(makeStore().cards(.folder(1)), [card])
  }
}
