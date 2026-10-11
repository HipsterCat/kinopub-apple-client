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
@testable import KinoPub
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

  // MARK: - Posters

  private func posters(_ range: Range<Int>) -> [TVPageItem] {
    DetailFixture.similarItems().map(MediaCard.init)[range].map(TVPageItem.card)
  }

  private func similar() -> TVPageSection {
    .strip(id: "similar", title: "Similar", groups: [
      TVPageGroup(id: "genres", title: "Фантастика", columns: 6, subheading: true, cell: .poster,
                  items: posters(0..<3)),
      TVPageGroup(id: "cast", title: "Эти же актёры", columns: 6, subheading: true, cell: .poster,
                  items: posters(3..<5))
    ])
  }

  /// A group of posters is the rails' poster at the rails' gutter — across groups too, which the
  /// subheadings tell apart — and the first cover's art lands on the side inset like any card.
  func testPostersAreTheRailsPosterAtTheRailsGutterAcrossGroupsToo() {
    let section = similar()
    let plan = plan(section)
    XCTAssertEqual(plan.frames.count, section.items.count, "two titles, five covers")
    let recipe = TVPageCellMetrics.recipe(kind: .poster, artWidth: TVHIGGrid.cardWidth(columns: 6, contentWidth: contentWidth),
                                          caption: .never)
    let covers = [plan.frames[1], plan.frames[2], plan.frames[3], plan.frames[5], plan.frames[6]]
    XCTAssertTrue(covers.allSatisfy { abs($0.width - recipe.itemSize.width) < 1 && abs($0.height - recipe.itemSize.height) < 1 },
                  "every cover is the rails' envelope")
    for (a, b) in zip(covers, covers.dropFirst()) {
      XCTAssertEqual(b.minX - a.minX, recipe.artSize.width + TVHIGGrid.gutter, accuracy: 1,
                     "art to art is the HIG gutter, inside a group and from one group to the next")
    }
    XCTAssertEqual(plan.insets.leading + covers[0].minX + recipe.artInsets.leading, sideInset, accuracy: 1)
  }

  /// A subheading starts where the art under it starts, and the focused cover has room to lift
  /// between the two.
  func testASubheadingSitsOnItsFirstCoversArtWithRoomToLiftBelowIt() {
    let section = similar()
    let plan = plan(section)
    let recipe = TVPageCellMetrics.recipe(kind: .poster, artWidth: TVHIGGrid.cardWidth(columns: 6, contentWidth: contentWidth),
                                          caption: .never)
    XCTAssertEqual(plan.frames[0].minX, plan.frames[1].minX + recipe.artInsets.leading, accuracy: 1)
    XCTAssertEqual(plan.frames[4].minX, plan.frames[5].minX + recipe.artInsets.leading, accuracy: 1)
    let artTop = plan.frames[1].minY + recipe.artInsets.top
    XCTAssertGreaterThanOrEqual(artTop - plan.frames[0].maxY, recipe.artInsets.top,
                                "the cover grows into the air under its title, not into the title")
  }

  // MARK: - One nesting, one look

  /// Cast & Crew and Similar are built alike and have to look alike (Sasha, 2026-10-11): the title
  /// strip, the air under it and where the stack begins are one geometry, whatever the stack is
  /// made of — people's cards or posters.
  func testTheSameNestingHasTheSameGeometryWhateverTheStackIsMadeOf() {
    let people = plan(credits())
    let covers = plan(similar())
    let card = TVPageStripPlan.metrics(of: credits().groups[0].items[0], columns: 3, contentWidth: contentWidth)
    let poster = TVPageStripPlan.metrics(of: similar().groups[0].items[0], columns: 6, contentWidth: contentWidth,
                                         cell: .poster)

    XCTAssertEqual(people.frames[0].minY, 0)
    XCTAssertEqual(covers.frames[0].minY, 0, "the titles are on the strip's top line in both")
    XCTAssertEqual(people.frames[0].height, covers.frames[0].height, "and are as tall")
    let peopleArtTop = people.frames[1].minY + card.insets.top
    let coversArtTop = covers.frames[1].minY + poster.insets.top
    XCTAssertEqual(peopleArtTop, coversArtTop, accuracy: 0.5, "the stack begins as far under its title")
  }

  /// A group's titles lift by one amount, whichever card has focus — the wide card's, which is
  /// what Cast & Crew has always lifted by — and it is less than the air they were given.
  func testEveryTitleLiftsByOneAmount() {
    let wide = TVPageCellMetrics.recipe(kind: .card, artWidth: 560, caption: .always)
    XCTAssertEqual(TVPageLayout.stripTitleLift, TVHIGGrid.focusRoom(cardHeight: wide.itemSize.height))
    XCTAssertGreaterThan(TVPageLayout.stripTitleLift, 0)
    XCTAssertLessThan(TVPageLayout.stripTitleLift, TVHIGGrid.headerToItems)
  }

  // MARK: - One row of people, a grid of stills

  /// A heading of the strip's own over groups with no titles — Cast & Crew's one row — leaves the
  /// cards as far under it as a rail's, which have the same header; with no heading there is no air.
  func testAHeadingOnlyStripStandsItsCardsUnderTheHeaderLikeARail() {
    func row(title: String?) -> TVPageSection {
      .strip(id: "credits", title: title, groups: [
        TVPageGroup(id: "people", title: nil, columns: 3, items: [person("A"), person("B")])
      ])
    }
    let card = TVPageStripPlan.metrics(of: person("A"), columns: 3, contentWidth: contentWidth)
    XCTAssertEqual(plan(row(title: "Cast & Crew")).insets.top, max(TVHIGGrid.headerToItems - card.insets.top, 0),
                   accuracy: 0.5)
    XCTAssertEqual(plan(row(title: nil)).insets.top, 0)
    // And a strip whose groups have titles of their own keeps the title strip, not this air.
    XCTAssertEqual(plan(credits()).insets.top, 0)
  }

  /// The stills are a grid that adapts to how many there are, up to six (Sasha, 2026-10-11), and
  /// fills the platter whatever the number: no cell is left over, nothing overlaps.
  func testStillsFillThePlatterWhateverTheirNumber() {
    XCTAssertEqual(TVPageInfoCard.Gallery.stillCount, 6)
    let platter = CGSize(width: 572, height: 276)
    for count in 1...6 {
      let frames = TVPageGalleryContent.frames(count: count, in: platter)
      XCTAssertEqual(frames.count, count)
      let union = frames.reduce(frames[0]) { $0.union($1) }
      XCTAssertEqual(union.width, platter.width, accuracy: 0.5, "\(count): edge to edge")
      XCTAssertEqual(union.height, platter.height, accuracy: 0.5, "\(count): top to bottom")
      for (index, frame) in frames.enumerated() {
        for other in frames[(index + 1)...] {
          XCTAssertFalse(frame.intersects(other), "\(count): \(frame) over \(other)")
        }
      }
    }
    let one = TVPageGalleryContent.frames(count: 1, in: platter)
    XCTAssertEqual(one, [CGRect(origin: .zero, size: platter)], "one still is the whole platter")
    let two = TVPageGalleryContent.frames(count: 2, in: platter)
    XCTAssertEqual(two[0].minY, two[1].minY, "two stand side by side")
    let three = TVPageGalleryContent.frames(count: 3, in: platter)
    XCTAssertEqual(three[0].minY, three[1].minY, "three: two over one …")
    XCTAssertEqual(three[2].width, platter.width, accuracy: 0.5, "… that is wide")
    let six = TVPageGalleryContent.frames(count: 6, in: platter)
    XCTAssertEqual(Set(six.map(\.minY)).count, 2, "six: three over three")
    XCTAssertTrue(TVPageGalleryContent.frames(count: 9, in: platter).count == 6, "never more than six")
    XCTAssertTrue(TVPageGalleryContent.frames(count: 0, in: platter).isEmpty)
  }

  // MARK: - The count of reviews

  private var reviewsCard: TVPageInfoCard {
    .reviews(.init(id: "reviews", title: "Отзывы", count: "1 063",
                   tones: .init(positive: "45", negative: "11", neutral: "4"), accessibilityLabel: "Отзывы"))
  }

  /// The count of reviews is a score's size — the same height, never narrower than its column — and
  /// is as wide as what it says needs, so a score beside it and it share a row.
  func testTheCountOfReviewsIsAScoresHeightAndAsWideAsItsWordsNeed() {
    let column = TVPageStripPlan.cardWidth(columns: 6, contentWidth: contentWidth, share: nil)
    let rating = TVPageInfoCard.rating(.init(id: "IMDb", source: .imdb, title: "IMDb", value: "6.5"))
    XCTAssertEqual(reviewsCard.height(forWidth: column), rating.height(forWidth: column), "the same height")
    XCTAssertGreaterThanOrEqual(reviewsCard.width(inColumn: column), column, "never narrower than a score")
    XCTAssertEqual(rating.width(inColumn: column), column)

    let section = TVPageSection.strip(id: "ratings", groups: [
      TVPageGroup(id: "scores", title: "Оценки", columns: 6, items: [.info(rating), .info(reviewsCard)])
    ])
    let plan = plan(section)
    let ratingFrame = plan.frames[1], reviewsFrame = plan.frames[2]
    XCTAssertEqual(ratingFrame.height, reviewsFrame.height, accuracy: 0.5, "one row, one height")
    XCTAssertGreaterThanOrEqual(reviewsFrame.width, ratingFrame.width)
    XCTAssertEqual(reviewsFrame.minX - ratingFrame.minX,
                   TVPageStripPlan.metrics(of: .info(rating), columns: 6, contentWidth: contentWidth).art.width + TVPageStripPlan.cardGap,
                   accuracy: 1, "the same air between a score and the count as between two scores")
  }

  /// With no tones — a source that has not said — the card is the total and its title, a score's width.
  func testWithoutTonesTheCountIsAScoresWidth() {
    let bare = TVPageInfoCard.reviews(.init(id: "reviews", title: "Отзывы", count: "63", accessibilityLabel: "Отзывы"))
    let column = TVPageStripPlan.cardWidth(columns: 6, contentWidth: contentWidth, share: nil)
    XCTAssertEqual(bare.width(inColumn: column), column)
  }

  // MARK: - Stacked columns

  private func spec(_ id: String, rows: Int) -> TVPageItem {
    .info(.spec(.init(id: id, title: id, showsHeader: false,
                      rows: (0..<rows).map { .init(id: "\($0)", text: "row \($0)", style: .value) })))
  }

  /// A stacked group is one column: its cards one under the other, each as tall as what it says, and
  /// two columns of three slots leave the third empty — the credits as text.
  func testStackedColumnsStandOneUnderTheOtherAndLeaveAnEmptySlotEmpty() {
    let section = TVPageSection.strip(id: "credits", title: "Cast & Crew", groups: [
      TVPageGroup(id: "authors", title: nil, columns: 3, stacked: true, items: [spec("a", rows: 2)]),
      TVPageGroup(id: "cast", title: nil, columns: 3, stacked: true, items: [spec("b", rows: 2), spec("c", rows: 6)])
    ])
    let plan = plan(section)
    XCTAssertEqual(plan.frames.count, 3)
    let (a, b, c) = (plan.frames[0], plan.frames[1], plan.frames[2])
    XCTAssertEqual(b.minX, c.minX, "one column")
    XCTAssertGreaterThan(c.minY, b.maxY - 1, "the second card under the first")
    XCTAssertGreaterThan(c.height, b.height, "each as tall as its rows, not one height")
    let width = TVPageStripPlan.cardWidth(columns: 3, contentWidth: contentWidth, share: 3)
    XCTAssertEqual(b.minX - a.minX, width + TVHIGGrid.gutter, accuracy: 1, "columns a gutter apart")
    XCTAssertLessThan(plan.size.width, contentWidth, "the third column is left empty")
  }

  /// Borderless items of the table need no room around them for a lift that does not happen.
  func testAnItemOfTheTableHasNoFocusRoom() {
    let metrics = TVPageStripPlan.metrics(of: spec("a", rows: 1), columns: 3, contentWidth: contentWidth, share: 3)
    XCTAssertEqual(metrics.insets, .zero)
    XCTAssertEqual(metrics.art, metrics.envelope)
  }
}
#endif
