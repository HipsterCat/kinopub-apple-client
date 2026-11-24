import XCTest
@testable import KinoPubUI

/// Certification text → drawing in `Media.xcassets/badges`.
final class AgeRatingBadgeTests: XCTestCase {

  func testEveryDrawnCertificationFindsItsMark() {
    let expected: [String: String] = [
      "0+": "0", "6+": "6", "12+": "12", "16+": "16", "18+": "18",
      "G": "g", "PG": "pg", "PG-13": "pg-13", "R": "R", "NC-17": "nc-17", "X": "x",
      "NR": "nr", "Not Rated": "nr", "Unrated": "unrated",
      "TV-Y": "tv-y", "TV-Y7": "tv-y7", "TV-G": "tv-g", "TV-PG": "tv-pg", "TV-MA": "tv-ma",
      "M": "m", "MA15+": "ma", "TV-14": "tv-14"
    ]
    for (rating, asset) in expected {
      XCTAssertEqual(MediaBadgeImages.ageRatingAssetName(rating), asset, rating)
    }
  }

  func testSpellingVariantsMatch() {
    XCTAssertEqual(MediaBadgeImages.ageRatingAssetName("tv-g"), "tv-g")
    XCTAssertEqual(MediaBadgeImages.ageRatingAssetName("TVG"), "tv-g")
    XCTAssertEqual(MediaBadgeImages.ageRatingAssetName("PG 13"), "pg-13")
    XCTAssertEqual(MediaBadgeImages.ageRatingAssetName("gb/18"), "18")
  }

  /// No drawing, or one that would drop part of the rating: stays typed.
  func testUndrawnCertificationsStayTyped() {
    for rating in ["TV-14", "TV-Y7", "R18+", "X18+", "15", "PG-12"] {
      XCTAssertNil(MediaBadgeImages.ageRatingAssetName(rating), rating)
    }
  }
}
