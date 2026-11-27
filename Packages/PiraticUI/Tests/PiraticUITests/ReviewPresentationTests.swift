import Foundation
import PiraticMetadata
import SwiftUI
import XCTest
@testable import PiraticUI

final class ReviewPresentationTests: XCTestCase {
  func testTraktTagKeepsItsNameAndLinksInTheFullReview() {
    let url = "https://app.trakt.tv/people/hunter-schafer"
    let review = Review(author: "Nickname", title: "", body: "[Hunter Schafer](\(url)) was great.\n\nMore thoughts.",
                        helpfulVotes: 14, source: .trakt, replyCount: 1, authorRating: 9)
    let card = ReviewPresentation(review, locale: Locale(identifier: "en_US"))

    XCTAssertNil(card.title)
    XCTAssertEqual(card.score, 4.5)
    XCTAssertEqual(card.counters.map(\.kind), [.replies, .likes])
    XCTAssertEqual(String(card.excerpt.characters), "Hunter Schafer was great. More thoughts.")
    for text in [card.excerpt, card.body] {
      let plain = ReviewPresentation.styled(text, linksEnabled: false)
      XCTAssertTrue(plain.runs.allSatisfy { $0.link == nil && $0.underlineStyle == nil })
    }
    let full = ReviewPresentation.styled(card.body, linksEnabled: true)
    XCTAssertEqual(String(full.characters), "Hunter Schafer was great.\n\nMore thoughts.")
    XCTAssertEqual(full.runs.compactMap(\.link), [URL(string: url)!])
  }

  func testHelpfulVotesAreOnTheRight() {
    let review = Review(author: "Viewer", title: "Title", body: "Review", helpfulVotes: 12, unhelpfulVotes: 2)
    let card = ReviewPresentation(review, locale: Locale(identifier: "ru_RU"))
    XCTAssertEqual(card.counters.map(\.kind), [.unhelpful, .helpful])
    XCTAssertEqual(card.counters.map(\.value), ["2", "12"])
  }
}
