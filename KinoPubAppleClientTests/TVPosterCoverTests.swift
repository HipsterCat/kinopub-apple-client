//
//  TVPosterCoverTests.swift
//  KinoPubAppleClientTests
//
//  A cover is the art the recipe promised, whatever its title or its year and whichever cell it
//  landed in. A lockup with a *system* footer splits the height of its cell between the art and
//  the footer, and the footer's second line collapsed in some cells and not in others (a grid
//  scrolled 40 rows: 28 of 99 covers one line with 421 pt of art and no year; the detail
//  fixture: 384 pt in one cover, 424 in the next). So no lockup has a footer: a rail's cover has
//  no caption (`.never`), a grid's has `TVPageCaptionView` — two lines that are there because
//  they are drawn, under an art that does not know about them.
//

#if os(tvOS)
import KinoPubMedia
import KinoPubUI
import TVUIKit
import UIKit
import XCTest
@testable import KinoPubUI

@MainActor
final class TVPosterCoverTests: XCTestCase {

  private var window: UIWindow!

  override func setUp() async throws {
    try await super.setUp()
    window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    window.isHidden = false
  }

  override func tearDown() async throws {
    window.isHidden = true
    window = nil
    try await super.tearDown()
  }

  private let entries: [(title: String, year: Int?)] = [
    ("Дальше от дома", 2023), ("The Old Man", nil), ("Х", nil),
    ("A title long enough to run out of room under any lockup, and then some", 1999), ("Wayne", 2019)
  ]

  /// A row of covers, laid out in cells of the recipe's envelope, with the art arrived.
  private func row(caption: TVPageCaption) async throws -> (cells: [TVPageLockupPosterCell], recipe: TVPageCellRecipe) {
    let recipe = TVPageCellMetrics.recipe(kind: .poster, artWidth: 256, caption: caption)
    var cells: [TVPageLockupPosterCell] = []
    for (index, entry) in entries.enumerated() {
      let cell = TVPageLockupPosterCell(frame: CGRect(x: 40 + CGFloat(index) * 320, y: 100,
                                                      width: recipe.itemSize.width, height: recipe.itemSize.height))
      window.addSubview(cell)
      cell.configure(card: MediaCard(id: index, posterURL: "", title: entry.title, year: entry.year),
                     recipe: recipe, caption: caption)
      cells.append(cell)
    }
    window.layoutIfNeeded()
    // The art is handed to the lockup on the next main-queue turn (`TVUIKitDeferredPosterView`).
    try await Task.sleep(nanoseconds: 600_000_000)
    window.layoutIfNeeded()
    return (cells, recipe)
  }

  /// With every caption there is: the footer is whatever it comes out as — a line, two, one
  /// that collapsed — and the art does not care.
  func testEveryCoverOfARowIsTheArtTheRecipePromised() async throws {
    for caption in [TVPageCaption.never, .always] {
      let (cells, recipe) = try await row(caption: caption)
      for (cell, entry) in zip(cells, entries) {
        let art = cell.posterView.contentView.frame
        let who = "\(caption) \(entry.title) (\(entry.year.map(String.init) ?? "no year"))"
        XCTAssertEqual(art.width, recipe.artSize.width, accuracy: 1, who)
        XCTAssertEqual(art.height, recipe.artSize.height, accuracy: 1, "\(who): the art grew or shrank")
        cell.removeFromSuperview()
      }
    }
  }



  // MARK: Captions follow the shape

  /// A rail names no cover and a grid names every one (Sasha, 2026-10-06) — whatever the call
  /// site says nothing about.
  func testRailsHaveNoCaptionsAndGridsNameEveryCover() {
    let card = MediaCard(id: 1, posterURL: "", title: "A")
    XCTAssertEqual(TVPageSection.posters(id: "r", title: nil, cards: [card]).caption, .never)
    XCTAssertEqual(TVPageSection.posters(id: "g", title: nil, flow: .grid, cards: [card]).caption, .always)
    XCTAssertEqual(TVPageSection.posters(id: "s", title: nil, caption: .always, cards: [card]).caption, .always,
                   "search's shelves say so themselves")
  }

