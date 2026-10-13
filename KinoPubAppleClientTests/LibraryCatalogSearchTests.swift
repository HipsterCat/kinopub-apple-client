//
//  LibraryCatalogSearchTests.swift
//  KinoPubAppleClientTests
//
//  What a typed query is on tvOS: a search from the third letter, scoped per search.
//

import XCTest
import KinoPubBackend
@testable import KinoPub

@MainActor
final class LibraryCatalogSearchTests: XCTestCase {

  private func catalog() -> LibraryCatalog {
    LibraryCatalog(itemsService: VideoContentServiceMock(),
                   authState: AuthState(authService: AuthorizationServiceMock(),
                                        accessTokenService: AccessTokenServiceMock()),
                   errorHandler: ErrorHandler(),
                   minimumQueryLength: 3)
  }

  /// One or two letters only narrow what is loaded; the third makes it a search.
  func testSearchStartsAtTheThirdLetter() {
    let catalog = catalog()
    catalog.query = "та"
    XCTAssertFalse(catalog.isSearching)
    XCTAssertEqual(catalog.searchQuery, "")
    catalog.query = " таб "
    XCTAssertTrue(catalog.isSearching)
    XCTAssertEqual(catalog.searchQuery, "таб")
  }

  /// Where to look is not remembered: a cleared field starts the next search everywhere.
  func testClearingTheFieldResetsTheScope() async throws {
    let catalog = catalog()
    catalog.query = "табак"
    catalog.updateSearchField(.cast)
    XCTAssertEqual(catalog.searchField, .cast)
    catalog.query = ""
    try await Task.sleep(for: .milliseconds(800))
    XCTAssertNil(catalog.searchField)
  }

  /// Staying in a search (editing the text) keeps the scope.
  func testEditingTheQueryKeepsTheScope() async throws {
    let catalog = catalog()
    catalog.query = "табак"
    catalog.updateSearchField(.director)
    catalog.query = "табаков"
    try await Task.sleep(for: .milliseconds(800))
    XCTAssertEqual(catalog.searchField, .director)
  }

  func testSilentRevalidateKeepsItemsAndSkipsWhenFresh() async {
    let box = FetchBox(items: [MediaItem.mock(id: 1), MediaItem.mock(id: 2)])
    let catalog = authorizedCatalog(box: box)
    await catalog.load()
    XCTAssertEqual(catalog.items.map(\.id), [1, 2])
    XCTAssertFalse(catalog.isLoading)
    XCTAssertEqual(box.fetches, 1)

    await catalog.revalidate(force: false)
    XCTAssertEqual(box.fetches, 1, "a just-loaded page is not stale")
    XCTAssertEqual(catalog.items.map(\.id), [1, 2])
    XCTAssertFalse(catalog.isLoading)
  }

  func testSilentRevalidateAppliesOnlyAChangedFirstPage() async {
    let box = FetchBox(items: [MediaItem.mock(id: 1), MediaItem.mock(id: 2)])
    let catalog = authorizedCatalog(box: box)
    await catalog.load()
    catalog.lastLoadedAt = Date().addingTimeInterval(-(LibraryCatalog.staleAfter + 1))
    box.items = [MediaItem.mock(id: 1), MediaItem.mock(id: 2)]
    await catalog.revalidate(force: false)
    XCTAssertEqual(box.fetches, 2)
    XCTAssertEqual(catalog.items.map(\.id), [1, 2], "the same prefix is not a new listing")
    XCTAssertFalse(catalog.isLoading)

    catalog.lastLoadedAt = Date().addingTimeInterval(-(LibraryCatalog.staleAfter + 1))
    box.items = [MediaItem.mock(id: 3), MediaItem.mock(id: 1)]
    await catalog.revalidate(force: false)
    XCTAssertEqual(box.fetches, 3)
    XCTAssertEqual(catalog.items.map(\.id), [3, 1])
    XCTAssertFalse(catalog.isLoading)
  }

  func testReenteringTheTabForcesASilentRefresh() async {
    let box = FetchBox(items: [MediaItem.mock(id: 1)])
    let catalog = authorizedCatalog(box: box)
    await catalog.load()
    box.items = [MediaItem.mock(id: 4)]
    await catalog.revalidate(force: true)
    XCTAssertEqual(box.fetches, 2)
    XCTAssertEqual(catalog.items.map(\.id), [4])
    XCTAssertFalse(catalog.isLoading)
  }

  private func authorizedCatalog(box: FetchBox) -> LibraryCatalog {
    var service = VideoContentServiceMock()
    service.catalogItems = { _, _, _ in
      box.fetches += 1
      return PaginatedData(items: box.items,
                           pagination: Pagination(total: 1, current: 1, perpage: 20))
    }
    let auth = AuthState(authService: AuthorizationServiceMock(),
                         accessTokenService: AccessTokenServiceMock())
    auth.userState = .authorized
    let catalog = LibraryCatalog(itemsService: service,
                                 authState: auth,
                                 errorHandler: ErrorHandler(),
                                 minimumQueryLength: 3)
    catalog.seedPickersForTesting()
    return catalog
  }
}

private final class FetchBox: @unchecked Sendable {
  var fetches = 0
  var items: [MediaItem]
  init(items: [MediaItem]) { self.items = items }
}
