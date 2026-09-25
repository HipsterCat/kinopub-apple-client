#if os(tvOS)
//
//  TVPageCollectionViewController.swift
//  KinoPubUI
//
//  One `UICollectionView` for one page region. Sections are data (`TVPageSection`),
//  the layout is a section provider (`TVPageLayout`), cells are the three system cell
//  families plus a chip, and identity is a diffable data source — so a row that gains
//  a page of items, a card whose progress moved, or a skeleton row that fills in is an
//  `apply(snapshot)`, not a rebuilt view tree.
//
//  Why one collection and not one bridged rail per row (what `MediaRowsView` does on
//  tvOS today): every bridged rail is its own view controller, its own focus owner, its
//  own reload cycle and its own copy of the width → metrics → item-size chain, run
//  once with SwiftUI's default width and again with the measured one. That second run
//  is the "posters grow on first draw" a tab switch shows. Here the width is read from
//  the layout environment at the moment cells are sized, so the first size is final.
//

import TVUIKit
import UIKit

/// What the page says about itself while it has nothing (or nothing yet) to show.
public enum TVPageStatus: Equatable {
  case content
  /// Contextual — "Loading Movies", never a bare "Loading".
  case loading(String)
  case failed(message: String, retryTitle: String)
  /// Nothing to show and nothing to retry — "No Results". Focus stays with whatever
  /// sits beside the page (the keyboard, a sidebar).
  case message(String)
}

@MainActor
public final class TVPageCollectionViewController: UIViewController {

