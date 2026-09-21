#if os(tvOS)
//
//  TVPageLayout.swift
//  KinoPubUI
//
//  Turns a `TVPageSection` into an `NSCollectionLayoutSection` at the width the
//  collection view actually has. Nothing here is passed in from SwiftUI geometry: the
//  section provider reads `environment.container.effectiveContentSize`, so the first
//  layout pass is already the right one — no 1920-default-then-relayout, no tile that
//  paints small and then grows.
//
//  The HIG grid describes the **unfocused** card: `TVHIGGrid.cardWidth(columns:)` wide,
//  40 apart, 80 from the screen edge. The system cells do not all take that as their
//  frame — `TVPosterView` treats its frame as the *focused envelope* and draws the
//  unfocused art inset by its own `focusSizeIncrease` (measured 2026-09-21 on tvOS 27.2:
//  13 / 20 pt for a 260 × 390 poster, and 0 when it has no image, so a lockup that gets
//  its art late jumps). `TVPageCellMetrics` measures each cell family once per width
//  and reports where the unfocused art sits inside the layout item; the layout then
//  places *envelopes* so that the *art* lands on the HIG grid.
//

import TVUIKit
import UIKit

public enum TVPageLayout {
  public static let headerKind = "TVPageSectionHeader"

  /// Height of the row title strip: `.headline` on tvOS plus breathing room.
  public static let headerHeight: CGFloat = 52

  /// Unfocused row-to-row spacing inside a grid, art bottom to art top.
  public static let gridRowSpacing: CGFloat = 64

  /// Chips are the system button height on tvOS; width is whatever the title needs.
  public static let chipHeight: CGFloat = 66
  public static let chipSpacing: CGFloat = 24

  /// The layout for one page: a section provider that resolves the section at that
  /// index from `sections()` at layout time, so a snapshot swap and its geometry can
  /// never disagree.
  @MainActor
  public static func makeLayout(sideInset: CGFloat = TVHIGGrid.sideInset,
                                sections: @escaping () -> [TVPageSection]) -> UICollectionViewCompositionalLayout {
    let configuration = UICollectionViewCompositionalLayoutConfiguration()
    configuration.scrollDirection = .vertical
    configuration.interSectionSpacing = 0
    // Sections carry the side insets; the controller applies the top/bottom safe area
    // as content inset. Referencing the safe area here too would inset twice.
    configuration.contentInsetsReference = .none
    return UICollectionViewCompositionalLayout(
      sectionProvider: { index, environment in
        let all = sections()
        guard all.indices.contains(index) else { return fallback }
        return section(for: all[index], environment: environment, sideInset: sideInset)
      },
      configuration: configuration
    )
  }

