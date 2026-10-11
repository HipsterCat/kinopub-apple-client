//
//  SeasonTabStripTests.swift
//  KinoPubAppleClientTests
//
//  The line above the episode rail (Sasha, 2026-10-11): «Сезон» first, then a pill per stop with
//  no gap; the same height whether it has pills or is just «Сезон 1»; a pill as tall as the
//  headline text plus 10 pt above and below and never narrower than tall; seasons that are not
//  on kino.pub say so with a glyph; a run of them is one pill («4–35»).
//

import SwiftUI
import XCTest
@testable import KinoPub

@MainActor
final class SeasonTabStripTests: XCTestCase {

  private func tab(_ id: Int, _ first: Int, _ last: Int? = nil,
                   _ status: SeasonTab.Status = .available) -> SeasonTab {
    SeasonTab(id: id, first: first, last: last ?? first, status: status)
  }

  // MARK: - What a pill says

  func testASeasonIsItsNumberAndARunIsItsEnds() {
    XCTAssertEqual(tab(1, 4).label, "4")
    XCTAssertEqual(tab(-1, 19, 20, .soon).label, "19–20")
    XCTAssertEqual(tab(-2, 4, 35, .unavailable).label, "4–35")
  }

  func testOnlySeasonsNotOnKinoPubCarryAGlyph() {
    XCTAssertNil(SeasonTab.Status.available.symbol)
    XCTAssertEqual(SeasonTab.Status.soon.symbol, "clock.fill")
    XCTAssertEqual(SeasonTab.Status.unavailable.symbol, "lock.fill")
  }

  /// The glyph alone means nothing spoken, so the pill's label says the status in words.
  func testTheSpokenLabelNamesTheStatusOfWhatCannotBeWatched() {
    XCTAssertFalse(tab(1, 3).spokenLabel.contains(","))
    XCTAssertTrue(tab(-1, 8, 8, .soon).spokenLabel.contains(","))
    XCTAssertTrue(tab(-2, 4, 7, .unavailable).spokenLabel.contains("4"))
    XCTAssertTrue(tab(-2, 4, 7, .unavailable).spokenLabel.contains("7"))
  }

#if os(iOS)
  // MARK: - How tall the line is (the SwiftUI strip; tvOS draws `TVSeasonRail`)

  private func height(of tabs: [SeasonTab], selected: Int? = nil,
                      typeSize: DynamicTypeSize = .large) -> CGFloat {
    let strip = SeasonTabStrip(tabs: tabs, selectedID: selected ?? tabs.first?.id, inset: 24, onSelect: { _ in })
      .environment(\.dynamicTypeSize, typeSize)
    let host = UIHostingController(rootView: strip)
    host.view.frame = CGRect(x: 0, y: 0, width: 1_920, height: 600)
    return host.sizeThatFits(in: CGSize(width: 1_920, height: 600)).height
  }

  private var everyKind: [SeasonTab] {
    [tab(1, 1), tab(2, 2), tab(3, 3), tab(-1, 4, 7, .unavailable), tab(-2, 8, 8, .soon)]
  }

  /// «Сезон 1» with nothing to press must not make the rail under it jump when another title
  /// has pills — or glyphs, which are taller than digits in some fonts.
  func testTheLineIsTheSameHeightWithOrWithoutPills() {
    let alone = height(of: [tab(1, 1)])
    XCTAssertGreaterThan(alone, 0)
    XCTAssertEqual(height(of: (1...3).map { tab($0, $0) }), alone, accuracy: 0.5)
    XCTAssertEqual(height(of: everyKind), alone, accuracy: 0.5)
    XCTAssertEqual(height(of: (1...24).map { tab($0, $0) } + [tab(-1, 25, 26, .soon)]), alone, accuracy: 0.5)
  }

  func testTheLineKeepsOneHeightAtLargeTypeToo() {
    let alone = height(of: [tab(1, 1)], typeSize: .accessibility3)
    XCTAssertEqual(height(of: everyKind, typeSize: .accessibility3), alone, accuracy: 0.5)
  }

  /// The pill is the headline style plus fixed padding, so it grows with the text and keeps no
  /// size of its own.
  func testTheLineFollowsDynamicType() throws {
    XCTAssertGreaterThan(height(of: everyKind, typeSize: .accessibility3),
                         height(of: everyKind, typeSize: .large))
  }

  private func pillSize(_ tab: SeasonTab) -> CGSize {
    let host = UIHostingController(rootView: SeasonPill(tab: tab, isSelected: false))
    return host.sizeThatFits(in: CGSize(width: 1_920, height: 600))
  }

  /// A pill is never narrower than tall — and past that it is as wide as its text plus 24 pt
  /// each side: «10» and «4–7» are stadiums, not circles.
  func testAPillIsAtLeastACircleAndTwoDigitsAreWiderThanOne() {
    let one = pillSize(tab(1, 1))
    let ten = pillSize(tab(10, 10))
    let run = pillSize(tab(-1, 4, 7, .unavailable))
    XCTAssertGreaterThanOrEqual(one.width, one.height)
    XCTAssertEqual(ten.height, one.height, accuracy: 0.5)
    XCTAssertGreaterThan(ten.width, one.width, "«10» is no wider than «1»")
    XCTAssertGreaterThan(ten.width, ten.height + 8, "«10» is as round as a single digit")
    XCTAssertGreaterThan(run.width, ten.width)
    XCTAssertGreaterThanOrEqual(one.width, 48, "a pill's text has 24 pt each side")
  }

  /// Headline text plus 10 pt above and below.
  func testTheLineIsHeadlineTextPlusTenPointsEachSide() {
    let headline = UIFont.preferredFont(forTextStyle: .headline).lineHeight
    XCTAssertEqual(height(of: everyKind), headline + 20, accuracy: 2)
  }
#endif
}
