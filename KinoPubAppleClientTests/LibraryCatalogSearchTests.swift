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
}