  @MainActor
  public static func section(for section: TVPageSection,
                             environment: NSCollectionLayoutEnvironment,
                             sideInset: CGFloat) -> NSCollectionLayoutSection {
    let containerWidth = environment.container.effectiveContentSize.width
    let contentWidth = max(containerWidth - sideInset * 2, 1)

    let layoutSection: NSCollectionLayoutSection
    switch (section.kind, section.flow) {
    case (.chip, _):
      layoutSection = chipRail(sideInset: sideInset)
    case (_, .rail):
      layoutSection = rail(section, contentWidth: contentWidth, sideInset: sideInset)
    case (_, .grid):
      layoutSection = grid(section, contentWidth: contentWidth, sideInset: sideInset)
    }

    if section.title != nil {
      let header = NSCollectionLayoutBoundarySupplementaryItem(
        layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                           heightDimension: .absolute(headerHeight)),
        elementKind: headerKind,
        alignment: .top
      )
      // The header aligns to the *art* column, not the envelope's: it does not follow
      // the section insets (which are envelope-relative) and takes the page inset.
      header.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: sideInset, bottom: 0, trailing: sideInset)
      layoutSection.supplementariesFollowContentInsets = false//'supplementariesFollowContentInsets' was deprecated in tvOS 16.0
      layoutSection.boundarySupplementaryItems = [header]
    }
    return layoutSection
  }

  // MARK: - Templates

  /// One row, orthogonal. The group is one envelope; envelopes are placed so the
  /// unfocused art is `cardWidth` wide, 40 apart, and `sideInset` from the edge. The
  /// trailing inset mirrors the leading one, so cards passing under either margin while
  /// scrolling are symmetrical — HIG "make partially hidden content look symmetrical".
  @MainActor
  private static func rail(_ section: TVPageSection,
                           contentWidth: CGFloat,
                           sideInset: CGFloat) -> NSCollectionLayoutSection {
    let art = TVHIGGrid.resolve(columns: section.columns, contentWidth: contentWidth).cardWidth
    let recipe = TVPageCellMetrics.recipe(kind: section.kind, artWidth: art, caption: section.caption)
    let size = NSCollectionLayoutSize(widthDimension: .absolute(recipe.itemSize.width),
                                      heightDimension: .absolute(recipe.itemSize.height))
    let item = NSCollectionLayoutItem(layoutSize: size)
    let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
    let layoutSection = NSCollectionLayoutSection(group: group)
    layoutSection.orthogonalScrollingBehavior = .continuous
    layoutSection.interGroupSpacing = TVHIGGrid.gutter - recipe.artInsets.leading - recipe.artInsets.trailing
    layoutSection.contentInsets = insets(for: recipe, sideInset: sideInset, titled: section.title != nil)
    return layoutSection
  }

  /// Wrapping rows. `repeatingSubitem` + a fixed inter-item spacing is the HIG formula:
  /// the group is the content width, the gutters come off first, the rest is divided by
  /// the count — applied to envelopes, so that the art inside lands on the grid.
  @MainActor
  private static func grid(_ section: TVPageSection,
                           contentWidth: CGFloat,
                           sideInset: CGFloat) -> NSCollectionLayoutSection {
    let (columns, art) = TVHIGGrid.resolve(columns: section.columns, contentWidth: contentWidth)
    let recipe = TVPageCellMetrics.recipe(kind: section.kind, artWidth: art, caption: section.caption)
    let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
      widthDimension: .fractionalWidth(1),
      heightDimension: .fractionalHeight(1)
    ))
    let group = NSCollectionLayoutGroup.horizontal(
      layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                         heightDimension: .absolute(recipe.itemSize.height)),
      repeatingSubitem: item,
      count: columns
    )
    group.interItemSpacing = .fixed(TVHIGGrid.gutter - recipe.artInsets.leading - recipe.artInsets.trailing)
    let layoutSection = NSCollectionLayoutSection(group: group)
    layoutSection.interGroupSpacing = gridRowSpacing + recipe.belowItem
      - recipe.artInsets.top - recipe.artInsets.bottom
    layoutSection.contentInsets = insets(for: recipe, sideInset: sideInset, titled: section.title != nil)
    return layoutSection
  }

  /// Self-sizing pills in one orthogonal row.
  private static func chipRail(sideInset: CGFloat) -> NSCollectionLayoutSection {
    let size = NSCollectionLayoutSize(widthDimension: .estimated(180),
                                      heightDimension: .absolute(chipHeight))
    let item = NSCollectionLayoutItem(layoutSize: size)
    let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
    let layoutSection = NSCollectionLayoutSection(group: group)
    layoutSection.orthogonalScrollingBehavior = .continuous
    layoutSection.interGroupSpacing = chipSpacing
    layoutSection.contentInsets = NSDirectionalEdgeInsets(
      top: TVHIGGrid.headerToItems, leading: sideInset,
      bottom: TVHIGGrid.titledRowGap, trailing: sideInset
    )
    return layoutSection
  }

  /// Section insets in envelope space, chosen so that the *art* keeps the HIG numbers:
  /// `sideInset` from the edge, `headerToItems` under the title, `titledRowGap` above
  /// the next title (measured from the unfocused art bottom, past any text that hangs
  /// below the item).
  private static func insets(for recipe: TVPageCellRecipe,
                             sideInset: CGFloat,
                             titled: Bool) -> NSDirectionalEdgeInsets {
    let top = titled ? TVHIGGrid.headerToItems : TVHIGGrid.focusRoom(cardHeight: recipe.itemSize.height)
    return NSDirectionalEdgeInsets(
      top: max(top - recipe.artInsets.top, 0),
      leading: max(sideInset - recipe.artInsets.leading, 0),
      bottom: max(TVHIGGrid.titledRowGap + recipe.belowItem - recipe.artInsets.bottom, 0),
      trailing: max(sideInset - recipe.artInsets.trailing, 0)
    )
  }

  private static var fallback: NSCollectionLayoutSection {
    let size = NSCollectionLayoutSize(widthDimension: .absolute(1), heightDimension: .absolute(1))
    let item = NSCollectionLayoutItem(layoutSize: size)
    return NSCollectionLayoutSection(group: .horizontal(layoutSize: size, subitems: [item]))
  }
}

