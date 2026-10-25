//
//  KinoPubBilingualTitleTests.swift
//  KinoPubBackendTests
//

import XCTest
@testable import KinoPubBackend

final class KinoPubBilingualTitleTests: XCTestCase {

  func testSpacedSlashSeparatesLocalizedAndOriginal() {
    let title = "Матрица / The Matrix"
    XCTAssertEqual(KinoPubBilingualTitle.parts(from: title).localized, "Матрица")
    XCTAssertEqual(KinoPubBilingualTitle.parts(from: title).original, "The Matrix")
  }

  func testSlashesInsideNameDoNotSplit() {
    let title = "National Geographic. 9/11: Один день из жизни Америки / 9/11: One Day in America"
    XCTAssertEqual(
      KinoPubBilingualTitle.parts(from: title).localized,
      "National Geographic. 9/11: Один день из жизни Америки"
    )
    XCTAssertEqual(
      KinoPubBilingualTitle.parts(from: title).original,
      "9/11: One Day in America"
    )
  }

  func testSingleNameHasNoSeparateOriginal() {
    let title = "Брат"
    XCTAssertFalse(KinoPubBilingualTitle.hasSeparateOriginal(title))
    XCTAssertEqual(KinoPubBilingualTitle.parts(from: title).localized, "Брат")
    XCTAssertEqual(KinoPubBilingualTitle.parts(from: title).original, "Брат")
  }
}
