//
//  TitleLogoPresentationTests.swift
//
//  Hero / banner title slot: empty while a logo is expected, text only after a
//  confirmed miss, and a stale load must not paint over a newer card.
//

import XCTest
@testable import KinoPubUI

final class TitleLogoPresentationTests: XCTestCase {

  private let resolved = TitleLogoPresentationPolicy.whenResolved
  private let ready = TitleLogoPresentationPolicy.whenReady

  func testWhenResolvedKeepsTheSlotEmptyWhileALookupIsInFlight() {
    XCTAssertEqual(
      resolved.mark(hasCachedLogo: false, lookupComplete: false, hasLogoURL: false,
                    imageReady: false, imageFailed: false, elapsed: 0.2),
      .empty
    )
    XCTAssertFalse(resolved.showsTextWhileLoading)
  }

  func testACachedLogoPaintsImmediately() {
    XCTAssertEqual(
      resolved.mark(hasCachedLogo: true, lookupComplete: false, hasLogoURL: true,
                    imageReady: false, imageFailed: false, elapsed: 0),
      .logo
    )
  }

  func testTextAppearsOnlyAfterAConfirmedMiss() {
    XCTAssertEqual(
      resolved.mark(hasCachedLogo: false, lookupComplete: true, hasLogoURL: false,
                    imageReady: false, imageFailed: false, elapsed: 0.1),
      .text,
      "metadata answered: no logo"
    )
    XCTAssertEqual(
      resolved.mark(hasCachedLogo: false, lookupComplete: true, hasLogoURL: true,
                    imageReady: false, imageFailed: true, elapsed: 0.4),
      .text,
      "the image 404'd"
    )
  }

  func testPendingLookupDoesNotTimeOutIntoText() {
    XCTAssertEqual(
      resolved.mark(hasCachedLogo: false, lookupComplete: false, hasLogoURL: false,
                    imageReady: false, imageFailed: false,
                    elapsed: TitleLogoPresentationPolicy.missTimeout),
      .empty,
      "metadata still in flight: empty, not the lettered title"
    )
  }

  func testImageLoadTimeoutIsAConfirmedMiss() {
    XCTAssertEqual(
      resolved.mark(hasCachedLogo: false, lookupComplete: true, hasLogoURL: true,
                    imageReady: false, imageFailed: false,
                    elapsed: TitleLogoPresentationPolicy.missTimeout),
      .text
    )
    XCTAssertEqual(
      resolved.mark(hasCachedLogo: false, lookupComplete: true, hasLogoURL: true,
                    imageReady: false, imageFailed: false,
                    elapsed: TitleLogoPresentationPolicy.missTimeout - 0.01),
      .empty
    )
  }

  func testResolutionMapsURLAndLoadedFlag() {
    XCTAssertEqual(TitleLogoResolution(url: nil, lookupComplete: false), .pending)
    XCTAssertEqual(TitleLogoResolution(url: nil, lookupComplete: true), .missing)
    let url = URL(string: "https://example.com/logo.png")!
    XCTAssertEqual(TitleLogoResolution(url: url, lookupComplete: false), .url(url))
    XCTAssertEqual(TitleLogoResolution(url: url, lookupComplete: true), .url(url))
  }

  func testALateLogoDoesNotReplaceTextAfterTheTimeout() {
    XCTAssertFalse(
      resolved.shouldAdoptLogo(elapsed: TitleLogoPresentationPolicy.missTimeout + 0.2,
                               alreadyShowingText: true),
      "text is already up; swapping it for a late logo is the flicker"
    )
    XCTAssertTrue(
      resolved.shouldAdoptLogo(elapsed: 0.3, alreadyShowingText: false)
    )
  }

  func testAStaleRequestCannotOverwriteANewerCard() {
    XCTAssertTrue(resolved.shouldApply(requestID: 7, current: 7))
    XCTAssertFalse(resolved.shouldApply(requestID: 7, current: 8),
                   "card 8 is on screen; card 7's image must not land")
  }

  func testWhenReadyShowsTextWhileLoading() {
    XCTAssertEqual(
      ready.mark(hasCachedLogo: false, lookupComplete: false, hasLogoURL: true,
                 imageReady: false, imageFailed: false, elapsed: 0.1),
      .text
    )
  }

  func testResolutionPendingHasNoURL() {
    XCTAssertNil(TitleLogoResolution.pending.url)
    XCTAssertNil(TitleLogoResolution.missing.url)
    XCTAssertEqual(TitleLogoResolution.url(URL(string: "https://example.com/logo.png")!).url?.host,
                   "example.com")
  }

#if os(tvOS)
  func testAPendingBannerFeatureIsNotAMiss() {
    let card = MediaCard(id: 1, posterURL: "", title: "Title")
    let pending = TVPageFeature(card: card, logo: .pending)
    let missing = TVPageFeature(card: card, logo: .missing)
    XCTAssertNotEqual(pending, missing)
    XCTAssertNil(pending.logoURL)
    XCTAssertEqual(TVPageFeature(card: card, logoURL: nil).logo, .missing)
  }
#endif
}
