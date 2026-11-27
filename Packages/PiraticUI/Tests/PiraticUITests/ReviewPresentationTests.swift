import Foundation
import PiraticMetadata
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
    XCTAssertTrue(card.styled(card.excerpt, linksEnabled: false).runs.allSatisfy { $0.link == nil })
    let full = card.styled(card.body, linksEnabled: true)
    XCTAssertEqual(String(full.characters), "Hunter Schafer was great.\n\nMore thoughts.")
    XCTAssertEqual(full.runs.compactMap(\.link), [URL(string: url)!])
  }
}
