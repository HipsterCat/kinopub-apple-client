//
//  WatchingListCacheTests.swift
//  KinoPubAppleClientTests
//

import XCTest
import KinoPubBackend
import KinoPubUI
@testable import KinoPub

@MainActor
final class WatchingListCacheTests: XCTestCase {

  override func setUp() async throws {
    try await super.setUp()
    WatchingListCache.shared.clear()
  }

  override func tearDown() async throws {
    WatchingListCache.shared.clear()
    try await super.tearDown()
  }

  func testCacheHitSkipsSecondNetworkCall() async throws {
    let box = WatchingFetchBox()
    let service = box.service()
    let cache = WatchingListCache.shared
    cache.clear()

    let first = try await cache.movies(using: service)
    let second = try await cache.movies(using: service)
    XCTAssertEqual(first.map(\.id), [1])
    XCTAssertEqual(second.map(\.id), [1])
    XCTAssertEqual(box.movieFetches, 1)
  }

  func testInFlightCallsCoalesce() async throws {
    let box = WatchingFetchBox(delayNanoseconds: 120_000_000)
    let service = box.service()
    let cache = WatchingListCache.shared
    cache.clear()

    async let a = cache.serials(subscribedOnly: true, using: service)
    async let b = cache.serials(subscribedOnly: true, using: service)
    let (left, right) = try await (a, b)
    XCTAssertEqual(left.map(\.id), [2])
    XCTAssertEqual(right.map(\.id), [2])
    XCTAssertEqual(box.serialFetchesSubscribed, 1)
  }

  func testInvalidateForcesRefetch() async throws {
    let box = WatchingFetchBox()
    let service = box.service()
    let cache = WatchingListCache.shared
    cache.clear()

    _ = try await cache.movies(using: service)
    cache.invalidate()
    box.movies = [WatchingItem(id: 9, type: "movie", title: "B", posters: WatchingFetchBox.emptyPosters)]
    let again = try await cache.movies(using: service)
    XCTAssertEqual(again.map(\.id), [9])
    XCTAssertEqual(box.movieFetches, 2)
  }

  func testForceBypassesWarmCache() async throws {
    let box = WatchingFetchBox()
    let service = box.service()
    let cache = WatchingListCache.shared
    cache.clear()

    _ = try await cache.serials(subscribedOnly: false, using: service)
    box.serialsUnsubscribed = [
      WatchingItem(id: 7, type: "serial", title: "C", posters: WatchingFetchBox.emptyPosters)
    ]
    let forced = try await cache.serials(subscribedOnly: false, using: service, force: true)
    XCTAssertEqual(forced.map(\.id), [7])
    XCTAssertEqual(box.serialFetchesUnsubscribed, 2)
  }

  func testCachedItemReadsWarmSubscribedSerialWithoutFetch() async throws {
    let box = WatchingFetchBox()
    let service = box.service()
    let cache = WatchingListCache.shared
    cache.clear()

    XCTAssertNil(cache.cachedItem(id: 2, subscribed: true))
    _ = try await cache.serials(subscribedOnly: true, using: service)
    let item = cache.cachedItem(id: 2, subscribed: true)
    XCTAssertEqual(item?.id, 2)
    XCTAssertEqual(item?.unwatchedCount, 9)
    XCTAssertEqual(box.serialFetchesSubscribed, 1,
                   "lookup must not hit the network again")
  }

  func testContentStorePaintsUnwatchedCountFromWarmWatchingCache() async throws {
    let box = WatchingFetchBox()
    let service = box.service()
    let cache = WatchingListCache.shared
    cache.clear()
    _ = try await cache.serials(subscribedOnly: true, using: service)

    let viewer = ViewerStateReaderMock()
    viewer.overlays[.title(2)] = ViewerOverlay(isFollowing: true)
    let disk = FileManager.default.temporaryDirectory
      .appendingPathComponent("WatchingListCacheChrome-\(UUID().uuidString)", isDirectory: true)
    let store = ContentStore(disk: RowSnapshotStore(directory: disk), viewer: viewer)
    // Catalog-shaped card: following, but no unwatchedEpisodes of its own.
    store.setItems([.card(MediaCard(id: 2, posterURL: "", title: "S", isSeries: true,
                                    viewerState: ViewerState(isFollowing: true)))],
                   for: .homeSection("chrome-test"))
    XCTAssertEqual(store.cards(.homeSection("chrome-test")).first?.unwatchedEpisodes, 9)
  }

  func testContentStoreWatchInvalidateClearsWatchingCache() async throws {
    let box = WatchingFetchBox()
    let service = box.service()
    let cache = WatchingListCache.shared
    cache.clear()
    _ = try await cache.movies(using: service)
    XCTAssertEqual(box.movieFetches, 1)

    let disk = FileManager.default.temporaryDirectory
      .appendingPathComponent("WatchingListCacheTests-\(UUID().uuidString)", isDirectory: true)
    let store = ContentStore(disk: RowSnapshotStore(directory: disk),
                             viewer: ViewerStateReaderMock())
    store.setItems([.card(MediaCard(id: 1, posterURL: "", title: "x"))], for: .continueWatching)
    store.invalidate(family: .watch)

    box.movies = [WatchingItem(id: 3, type: "movie", title: "D", posters: WatchingFetchBox.emptyPosters)]
    let after = try await cache.movies(using: service)
    XCTAssertEqual(after.map(\.id), [3])
    XCTAssertEqual(box.movieFetches, 2)
  }
}