  /// Under a cover: how many episodes of a followed series are left, else the year, else
  /// nothing — the caption keeps its second line anyway.
  func testTheLineUnderACover() {
    let year = MediaCard(id: 1, posterURL: "", title: "A", year: 2019)
    let followed = MediaCard(id: 2, posterURL: "", title: "B", year: 2019, unwatchedEpisodes: 3)
    let caughtUp = MediaCard(id: 3, posterURL: "", title: "C", unwatchedEpisodes: 0)
    let bare = MediaCard(id: 4, posterURL: "", title: "D")
    XCTAssertEqual(TVPageLockupPosterCell.posterSubtitle(for: year, caption: .always), "2019")
    XCTAssertEqual(TVPageLockupPosterCell.posterSubtitle(for: followed, caption: .always),
                   EpisodesLeftText(3)?.formatted(), "what is left beats the year")
    XCTAssertNil(TVPageLockupPosterCell.posterSubtitle(for: caughtUp, caption: .always))
    XCTAssertNil(TVPageLockupPosterCell.posterSubtitle(for: bare, caption: .always))
    XCTAssertNil(TVPageLockupPosterCell.posterSubtitle(for: followed, caption: .never), "a rail has no caption")
  }

  // MARK: The caption under a cover

  /// The envelope of a captioned cover is the bare cover's, the air under the art and two lines
  /// of the caption — the grid's rows keep the pitch they always had (510 pt at a 256 art), and
  /// the lockup is exactly the bare cover.
  func testACaptionedRecipeIsTheBareCoverPlusTwoLines() {
    let bare = TVPageCellMetrics.recipe(kind: .poster, artWidth: 256, caption: .never)
    let captioned = TVPageCellMetrics.recipe(kind: .poster, artWidth: 256, caption: .always)
    let lines = TVPageCaptionView.height(category: TVPageCellMetrics.contentSizeCategory)
    XCTAssertEqual(captioned.captionHeight, lines)
    XCTAssertEqual(captioned.itemSize.height, bare.itemSize.height + TVPageLockupPosterCell.footerGap + lines)
    XCTAssertEqual(captioned.lockupHeight, bare.itemSize.height)
    XCTAssertEqual(captioned.artSize, bare.artSize)
    XCTAssertEqual(captioned.posterContentSize, bare.posterContentSize)
    XCTAssertEqual(bare.captionHeight, 0)
  }

  /// Every captioned cover of a row has its two lines, at one place under its art, and no
  /// footer of the lockup's own — a title with no year included.
  func testEveryCaptionedCoverHasTwoLinesUnderItsArt() async throws {
    let (cells, recipe) = try await row(caption: .always)
    for (cell, entry) in zip(cells, entries) {
      let who = "\(entry.title) (\(entry.year.map(String.init) ?? "no year"))"
      XCTAssertNil(cell.posterView.footerView, "\(who): the lockup has a footer of its own")
      XCTAssertFalse(cell.captionView.isHidden, who)
      XCTAssertEqual(cell.captionView.titleText, entry.title, who)
      XCTAssertEqual(cell.captionView.detailText, entry.year.map(String.init), who)
      let art = cell.posterView.contentView.convert(cell.posterView.contentView.bounds, to: cell)
      XCTAssertEqual(cell.captionView.frame.minY, art.maxY + TVPageLockupPosterCell.footerGap, accuracy: 1, who)
      XCTAssertEqual(cell.captionView.frame.height, recipe.captionHeight, accuracy: 0.5, who)
      XCTAssertEqual(cell.captionView.frame.width, art.width, accuracy: 1, who)
      XCTAssertLessThanOrEqual(cell.captionView.frame.maxY, cell.bounds.height + 0.5, "\(who): hangs out of its cell")
      cell.removeFromSuperview()
    }
  }

