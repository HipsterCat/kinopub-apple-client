//
//  LocalePreferredTextTests.swift
//  KinoPubMetadataTests
//

import XCTest
@testable import KinoPubMetadata

final class LocalePreferredTextTests: XCTestCase {
  func testPrefersCyrillicOverLatin() {
    XCTAssertEqual(
      LocalePreferredText.preferRuEn(["Gong Yoo", "공유지", "Кон Ю"]),
      "Кон Ю"
    )
  }

  func testPrefersLatinOverHangulWhenNoCyrillic() {
    XCTAssertEqual(
      LocalePreferredText.preferRuEn(["공유", "Gong Yoo"]),
      "Gong Yoo"
    )
  }

  func testKeepsEastAsianOnlyWhenNothingElse() {
    XCTAssertEqual(LocalePreferredText.preferRuEn(["공유"]), "공유")
  }

  func testTitleDemotesOriginalScriptWhenEnglishExists() {
    XCTAssertEqual(
      LocalePreferredText.preferTitle(
        localized: "기생충",
        english: "Parasite",
        original: "기생충"
      ),
      "Parasite"
    )
  }

  func testTitleKeepsRussianLocalized() {
    XCTAssertEqual(
      LocalePreferredText.preferTitle(
        localized: "Паразиты",
        english: "Parasite",
        original: "기생충"
      ),
      "Паразиты"
    )
  }
}