/// Counting mock that can `await Task.sleep` so two callers overlap on MainActor.
@MainActor
private final class WatchingFetchBox {
  static let emptyPosters = Posters(small: "", medium: "", big: "")
  var movieFetches = 0
  var serialFetchesSubscribed = 0
  var serialFetchesUnsubscribed = 0
  var delayNanoseconds: UInt64 = 0
  var movies: [WatchingItem] = [
    WatchingItem(id: 1, type: "movie", title: "A", posters: emptyPosters)
  ]
  var serialsSubscribed: [WatchingItem] = [
    WatchingItem(id: 2, type: "serial", title: "S", posters: emptyPosters, total: 10, watched: 1, new: 2)
  ]
  var serialsUnsubscribed: [WatchingItem] = [
    WatchingItem(id: 4, type: "serial", title: "U", posters: emptyPosters, total: 8, watched: 2)
  ]

  init(delayNanoseconds: UInt64 = 0) {
    self.delayNanoseconds = delayNanoseconds
  }

  func service() -> any VideoContentService {
    DelayingWatchingService(box: self)
  }
}

/// Forwards the stock mock, but sleeps before watching GETs so in-flight coalesce is observable.
private struct DelayingWatchingService: VideoContentService {
  let box: WatchingFetchBox
  private let base = VideoContentServiceMock()

  func fetch(shortcut: MediaShortcut, contentType: MediaType, page: Int?, perPage: Int?) async throws -> PaginatedData<MediaItem> {
    try await base.fetch(shortcut: shortcut, contentType: contentType, page: page, perPage: perPage)
  }
  func search(query: String?, filter: LibraryFilter?, sort: MediaSortOrder?,
              field: SearchItemsRequest.Field?,
              page: Int?, perPage: Int?) async throws -> PaginatedData<MediaItem> {
    try await base.search(query: query, filter: filter, sort: sort, field: field, page: page, perPage: perPage)
  }
  func autocomplete(query: String) async throws -> [SearchAutocompleteEntry] {
    try await base.autocomplete(query: query)
  }
  func fetchDetails(for id: String, excludeLinks: Bool) async throws -> SingleItemData<MediaItem> {
    try await base.fetchDetails(for: id, excludeLinks: excludeLinks)
  }
  func fetchMediaLinks(mediaId: Int) async throws -> MediaLinks {
    try await base.fetchMediaLinks(mediaId: mediaId)
  }
  func fetchSimilar(for id: String) async throws -> ArrayData<MediaItem> {
    try await base.fetchSimilar(for: id)
  }
  func fetchBookmarks() async throws -> ArrayData<Bookmark> {
    try await base.fetchBookmarks()
  }
  func fetchBookmarkItems(id: String, page: Int?, perPage: Int?) async throws -> BookmarkFolderItemsData {
    try await base.fetchBookmarkItems(id: id, page: page, perPage: perPage)
  }
  func fetchWatchingMovies() async throws -> ArrayData<WatchingItem> {
    await MainActor.run { box.movieFetches += 1 }
    let delay = await MainActor.run { box.delayNanoseconds }
    if delay > 0 { try await Task.sleep(nanoseconds: delay) }
    let items = await MainActor.run { box.movies }
    return ArrayData.mock(data: items)
  }
  func fetchWatchingSerials(subscribedOnly: Bool) async throws -> ArrayData<WatchingItem> {
    let delay = await MainActor.run { () -> UInt64 in
      if subscribedOnly { box.serialFetchesSubscribed += 1 }
      else { box.serialFetchesUnsubscribed += 1 }
      return box.delayNanoseconds
    }
    if delay > 0 { try await Task.sleep(nanoseconds: delay) }
    let items = await MainActor.run {
      subscribedOnly ? box.serialsSubscribed : box.serialsUnsubscribed
    }
    return ArrayData.mock(data: items)
  }
  func fetchHistory(page: Int?, perPage: Int) async throws -> HistoryData {
    try await base.fetchHistory(page: page, perPage: perPage)
  }
  func fetchItems(filter: LibraryFilter, page: Int?, perPage: Int?) async throws -> PaginatedData<MediaItem> {
    try await base.fetchItems(filter: filter, page: page, perPage: perPage)
  }
  func fetchGenres(for type: MediaType?) async throws -> ArrayData<MediaGenre> {
    try await base.fetchGenres(for: type)
  }
  func fetchCountries() async throws -> ArrayData<Country> {
    try await base.fetchCountries()
  }
  func fetchItemFolders(itemId: Int) async throws -> ArrayData<Bookmark> {
    try await base.fetchItemFolders(itemId: itemId)
  }
  func toggleBookmark(itemId: Int, folderId: Int) async throws {
    try await base.toggleBookmark(itemId: itemId, folderId: folderId)
  }
  func fetchTVChannels() async throws -> [TVChannel] {
    try await base.fetchTVChannels()
  }
}
