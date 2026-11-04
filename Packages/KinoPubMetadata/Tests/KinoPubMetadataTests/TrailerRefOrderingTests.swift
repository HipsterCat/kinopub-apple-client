import XCTest
@testable import KinoPubMetadata

/// The title page's videos rail: which TMDB videos it keeps and in what order.
final class TrailerRefOrderingTests: XCTestCase {
  private func video(_ key: String, _ type: String = "Trailer", lang: String?, site: String = "YouTube",
                     official: Bool = true, daysAgo: Double = 0) -> TrailerRef {
    TrailerRef(site: site, key: key, type: type, official: official, language: lang,
               name: key, publishedAt: Date(timeIntervalSinceNow: -daysAgo * 86_400))
  }

  func testKeepsAppEnglishAndOriginalLanguagesOnly() {
    let videos = [video("de", lang: "de"), video("ko", lang: "ko"), video("en", lang: "en"),
                  video("ru", lang: "ru"), video("none", lang: nil)]
    let kept = TrailerRef.forTitlePage(videos, appLanguage: "ru", originalLanguage: "ko")
    XCTAssertEqual(kept.map(\.key), ["ru", "en", "ko"])
  }

  func testDropsNonYouTubeAndDuplicates() {
    let videos = [video("a", lang: "en", site: "Vimeo"), video("b", lang: "en"), video("b", lang: "en")]
    XCTAssertEqual(TrailerRef.forTitlePage(videos, appLanguage: "ru", originalLanguage: nil).map(\.key), ["b"])
  }

  func testTrailersBeforeTeasersBeforeClipsThenOfficialThenNewest() {
    let videos = [video("clip", "Clip", lang: "en"),
                  video("teaser", "Teaser", lang: "en"),
                  video("fan", "Trailer", lang: "en", official: false),
                  video("old", "Trailer", lang: "en", daysAgo: 30),
                  video("new", "Trailer", lang: "en", daysAgo: 1)]
    XCTAssertEqual(TrailerRef.forTitlePage(videos, appLanguage: "ru", originalLanguage: "en").map(\.key),
                   ["new", "old", "fan", "teaser", "clip"])
  }

  func testYouTubeLinks() {
    let ref = video("abc", lang: "en")
    XCTAssertEqual(ref.webURL?.absoluteString, "https://www.youtube.com/watch?v=abc")
    XCTAssertEqual(ref.appURL?.absoluteString, "youtube://watch/abc")
    XCTAssertEqual(ref.thumbnailURL?.absoluteString, "https://i.ytimg.com/vi/abc/maxresdefault.jpg")
  }
}
