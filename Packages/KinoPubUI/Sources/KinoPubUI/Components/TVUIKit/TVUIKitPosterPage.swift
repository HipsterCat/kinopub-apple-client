#if os(tvOS)
//
//  TVUIKitPosterPage.swift
//  KinoPubUI
//
//  One UICollectionView for a catalog page (Watch Now / Movies / Series): several
//  orthogonal rails as sections, not one UIViewControllerRepresentable per rail in a
//  VStack. Separate bridges are separate focus owners and the place metrics drift.
//
//  Posters: rebuilt continuous section at the HIG 6@260 recipe — Apple's
//  `orthogonalLayoutSectionForMediaItems()` is 16:9 only. Landscape Continue Watching
//  uses `TVUIKitMediaItemMetrics.section`, the accepted adapter around that factory.
//  Headers are non-focusable supplementaries (a navigating title is an extra stop on
//  the way down every row; no Apple tvOS app has one).
//
//  Inset model: 80 pt is the collection’s leading edge in the window (title +
//  first poster). Peek is leftover past 6@260, including the trailing 80 pt of
//  the screen. Not flush-to-edge, not `ignoreSafeArea`, not `insets none`.
//

import SwiftUI
import UIKit
import KinoPubBackend

public struct TVUIKitPosterPage: UIViewControllerRepresentable {
  public let rows: [MediaRow]
  public let typeSize: DynamicTypeSize
  public let onSelect: (MediaCard) -> Void
  public let onNearEnd: ((MediaRow, MediaCard) -> Void)?
  public let paginationProvider: ((MediaRow) -> PaginationState)?
  public let contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])?

  public init(rows: [MediaRow],
              typeSize: DynamicTypeSize = .large,
              onSelect: @escaping (MediaCard) -> Void,
              onNearEnd: ((MediaRow, MediaCard) -> Void)? = nil,
              paginationProvider: ((MediaRow) -> PaginationState)? = nil,
              contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])? = nil) {
    self.rows = rows
    self.typeSize = typeSize
    self.onSelect = onSelect
    self.onNearEnd = onNearEnd
    self.paginationProvider = paginationProvider
    self.contextMenuProvider = contextMenuProvider
  }

  public func makeUIViewController(context: Context) -> TVUIKitPosterPageController {
    let controller = TVUIKitPosterPageController()
    controller.apply(rows: rows,
                     typeSize: typeSize,
                     onSelect: onSelect,
                     onNearEnd: onNearEnd,
                     paginationProvider: paginationProvider,
                     contextMenuProvider: contextMenuProvider)
    return controller
  }

  public func updateUIViewController(_ controller: TVUIKitPosterPageController, context: Context) {
    controller.apply(rows: rows,
                     typeSize: typeSize,
                     onSelect: onSelect,
                     onNearEnd: onNearEnd,
                     paginationProvider: paginationProvider,
                     contextMenuProvider: contextMenuProvider)
  }

  public func sizeThatFits(_ proposal: ProposedViewSize,
                           uiViewController: TVUIKitPosterPageController,
                           context: Context) -> CGSize? {
    guard let width = proposal.width, width > 1 else { return nil }
    guard let height = proposal.height, height > 1 else { return nil }
    return CGSize(width: width, height: height)
  }
}

