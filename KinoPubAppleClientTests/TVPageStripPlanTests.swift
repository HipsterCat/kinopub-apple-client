//
//  TVPageStripPlanTests.swift
//  KinoPubAppleClientTests
//
//  Where the cells of a strip go — "Ratings | Reviews", "Director | Cast" — from sizes
//  alone. A strip is laid out the way its groups' own sections would be: the first card's
//  art on the side inset, half the HIG gutter between cards and half the titled-row gap
//  between groups (Sasha, 2026-10-06), titles on the first card's leading edge — and a
//  title that stays on screen while any of its group does.
//

#if os(tvOS)
import KinoPubBackend
import TVUIKit
import UIKit
import XCTest
@testable import KinoPubUI

@MainActor
final class TVPageStripPlanTests: XCTestCase {

  private let contentWidth: CGFloat = 1760
  private let sideInset: CGFloat = 80

  private func person(_ name: String) -> TVPageItem {
    .person(TVUIKitPerson(id: name, name: name, nameComponents: TVUIKitPerson.nameComponents(from: name),
                          caption: nil, photoURL: nil))
  }

  private func credits() -> TVPageSection {
    .strip(id: "credits", groups: [
      TVPageGroup(id: "directors", title: "Director", columns: 3, items: [person("D")]),
      TVPageGroup(id: "cast", title: "Cast", columns: 3, items: [person("A"), person("B"), person("C")])
    ])
  }

  private func plan(_ section: TVPageSection) -> TVPageStripPlan {
    TVPageStripPlan(section: section, contentWidth: contentWidth, sideInset: sideInset)
  }

  func testOneFramePerItemTitlesIncluded() {
    let section = credits()
    XCTAssertEqual(section.items.count, 6, "two titles, four cards")
    XCTAssertEqual(plan(section).frames.count, section.items.count)
  }

  /// The art of the first card — not its focus envelope — sits on the side inset.
  func testTheFirstCardsArtLandsOnTheSideInset() {
    let section = credits()
    let plan = plan(section)
    let card = TVPageStripPlan.metrics(of: section.groups[0].items[0], columns: 3, contentWidth: contentWidth)
    let frame = plan.frames[1]
    XCTAssertEqual(plan.insets.leading + frame.minX + card.insets.leading, sideInset, accuracy: 1)
  }

  func testTitlesSitOnTheirGroupsFirstCard() {
    let section = credits()
    let plan = plan(section)
    let directorTitle = plan.frames[0], directorCard = plan.frames[1]
    let castTitle = plan.frames[2], castCard = plan.frames[3]
    let envelope = TVPageStripPlan.metrics(of: section.groups[0].items[0], columns: 3, contentWidth: contentWidth)
    XCTAssertEqual(directorTitle.minX, directorCard.minX + envelope.insets.leading,
                   accuracy: 1, "a title starts where the art under it starts")
    XCTAssertEqual(castTitle.minX, castCard.minX + envelope.insets.leading, accuracy: 1)
    XCTAssertEqual(directorTitle.minY, 0)
    XCTAssertEqual(castTitle.minY, 0, "every title of the row on one baseline")
  }

  func testCardsOfAGroupAreHalfAGutterApartAndGroupsHalfAGapApart() {
    let section = credits()
    let plan = plan(section)
    let art = TVPageStripPlan.metrics(of: section.groups[1].items[0], columns: 3, contentWidth: contentWidth)
    // Envelopes are wider than the art by the focus room on each side.
    let first = plan.frames[3], second = plan.frames[4]
    XCTAssertEqual(TVPageStripPlan.cardGap, TVHIGGrid.gutter / 2)
    XCTAssertEqual(second.minX - first.minX, art.art.width + TVPageStripPlan.cardGap, accuracy: 1)
    XCTAssertEqual(TVPageLayout.stripGroupGap, TVHIGGrid.titledRowGap / 2)

    let lastDirector = plan.frames[1]
    let firstCast = plan.frames[3]
    let directorArtEnd = lastDirector.minX + art.insets.leading + art.art.width
    let castArtStart = firstCast.minX + art.insets.leading
    XCTAssertEqual(castArtStart - directorArtEnd, TVPageLayout.stripGroupGap, accuracy: 1)
  }

  func testEveryCardOfARowStartsOnTheSameLine() {
    let plan = plan(credits())
    let tops = Set([plan.frames[1], plan.frames[3], plan.frames[4], plan.frames[5]].map { $0.minY.rounded() })
    XCTAssertEqual(tops.count, 1, "\(tops)")
  }

  func testTheRowIsExactlyAsTallAsItsTallestCell() {
    let plan = plan(credits())
    XCTAssertEqual(plan.size.height, plan.frames.map(\.maxY).max() ?? 0, accuracy: 0.5)
    XCTAssertEqual(plan.frames.map(\.minY).min() ?? -1, 0, "nothing hangs above the row")
  }

  func testTheNextRowsTitleIsATitledRowGapBelowTheArt() {
    let section = credits()
    let plan = plan(section)
    let card = TVPageStripPlan.metrics(of: section.groups[0].items[0], columns: 3, contentWidth: contentWidth)
    let artBottom = plan.frames[1].minY + card.insets.top + card.art.height
    // Art bottom to the next row's top: what is left of the envelope, plus the inset.
    XCTAssertEqual(plan.size.height - artBottom + plan.insets.bottom, TVHIGGrid.titledRowGap, accuracy: 1)
  }

