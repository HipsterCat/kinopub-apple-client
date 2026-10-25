//
//  SetlistLinesTests.swift
//  KinoPubMediaTests
//
//  The shapes kino.pub's hand-typed setlists come in (Sasha, 2026-10-25).
//

import XCTest
@testable import KinoPubMedia

final class SetlistLinesTests: XCTestCase {

  func testTimecodeFirstIsTheSecondLine() {
    let lines = SetlistEntry(title: "(07:14) Roche").lines
    XCTAssertEqual(lines?.title, "Roche")
    XCTAssertEqual(lines?.subtitle, "07:14")
  }

  func testLongTimecodeAndBrackets() {
    let lines = SetlistEntry(title: "[1:02:03] La Ritournelle").lines
    XCTAssertEqual(lines?.title, "La Ritournelle")
    XCTAssertEqual(lines?.subtitle, "1:02:03")
  }

  func testDashSplitsAtTheFirstOne() {
    let part = SetlistEntry(title: "Taschenrechner / Dentaku - Part Two").lines
    XCTAssertEqual(part?.title, "Taschenrechner / Dentaku")
    XCTAssertEqual(part?.subtitle, "Part Two")

    let bonus = SetlistEntry(title: "Aero Dynamik - Mtv - Bonus").lines
    XCTAssertEqual(bonus?.title, "Aero Dynamik")
    XCTAssertEqual(bonus?.subtitle, "Mtv - Bonus")
  }

  func testPlainTitleKeepsTheArtistsUnderIt() {
    let lines = SetlistEntry(title: "Monologue by Anton Corbijn", artists: "Depeche Mode").lines
    XCTAssertEqual(lines?.title, "Monologue by Anton Corbijn")
    XCTAssertEqual(lines?.subtitle, "Depeche Mode")
  }

  func testHyphenInsideAWordDoesNotSplit() {
    let lines = SetlistEntry(title: "Die Mensch-Machine").lines
    XCTAssertEqual(lines?.title, "Die Mensch-Machine")
    XCTAssertNil(lines?.subtitle)
  }

  func testUnnamedSongHasNoLines() {
    XCTAssertNil(SetlistEntry(title: "N/A").lines)
  }
}
