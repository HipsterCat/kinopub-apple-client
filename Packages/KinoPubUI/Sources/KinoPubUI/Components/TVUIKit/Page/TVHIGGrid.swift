#if os(tvOS)
//
//  TVHIGGrid.swift
//  KinoPubUI
//
//  The tvOS HIG layout grid as one formula, not a table of pinned widths.
//
//  HIG › Layout › tvOS › Grids lists unfocused content widths per column count for a
//  1920-wide screen with 80 pt side margins and 40 pt horizontal spacing:
//
//      2 → 860 · 3 → 560 · 4 → 410 · 5 → 320 · 6 → 260 · 7 → 217 · 8 → 184 · 9 → 160
//
//  Every one of those is `(1760 − 40·(n−1)) / n` — the content box minus the gutters,
//  divided by the count. So the *column count* is the design decision, and the width is
//  what the container yields. A section beside a 420 pt sidebar with `columns: 4` gets
//  a narrower card than the same section full-width — that is the HIG behaviour ("the
//  number of columns in a grid is automatically determined based on the width and
//  spacing of your content"), not a defect to pin away.
//

import CoreGraphics
import Foundation

public enum TVHIGGrid {
  /// HIG: "Inset primary content 60 points from the top and bottom of the screen, and
  /// 80 points from the sides."
  public static let sideInset: CGFloat = 80
  public static let verticalInset: CGFloat = 0

  /// Horizontal spacing between cards. HIG states 40; the stock apps read a touch wider,
  /// and Sasha asked for +4 (2026-09-23). One number — every rail and grid uses it.
  public static let gutter: CGFloat = 44

  /// HIG: "Minimum vertical spacing 100 pt" between unfocused rows of a grid.
  public static let minimumRowSpacing: CGFloat = 100

  /// From the bottom of the chrome above a page (the tab bar's safe area) to the top of
  /// the first row's title strip. The title text sits at the strip's bottom, so the
  /// text itself lands ~`TVPageLayout.headerHeight` lower.
  public static let pageTopGap: CGFloat = 0

  /// Vertical rhythm between *titled* rows (bottom of one row's unfocused cards to the
  /// next row's title). Product decision 2026-09 (Sasha): 80, down from the HIG 100.
  public static let titledRowGap: CGFloat = 80

  /// Space between a row title's baseline box and the top of its unfocused cards. The
  /// focused card grows into this; it must stay clear of the title text.
  public static let headerToItems: CGFloat = 24

  /// A focused lockup grows roughly a tenth of its size (measured on TVPosterView at
  /// 260 wide: ~1.10×). Half of the growth lands above the unfocused top edge.
  public static let focusGrowth: CGFloat = 0.10

  /// The HIG content box: 1920 minus two side insets. The column counts in the table
  /// are stated for this width; a section's `columns` is read against it.
  public static let referenceContentWidth: CGFloat = 1920 - sideInset * 2

  /// Unfocused card width for `columns` cards across `contentWidth` (the container
  /// minus its side insets). Reproduces the HIG table at 1760 to within 1 pt.
  public static func cardWidth(columns: Int, contentWidth: CGFloat) -> CGFloat {
    let n = CGFloat(max(columns, 1))
    let usable = max(contentWidth - gutter * (n - 1), 1)
    return (usable / n).rounded(.down)
  }

  /// A classic collection: fixed side insets, fixed gutter, and as many cards of the
  /// section's size as fit, adjusted to fill the row exactly. `columns` is the count at
  /// 1920 (6 → 256-wide posters with the 44 gutter); a narrower container takes the
  /// nearest whole count, so a card stays within a few percent of its class — the
  /// 1400 pt Library pane beside the sidebar gets five posters of 245.
  public static func resolve(columns: Int, contentWidth: CGFloat) -> (columns: Int, cardWidth: CGFloat) {
    let preferred = cardWidth(columns: columns, contentWidth: referenceContentWidth)
    // Nearest, not floor: the card stays within a few percent of its class either way
    // (a 1400 pane gets five posters of 245, not four of 317).
    let fitting = Int(((contentWidth + gutter) / (preferred + gutter)).rounded())
    let count = max(1, fitting)
    return (count, cardWidth(columns: count, contentWidth: contentWidth))
  }

  /// The width a container yields for a column count, given the full container width
  /// and the side insets the section applies.
  public static func cardWidth(columns: Int,
                               containerWidth: CGFloat,
                               sideInset: CGFloat = sideInset) -> CGFloat {
    cardWidth(columns: columns, contentWidth: containerWidth - sideInset * 2)
  }

  /// Vertical room to reserve above a row so a focused card does not touch the row
  /// title, and below it so it does not touch the next row's title.
  public static func focusRoom(cardHeight: CGFloat) -> CGFloat {
    (cardHeight * focusGrowth / 2).rounded(.up)
  }
}
#endif
