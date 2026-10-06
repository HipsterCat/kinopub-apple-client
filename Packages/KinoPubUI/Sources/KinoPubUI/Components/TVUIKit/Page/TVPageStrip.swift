#if os(tvOS)
//
//  TVPageStrip.swift
//  KinoPubUI
//
//  Where the cells of a `.strip` go: a row of titled groups, side by side, in one rail.
//
//  A strip is one orthogonal section whose one group is placed by hand (as the chip rail
//  is), so the row scrolls as a single piece — Right from the last score is the first
//  review, and the row's title strip travels with the cards under it. Each group is laid
//  out the way its own kind of section would be, in the same HIG columns, with the same
//  focus room and the same envelope math (`TVPageCellMetrics`): the *art* of the first
//  card lands on the page's side inset and the next row's title is `titledRowGap` below
//  the art. The air is the strip's own — half the HIG gutter between cards, half the
//  group gap between groups (Sasha, 2026-10-06): these are cards of words, not posters,
//  and they read as one family when they are close.
//
//  A group's title stays on screen while any of the group does (`stickyShifts`).
//

import TVUIKit
import UIKit

/// The frames of a strip's cells, from sizes alone.
@MainActor
struct TVPageStripPlan {
  /// One per item of the section, in `items` order, in the group's own space: the top-left
  /// of everything the row draws — titles and focus room included — is (0, 0).
  let frames: [CGRect]
  /// What the group occupies. The row is exactly this tall.
  let size: CGSize
  /// The section's insets, which put the first card's art on the side inset and leave the
  /// art of the last one a side inset from the screen's trailing edge.
  let insets: NSDirectionalEdgeInsets
  /// Each group's title: which item it is, where it is, and how wide its words are.
  let titles: [Title]

  struct Title {
    /// The item's index in the section — the cell that draws it.
    let item: Int
    /// The cell, as wide as its group, in the same space as `frames`.
    let frame: CGRect
    /// What the words themselves take, from the label's leading edge.
    let labelWidth: CGFloat
  }

  /// What one card is: the art at rest, the envelope the cell is given, and what sits
  /// between them (focus room — the platter and the lockups draw outside their frame).
  struct Metrics {
    var art: CGSize
    var insets: NSDirectionalEdgeInsets
    var envelope: CGSize

    init(art: CGSize, insets: NSDirectionalEdgeInsets, envelope: CGSize) {
      self.art = art
      self.insets = insets
      self.envelope = envelope
    }

    init(_ recipe: TVPageCellRecipe) {
      self.init(art: recipe.artSize, insets: recipe.artInsets, envelope: recipe.itemSize)
    }
  }

  /// - Parameter infoHeight: how tall the group's info cards are — the tallest of them, so
  ///   three columns of one table are one height and their platters line up on focus.
  static func metrics(of item: TVPageItem, columns: Int, contentWidth: CGFloat,
                      infoHeight: CGFloat? = nil) -> Metrics {
    let width = TVHIGGrid.resolve(columns: max(columns, 1), contentWidth: contentWidth).cardWidth
    switch item {
    case .info(let card):
      return Metrics(TVPageCellMetrics.cardRecipe(artWidth: width,
                                                  height: infoHeight ?? card.height(forWidth: width)))
    case .chip(let chip):
      let size = CGSize(width: TVPageChipCell.fittingWidth(for: chip), height: TVPageLayout.chipHeight)
      return Metrics(art: size, insets: .zero, envelope: size)
    default:
      // Person, title, skeleton: the search page's wide card.
      return Metrics(TVPageCellMetrics.recipe(kind: .card, artWidth: width, caption: .always))
    }
  }

  /// Art to art between two cards of a group: half the HIG gutter. A pill row keeps its own
  /// spacing.
  static let cardGap: CGFloat = TVHIGGrid.gutter / 2

  private static func gap(after item: TVPageItem) -> CGFloat {
    if case .chip = item { return TVPageLayout.chipSpacing }
    return cardGap
  }

  /// Art to art between two groups. Pills have a row of their own to be told apart in, so
  /// they keep the wider gap; cards sit close.
  private static func groupGap(after group: TVPageGroup) -> CGFloat {
    if case .chip? = group.items.first { return TVPageLayout.stripPillGroupGap }
    return TVPageLayout.stripGroupGap
  }