  public var onSelect: ((TVPageSection, TVPageItem) -> Void)?
  /// A pull-down chip's option was picked: (chip id, option id).
  public var onChipOption: ((String, String) -> Void)?
  /// The section's last loaded item came on screen; the owner decides if there is more.
  public var onNearEnd: ((TVPageSection) -> Void)?
  public var contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])?
  public var onRetry: (() -> Void)?
  /// `kinopub.page.<name>` — how a UI test tells this page's cells from another tab's.
  public var accessibilityID: String? {
    didSet { if isViewLoaded { collectionView.accessibilityIdentifier = accessibilityID } }
  }

  private(set) var sections: [TVPageSection] = []
  private var sectionsByID: [String: TVPageSection] = [:]
  private var itemsByID: [TVPageItemID: TVPageItem] = [:]
  private var status: TVPageStatus = .content
  private let sideInset: CGFloat
  /// DEBUG `-KINOPUBFocusFirstPoster`: land on the first poster of the first poster
  /// section instead of wherever the engine would go.
  private let prefersFirstPosterFocus: Bool

  private var dataSource: UICollectionViewDiffableDataSource<String, TVPageItemID>!

  private lazy var collectionView: UICollectionView = {
    let layout = TVPageLayout.makeLayout(
      sideInset: sideInset,
      adjustedLeading: { [weak self] in self?.adjustedLeading ?? 0 },
      sections: { [weak self] in self?.sections ?? [] }
    )
    let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
    view.backgroundColor = .clear
    view.clipsToBounds = false
    view.showsVerticalScrollIndicator = false
    view.remembersLastFocusedIndexPath = true  // see `remembersFocus`
    // The safe area (the tab bar's region on top) is applied by the system: the tab bar
    // controller hides and reveals the bar from the *adjusted* insets of the scroll view
    // it observes, and opting out of the adjustment left the bar pinned. Horizontal
    // safe area is zero on a tab page but 80 inside the search container; the layout
    // subtracts it (`adjustedLeading`), so the side inset is 80 from the edge either way.
    view.contentInsetAdjustmentBehavior = .automatic
    view.delegate = self
    view.prefetchDataSource = self
    return view
  }()

  private let statusView = TVPageStatusView()

  public init(sideInset: CGFloat = TVHIGGrid.sideInset, prefersFirstPosterFocus: Bool = false) {
    self.sideInset = sideInset
    self.prefersFirstPosterFocus = prefersFirstPosterFocus
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  public override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    view.clipsToBounds = false

    collectionView.translatesAutoresizingMaskIntoConstraints = false
    collectionView.accessibilityIdentifier = accessibilityID
    view.addSubview(collectionView)
    statusView.translatesAutoresizingMaskIntoConstraints = false
    statusView.onRetry = { [weak self] in self?.onRetry?() }
    view.addSubview(statusView)
    let edges = [
      collectionView.topAnchor.constraint(equalTo: view.topAnchor),
      collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor),
      view.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor)
    ]
    windowExtension = edges
    NSLayoutConstraint.activate(edges + [
      statusView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
      statusView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
    ])

    if DebugLaunch.layoutDebug {
      // The page's own view red, the collection's frame blue; sections paint themselves
      // (`TVPageDebugSectionBackground`), cells and headers yellow / green.
      view.backgroundColor = UIColor.systemRed.withAlphaComponent(0.15)
      collectionView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
      collectionView.layer.borderColor = UIColor.systemBlue.cgColor
      collectionView.layer.borderWidth = 3
    }

    collectionView.remembersLastFocusedIndexPath = remembersFocus
    // Dynamic Type: captions and card text change height, so every recipe is re-measured.
    registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
      self.collectionView.collectionViewLayout.invalidateLayout()
    }

    configureDataSource()
    applySnapshot(animated: false)
    applyStatus()
    updateContentInsets()
    // Report the scroll view from the start. A controller *presented* by a search
    // controller need not get `viewDidAppear`, and the search screen uses this scroll
    // view to collapse its keyboard over the results and bring it back at the top.
    setContentScrollView(collectionView, for: .top)
  }

  public override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    updateContentInsets()
  }

  public override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    extendToWindow()
    updateAdjustedLeading()
    if DebugLaunch.layoutDebug {
      NSLog("PAGEPROBE %@ view=%@ collection=%@ adjusted=%@ safe=%@", accessibilityID ?? "-",
            NSCoder.string(for: view.convert(view.bounds, to: nil)),
            NSCoder.string(for: collectionView.convert(collectionView.bounds, to: nil)),
            NSCoder.string(for: collectionView.adjustedContentInset),
            NSCoder.string(for: collectionView.safeAreaInsets))
    }
  }

  /// top, leading, trailing, bottom — the collection's edges against the page's view.
  private var windowExtension: [NSLayoutConstraint] = []

  /// The collection covers the whole window even when its controller does not. A
  /// collection view keeps a cell only while it is inside its *bounds*; the search
  /// container lays its results out from y = 157 (under the field), so a card scrolling
  /// up was dropped there — still in plain sight, since nothing clips — and the band
  /// above went blank (2026-09-26). Out to the window edges, cells live exactly as long
  /// as they are on screen. The same amount goes back in as content inset (the automatic
  /// one did not grow — measured: the filter row landed on the suggestion row), so the
  /// content stays where it was.
  private func extendToWindow() {
    guard let window = view.window, windowExtension.count == 4 else { return }
    let frame = view.convert(view.bounds, to: window)
    // How far each edge sits inside the window. Every constraint takes the negative:
    // top / leading are collection→view, trailing / bottom view→collection, so a
    // negative constant moves each edge outward.
    let wanted = [frame.minY, frame.minX,
                  window.bounds.maxX - frame.maxX, window.bounds.maxY - frame.maxY].map { -max($0, 0) }
    var changed = false
    for (constraint, constant) in zip(windowExtension, wanted) where abs(constraint.constant - constant) > 0.5 {
      constraint.constant = constant
      changed = true
    }
    if changed { updateContentInsets() }
  }

  /// How far the collection's content already starts from the screen's leading edge:
  /// its own frame in the window (the search container lays its results controller out
  /// inside the 80 pt safe area — measured x = 80, width 1760) plus the scroll view's
  /// adjusted inset. A tab page is full screen with neither.
  private func updateAdjustedLeading() {
    guard view.window != nil else { return }
    let leading = collectionView.convert(collectionView.bounds.origin, to: nil).x - collectionView.contentOffset.x
      + collectionView.adjustedContentInset.left
    guard abs(leading - adjustedLeading) > 0.5 else { return }
    adjustedLeading = leading
    collectionView.collectionViewLayout.invalidateLayout()
  }

  /// See `updateAdjustedLeading` and `TVPageLayout.makeLayout`.
  private var adjustedLeading: CGFloat = 0

  public override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    observeTabBar()
    resetStrandedFocusAppearance()
  }

  public override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    resetStrandedFocusAppearance()
  }

  /// A tab switched away mid focus animation can leave a whole row's lockups lifted and
  /// captioned (the system's unfocus animation never ran). Undo it whenever the page
  /// comes or goes, and after every focus move — see `TVPageLockupPosterCell`.
  private func resetStrandedFocusAppearance() {
    for cell in collectionView.visibleCells where !cell.isFocused {
      (cell as? TVPageLockupPosterCell)?.resetStaleFocusAppearance()
    }
  }

  // MARK: - Row title dodge

  /// Which section holds focus, so a header dequeued while scrolling back starts in
  /// the right place.
  private var focusedSectionIndex: Int?

  private func header(at section: Int) -> UICollectionReusableView? {
    collectionView.supplementaryView(forElementKind: TVPageLayout.headerKind,
                                     at: IndexPath(item: 0, section: section))
  }

  /// The focused card grows upward by its lift; the row title moves up by the same
  /// amount so the two never touch — the small nudge the system rows have.
  private func headerDodge(for section: Int) -> CGAffineTransform {
    guard sections.indices.contains(section) else { return .identity }
    let target = sections[section]
    guard target.kind != .chip else { return .identity }
    let contentWidth = max(collectionView.bounds.width - sideInset * 2, 1)
    let art = TVHIGGrid.resolve(columns: target.columns, contentWidth: contentWidth).cardWidth
    let recipe = TVPageCellMetrics.recipe(kind: target.kind, artWidth: art, caption: target.caption)
    let lift = recipe.artInsets.top > 0
      ? recipe.artInsets.top
      : TVHIGGrid.focusRoom(cardHeight: recipe.itemSize.height)
    return CGAffineTransform(translationX: 0, y: -lift)
  }

  /// The system chrome above a page — the tab bar, a search field — hides and reveals
  /// itself from the scroll view the view controller reports for its top edge
  /// (`setContentScrollView(_:for:)`, the tvOS 15+ replacement for the deprecated
  /// `tabBarObservedScrollView` / `searchControllerObservedScrollView`). The chrome asks
  /// the view controller it holds — for a tab that is SwiftUI's hosting controller, not
  /// this one — so the scroll view is reported on every ancestor up to the container.
  private func observeTabBar() {
    var controller: UIViewController? = self
    // Stop at a search controller: it owns the scroll that carries its keyboard and
    // suggestions over the results. Handing it our collection instead cut the keyboard
    // off the focus graph — Up from the results could never reach it again.
    while let current = controller, !(current is UITabBarController) {
      if current is UISearchController { break }
      if current.contentScrollView(for: .top) !== collectionView {
        current.setContentScrollView(collectionView, for: .top)
      }
      controller = current.parent
    }
  }

  /// The page runs under the tab bar (the host ignores the safe area); the bar's region
  /// arrives as the adjusted top inset, so the first row starts right under it and
  /// scrolls beneath it. Ours is only the HIG 60 pt bottom page inset.
  private func updateContentInsets() {
    // The window extension comes back as content inset, so the first row starts where
    // the page's own view starts — the extension only keeps cells alive past it.
    let extended = windowExtension.map { -$0.constant }
    let top = extended.first ?? 0
    let bottom = extended.count == 4 ? extended[3] : 0
    let insets = UIEdgeInsets(top: top, left: 0, bottom: TVHIGGrid.verticalInset + bottom, right: 0)
    guard collectionView.contentInset != insets else { return }
    collectionView.contentInset = insets
  }

  // MARK: - Data source

  private func configureDataSource() {
    let poster = UICollectionView.CellRegistration<TVPageLockupPosterCell, TVPageItemID> {
      [weak self] cell, indexPath, id in
      guard let self, let section = self.sectionsByID[id.section] else { return }
      let width = self.collectionView.layoutAttributesForItem(at: indexPath)?.size.width
        ?? cell.bounds.width
      let recipe = TVPageCellMetrics.recipe(kind: .poster, itemWidth: width, caption: section.caption)
      switch self.itemsByID[id] {
      case .card(let card)?:
        cell.configure(card: card, recipe: recipe, caption: section.caption)
      default:
        cell.configurePlaceholder(recipe: recipe)
      }
    }

    let still = UICollectionView.CellRegistration<TVUIKitMediaItemCell, TVPageItemID> {
      [weak self] cell, _, id in
      guard let self else { return }
      let captionOnFocus = self.sectionsByID[id.section]?.caption == .onFocus
      switch self.itemsByID[id] {
      case .card(let card)?:
        cell.configure(TVUIKitMediaItem(card: card), captionOnFocus: captionOnFocus)
      default:
        cell.configure(TVUIKitMediaItem(id: id.hashValue, tint: UIColor(white: 0.16, alpha: 1)))
      }
    }

    let person = UICollectionView.CellRegistration<TVUIKitPersonCell, TVPageItemID> {
      [weak self] cell, _, id in
      guard let self, case .person(let person)? = self.itemsByID[id] else { return }
      cell.configure(person: person)
    }

    let chip = UICollectionView.CellRegistration<TVPageChipCell, TVPageItemID> {
      [weak self] cell, _, id in
      guard let self, case .chip(let chip)? = self.itemsByID[id] else { return }
      cell.configure(chip: chip)
      // A pull-down's Select opens its menu; the pick is the action, not the press.
      cell.onSelect = chip.menu != nil ? nil : { [weak self] in
        guard let self, let section = self.sectionsByID[id.section] else { return }
        self.onSelect?(section, .chip(chip))
      }
      cell.onOption = { [weak self] option in
        self?.onChipOption?(chip.id, option)
      }
    }

    let card = UICollectionView.CellRegistration<TVPageWideCardCell, TVPageItemID> {
      [weak self] cell, indexPath, id in
      guard let self else { return }
      let width = self.collectionView.layoutAttributesForItem(at: indexPath)?.size.width
        ?? cell.bounds.width
      cell.apply(recipe: TVPageCellMetrics.recipe(kind: .card, itemWidth: width, caption: .always))
      switch self.itemsByID[id] {
      case .card(let item)?: cell.configure(card: item, match: self.sectionsByID[id.section]?.match)
      case .person(let person)?: cell.configure(person: person)
      default: cell.configurePlaceholder()
      }
    }

    let header = UICollectionView.SupplementaryRegistration<TVPageHeaderView>(
      elementKind: TVPageLayout.headerKind
    ) { [weak self] view, _, indexPath in
      guard let self, self.sections.indices.contains(indexPath.section) else { return }
      let section = self.sections[indexPath.section]
      view.configure(title: section.title ?? "", count: section.count)
      if DebugLaunch.layoutDebug { view.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.3) }
      view.transform = indexPath.section == self.focusedSectionIndex
        ? self.headerDodge(for: indexPath.section)
        : .identity
    }

    dataSource = UICollectionViewDiffableDataSource<String, TVPageItemID>(
      collectionView: collectionView
    ) { [weak self] collectionView, indexPath, id in
      guard let self, let section = self.sectionsByID[id.section] else {
        return collectionView.dequeueConfiguredReusableCell(using: chip, for: indexPath, item: id)
      }
      switch section.kind {
      case .poster:
        return collectionView.dequeueConfiguredReusableCell(using: poster, for: indexPath, item: id)
      case .still:
        return collectionView.dequeueConfiguredReusableCell(using: still, for: indexPath, item: id)
      case .person:
        return collectionView.dequeueConfiguredReusableCell(using: person, for: indexPath, item: id)
      case .chip:
        return collectionView.dequeueConfiguredReusableCell(using: chip, for: indexPath, item: id)
      case .card:
        return collectionView.dequeueConfiguredReusableCell(using: card, for: indexPath, item: id)
      }
    }
    dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
      collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
    }
  }

  // MARK: - Input

  public func apply(sections newSections: [TVPageSection], status: TVPageStatus, animated: Bool) {
    let sectionsChanged = newSections != sections
    if sectionsChanged {
      // Items whose content changed under the same id (progress moved, watched
      // flipped) are reconfigured in place; the diff only moves what moved.
      var nextItems: [TVPageItemID: TVPageItem] = [:]
      nextItems.reserveCapacity(newSections.reduce(0) { $0 + $1.items.count })
      var changed: [TVPageItemID] = []
      for section in newSections {
        for (index, item) in section.items.enumerated() {
          let id = section.itemID(at: index)
          nextItems[id] = item
          if let previous = itemsByID[id], previous != item { changed.append(id) }
        }
      }
      let layoutAffecting = newSections.map(Self.layoutSignature) != sections.map(Self.layoutSignature)
      sections = newSections
      sectionsByID = Dictionary(uniqueKeysWithValues: newSections.map { ($0.id, $0) })
      itemsByID = nextItems
      pendingReconfigure = changed
      if layoutAffecting, isViewLoaded {
        // Column count / kind / flow moved: the section provider must run again.
        collectionView.collectionViewLayout.invalidateLayout()
      }
      applySnapshot(animated: animated)
    }
    if status != self.status || sectionsChanged {
      self.status = status
      applyStatus()
    }
  }

  private var pendingReconfigure: [TVPageItemID] = []
  private var hasAppliedOnce = false

  private func applySnapshot(animated: Bool) {
    guard isViewLoaded, dataSource != nil else { return }
    var snapshot = NSDiffableDataSourceSnapshot<String, TVPageItemID>()
    snapshot.appendSections(sections.map(\.id))
    for section in sections {
      snapshot.appendItems(section.items.indices.map(section.itemID(at:)), toSection: section.id)
    }
    if !pendingReconfigure.isEmpty {
      snapshot.reconfigureItems(pendingReconfigure)
      pendingReconfigure = []
    }
    dataSource.apply(snapshot, animatingDifferences: animated && hasAppliedOnce)
    hasAppliedOnce = true
  }

  /// Everything the layout reads from a section — not its items, except a chip row's
  /// titles (a filter row places each pill at its measured width).
  /// A filter row's pills are laid out at their measured widths, so a title change
  /// ("Жанр" → "Драма +2") is a layout change.
  private static func chipSignature(_ section: TVPageSection) -> String {
    section.items.map { item in
      if case .chip(let chip) = item { return chip.title } else { return "?" }
    }.joined(separator: "|")
  }

  private static func layoutSignature(_ section: TVPageSection) -> String {
    "\(section.id)|\(section.kind)|\(section.flow)|\(section.columns)|\(section.caption)|\(section.title != nil)|\(section.rows)|\(section.kind == .chip ? chipSignature(section) : "")"
  }

  /// The status shows when the page has nothing but chrome: no sections, or only chip
  /// rows. A filter row stays on screen above "No Results" / "Try Again" — a filter or
  /// sort that emptied the page has to be undoable from where it was set.
  private func applyStatus() {
    guard isViewLoaded else { return }
    let onlyChrome = sections.allSatisfy { $0.kind == .chip }
    let showsStatus = onlyChrome && status != .content
    statusView.isHidden = !showsStatus
    collectionView.isHidden = showsStatus && sections.isEmpty
    statusView.apply(status)
    if showsStatus { setNeedsFocusUpdate() }
  }

  // MARK: - Focus

  /// `false` when the page is not the thing focus should land on first — the search
  /// results under the keyboard: preferring the collection there pulled Down from the
  /// tab bar straight into the first poster, past the keyboard, suggestions and scope.
  public var claimsInitialFocus = true

  /// Coming back into the page lands on the card it was left from — what a tab page
  /// wants from the tab bar. Off for search: its filter row lives in the same
  /// collection, and Down from the keyboard jumped past the filters straight to the
  /// last card scrolled to (2026-09-26); there focus should go to what is below.
  public var remembersFocus = true {
    didSet { if isViewLoaded { collectionView.remembersLastFocusedIndexPath = remembersFocus } }
  }

  public override var preferredFocusEnvironments: [UIFocusEnvironment] {
    guard claimsInitialFocus else { return super.preferredFocusEnvironments }
    if !statusView.isHidden { return [statusView] }
    return [collectionView]
  }

  private var firstPosterIndexPath: IndexPath? {
    guard let index = sections.firstIndex(where: { $0.kind == .poster && !$0.items.isEmpty }) else {
      return nil
    }
    return IndexPath(item: 0, section: index)
  }
}

