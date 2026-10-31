//
//  SectionStateTests.swift
//  KinoPubAppleClientTests
//
//  Switching sections keeps what each had (Sasha, 2026-10-31): a title opened in Search is
//  still there after a visit to Home, and Home's model — its banner — is the same one.
//

import XCTest
import KinoPubBackend
import KinoPubUI
@testable import KinoPub

@MainActor
final class SectionStateTests: XCTestCase {

  /// A section's stack torn down on leaving it writes back an empty path; the titles stay.
  func testLeavingASectionKeepsItsStack() {
    let navigation = NavigationState()
    navigation.selectedTab = .search
    navigation.path(for: .search).wrappedValue = [.detailsById(19288)]

    navigation.selectedTab = .home
    navigation.path(for: .search).wrappedValue = []   // the hidden stack's teardown

    navigation.selectedTab = .search
    XCTAssertEqual(navigation.searchRoutes.count, 1)
  }

  /// Going back on the section on screen still empties it.
  func testBackOnTheShownSectionStillPops() {
    let navigation = NavigationState()
    navigation.selectedTab = .search
    navigation.path(for: .search).wrappedValue = [.detailsById(19288)]
    navigation.path(for: .search).wrappedValue = []
    XCTAssertTrue(navigation.searchRoutes.isEmpty)
  }

  /// One model per section for the whole run: Home's banner is not drawn again.
  func testSectionModelIsMadeOnce() {
    let models = SectionModels()
    var made = 0
    let first = models.model("shelves-home") { made += 1; return NSObject() }
    let again = models.model("shelves-home") { made += 1; return NSObject() }
    XCTAssertTrue(first === again)
    XCTAssertEqual(made, 1)
  }

  /// A title kept for its stack: the same model on coming back, let go when popped.
  func testTitleModelLivesWhileOnTheStack() {
    let cache = MediaItemModelCache()
    var made = 0
    let make: () -> MediaItemModel = {
      made += 1
      return MediaItemModel(mediaItemId: 7, itemsService: VideoContentServiceMock(),
                            downloadManager: AppContext.shared.downloadManager,
                            linkProvider: AppRoutesLinkProvider(),
                            errorHandler: ErrorHandler())
    }
    let first = cache.model(tab: .search, itemID: 7, make: make)
    XCTAssertTrue(first === cache.model(tab: .search, itemID: 7, make: make))
    XCTAssertEqual(made, 1)
    cache.keep(only: [], on: .search)
    _ = cache.model(tab: .search, itemID: 7, make: make)
    XCTAssertEqual(made, 2)
  }

  /// The memory a page scrolls with outlives the page itself.
  func testScrollMemoryLivesInTheModel() {
    let models = SectionModels()
    let memory = models.model("search-memory") { ScrollMemory() }
    memory.y = 840
    XCTAssertEqual(models.model("search-memory") { ScrollMemory() }.y, 840)
  }
}
