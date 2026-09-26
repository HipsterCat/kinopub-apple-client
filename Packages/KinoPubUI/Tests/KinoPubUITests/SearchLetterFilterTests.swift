import XCTest
@testable import KinoPubUI

/// The first letters narrow what is loaded; the device's other titles stay apart.
final class SearchLetterFilterTests: XCTestCase {

  private func card(_ id: Int, _ title: String, _ original: String? = nil) -> MediaCard {
    MediaCard(id: id, posterURL: "", title: title, subtitle: original)
  }

  func testMatchesAWordStartNotTheMiddle() {
    XCTAssertTrue(card(1, "Табу").hasWord(startingWith: "та"))
    XCTAssertTrue(card(2, "Шокирующая Азия 2: Строгие табу").hasWord(startingWith: "та"))
    XCTAssertFalse(card(3, "Звезда не того масштаба").hasWord(startingWith: "та"))
    XCTAssertTrue(card(4, "Мир", "Tabu").hasWord(startingWith: "ta"))
  }

  func testIgnoresCaseAndDiacritics() {
    XCTAssertTrue(card(1, "Ёлки").hasWord(startingWith: "ел"))
    XCTAssertTrue(card(2, "табу").hasWord(startingWith: "ТА"))
    XCTAssertFalse(card(3, "Табу").hasWord(startingWith: ""))
  }

  /// A filtered listing ("4K anime") keeps its own answer; shelf titles that match
  /// come back apart, in their order, never twice.
  func testSplitKeepsTheListingApartFromTheRest() {
    let loaded = [card(1, "Табакошка"), card(2, "Мастер"), card(3, "Тамако")]
    let elsewhere = [card(3, "Тамако"), card(4, "Табу"), card(5, "Лёд")]
    let split = SearchLetterFilter.split(loaded: loaded, elsewhere: elsewhere, letters: "та")
    XCTAssertEqual(split.matches.map(\.id), [1, 3])
    XCTAssertEqual(split.others.map(\.id), [4])
  }
}
