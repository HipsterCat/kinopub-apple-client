import XCTest
@testable import Piratic

final class AgeRatingPresentationTests: XCTestCase {
  func testLocalEquivalents() {
    XCTAssertEqual(AgeRatingPresentation.localEquivalent("PG-13"), "12+")
    XCTAssertEqual(AgeRatingPresentation.localEquivalent("TV-MA"), "18+")
    XCTAssertEqual(AgeRatingPresentation.localEquivalent("16+"), "16+")
    XCTAssertEqual(AgeRatingPresentation.localEquivalent("R"), "16+")
    XCTAssertTrue(AgeRatingPresentation.isForeign("R"))
    XCTAssertFalse(AgeRatingPresentation.isForeign("16+"))
  }

  func testInfoStripHonorsMasterOff() {
    withAgePrefs(master: false, convert: true, foreign: true) {
      XCTAssertEqual(MediaItemDisplayPreferences.ageRatingsForInfoStrip("R"), [])
      XCTAssertNil(MediaItemDisplayPreferences.ageRatingForInfoStrip("16+"))
    }
  }

  func testConvertAndForeignShowBoth() {
    withAgePrefs(master: true, convert: true, foreign: true) {
      XCTAssertEqual(MediaItemDisplayPreferences.ageRatingsForInfoStrip("R"), ["16+", "R"])
    }
  }

  func testConvertOnlyShowsLocal() {
    withAgePrefs(master: true, convert: true, foreign: false) {
      XCTAssertEqual(MediaItemDisplayPreferences.ageRatingsForInfoStrip("R"), ["16+"])
    }
  }

  func testForeignOnlyShowsMPA() {
    withAgePrefs(master: true, convert: false, foreign: true) {
      XCTAssertEqual(MediaItemDisplayPreferences.ageRatingsForInfoStrip("R"), ["R"])
    }
  }

  func testBothOffHidesForeignSource() {
    withAgePrefs(master: true, convert: false, foreign: false) {
      XCTAssertEqual(MediaItemDisplayPreferences.ageRatingsForInfoStrip("R"), [])
    }
  }

  func testLocalAgeUnchanged() {
    withAgePrefs(master: true, convert: true, foreign: true) {
      XCTAssertEqual(MediaItemDisplayPreferences.ageRatingsForInfoStrip("16+"), ["16+"])
    }
  }

  private func withAgePrefs(master: Bool, convert: Bool, foreign: Bool, _ body: () -> Void) {
    let defaults = UserDefaults.standard
    let keys = [
      MediaItemDisplayPreferences.showAgeRatingBadgeKey,
      MediaItemDisplayPreferences.convertAgeRatingKey,
      MediaItemDisplayPreferences.showForeignAgeRatingKey,
    ]
    let previous = keys.map { ($0, defaults.object(forKey: $0)) }
    defer {
      for (key, value) in previous {
        if let value {
          defaults.set(value, forKey: key)
        } else {
          defaults.removeObject(forKey: key)
        }
      }
    }
    defaults.set(master, forKey: MediaItemDisplayPreferences.showAgeRatingBadgeKey)
    defaults.set(convert, forKey: MediaItemDisplayPreferences.convertAgeRatingKey)
    defaults.set(foreign, forKey: MediaItemDisplayPreferences.showForeignAgeRatingKey)
    body()
  }
}