@MainActor
public final class TVUIKitPosterPageController: UIViewController {
  private var rows: [MediaRow] = []
  private var typeSize: DynamicTypeSize = .large
  private var onSelect: ((MediaCard) -> Void)?
  private var onNearEnd: ((MediaRow, MediaCard) -> Void)?
  private var paginationProvider: ((MediaRow) -> PaginationState)?
  private var contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])?
  private var collectionLeading: NSLayoutConstraint?
  private var collectionTrailing: NSLayoutConstraint?

  private lazy var collectionView: UICollectionView = {
    let config = UICollectionViewCompositionalLayoutConfiguration()
    config.scrollDirection = .vertical
    config.interSectionSpacing = ShelfMetrics.tvTitledRowSpacing
    // Horizontal 80 pt is a collection-frame constant (`tvPageChrome`), not
    // `contentInsetsReference`. `.none` dropped section insets (flush); `.automatic`
    // would double-cut. Zero layout margins so UIKit does not add a second side inset.
    config.contentInsetsReference = .layoutMargins
    let layout = UICollectionViewCompositionalLayout(
      sectionProvider: { [weak self] index, environment in
        self?.makeSection(at: index, width: environment.container.contentSize.width)
      },
      configuration: config
    )
    let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
    view.backgroundColor = .clear
    view.clipsToBounds = false
    view.insetsLayoutMarginsFromSafeArea = false
    view.directionalLayoutMargins = .zero
    view.contentInsetAdjustmentBehavior = .never
    view.contentInset = UIEdgeInsets(
      top: ShelfMetrics.tvPageVerticalInset,
      left: 0,
      bottom: ShelfMetrics.tvPageVerticalInset,
      right: 0
    )
    view.remembersLastFocusedIndexPath = true
    view.showsHorizontalScrollIndicator = false
    view.showsVerticalScrollIndicator = false
    view.alwaysBounceVertical = true
    view.dataSource = self
    view.delegate = self
    view.prefetchDataSource = self
    view.register(TVUIKitPosterCell.self, forCellWithReuseIdentifier: TVUIKitPosterCell.reuseID)
    view.register(TVUIKitMediaItemCell.self, forCellWithReuseIdentifier: TVUIKitMediaItemCell.reuseID)
    view.register(
      TVUIKitPosterPageHeader.self,
      forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
      withReuseIdentifier: TVUIKitPosterPageHeader.reuseID
    )
    view.accessibilityIdentifier = "poster-page"
    return view
  }()

  public override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updateContentInsetsFromScreen()
    unclipOrthogonalScrollers(in: collectionView)
    unclipAncestorsForPeek()
    FocusLog.railGeometry(collectionView, section: "poster-page")
  }

  public override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    view.clipsToBounds = false
    view.insetsLayoutMarginsFromSafeArea = false
    viewRespectsSystemMinimumLayoutMargins = false
    collectionView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(collectionView)
    let leading = collectionView.leadingAnchor.constraint(
      equalTo: view.leadingAnchor,
      constant: ShelfMetrics.tvContentMargin
    )
    let trailing = collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
    collectionLeading = leading
    collectionTrailing = trailing
    NSLayoutConstraint.activate([
      collectionView.topAnchor.constraint(equalTo: view.topAnchor),
      collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      leading,
      trailing
    ])
  }

  /// CURRENT.md: 80 pt leading content column (headers + first poster). Peek is a
  /// partial next card **past that box**, not “insets none” / edge-to-edge chrome.
  /// The 80 pt is the collection’s leading edge in the window — never a negative
  /// bleed, never `ignoreSafeArea`. Trailing may extend into the screen’s last
  /// 80 pt so 6@260 still peeks. Section horizontal insets stay 0.
  private func updateContentInsetsFromScreen() {
    let chrome: ShelfMetrics.TVPageChrome
    if let window = view.window {
      chrome = ShelfMetrics.tvPageChrome(
        viewFrameInWindow: view.convert(view.bounds, to: window),
        windowWidth: window.bounds.width
      )
    } else {
      chrome = ShelfMetrics.TVPageChrome(
        leadingConstant: ShelfMetrics.tvContentMargin,
        trailingOverflow: 0
      )
    }
    let leadingChanged = abs((collectionLeading?.constant ?? 0) - chrome.leadingConstant) > 0.5
    let trailingChanged = abs((collectionTrailing?.constant ?? 0) - chrome.trailingOverflow) > 0.5
    collectionLeading?.constant = chrome.leadingConstant
    collectionTrailing?.constant = chrome.trailingOverflow
    if leadingChanged || trailingChanged {
      collectionView.collectionViewLayout.invalidateLayout()
    }
  }

  /// Compositional orthogonal rails nest a `UICollectionView` per section. Those
  /// inner scrollers default to `clipsToBounds = true`, which is what makes a
  /// 6@260 row look like a non-scrolling stack (CURRENT.md shelf clipping law).
  private func unclipOrthogonalScrollers(in view: UIView) {
    if view is UIScrollView {
      view.clipsToBounds = false
    }
    view.subviews.forEach { unclipOrthogonalScrollers(in: $0) }
  }

  /// Trailing overflow paints the 7th card into the screen’s trailing 80 pt. SwiftUI’s
  /// hosting views clip by default; walk a few ancestors, never the window.
  private func unclipAncestorsForPeek() {
    var ancestor: UIView? = view
    var hops = 0
    while let current = ancestor, hops < 6, !(current is UIWindow) {
      current.clipsToBounds = false
      ancestor = current.superview
      hops += 1
    }
  }

  func apply(rows: [MediaRow],
             typeSize: DynamicTypeSize,
             onSelect: @escaping (MediaCard) -> Void,
             onNearEnd: ((MediaRow, MediaCard) -> Void)?,
             paginationProvider: ((MediaRow) -> PaginationState)?,
             contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])?) {
    let visible = rows.filter { !$0.cards.isEmpty }
    let cardsChanged = Self.cardsSignature(self.rows) != Self.cardsSignature(visible)
    let typeChanged = self.typeSize != typeSize
    self.rows = visible
    self.typeSize = typeSize
    self.onSelect = onSelect
    self.onNearEnd = onNearEnd
    self.paginationProvider = paginationProvider
    self.contextMenuProvider = contextMenuProvider

    if cardsChanged || typeChanged {
      collectionView.reloadData()
    } else {
      refreshVisibleHeaders()
    }
  }

  /// Tuples are not `Equatable`, so an array of them cannot use `!=`.
  private struct CardsSignature: Equatable {
    var id: String
    var cardIDs: [Int]
    var progress: [Double?]
    var watched: [Bool]
  }

  private static func cardsSignature(_ rows: [MediaRow]) -> [CardsSignature] {
    rows.map { row in
      CardsSignature(
        id: row.id,
        cardIDs: row.cards.map(\.id),
        progress: row.cards.map(\.progress),
        watched: row.cards.map(\.isWatched)
      )
    }
  }

  private func isLandscape(section: Int) -> Bool {
    rows.indices.contains(section) && rows[section].cards.first?.isLandscape == true
  }

  private func makeSection(at index: Int, width: CGFloat) -> NSCollectionLayoutSection {
    let section = isLandscape(section: index)
      ? TVUIKitMediaItemMetrics.section(width: max(width, 1), inset: 0)
      : TVUIKitPosterMetrics.orthogonalPosterSection(width: max(width, 1))
    let headerSize = NSCollectionLayoutSize(
      widthDimension: .fractionalWidth(1),
      heightDimension: .estimated(56)
    )
    let header = NSCollectionLayoutBoundarySupplementaryItem(
      layoutSize: headerSize,
      elementKind: UICollectionView.elementKindSectionHeader,
      alignment: .top
    )
    header.pinToVisibleBounds = false
    section.boundarySupplementaryItems = [header]
    section.supplementariesFollowContentInsets = true
    section.contentInsetsReference = .layoutMargins
    // Horizontal column is the collection frame (`tvPageChrome`), not section insets.
    section.contentInsets.leading = 0
    section.contentInsets.trailing = 0
    return section
  }

  private func refreshVisibleHeaders() {
    let kind = UICollectionView.elementKindSectionHeader
    for path in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
      guard let header = collectionView.supplementaryView(
        forElementKind: kind,
        at: path
      ) as? TVUIKitPosterPageHeader,
            rows.indices.contains(path.section)
      else { continue }
      configure(header, for: rows[path.section])
    }
  }

  private func configure(_ header: TVUIKitPosterPageHeader, for row: MediaRow) {
    header.apply(
      title: row.title,
      count: row.count,
      pagination: paginationProvider?(row) ?? .idle
    )
  }

  private func card(at indexPath: IndexPath) -> MediaCard? {
    guard rows.indices.contains(indexPath.section),
          rows[indexPath.section].cards.indices.contains(indexPath.item)
    else { return nil }
    return rows[indexPath.section].cards[indexPath.item]
  }

  private func posterTileSize(width: CGFloat) -> CGSize {
    TVUIKitPosterMetrics.posterSize(
      containerWidth: width,
      typeSize: typeSize
    )
  }
}

