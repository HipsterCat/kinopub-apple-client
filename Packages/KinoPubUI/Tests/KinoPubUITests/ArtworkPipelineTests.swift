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

  func testMemoryByteLimitScalesWithRAMAndCaps() {
    let gb: UInt64 = 1024 * 1024 * 1024
#if os(tvOS)
    XCTAssertEqual(Artwork.memoryByteLimit(physicalMemory: 2 * gb), 128 * 1024 * 1024)
    XCTAssertEqual(Artwork.memoryByteLimit(physicalMemory: 3 * gb), 192 * 1024 * 1024)
    XCTAssertEqual(Artwork.memoryByteLimit(physicalMemory: 4 * gb), 192 * 1024 * 1024)
#elseif os(iOS)
    XCTAssertEqual(Artwork.memoryByteLimit(physicalMemory: 2 * gb), 128 * 1024 * 1024)
    XCTAssertEqual(Artwork.memoryByteLimit(physicalMemory: 8 * gb), 256 * 1024 * 1024)
#else
    XCTAssertEqual(Artwork.memoryByteLimit(physicalMemory: 8 * gb), 256 * 1024 * 1024)
    XCTAssertEqual(Artwork.memoryByteLimit(physicalMemory: 32 * gb), 512 * 1024 * 1024)
#endif
  }

  func testLogoDecodeSizeIsTheLargestSlot() {
#if os(tvOS)
    XCTAssertEqual(Artwork.logoDecodeSize, CGSize(width: 680, height: 170))
#elseif os(macOS)
    XCTAssertEqual(Artwork.logoDecodeSize, CGSize(width: 440, height: 120))
#else
    XCTAssertEqual(Artwork.logoDecodeSize, CGSize(width: 360, height: 96))
#endif
    XCTAssertEqual(Artwork.maxDecodePixels(for: .fit), 1280)
    XCTAssertEqual(Artwork.maxDecodePixels(for: .fill), 1920)
    XCTAssertEqual(Artwork.maxDecodePixels(for: .fillTop), 1920)
  }

  func testPixelSizeCapsFillAt1920() {
    Artwork.cacheDisplayScale(2)
    let pixels = Artwork.pixelSize(forPoints: CGSize(width: 1920, height: 1080), mode: .fill)
    XCTAssertLessThanOrEqual(max(pixels.width, pixels.height), 1920 + 0.5)
  }

  func testPixelSizeCapsFitAt1280() {
    Artwork.cacheDisplayScale(2)
    let pixels = Artwork.pixelSize(forPoints: Artwork.logoDecodeSize, mode: .fit)
    XCTAssertLessThanOrEqual(max(pixels.width, pixels.height), 1280 + 0.5)
  }

  func testEvictionConstants() {
    XCTAssertEqual(Artwork.memoryEntryTTL, 15 * 60)
    XCTAssertEqual(Artwork.memoryEntryCostLimit, 0.2, accuracy: 0.0001)
    XCTAssertEqual(Artwork.diskEntryMaxAge, 7 * 24 * 60 * 60)
  }

  func testExpiredDiskURLsUsesAccessAgeAndSkipsHidden() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ArtworkDiskSweep-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let visible = dir.appendingPathComponent("poster.bin")
    let hidden = dir.appendingPathComponent(".data-cache-info")
    try Data([1]).write(to: visible)
    try Data([2]).write(to: hidden)

    XCTAssertTrue(
      Artwork.expiredDiskURLs(in: dir, olderThan: Artwork.diskEntryMaxAge).isEmpty
    )
    XCTAssertTrue(
      Artwork.expiredDiskURLs(in: dir, olderThan: 0).isEmpty
    )

    let eightDays = Date().addingTimeInterval(8 * 24 * 60 * 60)
    let expired = Artwork.expiredDiskURLs(
      in: dir, olderThan: Artwork.diskEntryMaxAge, now: eightDays
    )
    XCTAssertEqual(Set(expired.map(\.lastPathComponent)), ["poster.bin"])
  }

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
