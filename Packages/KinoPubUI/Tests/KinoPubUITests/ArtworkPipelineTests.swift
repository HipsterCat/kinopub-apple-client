import XCTest
@testable import KinoPubUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class ArtworkPipelineTests: XCTestCase {
  func testPixelSizeZeroStaysFullResolution() {
    XCTAssertEqual(Artwork.pixelSize(forPoints: .zero), .zero)
  }

  func testPixelSizeScalesPoints() {
    Artwork.cacheDisplayScale(2)
    let points = CGSize(width: 100, height: 50)
    let pixels = Artwork.pixelSize(forPoints: points)
    XCTAssertEqual(pixels.width, 200, accuracy: 0.01)
    XCTAssertEqual(pixels.height, 100, accuracy: 0.01)
  }

  @MainActor
  func testRememberDisplayScaleReadsScreenTraits() {
    Artwork.cacheDisplayScale(1)
    Artwork.rememberDisplayScale()
#if os(macOS)
    let live = NSScreen.main?.backingScaleFactor
      ?? NSScreen.screens.map(\.backingScaleFactor).max()
      ?? 2
    XCTAssertEqual(Artwork.displayScale, max(live, 1), accuracy: 0.01)
#else
    XCTAssertEqual(Artwork.displayScale, UIScreen.main.scale, accuracy: 0.01)
#endif
  }

  func testPixelSizeUsesCachedScaleNotTraitCollection() {
    Artwork.cacheDisplayScale(3)
    let pixels = Artwork.pixelSize(forPoints: CGSize(width: 10, height: 10))
#if os(macOS)
    // Signpost size follows the request (KP-14 floor 2), not the signpost cache.
    XCTAssertGreaterThanOrEqual(pixels.width, 20)
    XCTAssertEqual(Artwork.displayScale, 3, accuracy: 0.01)
#else
    XCTAssertEqual(pixels.width, 30, accuracy: 0.01)
    XCTAssertEqual(Artwork.displayScale, 3, accuracy: 0.01)
#endif
  }

#if os(macOS)
  func testMacOSRequestScaleFloorsAtTwoIndependentOfSignpostCache() {
    Artwork.cacheDisplayScale(1)
    XCTAssertGreaterThanOrEqual(Artwork.macOSRequestScale, 2)
    let pixels = Artwork.pixelSize(forPoints: CGSize(width: 100, height: 50))
    XCTAssertGreaterThanOrEqual(pixels.width, 200)
  }
#endif

  func testDecodedByteCountCountsRasterData() {
#if os(macOS)
    let image = NSImage(size: NSSize(width: 8, height: 4))
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(x: 0, y: 0, width: 8, height: 4).fill()
    image.unlockFocus()
    let bytes = Artwork.decodedByteCount(image)
#else
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 4), format: format)
      .image { ctx in
        UIColor.red.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
      }
    let bytes = Artwork.decodedByteCount(image)
#endif
    XCTAssertGreaterThanOrEqual(bytes, 8 * 4 * 4)
  }
}
