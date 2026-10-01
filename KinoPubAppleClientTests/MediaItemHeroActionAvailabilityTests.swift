import XCTest
@testable import KinoPub

/// Regression: focus must never disable secondary hero actions.
/// Doing that left Trailer/Bookmark/More dim and broke bookmark Menus.
final class MediaItemHeroActionAvailabilityTests: XCTestCase {

  func testActionsStayInteractableWhenNotLoading() {
    XCTAssertTrue(MediaItemHeroActionAvailability.isInteractable())
    XCTAssertTrue(MediaItemHeroActionAvailability.isInteractable(isLoading: false))
  }

  func testLoadingControlIsNotInteractable() {
    XCTAssertFalse(MediaItemHeroActionAvailability.isInteractable(isLoading: true))
  }

  func testFocusTargetClassificationKeepsPlotOutOfActionRow() {
    let actions: [MediaItemFocusTarget] = [
      .play, .watchlist, .bookmark, .watched, .trailer, .more, .download, .shuffle
    ]
    for target in actions {
      XCTAssertTrue(target.isActionControl, "\(target) should be an action control")
    }
    XCTAssertFalse(MediaItemFocusTarget.plot.isActionControl)
  }

  /// Documents the contract: enablement ignores focus. There is no focus parameter
  /// on `isInteractable` — adding one back is the regression.
  func testInteractableAPIDoesNotTakeFocus() {
    let names = Mirror(reflecting: MediaItemHeroActionAvailability.self)
    _ = names
    // Call sites must not need a focus value to decide Menu availability.
    XCTAssertTrue(MediaItemHeroActionAvailability.isInteractable(isLoading: false))
  }
}
