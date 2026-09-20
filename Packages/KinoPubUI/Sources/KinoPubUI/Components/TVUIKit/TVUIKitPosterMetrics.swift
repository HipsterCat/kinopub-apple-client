#if os(tvOS)
//
//  TVUIKitPosterMetrics.swift
//  KinoPubUI
//
//  One sizing model for shelves AND grids — same `ShelfMetrics` column equation.
//  A horizontal shelf is the same poster grid scrolled sideways.
//
//  The poster tile is deliberately back to **one** caption line (2026-08-11). A second
//  line was tried and reverted along with the rest of the poster experiment: see
//  `TVUIKitPosterCell`.
//

import CoreGraphics
import SwiftUI
import UIKit

public enum TVUIKitPosterMetrics {
  /// On-focus caption under poster. One line.
  public static let captionHeight: CGFloat = 44
  /// Rest gap, unfocused poster → caption. Sasha: **2 pt**. Focused lockups grow
  /// downward; see `captionFocusClearance(tileHeight:)`.
  public static let captionTopPadding: CGFloat = 2

  /// Extra caption offset so the label clears the **focused** (scaled) poster.
  /// Half of the ~10% focus growth — the part that expands below the unfocused bottom.
  public static func captionFocusClearance(tileHeight: CGFloat) -> CGFloat {
    (tileHeight * ShelfMetrics.tvFocusGrowth / 2).rounded()
  }
  public static let cornerRadius: CGFloat = 16

  /// Room a tile needs above and below itself for the focus lift, plus a gap so two
  /// stacked rows do not touch when one of them is focused. Same rule as
  /// `ShelfMetrics.tvGutter`, applied to the tile's *height* — a constant reserve is
  /// either wasted space on a small tile or a collision on a large one.
  public static func focusGrowthPadding(tileHeight: CGFloat) -> CGFloat {
    (tileHeight * ShelfMetrics.tvFocusGrowth / 2).rounded() + ShelfMetrics.tvMinimumGap
  }

  public static func posterSize(containerWidth: CGFloat,
                                typeSize: DynamicTypeSize = .large,
                                safeArea: CGFloat = 0,
                                leadingInset: CGFloat? = nil) -> CGSize {
    // Width is the HIG pin (260), not a divide of this container. Filling a
    // sidebar-narrow Library pane by 6 columns is what shrank those posters.
    _ = leadingInset
    let metrics = ShelfMetrics.posters(width: containerWidth, typeSize: typeSize, safeArea: safeArea)
    let width = metrics.cardWidth(in: containerWidth)
    let height = width / CardAspect.poster.ratio
    return CGSize(width: width, height: height)
  }

  public static func landscapeSize(containerWidth: CGFloat,
                                   typeSize: DynamicTypeSize = .large,
                                   safeArea: CGFloat = 0) -> CGSize {
    let metrics = ShelfMetrics.landscape(width: containerWidth, typeSize: typeSize, safeArea: safeArea)
    let width = metrics.cardWidth(in: containerWidth)
    let height = width / CardAspect.landscape.ratio
    return CGSize(width: width, height: height)
  }

  public static func shelfMetrics(isLandscape: Bool,
                                  containerWidth: CGFloat,
                                  typeSize: DynamicTypeSize = .large,
                                  safeArea: CGFloat = 0) -> ShelfMetrics {
    isLandscape
      ? .landscape(width: containerWidth, typeSize: typeSize, safeArea: safeArea)
      : .posters(width: containerWidth, typeSize: typeSize, safeArea: safeArea)
  }

  public static func itemSize(isLandscape: Bool,
                              containerWidth: CGFloat,
                              typeSize: DynamicTypeSize = .large,
                              safeArea: CGFloat = 0,
                              leadingInset: CGFloat? = nil) -> CGSize {
    let tile = isLandscape
      ? landscapeSize(containerWidth: containerWidth, typeSize: typeSize, safeArea: safeArea)
      : posterSize(
        containerWidth: containerWidth,
        typeSize: typeSize,
        safeArea: safeArea,
        leadingInset: leadingInset
      )
    let captionClearance = isLandscape ? 0 : captionFocusClearance(tileHeight: tile.height)
    return CGSize(width: tile.width,
                  height: tile.height
                    + captionTopPadding
                    + captionClearance
                    + captionHeight)
  }

