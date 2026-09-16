import XCTest
@testable import KinoPubUI

#if os(tvOS)
final class TVPageChromeTests: XCTestCase {

  func testFullBleedHostKeeps80ptLeadingAndUsesCollectionWidthForPeek() {
    let chrome = ShelfMetrics.tvPageChrome(
      viewFrameInWindow: CGRect(x: 0, y: 0, width: 1920, height: 1080),
      windowWidth: 1920
    )
    XCTAssertEqual(chrome.leadingConstant, 80)
    XCTAssertEqual(chrome.trailingOverflow, 0)
  }

  func testSafeAreaHostDoesNotDoubleCutAndOverflowsTrailingForPeek() {
    let chrome = ShelfMetrics.tvPageChrome(
      viewFrameInWindow: CGRect(x: 80, y: 0, width: 1760, height: 1080),
      windowWidth: 1920
    )
    XCTAssertEqual(chrome.leadingConstant, 0)
    XCTAssertEqual(chrome.trailingOverflow, 80)
  }

  func testLeadingConstantIsNeverNegative() {
    let chrome = ShelfMetrics.tvPageChrome(
      viewFrameInWindow: CGRect(x: 120, y: 0, width: 1680, height: 1080),
      windowWidth: 1920
    )
    XCTAssertEqual(chrome.leadingConstant, 0)
    XCTAssertGreaterThanOrEqual(chrome.leadingConstant, 0)
  }
}
#endif