// MARK: - Delegate

extension TVPageCollectionViewController: UICollectionViewDelegate {
  public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard let id = dataSource.itemIdentifier(for: indexPath),
          let section = sectionsByID[id.section],
          let item = itemsByID[id] else { return }
    onSelect?(section, item)
  }

  public func collectionView(_ collectionView: UICollectionView,
                             willDisplay cell: UICollectionViewCell,
                             forItemAt indexPath: IndexPath) {
    if DebugLaunch.layoutDebug { cell.contentView.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.25) }
    guard sections.indices.contains(indexPath.section) else { return }
    let section = sections[indexPath.section]
    guard !section.isPlaceholder, indexPath.item == section.items.count - 1 else { return }
    onNearEnd?(section)
  }

  public func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
    guard sections.indices.contains(indexPath.section) else { return false }
    // Skeleton tiles are not destinations; the page keeps its focus escape elsewhere.
    return !sections[indexPath.section].isPlaceholder
  }

  public func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
    guard prefersFirstPosterFocus else { return nil }
    return firstPosterIndexPath
  }

  public func collectionView(_ collectionView: UICollectionView,
                             didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                             with coordinator: UIFocusAnimationCoordinator) {
    let previousSection = context.previouslyFocusedIndexPath?.section
    let nextSection = context.nextFocusedIndexPath?.section
    focusedSectionIndex = nextSection
    coordinator.addCoordinatedAnimations({ [weak self] in
      guard let self else { return }
      if let previousSection, previousSection != nextSection {
        self.header(at: previousSection)?.transform = .identity
      }
      if let nextSection {
        self.header(at: nextSection)?.transform = self.headerDodge(for: nextSection)
      }
    }, completion: { [weak self] in
      self?.resetStrandedFocusAppearance()
    })

    guard FocusLog.isEnabled else { return }
    let name: (IndexPath?) -> String? = { [weak self] path in
      guard let self, let path, let id = self.dataSource.itemIdentifier(for: path) else { return nil }
      return self.itemsByID[id]?.card?.title ?? id.item
    }
    let sectionName = context.nextFocusedIndexPath.flatMap { path -> String? in
      sections.indices.contains(path.section) ? sections[path.section].id : nil
    } ?? "page"
    FocusLog.engine(section: sectionName,
                    from: name(context.previouslyFocusedIndexPath),
                    to: name(context.nextFocusedIndexPath))
  }

  // tvOS routes long-press-Select to the focused view's responder chain; the
  // collection's own delegate hook is the one UIKit wires to the focus engine, and
  // only the `…ForItemsAt indexPaths:` variant exists on tvOS.
  public func collectionView(_ collectionView: UICollectionView,
                             contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                             point: CGPoint) -> UIContextMenuConfiguration? {
    guard let indexPath = indexPaths.first,
          let id = dataSource.itemIdentifier(for: indexPath),
          let card = itemsByID[id]?.card,
          let entries = contextMenuProvider?(card),
          !entries.isEmpty else { return nil }
    return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { _ in
      TVUIKitContextMenuBuilder.menu(from: entries)
    }
  }
}

