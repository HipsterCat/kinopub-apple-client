import XCTest
import KinoPubBackend
@testable import Piratic

@MainActor
final class BestVideoQualityFinderTests: XCTestCase {

  func testPrefersHighestResolutionHLS4() {
    let files = [
      file(quality: "480p", h: 480, hls4: "https://cdn.example/480.m3u8"),
      file(quality: "1080p", h: 1080, hls4: "https://cdn.example/1080.m3u8"),
      file(quality: "720p", h: 720, hls4: "https://cdn.example/720.m3u8"),
    ]
    XCTAssertEqual(BestVideoQualityFinder.findBestURL(for: files),
                   "https://cdn.example/1080.m3u8")
  }

  func testSkipsEmptyHLS4Rungs() {
    let files = [
      file(quality: "1080p", h: 1080, hls4: ""),
      file(quality: "720p", h: 720, hls4: "https://cdn.example/720.m3u8"),
    ]
    XCTAssertEqual(BestVideoQualityFinder.findBestURL(for: files),
                   "https://cdn.example/720.m3u8")
  }

  func testFallsBackWhenHLS4Missing() {
    let files = [
      file(quality: "720p", h: 720, hls4: "", hls2: "https://cdn.example/720-hls2.m3u8"),
    ]
    XCTAssertEqual(BestVideoQualityFinder.findBestURL(for: files),
                   "https://cdn.example/720-hls2.m3u8")
  }

  private func file(quality: String, h: Int, hls4: String, hls2: String = "") -> FileInfo {
    FileInfo(codec: "h264", w: h * 16 / 9, h: h, quality: quality, qualityID: h,
             url: URLInfo(http: "", hls: "", hls4: hls4, hls2: hls2))
  }
}