extension TVUIKitPosterPageController: UICollectionViewDataSourcePrefetching {
  public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
    TVUIKitRemoteImage.prefetch(artworkURLs(at: indexPaths))
  }

  public func collectionView(_ collectionView: UICollectionView,
                             cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
    TVUIKitRemoteImage.cancelPrefetch(artworkURLs(at: indexPaths))
  }

  private func artworkURLs(at indexPaths: [IndexPath]) -> [URL?] {
    indexPaths.map { path in
      guard let card = card(at: path) else { return nil }
      let string = isLandscape(section: path.section)
        ? (card.landscapeImageURL ?? card.backdropURL ?? card.posterURL)
        : card.posterURL
      return URL(string: string)
    }
  }
}

extension TVUIKitPosterPageController: UICollectionViewDataSource, UICollectionViewDelegate {
  public func numberOfSections(in collectionView: UICollectionView) -> Int {
    rows.count
  }

  public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    rows.indices.contains(section) ? rows[section].cards.count : 0
  }

  public func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  ) -> UICollectionViewCell {
    guard let card = card(at: indexPath) else {
      return collectionView.dequeueReusableCell(
        withReuseIdentifier: TVUIKitPosterCell.reuseID,
        for: indexPath
      )
    }
    if isLandscape(section: indexPath.section) {
      let cell = collectionView.dequeueReusableCell(
        withReuseIdentifier: TVUIKitMediaItemCell.reuseID,
        for: indexPath
      ) as! TVUIKitMediaItemCell
      cell.configure(TVUIKitMediaItem(card: card))
      return cell
    }
    let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: TVUIKitPosterCell.reuseID,
      for: indexPath
    ) as! TVUIKitPosterCell
    cell.configure(card: card, size: posterTileSize(width: collectionView.bounds.width))
    return cell
  }

  public func collectionView(
    _ collectionView: UICollectionView,
    viewForSupplementaryElementOfKind kind: String,
    at indexPath: IndexPath
  ) -> UICollectionReusableView {
    let header = collectionView.dequeueReusableSupplementaryView(
      ofKind: kind,
      withReuseIdentifier: TVUIKitPosterPageHeader.reuseID,
      for: indexPath
    ) as! TVUIKitPosterPageHeader
    if rows.indices.contains(indexPath.section) {
      configure(header, for: rows[indexPath.section])
    }
    return header
  }

  public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard let card = card(at: indexPath) else { return }
    onSelect?(card)
  }

  public func collectionView(_ collectionView: UICollectionView,
                             didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                             with coordinator: UIFocusAnimationCoordinator) {
    let name: (IndexPath?) -> String? = { [weak self] path in
      guard let self, let path, let card = self.card(at: path) else { return nil }
      let row = self.rows.indices.contains(path.section) ? self.rows[path.section].title : "?"
      return "\(row) · \(card.title)"
    }
    let focused = name(context.nextFocusedIndexPath)
    FocusLog.engine(section: "poster-page",
                    from: name(context.previouslyFocusedIndexPath),
                    to: focused)

    coordinator.addCoordinatedAnimations(nil) { [weak self] in
      guard let self else { return }
      var scaled: [String] = []
      var motionOnly: [String] = []
      for cell in collectionView.visibleCells where !cell.isFocused {
        guard let path = collectionView.indexPath(for: cell),
              let card = self.card(at: path) else { continue }
        let residue = cell.focusAppearanceResidue
        if residue.scaled {
          scaled.append(card.title)
        } else if residue.motion {
          motionOnly.append(card.title)
        }
      }
      FocusLog.stranded(section: "poster-page",
                        focused: focused,
                        scaled: scaled,
                        motionOnly: motionOnly)
    }
  }

  public func collectionView(
    _ collectionView: UICollectionView,
    willDisplay cell: UICollectionViewCell,
    forItemAt indexPath: IndexPath
  ) {
    guard rows.indices.contains(indexPath.section) else { return }
    let row = rows[indexPath.section]
    guard let card = card(at: indexPath),
          CatalogLoadMore.isThresholdID(card.id, lastID: row.cards.last?.id)
    else { return }
    onNearEnd?(row, card)
  }

  public func collectionView(
    _ collectionView: UICollectionView,
    contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
    point: CGPoint
  ) -> UIContextMenuConfiguration? {
    guard let indexPath = indexPaths.first,
          let card = card(at: indexPath),
          let entries = contextMenuProvider?(card),
          !entries.isEmpty
    else { return nil }

    return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { _ in
      TVUIKitContextMenuBuilder.menu(from: entries)
    }
  }

  public func collectionView(
    _ collectionView: UICollectionView,
    willEndContextMenuInteractionWith configuration: UIContextMenuConfiguration,
    animator: (any UIContextMenuInteractionAnimating)?
  ) {
    let reset: () -> Void = { [weak self] in
      guard let self else { return }
      collectionView.visibleCells
        .compactMap { $0 as? TVUIKitPosterCell }
        .forEach { $0.resetStaleFocusAppearance() }
    }
    if let animator {
      animator.addCompletion(reset)
    } else {
      reset()
    }
  }
}