/// How one cell family occupies a layout item at a given unfocused art width.
public struct TVPageCellRecipe: Equatable {
  /// The layout item — a `TVPosterView` envelope, or the still's image box.
  public var itemSize: CGSize
  /// Where the unfocused art sits inside `itemSize`. Zero for cells that draw the art
  /// edge to edge and grow outward on focus (the media-item content view).
  public var artInsets: NSDirectionalEdgeInsets
  /// Text the cell draws *under* its item frame (the media-item content view lays its
  /// lines below the image, outside the item). Reserved in the section's bottom inset.
  public var belowItem: CGFloat
  /// The box the artwork is decoded into.
  public var artSize: CGSize
  /// `TVPosterView.contentSize` that yields `artSize` unfocused.
  public var posterContentSize: CGSize

  public static func == (lhs: TVPageCellRecipe, rhs: TVPageCellRecipe) -> Bool {
    lhs.itemSize == rhs.itemSize
      && lhs.artInsets.top == rhs.artInsets.top && lhs.artInsets.leading == rhs.artInsets.leading
      && lhs.artInsets.bottom == rhs.artInsets.bottom && lhs.artInsets.trailing == rhs.artInsets.trailing
      && lhs.belowItem == rhs.belowItem && lhs.artSize == rhs.artSize
      && lhs.posterContentSize == rhs.posterContentSize
  }
}

/// Accepted adapter. The system cells publish neither their focus envelope nor their
/// text-block height, so each family is probed once per art width with representative
/// content and the answer cached. The probe is the real view type; whatever Apple
/// changes about a lockup's proportions, the next launch measures it.
@MainActor
public enum TVPageCellMetrics {
  private struct Key: Hashable {
    let kind: TVPageCellKind
    let width: CGFloat
    let caption: TVPageCaption
  }

  private static var cache: [Key: TVPageCellRecipe] = [:]

  public static func recipe(kind: TVPageCellKind, artWidth: CGFloat, caption: TVPageCaption) -> TVPageCellRecipe {
    let key = Key(kind: kind, width: artWidth.rounded(), caption: kind == .poster ? caption : .always)
    if let cached = cache[key] { return cached }
    let recipe: TVPageCellRecipe
    switch kind {
    case .poster: recipe = measurePoster(artWidth: key.width, caption: caption)
    case .still: recipe = still(artWidth: key.width)
    case .person: recipe = person(artWidth: key.width)
    case .chip:
      let size = CGSize(width: key.width, height: TVPageLayout.chipHeight)
      recipe = TVPageCellRecipe(itemSize: size, artInsets: .zero, belowItem: 0,
                                artSize: size, posterContentSize: size)
    }
    cache[key] = recipe
    return recipe
  }

