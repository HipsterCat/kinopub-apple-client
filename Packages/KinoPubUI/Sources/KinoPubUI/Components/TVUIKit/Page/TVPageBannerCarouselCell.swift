#if os(tvOS)
//
//  TVPageBannerCarouselCell.swift
//  KinoPubUI
//
//  The Home banner row: one page item the width of the screen holding a collection of
//  its own, laid out by the system's `TVCollectionViewFullScreenLayout` (TVUIKit, WWDC19
//  211, Apple's "Creating immersive experiences using a full-screen layout" sample).
//  The page is a compositional layout and this one is a whole layout, so it nests.
//
//  How the layout works, measured on the tvOS 27.2 simulator (2026-10-02) rather than
//  read from the headers:
//  - Each cell *is* the visible card: the collection's bounds less `maskInset`. Its
//    `maskedBackgroundView` and `maskedContentView` bleed out to the collection's bounds
//    (less the bottom inset), so a cell lays its content out in collection coordinates
//    and keeps it inside the card window, the way the sample does.
//  - The layout owns the scroll. Focus moves a card at a time and the focus engine's
//    scroll animator centres it; the words in `maskedContentView` fade out in flight and
//    back in on the new card, the backdrop runs at the parallax rate.
//  - The card hangs from the top: rounded top corners, a straight bottom edge on the
//    layout's bottom. The bottom inset is never filled, so the band ends at the card.
//  - `maskAmount` opens the mask: 1 is the card with its neighbours, 0 is edge to edge.
//    At any other value than 1 the layout stops browsing: its cards cannot take focus,
//    so Left / Right and Up into the row do nothing (tried 0.5 and 1.3 as a focus
//    look). It is the sample's Expand, not a focus state: Select opens the card edge to
//    edge, reports the title, and closes it again.
//  - Focus is drawn by the system, on the images: the backdrop and the poster set
//    `adjustsImageWhenAncestorFocused`, so the focused card's art zooms inside its mask
//    with the specular highlight and the poster lifts (`TVPageBannerCell`).
//
//  Two things the layout does not survive, both seen in the simulator:
//  - `indexPathForPreferredFocusedView(in:)` is asked on *every* move inside the row.
//    Answering with a title pins focus there and the row stops scrolling (what the
//    device showed on 2026-10-01). It answers once — the middle title, on the first
//    entry — and nil after that; `remembersLastFocusedIndexPath` brings focus back.
//  - Scrolling it by hand (`scrollToItem`, `contentOffset`) leaves the centred card
//    unpainted, and doing it inside `layoutSubviews` moved focus during a layout pass.
//    Nothing here sets the offset.
//
//  Each title once: no laps, no repeats (Sasha, 2026-10-01).
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

  /// How far each card sits in from the band's sides. A neighbour shows
  /// `sideMask − interitemSpacing` past either side: 196 at 1920.
  static let sideMask: CGFloat = 240
  /// Card width over height. Wider than the backdrop's 16:9: the band stays short
  /// enough for the first row under it to show.
  static let cardAspect: CGFloat = 12 / 5
  /// The layout's own room over the card (40 at 1920). The bottom is 0: the layout
  /// never fills it (see the header).
  private static let systemTopInset = TVCollectionViewFullScreenLayout().maskInset.top

  static var maskInset: UIEdgeInsets {
    UIEdgeInsets(top: systemTopInset, left: sideMask, bottom: 0, right: sideMask)
  }

  /// The band's height at this width: the card at `cardAspect` and the room over it.
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
    // The layout sets its own content inset from `maskInset`.
    view.contentInsetAdjustmentBehavior = .never
    // Back into the row lands on the title it was left on — the centred one.
    view.remembersLastFocusedIndexPath = true
    view.accessibilityIdentifier = "kinopub.banner"
    view.delegate = self
    return view
  }()

  private var dataSource: UICollectionViewDiffableDataSource<Int, Int>!
  private var features: [Int: TVPageFeature] = [:]
  private var ids: [Int] = []
  /// Focus has entered this set of titles once; after that the row's own memory and
  /// the layout decide where it lands.
  private var hasEntered = false

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
  /// the middle the next time focus comes in.
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
      hasEntered = false
      var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
      snapshot.appendSections([0])
      snapshot.appendItems(nextIDs, toSection: 0)
      dataSource.apply(snapshot, animatingDifferences: false)
      TVUIKitRemoteImage.prefetch(unique.map { URL(string: $0.card.backdropImageURL) })
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

  /// The page cannot focus this cell; it hands focus to the row, which picks its title.
  override var preferredFocusEnvironments: [UIFocusEnvironment] { [collectionView] }
}

// MARK: - Delegate

extension TVPageBannerCarouselCell: UICollectionViewDelegate {
  /// Once, for the first entry: the middle title. Every later call — and there is one
  /// on every move inside the row — answers nil (see the header).
  func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
    guard !hasEntered else { return nil }
    hasEntered = true
    return startIndexPath
  }

  /// The sample's Expand: the card opens edge to edge, the title is reported, and the
  /// card closes again — the row cannot be browsed while it is open (see the header),
  /// so it never stays open, whether or not the page navigates.
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard let id = dataSource.itemIdentifier(for: indexPath), let feature = features[id] else { return }
    setMaskAmount(0) { [weak self] in
      self?.onSelect?(feature)
      self?.setMaskAmount(1)
    }
  }

  /// `maskAmount` only invalidates the layout; the cards move on the next layout pass,
  /// so the pass runs inside the animation (without it the change lands unanimated and
  /// the completion fires at once).
  private func setMaskAmount(_ amount: CGFloat, completion: (() -> Void)? = nil) {
    UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
      self.layout.maskAmount = amount
      self.collectionView.layoutIfNeeded()
    } completion: { _ in
      completion?()
    }
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