  /// Room reserved above and below the tiles of a section, for the focus lift.
  public static func sectionFocusPadding(isLandscape: Bool,
                                         containerWidth: CGFloat,
                                         typeSize: DynamicTypeSize = .large,
                                         safeArea: CGFloat = 0,
                                         leadingInset: CGFloat? = nil) -> CGFloat {
    let tile = isLandscape
      ? landscapeSize(containerWidth: containerWidth, typeSize: typeSize, safeArea: safeArea)
      : posterSize(
        containerWidth: containerWidth,
        typeSize: typeSize,
        safeArea: safeArea,
        leadingInset: leadingInset
      )
    return focusGrowthPadding(tileHeight: tile.height)
  }

  public static func railHeight(isLandscape: Bool,
                                containerWidth: CGFloat,
                                typeSize: DynamicTypeSize = .large,
                                safeArea: CGFloat = 0,
                                leadingInset: CGFloat? = nil) -> CGFloat {
    let item = itemSize(isLandscape: isLandscape,
                        containerWidth: containerWidth,
                        typeSize: typeSize,
                        safeArea: safeArea,
                        leadingInset: leadingInset)
    let below = sectionFocusPadding(isLandscape: isLandscape,
                                    containerWidth: containerWidth,
                                    typeSize: typeSize,
                                    safeArea: safeArea,
                                    leadingInset: leadingInset)
    // Horizontal poster shelf: no spare strip *above* the cards. Sketch
    // header→items is ~8–24 pt and Section already owns it; stacking a focus
    // strip here was the void. Focus growth goes up into that gap / header dodge
    // (`clipsToBounds` is false). Bottom still reserves lift vs the next row.
    let above: CGFloat = isLandscape ? below : 0
    return item.height + above + below
  }

  /// Orthogonal poster rail for a page collection. `orthogonalLayoutSectionForMediaItems()`
  /// is 16:9 `wideCell` only — there is no 2:3 factory — so this rebuilds the same
  /// continuous section at the HIG poster recipe: 6-col @ **260**, gutter 40.
  @MainActor
  public static func orthogonalPosterSection(
    width: CGFloat,
    leadingInset: CGFloat = 0
  ) -> NSCollectionLayoutSection {
    makeHorizontalPosterSection(
      collectionWidth: width,
      leadingInset: leadingInset,
      trailingInset: 0,
      topInset: 0
    )
  }

  /// Horizontal poster rail: item `fractionalWidth(1)` fills a **260**-wide group
  /// (HIG 6@260). Height fills the collection so the lockup sits at the top —
  /// leftover focus room stays below, not as a gap under the section title.
  @MainActor
  public static func makeHorizontalPosterSection(
    collectionWidth: CGFloat,
    leadingInset: CGFloat,
    trailingInset: CGFloat,
    topInset: CGFloat,
    orthogonal: Bool = true
  ) -> NSCollectionLayoutSection {
    let width = max(collectionWidth, 1)
    let tileWidth = ShelfMetrics.tvCardWidth
    let tileHeight = tileWidth / CardAspect.poster.ratio
    let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
      widthDimension: .fractionalWidth(1),
      heightDimension: .fractionalHeight(1)
    ))
    let group = NSCollectionLayoutGroup.horizontal(
      layoutSize: NSCollectionLayoutSize(
        widthDimension: .absolute(tileWidth),
        heightDimension: .fractionalHeight(1)
      ),
      subitems: [item]
    )
    let section = NSCollectionLayoutSection(group: group)
    if orthogonal {
      section.orthogonalScrollingBehavior = .continuous
    }
    section.interGroupSpacing = ShelfMetrics.tvHorizontalSpacing
    let growth = focusGrowthPadding(tileHeight: tileHeight)
    let system = TVUIKitMediaItemMetrics.systemMetrics(width: width).verticalPadding / 2
    let below = max(growth, system)
    section.contentInsets = NSDirectionalEdgeInsets(
      top: topInset,
      leading: leadingInset,
      bottom: below,
      trailing: trailingInset
    )
    return section
  }
}
#endif