  /// A cell is dequeued again and again as a grid scrolls, with a cover of another shape each
  /// time. Nothing it showed before may change the art or the caption it shows now.
  func testReusedCellsKeepTheirArtAndTheirTwoLines() async throws {
    let captioned = TVPageCellMetrics.recipe(kind: .poster, artWidth: 256, caption: .always)
    let bare = TVPageCellMetrics.recipe(kind: .poster, artWidth: 256, caption: .never)
    var cells: [TVPageLockupPosterCell] = []
    for index in 0..<6 {
      let cell = TVPageLockupPosterCell(frame: CGRect(x: 40 + CGFloat(index) * 300, y: 100,
                                                      width: captioned.itemSize.width, height: captioned.itemSize.height))
      window.addSubview(cell)
      cells.append(cell)
    }
    for round in 0..<12 {
      for (index, cell) in cells.enumerated() {
        let id = round * 10 + index
        let withCaption = (round + index) % 4 != 3
        let recipe = withCaption ? captioned : bare
        cell.prepareForReuse()
        cell.frame.size = recipe.itemSize
        cell.configure(card: MediaCard(id: id, posterURL: "", title: "Cover \(id)",
                                       year: id % 5 == 0 ? nil : 1990 + id % 30, unwatchedEpisodes: id % 7 == 0 ? id % 4 + 1 : nil),
                       recipe: recipe, caption: withCaption ? .always : .never)
      }
      window.layoutIfNeeded()
      try await Task.sleep(nanoseconds: 150_000_000)
      window.layoutIfNeeded()
      for (index, cell) in cells.enumerated() {
        let withCaption = (round + index) % 4 != 3
        let who = "round \(round) cell \(index) captioned=\(withCaption)"
        XCTAssertEqual(cell.posterView.contentView.frame.height, captioned.artSize.height, accuracy: 1, "\(who): the art grew")
        XCTAssertEqual(cell.captionView.isHidden, !withCaption, who)
        if withCaption { XCTAssertEqual(cell.captionView.frame.height, captioned.captionHeight, accuracy: 0.5, who) }
      }
    }
  }

  /// The caption follows the cover down when it grows, and back.
  func testTheCaptionDropsWithTheCover() {
    let caption = TVPageCaptionView()
    caption.configure(title: "A", detail: "2019", category: TVPageCellMetrics.contentSizeCategory)
    caption.setFocusedLook(drop: 20)
    XCTAssertEqual(caption.transform.ty, 20, accuracy: 0.01)
    caption.resetToRest()
    XCTAssertTrue(caption.transform.isIdentity)
    caption.resetToRest(reveals: true)
    XCTAssertEqual(caption.alpha, 0, "an .onFocus caption is not there at rest")
  }

  /// A title wider than its line scrolls while focused; one that fits stays put.
  func testOnlyATitleThatDoesNotFitScrolls() {
    let line = TVPageMarqueeLine(frame: CGRect(x: 0, y: 0, width: 256, height: 37))
    line.font = TVPageCaptionView.font(category: TVPageCellMetrics.contentSizeCategory)
    line.text = "Короткое"
    line.startScrolling()
    XCTAssertFalse(line.isScrolling)
    line.text = "A title long enough to run out of room under any lockup, and then some"
    line.startScrolling()
    XCTAssertTrue(line.isScrolling)
    line.stopScrolling()
    XCTAssertFalse(line.isScrolling)
  }

  func testNoCoverHasAFooterToTakeHeightFromItsArt() async throws {
    for caption in [TVPageCaption.never, .always] {
      let (cells, _) = try await row(caption: caption)
      for cell in cells {
        XCTAssertNil(cell.posterView.title)
        XCTAssertNil(cell.posterView.subtitle)
        XCTAssertNil(cell.posterView.footerView, "\(caption)")
        cell.removeFromSuperview()
      }
    }
  }
}
#endif