// MARK: - Prefetch

extension TVPageCollectionViewController: UICollectionViewDataSourcePrefetching {
  private func artworkURL(at indexPath: IndexPath) -> URL? {
    guard sections.indices.contains(indexPath.section) else { return nil }
    let section = sections[indexPath.section]
    guard section.items.indices.contains(indexPath.item) else { return nil }
    switch section.items[indexPath.item] {
    case .card(let card):
      let string = section.kind == .still
        ? (card.landscapeImageURL ?? card.backdropURL ?? card.posterURL)
        : card.posterURL
      return URL(string: string)
    case .person(let person):
      return person.photoURL
    case .chip, .placeholder:
      return nil
    }
  }

  public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
    TVUIKitRemoteImage.prefetch(indexPaths.map(artworkURL(at:)))
  }

  public func collectionView(_ collectionView: UICollectionView,
                             cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
    TVUIKitRemoteImage.cancelPrefetch(indexPaths.map(artworkURL(at:)))
  }
}

// MARK: - Status

/// "What are we waiting for", or "it failed, try again". The activity indicator always
/// carries a contextual label (HIG: never a bare spinner), and the failure state is a
/// focusable control — a page with nothing focusable is a dead end on a remote.
@MainActor
final class TVPageStatusView: UIView {
  var onRetry: (() -> Void)?

  private let spinner = UIActivityIndicatorView(style: .large)
  private let label = UILabel()
  private let retryButton = UIButton(configuration: .gray())
  private let stack = UIStackView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    label.font = .preferredFont(forTextStyle: .headline)
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 2
    retryButton.configuration?.cornerStyle = .capsule
    retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .primaryActionTriggered)

    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 24
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.addArrangedSubview(spinner)
    stack.addArrangedSubview(label)
    stack.addArrangedSubview(retryButton)
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      widthAnchor.constraint(lessThanOrEqualToConstant: 900)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(_ status: TVPageStatus) {
    switch status {
    case .content:
      spinner.stopAnimating()
      label.text = nil
      retryButton.isHidden = true
    case .loading(let text):
      spinner.startAnimating()
      label.text = text
      retryButton.isHidden = true
    case .failed(let message, let retryTitle):
      spinner.stopAnimating()
      label.text = message
      retryButton.configuration?.title = retryTitle
      retryButton.isHidden = false
    case .message(let text):
      spinner.stopAnimating()
      label.text = text
      retryButton.isHidden = true
    }
  }

  override var preferredFocusEnvironments: [UIFocusEnvironment] {
    retryButton.isHidden ? [] : [retryButton]
  }
}
#endif