  /// `TVPosterView` draws the unfocused art at `contentSize` minus its own
  /// `focusSizeIncrease` (≈5% per side, computed from the image). Ask for a content
  /// size a tenth larger, then read back where the art actually landed.
  private static func measurePoster(artWidth: CGFloat, caption: TVPageCaption) -> TVPageCellRecipe {
    let art = CGSize(width: artWidth, height: (artWidth / CardAspect.poster.ratio).rounded())
    var contentSize = CGSize(width: (art.width / (1 - TVHIGGrid.focusGrowth)).rounded(),
                             height: (art.height / (1 - TVHIGGrid.focusGrowth)).rounded())

    // The increase is not a flat percentage (260 → 13, 289 → 13), so converge on the
    // content size whose unfocused art is exactly `art` — two passes are enough.
    var envelope = CGSize.zero
    var landed = CGRect.zero
    for _ in 0..<3 {
      let probe = TVPosterView(image: TVUIKitTileArtwork.placeholder(size: contentSize))
      probe.contentSize = contentSize
      probe.title = caption == .never ? nil : "Ag"
      envelope = probe.intrinsicContentSize
      probe.frame = CGRect(origin: .zero, size: envelope)
      probe.layoutIfNeeded()
      landed = probe.contentView.frame
      guard landed.width > 1 else { break }
      let dw = art.width - landed.width
      let dh = art.height - landed.height
      if abs(dw) < 1, abs(dh) < 1 { break }
      contentSize.width += dw
      contentSize.height += dh
    }

    guard envelope.width > 1, envelope.height > 1, landed.width > 1 else {
      // The probe reported nothing: fall back to the art box itself, no envelope.
      return TVPageCellRecipe(itemSize: art, artInsets: .zero, belowItem: 0,
                              artSize: art, posterContentSize: art)
    }
    let insets = NSDirectionalEdgeInsets(
      top: landed.minY,
      leading: landed.minX,
      bottom: envelope.height - landed.maxY,
      trailing: envelope.width - landed.maxX
    )
    return TVPageCellRecipe(itemSize: envelope,
                            artInsets: insets,
                            belowItem: 0,
                            artSize: landed.size,
                            posterContentSize: contentSize)
  }

  /// `TVMediaItemContentView` fills its bounds with the image and lays its text lines
  /// *below* the bounds. Apple's own `orthogonalLayoutSectionForMediaItems()` at 1920
  /// measures 320 × 180 items — the HIG 5-column still — with 130 pt of section
  /// padding around them for the text and the focus lift.
  private static func still(artWidth: CGFloat) -> TVPageCellRecipe {
    let art = CGSize(width: artWidth, height: (artWidth / CardAspect.landscape.ratio).rounded())
    return TVPageCellRecipe(itemSize: art, artInsets: .zero, belowItem: stillTextBlock,
                            artSize: art, posterContentSize: art)
  }

  /// One caption line under a still: measured 9 pt gap + 39 pt label on tvOS 27.2.
  static let stillTextBlock: CGFloat = 48

  /// Circle the width of the art, two text lines under it inside the item.
  private static func person(artWidth: CGFloat) -> TVPageCellRecipe {
    let size = CGSize(width: artWidth, height: artWidth + 96)
    return TVPageCellRecipe(itemSize: size, artInsets: .zero, belowItem: 0,
                            artSize: CGSize(width: artWidth, height: artWidth),
                            posterContentSize: size)
  }

  /// The recipe behind a dequeued cell: the cell only knows its item width (the
  /// envelope the layout gave it), so look the recipe up by that. Every recipe the
  /// layout hands out is cached first, so this is a hit for any cell on screen.
  public static func recipe(kind: TVPageCellKind, itemWidth: CGFloat, caption: TVPageCaption) -> TVPageCellRecipe {
    let captionKey: TVPageCaption = kind == .poster ? caption : .always
    if let hit = cache.first(where: { $0.key.kind == kind && $0.key.caption == captionKey
                                        && abs($0.value.itemSize.width - itemWidth) < 1 }) {
      return hit.value
    }
    return recipe(kind: kind, artWidth: itemWidth, caption: caption)
  }

  /// DEBUG readout for the templates gallery.
  public static func debugDescription(kind: TVPageCellKind, artWidth: CGFloat, caption: TVPageCaption) -> String {
    let r = recipe(kind: kind, artWidth: artWidth, caption: caption)
    return "\(kind) art \(Int(artWidth)) → item \(Int(r.itemSize.width))×\(Int(r.itemSize.height)) insets \(Int(r.artInsets.top))/\(Int(r.artInsets.leading))/\(Int(r.artInsets.bottom))/\(Int(r.artInsets.trailing))"
  }
}
#endif
