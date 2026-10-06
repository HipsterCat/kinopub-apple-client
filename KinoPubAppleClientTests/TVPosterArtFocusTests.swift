//
//  TVPosterArtFocusTests.swift
//  KinoPubAppleClientTests
//
//  A poster's art wears the focused look when its own cell is focused and not when some
//  other view that merely contains it is — the detail page's SwiftUI container, which UIKit
//  names the focused view while the hero's buttons hold focus (tvOS 26.5: every poster of
//  every shelf looked focused at once). UIKit's question is asked directly here, the way it
//  asks it on layout, so no focus system has to be driven. tvOS 27.2 has no such question and
//  these tests skip there.
//

#if os(tvOS)
import TVUIKit
import UIKit
import XCTest
@testable import KinoPubUI

@MainActor
final class TVPosterArtFocusTests: XCTestCase {

  private let ask = NSSelectorFromString("_updateLayeredImageIsFocusedWithFocusedView:focusAnimationCoordinator:")

  private var window: UIWindow!
  /// Stands for the SwiftUI container: a view that holds everything and is never itself a cell.
  private var container: UIView!

  override func setUp() async throws {
    try await super.setUp()
    window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    container = UIView(frame: window.bounds)
    window.addSubview(container)
    window.isHidden = false
  }

  override func tearDown() async throws {
    window.isHidden = true
    window = nil
    container = nil
    try await super.tearDown()
  }

  private var artwork: UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 258, height: 387)).image { context in
      UIColor.systemGreen.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 258, height: 387))
    }
  }

  private func stack(of imageView: UIImageView) -> UIView? {
    imageView.subviews.first { String(describing: type(of: $0)) == "_UIStackedImageContainerView" }
  }

  private func isFocused(_ imageView: UIImageView) throws -> Bool {
    let stack = try XCTUnwrap(stack(of: imageView), "UIKit built no stack for the art")
    return try XCTUnwrap(stack.value(forKey: "isStackFocused") as? Bool)
  }

  /// UIKit's own layout-time question: "is this art inside the focused view?".
  private func tell(_ imageView: UIImageView, focusedView: UIView?) {
    _ = imageView.perform(ask, with: focusedView, with: nil)
  }

  /// A bare art view in the container that follows UIKit's rule as shipped. The question
  /// exists on tvOS 26.x; 27.2 has no such method (and no such bug), so there is nothing to test.
  private func controlArt() throws -> UIImageView {
    try XCTSkipUnless(UIImageView.instancesRespond(to: ask),
                      "this OS has no layout-time focus question for a layered image")
    let imageView = UIImageView(image: artwork)
    imageView.adjustsImageWhenAncestorFocused = true
    imageView.frame = CGRect(x: 600, y: 100, width: 258, height: 387)
    container.addSubview(imageView)
    window.layoutIfNeeded()
    try XCTSkipIf(stack(of: imageView) == nil, "this OS builds no stack for a plain image view")
    tell(imageView, focusedView: container)
    try XCTSkipUnless(try isFocused(imageView),
                      "this OS does not read a view that contains the art as its focus — nothing to guard against")
    return imageView
  }

  private func cellWithArt() throws -> TVPageLockupPosterCell {
    let cell = TVPageLockupPosterCell(frame: CGRect(x: 100, y: 100, width: 300, height: 450))
    container.addSubview(cell)
    cell.posterView.contentSize = CGSize(width: 258, height: 387)
    cell.posterView.image = artwork
    window.layoutIfNeeded()
    try XCTSkipIf(stack(of: cell.posterView.imageView) == nil, "UIKit built no stack for the poster's art")
    return cell
  }

  /// The control: without the guard, UIKit answers yes for a container. If it does not on this
  /// OS there is nothing for the guard to do and the other tests would pass for nothing.
  func testUIKitReadsAContainerAsFocusOnThisOS() throws {
    _ = try controlArt()
  }

  func testAPostersArtIsNotFocusedByAViewThatOnlyContainsIt() throws {
    _ = try controlArt()
    let cell = try cellWithArt()
    let art = cell.posterView.imageView
    tell(art, focusedView: container)
    XCTAssertFalse(try isFocused(art), "the container is not the cell")
    tell(art, focusedView: window)
    XCTAssertFalse(try isFocused(art))
  }

  func testAPostersArtIsFocusedByItsOwnCellAndNoLongerWhenFocusLeaves() throws {
    _ = try controlArt()
    let cell = try cellWithArt()
    let art = cell.posterView.imageView
    tell(art, focusedView: cell)
    XCTAssertTrue(try isFocused(art))
    tell(art, focusedView: container)
    XCTAssertFalse(try isFocused(art), "focus went to the container the cell is in")
    tell(art, focusedView: cell)
    tell(art, focusedView: nil)
    XCTAssertFalse(try isFocused(art), "nothing is focused")
  }

  /// Another cell's focus never lights this one (always true, but it is the rule the guard states).
  func testAPostersArtIsNotFocusedByAnotherCell() throws {
    _ = try controlArt()
    let cell = try cellWithArt()
    let other = UIView(frame: CGRect(x: 800, y: 100, width: 300, height: 450))
    container.addSubview(other)
    tell(cell.posterView.imageView, focusedView: other)
    XCTAssertFalse(try isFocused(cell.posterView.imageView))
  }

  /// Art that no cell has claimed is left to UIKit.
  func testArtOfNothingTheGuardOwnsIsUntouched() throws {
    let art = try controlArt()
    tell(art, focusedView: container)
    XCTAssertTrue(try isFocused(art))
  }
}
#endif
