//
//  TopShelfLinkTests.swift
//  KinoPubAppleClientTests
//

import XCTest
@testable import KinoPub

final class TopShelfLinkTests: XCTestCase {
  func testLinksRoundTripThroughTheirURL() {
    for link in [TopShelfLink.title(128125), .play(127393)] {
      XCTAssertEqual(TopShelfLink(url: link.url), link)
    }
    XCTAssertEqual(TopShelfLink.title(7).url.absoluteString, "kinopub://title/7")
    XCTAssertEqual(TopShelfLink.play(7).url.absoluteString, "kinopub://play/7")
  }

  func testForeignAndMalformedURLsAreIgnored() {
    for raw in ["https://kino.pub/item/7", "kinopub://title/", "kinopub://title/abc", "kinopub://episode/7"] {
      XCTAssertNil(TopShelfLink(url: URL(string: raw)!), raw)
    }
  }
}
