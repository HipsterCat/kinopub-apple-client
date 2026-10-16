//
//  TitleLogoSessionTests.swift
//
//  Shared title-logo state: empty while metadata is pending, logo when the image
//  is ready, text only after a confirmed miss — never text then logo.
//

import XCTest
@testable import KinoPubUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class TitleLogoSessionTests: XCTestCase {

  private let url = URL(string: "https://example.com/logo.png")!

  func testPendingStaysEmptyThroughTimeout() {
    let session = TitleLogoSession(images: MockTitleLogoImages(hang: true))
    session.setResolution(.pending)
    XCTAssertEqual(session.mark, .empty)
    session.handleTimeout()
    XCTAssertEqual(session.mark, .empty,
                   "a pending lookup must not flash the lettered title")
  }

  func testPendingThenURLThenLogoNeverShowsText() {
    let images = MockTitleLogoImages(hang: true)
    let session = TitleLogoSession(images: images)
    session.setResolution(.pending)
    XCTAssertEqual(session.mark, .empty)
    session.setResolution(.url(url))
    XCTAssertEqual(session.mark, .empty,
                   "URL arrived; the image is still in flight")
    session.handleLoaded(MockTitleLogoImages.pixel, elapsed: 0.4)
    XCTAssertEqual(session.mark, .logo)
  }

  func testMissingIsTextImmediately() {
    let session = TitleLogoSession(images: MockTitleLogoImages(hang: true))
    session.setResolution(.pending)
    session.setResolution(.missing)
    XCTAssertEqual(session.mark, .text)
  }

  func testCachedURLIsLogoOnTheSameCall() {
    let images = MockTitleLogoImages(hang: true)
    images.cached = MockTitleLogoImages.pixel
    let session = TitleLogoSession(images: images)
    session.setResolution(.url(url))
    XCTAssertEqual(session.mark, .logo)
  }

  func testImageTimeoutShowsTextAndRejectsALateLogo() {
    let session = TitleLogoSession(images: MockTitleLogoImages(hang: true))
    session.setResolution(.url(url))
    XCTAssertEqual(session.mark, .empty)
    session.handleTimeout()
    XCTAssertEqual(session.mark, .text)
    session.handleLoaded(
      MockTitleLogoImages.pixel,
      elapsed: TitleLogoPresentationPolicy.missTimeout + 0.2
    )
    XCTAssertEqual(session.mark, .text,
                   "swapping text for a late logo is the flicker")
  }

  func testFailedImageIsText() {
    let session = TitleLogoSession(images: MockTitleLogoImages(hang: true))
    session.setResolution(.url(url))
    session.handleFailed()
    XCTAssertEqual(session.mark, .text)
  }

  func testANewTitleIsNotAContinuation() {
    XCTAssertTrue(TitleLogoSession.isContinuation(from: .pending, to: .url(url)))
    XCTAssertTrue(TitleLogoSession.isContinuation(from: .pending, to: .missing))
    XCTAssertFalse(TitleLogoSession.isContinuation(from: .url(url), to: .pending),
                   "a reused cell with a new title must reset")
    let other = URL(string: "https://example.com/other.png")!
    XCTAssertFalse(TitleLogoSession.isContinuation(from: .url(url), to: .url(other)))
  }

  func testResetReturnsToEmptyPending() {
    let session = TitleLogoSession(images: MockTitleLogoImages(hang: true))
    session.setResolution(.missing)
    XCTAssertEqual(session.mark, .text)
    session.reset()
    XCTAssertEqual(session.mark, .empty)
  }
}

final class MockTitleLogoImages: TitleLogoImageLoading, @unchecked Sendable {
  var cached: TitleLogoImage?
  var hang: Bool

  init(hang: Bool) {
    self.hang = hang
  }

  func cachedImage(for url: URL) -> TitleLogoImage? { cached }

  func image(for url: URL) async throws -> TitleLogoImage {
    if hang {
      try await Task.sleep(nanoseconds: 60_000_000_000)
    }
    return Self.pixel
  }

  static var pixel: TitleLogoImage {
#if os(macOS)
    NSImage(size: NSSize(width: 2, height: 2))
#else
    UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { ctx in
      UIColor.white.setFill()
      ctx.fill(CGRect(origin: .zero, size: CGSize(width: 2, height: 2)))
    }
#endif
  }
}