  init(section: TVPageSection, contentWidth: CGFloat, sideInset: CGFloat) {
    let hasTitles = section.groups.contains { $0.title != nil }
    let titleHeight = TVPageLayout.headerHeight

    let metrics = section.groups.map { group -> [Metrics] in
      let width = TVHIGGrid.resolve(columns: max(group.columns, 1), contentWidth: contentWidth).cardWidth
      let infoHeight = group.items.compactMap { item -> CGFloat? in
        if case .info(let card) = item { return card.height(forWidth: width) }
        return nil
      }.max()
      return group.items.map {
        Self.metrics(of: $0, columns: group.columns, contentWidth: contentWidth, infoHeight: infoHeight)
      }
    }
    let roomAbove = metrics.joined().map(\.insets.top).max() ?? 0
    // Titled: the title strip, then the same air a titled row leaves under its header.
    // Untitled: just the room the focused cards need.
    let artTop = hasTitles ? titleHeight + TVHIGGrid.headerToItems : roomAbove

    var frames: [CGRect] = []
    var titleRecords: [(item: Int, labelWidth: CGFloat)] = []
    var cursor: CGFloat = 0
    for (index, group) in section.groups.enumerated() {
      let start = cursor
      var end = start
      var cards: [CGRect] = []
      for (itemIndex, item) in group.items.enumerated() {
        let card = metrics[index][itemIndex]
        let art = CGRect(x: end, y: artTop, width: card.art.width, height: card.art.height)
        cards.append(CGRect(x: art.minX - card.insets.leading, y: art.minY - card.insets.top,
                            width: card.envelope.width, height: card.envelope.height))
        end = art.maxX + (itemIndex == group.items.count - 1 ? 0 : Self.gap(after: item))
      }
      if let title = group.title {
        let titleFont = TVPageGroupTitleCell.font(subheading: group.isSubheading)
        let wanted = ceil((title as NSString).size(withAttributes: [.font: titleFont]).width) + 4
        end = max(end, start + wanted)
        titleRecords.append((frames.count, wanted))
        frames.append(CGRect(x: start, y: 0, width: end - start, height: titleHeight))
      }
      frames.append(contentsOf: cards)
      cursor = end + Self.groupGap(after: group)
    }

    // Everything above is in art space — x = 0 is the first card's art, and an envelope
    // reaches left of it — so move it all to start at (0, 0) and let the insets say where
    // that lands on the page.
    let union = frames.reduce(frames.first ?? .zero) { $0.union($1) }
    let placed = frames.map { $0.offsetBy(dx: -union.minX, dy: -union.minY) }
    self.frames = placed
    self.size = union.size
    self.titles = titleRecords.map { Title(item: $0.item, frame: placed[$0.item], labelWidth: $0.labelWidth) }

    let roomBelow = metrics.joined().map(\.insets.bottom).max() ?? 0
    let trailing = metrics.last?.last?.insets.trailing ?? 0
    self.insets = NSDirectionalEdgeInsets(
      top: 0,
      leading: max(sideInset + union.minX, 0),
      bottom: max(TVHIGGrid.titledRowGap - roomBelow, 0),
      trailing: max(sideInset - trailing, 0)
    )
  }
}

extension TVPageStripPlan {
  /// How far each title's label stands right of its group's leading edge when the row is
  /// scrolled `offset` points: nothing until the group has begun to slide under the page's
  /// side inset, then enough to hold the label on that line — and no more than the group
  /// has room for, so the label leaves with the last of its cards and the next group's
  /// takes the line, the way a section header is pushed out by the next one.
  ///
  /// Keyed by item index; every title is in the answer, a zero for one that is not moving.
  nonisolated func stickyShifts(offset: CGFloat, sideInset: CGFloat) -> [Int: CGFloat] {
    var shifts: [Int: CGFloat] = [:]
    for title in titles {
      let left = insets.leading + title.frame.minX - offset
      let room = max(title.frame.width - title.labelWidth, 0)
      shifts[title.item] = min(max(sideInset - left, 0), room)
    }
    return shifts
  }
}

extension TVPageLayout {
  /// Air between two groups of cards in a strip, art to art — half the HIG's 80 between
  /// titled rows (Sasha, 2026-10-06). The titles over the groups do the telling-apart.
  public static let stripGroupGap: CGFloat = 40
  /// Between two groups of pills: they keep the wider gap, because the spacing inside a
  /// pill row (`chipSpacing`) is already close to the half.
  public static let stripPillGroupGap: CGFloat = 80

  /// `scrolled` hears the titles' sticky shifts (`TVPageStripPlan.stickyShifts`) every
  /// time the row moves, on the main thread, and puts them on the cells.
  @MainActor
  static func strip(_ section: TVPageSection, contentWidth: CGFloat, sideInset: CGFloat,
                    scrolled: (@MainActor ([Int: CGFloat]) -> Void)? = nil) -> NSCollectionLayoutSection {
    let plan = TVPageStripPlan(section: section, contentWidth: contentWidth, sideInset: sideInset)
    let group = NSCollectionLayoutGroup.custom(
      layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(max(plan.size.width, 1)),
                                         heightDimension: .absolute(max(plan.size.height, 1)))
    ) { _ in plan.frames.map { NSCollectionLayoutGroupCustomItem(frame: $0) } }
    let layoutSection = NSCollectionLayoutSection(group: group)
    layoutSection.orthogonalScrollingBehavior = .continuous
    layoutSection.contentInsets = plan.insets
    if let scrolled, !plan.titles.isEmpty {
      layoutSection.visibleItemsInvalidationHandler = { _, offset, _ in
        let shifts = plan.stickyShifts(offset: offset.x, sideInset: sideInset)
        MainActor.assumeIsolated { scrolled(shifts) }
      }
    }
    return layoutSection
  }
}

extension TVPageInfoCard {
  /// How tall this card is at the width its column gives it.
  @MainActor
  func height(forWidth width: CGFloat) -> CGFloat {
    switch self {
    case .spec(let spec): return max(TVPageSpecContent.height(for: spec), TVPageLayout.infoCardHeight)
    case .rating, .review, .fact, .gallery: return TVPageLayout.infoCardHeight
    }
  }
}
#endif
