import XCTest
@testable import KinoPubUI

#if os(tvOS)
@MainActor
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

  func testHeaderActionsMatchTheSearchChipSize() {
    let chip = TVPageChip(id: "type", title: "Фильмы и сериалы")
    let size = TVPageHeaderView.actionSize(for: chip)
    XCTAssertEqual(size.width, TVPageChipCell.fittingWidth(for: chip))
    XCTAssertEqual(size.height, TVPageLayout.chipHeight)
    XCTAssertGreaterThan(size.width, TVPageLayout.chipHeight,
                         "a titled pill is wider than the round icon it used to be squeezed to")
  }

  func testGridHeadersWithActionsScrollWithTheContent() {
    XCTAssertFalse(TVPageLayout.headersPinToVisibleBounds,
                   "pinning overlays the title on the first row of covers")
  }

  func testLeadingConstantIsNeverNegative() {
    let chrome = ShelfMetrics.tvPageChrome(
      viewFrameInWindow: CGRect(x: 120, y: 0, width: 1680, height: 1080),
      windowWidth: 1920
    )
    XCTAssertEqual(chrome.leadingConstant, 0)
    XCTAssertGreaterThanOrEqual(chrome.leadingConstant, 0)
  }

  func testBannerChromeTextColorIsForcedDark() {
    let chrome = TVPageBannerChrome.current
    let lightColor = chrome.resolvedTextColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    let darkColor = chrome.resolvedTextColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    XCTAssertEqual(lightColor, darkColor, "Banner text color must stay vivid and not degrade in light appearance")

    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    XCTAssertTrue(lightColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
    XCTAssertGreaterThan(red, 0.9, "Red channel must remain bright")
    XCTAssertGreaterThan(green, 0.9, "Green channel must remain bright")
    XCTAssertGreaterThan(blue, 0.9, "Blue channel must remain bright")
  }
}
#endif
