import Nuke
import PiraticMetadata
import XCTest
@testable import PiraticUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class ArtworkPipelineTests: XCTestCase {
  func testArtworkMirrorsKeepOriginalCacheKeyAndDiscardFailedResponses() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PosterMirrorURLProtocol.self]
    let cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: cacheDirectory) }
    let cache = try DataCache(path: cacheDirectory)
    let pipeline = ImagePipeline {
      $0.dataLoader = ArtworkDataLoader(DataLoader(configuration: configuration))
      $0.dataCache = cache
      $0.dataCachePolicy = .storeOriginalData
    }

    for path in ["/poster/item/wide/126952.jpg?v=1", "/thumb/a/aa/hash/1000/480.jpg?v=1"] {
      let source = try XCTUnwrap(URL(string: "https://m.pushbr.com\(path)"))
      let request = ImageRequest(url: source)
      let (data, response) = try await pipeline.data(for: request)
      XCTAssertEqual(data, PosterMirrorURLProtocol.jpeg)
      XCTAssertEqual(response?.url?.absoluteString, "https://media.service-kp.com\(path)")
      XCTAssertEqual(pipeline.cache.cachedData(for: request), data)
    }
  }

  func testArtworkMirrorsAreLimitedToCatalogueImageURLs() throws {
    for raw in ["https://m.staticpop.net/actors/126952.jpg",
                "https://m.staticpop.net.example.org/poster/item/big/126952.jpg"] {
      XCTAssertNil(KinoPubArtworkCDN.origins(for: try XCTUnwrap(URL(string: raw))))
    }
  }

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

private final class PosterMirrorURLProtocol: URLProtocol, @unchecked Sendable {
  static let jpeg = Data([0xff, 0xd8, 0xff, 0xd9])

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else { return }
    if url.host == "m.staticpop.net" {
      client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
      return
    }
    let isMirror = url.host == "media.service-kp.com"
    let isThumb = url.path.hasPrefix("/thumb/")
    let headers = ["Content-Type": isMirror ? "image/jpeg" : (isThumb ? "image/png" : "text/html")]
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    let invalid = isThumb ? Data([0x89, 0x50, 0x4e, 0x47]) : Data("blocked".utf8)
    client?.urlProtocol(self, didLoad: isMirror ? Self.jpeg : invalid)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

final class WorkerArtworkDailyTests: XCTestCase {
  func testADiscoveryURLCarriesTheDayAndAStampedFileDoesNot() throws {
    let now = Date(timeIntervalSince1970: 86_400 * 20_000 + 5)
    let discovery = try XCTUnwrap(URL(string: "https://w.test/img/poster/by/kinopub/1?w=780&lang=ru"))
    XCTAssertEqual(WorkerArtwork.daily(discovery, now: now).absoluteString,
                   "https://w.test/img/poster/by/kinopub/1?w=780&lang=ru&d=20000")
    let stamped = try XCTUnwrap(URL(string: "https://w.test/img/poster/by/kinopub/1/ru/poster.jpg?w=780"))
    XCTAssertEqual(WorkerArtwork.daily(stamped, now: now), stamped)
    let other = try XCTUnwrap(URL(string: "https://m.staticpop.net/poster/item/big/1.jpg"))
    XCTAssertEqual(WorkerArtwork.daily(other, now: now), other)
  }
}
