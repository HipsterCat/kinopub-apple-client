import XCTest
@testable import KinoPubUI

final class StagedMenuBackTests: XCTestCase {

  func testNilFocusPassesThrough() {
    XCTAssertFalse(StagedMenuBack.shouldReturnToTop(
      focusedSection: nil, focusedItem: 3, topSection: 0, firstRowItemCount: 1))
  }

  func testFocusOnTopSectionFirstItemPassesThrough() {
    XCTAssertFalse(StagedMenuBack.shouldReturnToTop(
      focusedSection: 0, focusedItem: 0, topSection: 0, firstRowItemCount: 6))
  }

  func testNestedFocusOnTopSectionPassesThrough() {
    // Banner titles live in a nested collection; the page only knows the section.
    XCTAssertFalse(StagedMenuBack.shouldReturnToTop(
      focusedSection: 0, focusedItem: nil, topSection: 0, firstRowItemCount: 1))
  }

  func testSidewaysOnTheTopRailPassesThrough() {
    XCTAssertFalse(StagedMenuBack.shouldReturnToTop(
      focusedSection: 0, focusedItem: 11, topSection: 0, firstRowItemCount: 14))
  }

  func testSectionBelowTopReturns() {
    XCTAssertTrue(StagedMenuBack.shouldReturnToTop(
      focusedSection: 2, focusedItem: 0, topSection: 0, firstRowItemCount: 1))
  }

  func testGridSecondRowReturns() {
    XCTAssertTrue(StagedMenuBack.shouldReturnToTop(
      focusedSection: 0, focusedItem: 4, topSection: 0, firstRowItemCount: 4))
  }

  func testGridFirstRowLastItemPassesThrough() {
    XCTAssertFalse(StagedMenuBack.shouldReturnToTop(
      focusedSection: 0, focusedItem: 3, topSection: 0, firstRowItemCount: 4))
  }

  func testRailFirstRowCountIsTheWholeSection() {
    XCTAssertEqual(StagedMenuBack.firstRowItemCount(flowIsGrid: false, columns: 6, itemCount: 14), 14)
  }

  func testGridFirstRowCountIsColumnsCappedByItems() {
    XCTAssertEqual(StagedMenuBack.firstRowItemCount(flowIsGrid: true, columns: 4, itemCount: 20), 4)
    XCTAssertEqual(StagedMenuBack.firstRowItemCount(flowIsGrid: true, columns: 6, itemCount: 3), 3)
  }
}