// MARK: - Header

/// Row title. Not a focusable control — see `MediaPosterShelf` header on tvOS.
@MainActor
final class TVUIKitPosterPageHeader: UICollectionReusableView {
  static let reuseID = "TVUIKitPosterPageHeader"

  private let titleLabel = UILabel()
  private let countLabel = UILabel()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let failedView = UIImageView()
  private let stack = UIStackView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false

    titleLabel.textColor = .secondaryLabel
    titleLabel.numberOfLines = 1
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    countLabel.textColor = .tertiaryLabel
    countLabel.numberOfLines = 1
    countLabel.adjustsFontForContentSizeCategory = true
    countLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    spinner.hidesWhenStopped = true

    failedView.image = UIImage(systemName: "exclamationmark.triangle")
    failedView.tintColor = .tertiaryLabel
    failedView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption1)
    failedView.setContentHuggingPriority(.required, for: .horizontal)
    failedView.isHidden = true

    let spacer = UIView()
    spacer.setContentHuggingPriority(.init(1), for: .horizontal)
    spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)

    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 8
    stack.addArrangedSubview(titleLabel)
    stack.addArrangedSubview(countLabel)
    stack.addArrangedSubview(spacer)
    stack.addArrangedSubview(spinner)
    stack.addArrangedSubview(failedView)
    addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var canBecomeFocused: Bool { false }

  func apply(title: String, count: String?, pagination: PaginationState) {
    let title2 = UIFont.preferredFont(forTextStyle: .title2)
    titleLabel.font = UIFont.systemFont(ofSize: title2.pointSize, weight: .semibold)
    let title3 = UIFont.preferredFont(forTextStyle: .title3)
    countLabel.font = UIFont.systemFont(ofSize: title3.pointSize, weight: .medium)

    titleLabel.text = title
    let trimmed = count?.trimmingCharacters(in: .whitespacesAndNewlines)
    countLabel.text = trimmed?.isEmpty == false ? trimmed : nil
    countLabel.isHidden = countLabel.text == nil

    switch pagination.phase {
    case .loading:
      spinner.startAnimating()
      failedView.isHidden = true
    case .failed:
      spinner.stopAnimating()
      failedView.isHidden = false
    case .idle, .complete:
      spinner.stopAnimating()
      failedView.isHidden = true
    }
  }
}
#endif