  func testPillsKeepTheirOwnSpacingAndWidths() {
    let chips = TVPageSection.strip(id: "tags", groups: [
      TVPageGroup(id: "type", title: "Тип", columns: 0, items: [.chip(TVPageChip(id: "a", title: "Фильм"))]),
      TVPageGroup(id: "genres", title: "Жанры", columns: 0, items: [
        .chip(TVPageChip(id: "b", title: "Фантастика")), .chip(TVPageChip(id: "c", title: "Боевик"))
      ])
    ])
    let plan = plan(chips)
    // title, pill, title, pill, pill
    XCTAssertEqual(plan.frames.count, 5)
    let first = plan.frames[3], second = plan.frames[4]
    XCTAssertEqual(second.minX - first.maxX, TVPageLayout.chipSpacing, accuracy: 1)
    XCTAssertEqual(first.height, TVPageLayout.chipHeight)
    // Between two groups of pills the wider gap stays: the spacing inside a row of pills
    // is already near the half.
    let lastOfTheFirstGroup = plan.frames[1]
    XCTAssertEqual(first.minX - lastOfTheFirstGroup.maxX - 0, TVPageLayout.stripPillGroupGap, accuracy: 1)
  }

  // MARK: Sticky titles

  private func titles(_ plan: TVPageStripPlan) -> (director: Int, cast: Int) {
    (plan.titles[0].item, plan.titles[1].item)
  }

  /// At rest every title is on its group and none is moved.
  func testNoTitleMovesWhileTheRowIsAtRest() {
    let plan = plan(credits())
    XCTAssertEqual(plan.titles.count, 2)
    let shifts = plan.stickyShifts(offset: 0, sideInset: sideInset)
    XCTAssertTrue(shifts.values.allSatisfy { $0 == 0 }, "\(shifts)")
  }

  /// Scroll the row until the first group has begun to slide under the side inset: its
  /// title holds on that line, the next group's has not reached it yet.
  func testATitleHoldsTheSideInsetWhileItsGroupScrollsUnderIt() {
    let plan = plan(credits())
    let (director, cast) = titles(plan)
    // The director title is on the inset at rest; 100 pt of scrolling takes its group 100
    // to the left of it.
    let shifts = plan.stickyShifts(offset: 100, sideInset: sideInset)
    XCTAssertEqual(shifts[director], 100, "the label stays on the inset")
    XCTAssertEqual(shifts[cast], 0, "the next group's title has not reached it")
    // The label's screen position is where it should be: on the inset.
    let title = plan.titles[0]
    XCTAssertEqual(plan.insets.leading + title.frame.minX - 100 + (shifts[director] ?? 0), sideInset, accuracy: 0.5)
  }

  /// The label leaves with its group's last card — never past it — and the next group's
  /// title takes the line.
  func testATitleLeavesWithItsGroupAndTheNextOneTakesTheLine() {
    let plan = plan(credits())
    let (director, cast) = titles(plan)
    let room = plan.titles[0].frame.width - plan.titles[0].labelWidth
    XCTAssertGreaterThan(room, 0)
    let far = plan.stickyShifts(offset: plan.titles[1].frame.minX + plan.insets.leading, sideInset: sideInset)
    XCTAssertEqual(far[director] ?? -1, room, accuracy: 0.5, "stopped at the end of its group")
    XCTAssertGreaterThan(far[cast] ?? -1, 0, "the next title is on its way to the line")
    let farther = plan.stickyShifts(offset: 10_000, sideInset: sideInset)
    XCTAssertEqual(farther[director] ?? -1, room, accuracy: 0.5)
  }

  func testASubheadingIsSmallerThanARowTitle() {
    XCTAssertLessThan(TVPageGroupTitleCell.subheadingFont.pointSize, TVPageGroupTitleCell.titleFont.pointSize)
    // A group that says it is a subheading is measured in the subheading's type.
    let headed = TVPageSection.strip(id: "credits", title: "Cast & Crew", groups: [
      TVPageGroup(id: "directors", title: "Director", columns: 3, subheading: true, items: [person("D")])
    ])
    let plain = TVPageSection.strip(id: "credits", groups: [
      TVPageGroup(id: "directors", title: "Director", columns: 3, items: [person("D")])
    ])
    XCTAssertLessThan(plan(headed).titles[0].labelWidth, plan(plain).titles[0].labelWidth)
  }

  func testColumnsOfOneTableShareOneHeight() {
    func spec(_ id: String, rows: Int) -> TVPageItem {
      .info(.spec(.init(id: id, symbol: "play.fill", title: id,
                        rows: (0..<rows).map { .init(id: "\($0)", text: "row \($0)", style: .value) })))
    }
    let table = TVPageSection.strip(id: "specs", groups: [
      TVPageGroup(id: "specs", title: nil, columns: 3, items: [spec("a", rows: 1), spec("b", rows: 9), spec("c", rows: 3)])
    ])
    let heights = Set(plan(table).frames.map(\.height))
    XCTAssertEqual(heights.count, 1, "\(heights)")
  }

  func testAStripIsFindableByItem() {
    let section = credits()
    // Items: 0 title, 1 director, 2 title, 3 A, 4 B, 5 C.
    XCTAssertEqual(section.stripGroup(ofItem: 1)?.group, 0)
    XCTAssertEqual(section.stripGroup(ofItem: 1)?.title, 0)
    XCTAssertEqual(section.stripGroup(ofItem: 5)?.group, 1)
    XCTAssertEqual(section.stripGroup(ofItem: 5)?.title, 2)
    XCTAssertNil(section.stripGroup(ofItem: 6))
    XCTAssertNil(TVPageSection.posters(id: "p", title: nil, cards: []).stripGroup(ofItem: 0))
  }
}
#endif
