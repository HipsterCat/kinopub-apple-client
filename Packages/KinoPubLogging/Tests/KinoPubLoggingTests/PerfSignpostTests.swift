import XCTest
@testable import KinoPubLogging

final class PerfSignpostTests: XCTestCase {
  func testSubsystemAndIntervalNamesAreStable() {
    XCTAssertEqual(PerfSignpost.subsystem, "com.soda.kinopub.perf")
    XCTAssertEqual(PerfSignpost.Interval.artworkRequest, "artwork.request")
    XCTAssertEqual(PerfSignpost.Interval.artworkDisplay, "artwork.display")
    XCTAssertEqual(PerfSignpost.Interval.heroPage, "hero.page")
    XCTAssertEqual(PerfSignpost.Interval.heroBackdrop, "hero.backdrop")
    XCTAssertEqual(PerfSignpost.Interval.scrollHome, "scroll.home")
    XCTAssertEqual(PerfSignpost.Interval.scrollSeason, "scroll.season")
    XCTAssertEqual(PerfSignpost.Interval.pageTitle, "page.title")
    XCTAssertEqual(PerfSignpost.Interval.pageResize, "page.resize")
  }

  func testBeginEndIsSafeWhenNotRecording() {
    let interval = PerfSignpost.beginArtworkRequest(
      url: URL(string: "https://example.com/backdrop.jpg")!,
      pixelSize: CGSize(width: 1920, height: 1080)
    )
    interval.endArtwork(tier: "memory", bytes: 12, pixelSize: CGSize(width: 1920, height: 1080))
    interval.end("second end is a no-op")

    PerfSignpost.beginHomeScroll("test")
    PerfSignpost.endHomeScroll("test")
    PerfSignpost.endHomeScroll("already ended")

    PerfSignpost.beginTitleOpen(id: "1")
    PerfSignpost.endTitleOpen(reason: "painted", id: "1")
    PerfSignpost.cancelTitleOpen(id: "1")
  }
}
