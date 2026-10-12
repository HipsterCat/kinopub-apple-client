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

  /// Following cards are stored as `.card`, then painted with today's viewer state.
  /// The unwatched count must survive that overlay or every cover has an empty subtitle.
  func testAFollowingCardKeepsItsUnwatchedCountWhenTheViewerStateIsLaidOver() {
    let viewer = ViewerStateReaderMock()
    viewer.overlays[.title(1)] = ViewerOverlay(isFollowing: true)
    let store = makeStore(viewer: viewer)
    let card = LibrarySectionCatalog.followingCard(for: WatchingItem(
      id: 1, type: "serial", title: "Дом Дракона / House of the Dragon",
      posters: Posters(small: "", medium: "https://x/m.jpg", big: "", wide: nil),
      total: 18, watched: 16, new: 2))
    store.setItems([.card(card)], for: .watchlist)
    let painted = store.cards(.watchlist).first
    XCTAssertEqual(painted?.unwatchedEpisodes, 2)
    XCTAssertEqual(painted?.subtitle, EpisodesLeftText(2)?.formatted())
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

  /// Invalidate while a fetch is in flight used to stamp `fetchedAt = now` on the
  /// discarded decode — Home then trusted the old row for the whole TTL, which is
  /// why the network log filled with requests and Continue Watching never moved.
  func testAnInvalidateDuringFetchDiscardsTheStaleWriteAndRetries() async {
    let store = makeStore()
    store.setItems([.card(MediaCard(id: 1, posterURL: "https://x/o.jpg", title: "Old"))],
                   for: .continueWatching)
    let hold = FetchHold()
    let calls = FetchCounter()

    let refresh = Task {
      await store.refresh(.continueWatching) {
        let n = await calls.next()
        if n == 1 {
          await hold.signalEnteredAndWait()
          return [.card(MediaCard(id: 1, posterURL: "https://x/s.jpg", title: "Stale"))]
        }
        return [.card(MediaCard(id: 1, posterURL: "https://x/n.jpg", title: "New"))]
      }
    }

    await hold.waitUntilEntered()
    store.invalidate(family: .watch)
    XCTAssertEqual(store.cards(.continueWatching).first?.title, "Old",
                   "the in-flight decode must not land")
    XCTAssertTrue(store.isStale(.continueWatching))
    await hold.release()
    await refresh.value

    XCTAssertEqual(store.cards(.continueWatching).first?.title, "New")
    XCTAssertFalse(store.isStale(.continueWatching))
    let total = await calls.value
    XCTAssertEqual(total, 2, "the discarded fetch must be followed by a retry")
  }

  func testWatchInvalidatePostsANotification() async {
    let store = makeStore()
    store.setItems([.card(MediaCard(id: 1, posterURL: "", title: "A"))],
                   for: .continueWatching)
    let posted = expectation(description: "watch invalidate")
    let observer = NotificationCenter.default.addObserver(
      forName: .contentStoreDidInvalidateWatch, object: nil, queue: .main
    ) { _ in posted.fulfill() }
    store.invalidate(family: .watch)
    await fulfillment(of: [posted], timeout: 1)
    NotificationCenter.default.removeObserver(observer)
  }

  func testCatalogInvalidateDoesNotPostAWatchNotification() async {
    let store = makeStore()
    store.setItems([.card(MediaCard(id: 1, posterURL: "", title: "A"))],
                   for: .collections)
    let posted = expectation(description: "must not fire")
    posted.isInverted = true
    let observer = NotificationCenter.default.addObserver(
      forName: .contentStoreDidInvalidateWatch, object: nil, queue: .main
    ) { _ in posted.fulfill() }
    store.invalidate(family: .catalog)
    await fulfillment(of: [posted], timeout: 0.2)
    NotificationCenter.default.removeObserver(observer)
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

/// Gates a fetch so the test can invalidate while it is in flight.
private actor FetchHold {
  private var entered: CheckedContinuation<Void, Never>?
  private var go: CheckedContinuation<Void, Never>?
  private var released = false

  func waitUntilEntered() async {
    await withCheckedContinuation { continuation in
      if released {
        continuation.resume()
      } else {
        entered = continuation
      }
    }
  }

  func signalEnteredAndWait() async {
    entered?.resume()
    entered = nil
    await withCheckedContinuation { continuation in
      if released {
        continuation.resume()
      } else {
        go = continuation
      }
    }
  }

  func release() {
    released = true
    entered?.resume()
    entered = nil
    go?.resume()
    go = nil
  }
}

private actor FetchCounter {
  private(set) var value = 0
  func next() -> Int {
    value += 1
    return value
  }
}
