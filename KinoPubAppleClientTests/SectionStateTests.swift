//
//  SectionStateTests.swift
//  KinoPubAppleClientTests
//
//  Switching sections keeps what each had (Sasha, 2026-10-31): a title opened in Search is
//  still there after a visit to Home, and Home's model — its banner — is the same one.
//

import XCTest
import KinoPubBackend
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
}
