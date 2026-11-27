//
//  WatchingListCacheTests.swift
//  PiraticTests
//

import XCTest
import Observation
import Synchronization
import KinoPubBackend
import PiraticUI
@testable import Piratic

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

  // MARK: - «Новые серии»: one count everywhere

  /// The tab's badge, the page's subtitle, the Watching covers and Library Following all
  /// count from the followed list: a caught-up series (its `new` not yet cleared) counts
  /// nothing anywhere. The badge summed `new` while the covers counted `total − watched`.
  func testNewEpisodesBadgeSubtitleAndCoversAgree() {
    let posters = WatchingFetchBox.emptyPosters
    let followed = [
      WatchingItem(id: 128431, type: "serial", title: "Яга / Yaga", posters: posters,
                   total: 6, watched: 4, new: 2),
      WatchingItem(id: 128597, type: "serial", title: "Ноктюрн / Nocturne", posters: posters,
                   total: 5, watched: 4, new: 1),
      WatchingItem(id: 7, type: "serial", title: "Досмотрен / Caught up", posters: posters,
                   total: 28, watched: 28, new: 1)
    ]
    let viewer = ViewerStateReaderMock()
    for item in followed { viewer.overlays[.title(item.id)] = ViewerOverlay(isFollowing: true) }
    let disk = FileManager.default.temporaryDirectory
      .appendingPathComponent("NewEpisodesCount-\(UUID().uuidString)", isDirectory: true)
    let store = ContentStore(disk: RowSnapshotStore(directory: disk), viewer: viewer)
    store.setItems(followed.map { .card(WatchlistView.card(for: $0)) }, for: .watchlist)

    let painted = store.cards(.watchlist).map(\.followedUnwatchedEpisodes)
    XCTAssertEqual(painted, [2, 1, nil], "covers")
    XCTAssertEqual(followed.unwatchedEpisodeTotal, 3, "badge")
    XCTAssertEqual(painted.compactMap { $0 }.reduce(0, +), followed.unwatchedEpisodeTotal, "subtitle")
    XCTAssertEqual(followed.map { LibrarySectionCatalog.followingCard(for: $0).followedUnwatchedEpisodes },
                   painted, "Library Following")
  }

  /// A local «not following» on a title the server lists as followed hides its count;
  /// the server's answer replaces it unless the user toggled after the request left.
  func testServerFollowReplacesAStaleLocalMark() {
    let asked = Date()
    XCTAssertEqual(MediaLibraryStore.reconciledFollow(local: false, toggledAt: nil,
                                                      server: true, requestedAt: asked), true,
                   "a mark from an earlier launch or another device")
    XCTAssertEqual(MediaLibraryStore.reconciledFollow(local: false, toggledAt: asked.addingTimeInterval(-60),
                                                      server: true, requestedAt: asked), true,
                   "a toggle the request already carries")
    XCTAssertEqual(MediaLibraryStore.reconciledFollow(local: false, toggledAt: asked.addingTimeInterval(1),
                                                      server: true, requestedAt: asked), false,
                   "a toggle made while the request was out")

    let viewer = ViewerStateReaderMock()
    viewer.overlays[.title(128431)] = ViewerOverlay(isFollowing: false)
    let disk = FileManager.default.temporaryDirectory
      .appendingPathComponent("NewEpisodesStale-\(UUID().uuidString)", isDirectory: true)
    let store = ContentStore(disk: RowSnapshotStore(directory: disk), viewer: viewer)
    let yaga = WatchingItem(id: 128431, type: "serial", title: "Яга / Yaga",
                            posters: WatchingFetchBox.emptyPosters, total: 6, watched: 4, new: 2)
    store.setItems([.card(WatchlistView.card(for: yaga))], for: .watchlist)
    XCTAssertNil(store.cards(.watchlist).first?.followedUnwatchedEpisodes,
                 "what the stale mark did — why it has to be reconciled")
  }

  /// Each followed list fetched from the network reports its ids and when it was asked —
  /// what the app reconciles follow marks with. A cache hit or another list does not.
  func testFollowedListFetchReportsItsIDs() async throws {
    let box = WatchingFetchBox()
    let service = box.service()
    let cache = WatchingListCache.shared
    var reports: [([Int], Date)] = []
    cache.onFollowedSerialsFetched = { reports.append(($0, $1)) }
    defer { cache.onFollowedSerialsFetched = nil }

    let before = Date()
    _ = try await cache.serials(subscribedOnly: false, using: service)
    XCTAssertTrue(reports.isEmpty)
    _ = try await cache.serials(subscribedOnly: true, using: service)
    _ = try await cache.serials(subscribedOnly: true, using: service)
    XCTAssertEqual(reports.map(\.0), [[2]])
    XCTAssertGreaterThanOrEqual(reports.first?.1 ?? .distantPast, before)
  }

  // MARK: - «Новые серии» badge follows the list (2026-11-24)

  /// Sasha's case: Dexter (2 new) followed at launch, then «12 12 12» and «Reggie Dinkins»
  /// (1 each). The badge stayed at 2 while the page said 4 — the badge was the root
  /// view's own number, fetched at sign-in and on a tab switch at most every two minutes.
  /// The arithmetic test above passed: nothing checked that the badge *changes* with the
  /// list. Here the follow path (invalidate + `refreshFollowed`) must move the one number
  /// both read, at once, and it counts episodes (4), not serials (3).
  func testFollowingASeriesMovesTheBadgeAndTheSubtitleAtOnce() async throws {
    let box = WatchingFetchBox()
    let service = box.service()
    let cache = WatchingListCache.shared
    let posters = WatchingFetchBox.emptyPosters
    let dexter = WatchingItem(id: 1, type: "serial", title: "Декстер / Dexter", posters: posters,
                              total: 10, watched: 8, new: 2)
    box.serialsSubscribed = [dexter]
    _ = try await cache.serials(subscribedOnly: true, using: service)
    XCTAssertEqual(cache.followedEpisodeTotal, 2)
    let revision = cache.followedListRevision

    // Follow two more, the way the title page and the card menu do.
    box.serialsSubscribed = [
      dexter,
      WatchingItem(id: 2, type: "serial", title: "12 12 12", posters: posters,
                   total: 3, watched: 2, new: 1),
      WatchingItem(id: 3, type: "serial", title: "Падение и взлёт / Reggie Dinkins", posters: posters,
                   total: 1, watched: 0, new: 1)
    ]
    let disk = FileManager.default.temporaryDirectory
      .appendingPathComponent("FollowMovesBadge-\(UUID().uuidString)", isDirectory: true)
    let store = ContentStore(disk: RowSnapshotStore(directory: disk), viewer: ViewerStateReaderMock())
    store.setItems([.card(WatchlistView.card(for: dexter))], for: .watchlist)

    let badgeRepainted = RepaintFlag()
    withObservationTracking { _ = cache.followedEpisodeTotal } onChange: { badgeRepainted.set() }
    store.invalidate(family: .watch)
    XCTAssertEqual(cache.followedEpisodeTotal, 2, "the badge does not blink to nothing while the list refetches")
    await cache.refreshFollowed(using: service)

    XCTAssertTrue(badgeRepainted.value, "the tab badge reads this number in its body")
    XCTAssertEqual(cache.followedEpisodeTotal, 4, "episodes, not the 3 serials")
    XCTAssertGreaterThan(cache.followedListRevision, revision, "«Новые серии» reloads its covers")
    XCTAssertEqual(box.serialFetchesSubscribed, 2)

    let staleCards = store.cards(.watchlist)
    XCTAssertEqual(WatchlistView.newEpisodesTotal(cached: cache.followedEpisodeTotal, cards: staleCards), 4,
                   "the subtitle says what the badge says, even before the covers reload")
  }

  /// The same list fetched again (a tab switch, Home) changes nothing: no reload of the
  /// page, no repaint. An account switch drops the number.
  func testAnUnchangedListKeepsTheRevisionAndClearDropsTheBadge() async throws {
    let box = WatchingFetchBox()
    let service = box.service()
    let cache = WatchingListCache.shared
    _ = try await cache.serials(subscribedOnly: true, using: service)
    let revision = cache.followedListRevision
    XCTAssertEqual(cache.followedEpisodeTotal, 9, "total 10, watched 1")
    await cache.refreshFollowed(using: service)
    XCTAssertEqual(cache.followedListRevision, revision)
    cache.clear()
    XCTAssertNil(cache.followedEpisodeTotal)
  }
}

/// Set from `withObservationTracking`'s `@Sendable` onChange.
private final class RepaintFlag: Sendable {
  private let flag = Mutex(false)
  func set() { flag.withLock { $0 = true } }
  var value: Bool { flag.withLock { $0 } }
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
