#if os(tvOS)
//
//  TVPageBannerCarouselCell.swift
//  KinoPubUI
//
//  The Home banner row: one page item the width of the screen holding a collection of
//  its own, laid out by the system's `TVCollectionViewFullScreenLayout` (TVUIKit, the
//  layout Top Shelf's carousel uses — WWDC19 211). The page is a compositional layout
//  and this one is a whole layout, not a section, so it nests.
//
//  One card in the middle, a sliver of each neighbour past its sides; focus moves the
//  row a card at a time and the layout centres it, with its own parallax between the
//  backdrop and the words. Each title once: no laps, no repeats (Sasha, 2026-10-01).
//  The page hands focus here (`preferredFocusEnvironments`) and the row starts on its
//  middle title, so there is a neighbour on either side from the first frame.
//

import TVUIKit
import UIKit

@MainActor
final class TVPageBannerCarouselCell: UICollectionViewCell {
  /// Select on the centred title.
  var onSelect: ((TVPageFeature) -> Void)?
  /// The card menu for a title (long Select / Play-Pause).
  var contextMenuEntries: ((MediaCard) -> [MediaCardContextEntry])?

  // MARK: - Geometry

  /// How far each card sits in from the band's sides. The layout places its cells (each
  /// as wide as the band) one card plus `interitemSpacing` apart, so a neighbour shows
  /// `sideMask − gutter` past either side: about 200 at 1920. Read from the docs and
  /// WWDC19 211, not yet seen on a device.
  static let sideMask: CGFloat = 240
  /// Card width over height. Wider than the backdrop's 16:9: the band stays short
  /// enough for the first row under it to show.
  static let cardAspect: CGFloat = 12 / 5
  /// The layout's own top and bottom mask (32 and 0 by default): room over the card.
  private static let systemMaskInset = TVCollectionViewFullScreenLayout().maskInset

  static var maskInset: UIEdgeInsets {
    UIEdgeInsets(top: systemMaskInset.top, left: sideMask, bottom: systemMaskInset.bottom, right: sideMask)
  }

  /// The band's height at this width: the card at `cardAspect`, plus the mask over and
  /// under it.
  static func height(containerWidth: CGFloat) -> CGFloat {
    let card = max(containerWidth - sideMask * 2, 1) / cardAspect
    return (card + maskInset.top + maskInset.bottom).rounded()
  }

  // MARK: - Views

  private let layout: TVCollectionViewFullScreenLayout = {
    let layout = TVCollectionViewFullScreenLayout()
    layout.maskInset = TVPageBannerCarouselCell.maskInset
    layout.interitemSpacing = TVHIGGrid.gutter
    return layout
  }()

  private lazy var collectionView: UICollectionView = {
    let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
    view.backgroundColor = .clear
    view.showsHorizontalScrollIndicator = false
    view.contentInsetAdjustmentBehavior = .never
    // Back into the row lands on the title it was left on — the centred one.
    view.remembersLastFocusedIndexPath = true
    view.delegate = self
    return view
  }()

  private var dataSource: UICollectionViewDiffableDataSource<Int, Int>!
  private var features: [Int: TVPageFeature] = [:]
  private var ids: [Int] = []
  /// A new set of titles waits for the next layout pass to centre its middle one.
  private var needsStartPosition = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    collectionView.frame = contentView.bounds
    collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    contentView.addSubview(collectionView)

    let card = UICollectionView.CellRegistration<TVPageBannerCell, Int> { [weak self] cell, _, id in
      guard let self, let feature = self.features[id] else { return }
      cell.configure(feature: feature, cardInsets: self.layout.maskInset, size: self.collectionView.bounds.size)
    }
    dataSource = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collectionView) { view, indexPath, id in
      view.dequeueConfiguredReusableCell(using: card, for: indexPath, item: id)
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// The titles, each once. The same titles again (their details or logo arrived)
  /// repaint in place and the row stays where it is; a different set starts over in
  /// the middle.
  func configure(features: [TVPageFeature]) {
    var seen = Set<Int>()
    let unique = features.filter { seen.insert($0.card.id).inserted }
    let nextIDs = unique.map(\.card.id)
    let changed = unique.filter { feature in
      self.features[feature.card.id].map { $0 != feature } ?? false
    }.map(\.card.id)
    self.features = Dictionary(uniqueKeysWithValues: unique.map { ($0.card.id, $0) })

    if nextIDs != ids {
      ids = nextIDs
      var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
      snapshot.appendSections([0])
      snapshot.appendItems(nextIDs, toSection: 0)
      dataSource.apply(snapshot, animatingDifferences: false)
      TVUIKitRemoteImage.prefetch(unique.map { URL(string: $0.card.backdropImageURL) })
      needsStartPosition = true
      setNeedsLayout()
    } else if !changed.isEmpty {
      var snapshot = dataSource.snapshot()
      snapshot.reconfigureItems(changed)
      dataSource.apply(snapshot, animatingDifferences: false)
    }
  }

  /// The middle title, rounded down: with six, two to its left and three to its right.
  private var startIndexPath: IndexPath? {
    ids.isEmpty ? nil : IndexPath(item: (ids.count - 1) / 2, section: 0)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    collectionView.frame = contentView.bounds
    guard needsStartPosition, collectionView.bounds.width > 0, let start = startIndexPath else { return }
    needsStartPosition = false
    collectionView.layoutIfNeeded()
    collectionView.scrollToItem(at: start, at: .centeredHorizontally, animated: false)
  }

  /// The page cannot focus this cell; it hands focus to the row, which picks its title.
  override var preferredFocusEnvironments: [UIFocusEnvironment] { [collectionView] }
}

// MARK: - Delegate

extension TVPageBannerCarouselCell: UICollectionViewDelegate {
  func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
    layout.centerIndexPath ?? startIndexPath
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard let id = dataSource.itemIdentifier(for: indexPath), let feature = features[id] else { return }
    onSelect?(feature)
  }

  func collectionView(_ collectionView: UICollectionView,
                      contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                      point: CGPoint) -> UIContextMenuConfiguration? {
    guard let indexPath = TVUIKitContextMenuIndexPath.resolve(in: collectionView, indexPaths: indexPaths, point: point),
          let id = dataSource.itemIdentifier(for: indexPath),
          let card = features[id]?.card else { return nil }
    let entries = contextMenuEntries?(card) ?? []
    guard !entries.isEmpty else { return nil }
    return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { _ in
      TVUIKitContextMenuBuilder.menu(from: entries)
    }
  }
}
#endif
