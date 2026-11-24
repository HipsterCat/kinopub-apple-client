import XCTest
@testable import KinoPub

final class AgeRatingPresentationTests: XCTestCase {
  func testLocalEquivalents() {
    XCTAssertEqual(AgeRatingPresentation.localEquivalent("PG-13"), "12+")
    XCTAssertEqual(AgeRatingPresentation.localEquivalent("TV-MA"), "18+")
    XCTAssertEqual(AgeRatingPresentation.localEquivalent("16+"), "16+")
    XCTAssertTrue(AgeRatingPresentation.isForeign("R"))
    XCTAssertFalse(AgeRatingPresentation.isForeign("16+"))
  }

  func testInfoStripHonorsMasterOff() {
    let defaults = UserDefaults.standard
    let key = MediaItemDisplayPreferences.showAgeRatingBadgeKey
    let previous = defaults.object(forKey: key)
    defer {
      if let previous {
        defaults.set(previous, forKey: key)
      } else {
        defaults.removeObject(forKey: key)
      }
    }
    defaults.set(false, forKey: key)
    XCTAssertNil(MediaItemDisplayPreferences.ageRatingForInfoStrip("16+"))
    defaults.set(true, forKey: key)
    XCTAssertEqual(MediaItemDisplayPreferences.ageRatingForInfoStrip("16+"), "16+")
  }
}
