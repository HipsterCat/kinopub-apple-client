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
  /// A multi-select pull-down closed with a new selection: (chip id, option ids).
  public var onChipSelection: ((String, Set<String>) -> Void)?
  /// The section's last loaded item came on screen; the owner decides if there is more.
  public var onNearEnd: ((TVPageSection) -> Void)?
  public var contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])?
  public var onRetry: (() -> Void)?
  /// Menu below the top row returns there; at the top it passes through. On for
  /// every `TVPage` list and Search's results collection. Off on an embedded
  /// page so the detail's Menu still pops. See `StagedMenuBack`.
  public var returnsToTopOnMenu = true
  /// This page is one region of a bigger scroll — the detail page's sections under the
  /// hero. The collection is as tall as its content and does not scroll: the host's
  /// scroll view owns the vertical axis, so the hero, its artwork and these sections stay
  /// one view and focus graph and the focus engine scrolls the one page. It stays out of
  /// the tab bar's scroll-edge observation and never claims first focus. Set before the
  /// view loads. See `TVEmbeddedPage`.
  public var isEmbedded = false
  /// SwiftUI `.onExitCommand` is attached only while this is true, so at the top
  /// row the modifier is `nil` and the tab bar keeps the system default.
  public var onBelowTopRowChange: ((Bool) -> Void)?
  /// `kinopub.page.<name>` — how a UI test tells this page's cells from another tab's.
  public var accessibilityID: String? {
    didSet { if isViewLoaded { collectionView.accessibilityIdentifier = accessibilityID } }
  }

  private(set) var sections: [TVPageSection] = []
  /// Per section, the length it had when it last asked for more.
  private var nearEndReported: [String: Int] = [:]
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
      sideInset: { [weak self] in self?.resolvedSideInset ?? TVHIGGrid.sideInset },
      adjustedLeading: { [weak self] in self?.currentLeading() ?? 0 },
      stripScrolled: { [weak self] section, shifts in self?.stripTitlesMoved(section: section, shifts: shifts) },
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
    view.contentInsetAdjustmentBehavior = isEmbedded ? .never : .automatic
    view.isScrollEnabled = !isEmbedded
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

    // A catalog that wants its first stop on a poster must not remember the sort
    // chip the engine touches while the grid is still a skeleton.
    collectionView.remembersLastFocusedIndexPath = remembersFocus && !prefersFirstPosterFocus
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
    // An embedded page has no scroll of its own to report — the host's is the page's.
    if !isEmbedded { setContentScrollView(collectionView, for: .top) }
  }

  public override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    updateContentInsets()
    collectionView.collectionViewLayout.invalidateLayout()
  }

  public override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if !isEmbedded { extendToWindow() }
    updateAdjustedLeading()
    refreshLoadingTails()
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

  /// The page is the whole screen's width, only laid out inside a narrower box (the
  /// search container's safe area): the collection also reaches the window's sides and
  /// the side inset counts from the screen edge. Off for a page that shares the width
  /// with something beside it — the Library's section list: reaching left put the
  /// grid under the list (2026-09-26).
  public var spansScreenWidth = false {
    didSet { if isViewLoaded { view.setNeedsLayout() } }
  }

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
    let leading = spansScreenWidth ? frame.minX : 0
    let trailing = spansScreenWidth ? window.bounds.maxX - frame.maxX : 0
    let wanted = [frame.minY, leading, trailing, window.bounds.maxY - frame.maxY].map { -max($0, 0) }
    var changed = false
    for (constraint, constant) in zip(windowExtension, wanted) where abs(constraint.constant - constant) > 0.5 {
      constraint.constant = constant
      changed = true
    }
    if changed { updateContentInsets() }
  }

  /// How far the collection's content already starts from the screen's leading edge:
  /// its own frame in the window (the search container lays its results controller out
  /// inside the overscan safe area — measured x = 80, width 1760 on a 1920 display)
  /// plus the scroll view's adjusted inset. A tab page is full screen with neither.
  private func updateAdjustedLeading() {
    guard view.window != nil else { return }
    let leading = currentLeading()
    guard abs(leading - adjustedLeading) > 0.5 else { return }
    adjustedLeading = leading
    collectionView.collectionViewLayout.invalidateLayout()
  }

  /// The last leading `updateAdjustedLeading` saw — only to tell when it moved.
  private var adjustedLeading: CGFloat = 0

  /// The leading edge as the collection sits *now*. The layout reads this, never the
  /// value cached in `viewDidLayoutSubviews`: the search container re-lays its results
  /// out while the keyboard collapses, and a width from one pass with a leading from the
  /// other put the grid at 5, 6 or 7 columns while pages arrived (2026-09-27) — the
  /// column count comes from that width (`TVHIGGrid.resolve`).
  private func currentLeading() -> CGFloat {
    // Beside a sidebar the inset counts from the page's own edge.
    guard spansScreenWidth else { return 0 }
    guard collectionView.window != nil else { return adjustedLeading }
    return collectionView.convert(collectionView.bounds.origin, to: nil).x - collectionView.contentOffset.x
      + collectionView.adjustedContentInset.left
  }

  public override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if !isEmbedded { observeTabBar() }
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

  /// Live overscan inset. Hosts that already sit inside the safe area report 0 here
  /// and `adjustedLeading` removes the remaining gap, so Search is not cut twice.
  /// Full-bleed catalog pages (collection / person) read the real overscan instead of
  /// a hardcoded 80 pt / 1920 canvas.
  private var resolvedSideInset: CGFloat {
    guard isViewLoaded else { return sideInset }
    let safe = max(collectionView.safeAreaInsets.left, collectionView.safeAreaInsets.right)
    return safe > 1 ? safe : sideInset
  }

  private func header(at section: Int) -> UICollectionReusableView? {
    collectionView.supplementaryView(forElementKind: TVPageLayout.headerKind,
                                     at: IndexPath(item: 0, section: section))
  }

  /// The focused card grows upward by its lift; the row title moves up by the same
  /// amount so the two never touch — the small nudge the system rows have.
  private func headerDodge(for section: Int) -> CGAffineTransform {
    guard sections.indices.contains(section) else { return .identity }
    let target = sections[section]
    guard target.kind != .chip, target.kind != .masthead, target.kind != .banner,
          target.kind != .strip, target.kind != .infoCard else { return .identity }
    let contentWidth = max(collectionView.bounds.width - resolvedSideInset * 2, 1)
    let art = TVHIGGrid.resolve(columns: target.columns, contentWidth: contentWidth).cardWidth
    let recipe = TVPageCellMetrics.recipe(kind: target.kind, artWidth: art, caption: target.caption)
    let lift = recipe.artInsets.top > 0
      ? recipe.artInsets.top
      : TVHIGGrid.focusRoom(cardHeight: recipe.itemSize.height)
    return CGAffineTransform(translationX: 0, y: -lift)
  }

  /// Where each strip's group titles stand, by section index and item: a row that has
  /// scrolled keeps the title of the group still on screen at the page's side inset
  /// (`TVPageStripPlan.stickyShifts`). Kept so a title cell dequeued mid-scroll starts
  /// where it belongs.
  private var stickyShifts: [Int: [Int: CGFloat]] = [:]

  /// A strip scrolled: put its titles where they stand now.
  private func stripTitlesMoved(section: Int, shifts: [Int: CGFloat]) {
    guard stickyShifts[section] != shifts else { return }
    stickyShifts[section] = shifts
    for (item, shift) in shifts {
      let cell = collectionView.cellForItem(at: IndexPath(item: item, section: section))
      (cell as? TVPageGroupTitleCell)?.setStickyShift(shift)
    }
  }

  /// Every title cell of the strip `path` is in — all of them, not only the focused card's
  /// own: the titles of one row share a baseline, and one lifting alone reads as misplaced.
  private func stripTitleCells(over path: IndexPath) -> [UICollectionViewCell] {
    guard sections.indices.contains(path.section), sections[path.section].kind == .strip else { return [] }
    let section = sections[path.section]
    return section.items.indices.compactMap { index in
      guard case .groupTitle = section.items[index] else { return nil }
      return collectionView.cellForItem(at: IndexPath(item: index, section: path.section))
    }
  }

  /// The focused card grows upward by its lift; the title over its group moves up by the
  /// same amount so the two never touch — what a row's header does in any other section.
  private func stripTitleDodge(over path: IndexPath) -> CGAffineTransform {
    guard let cell = collectionView.cellForItem(at: path) else { return .identity }
    return CGAffineTransform(translationX: 0, y: -TVHIGGrid.focusRoom(cardHeight: cell.bounds.height))
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
    // An embedded page is exactly its content: no bar above it, no page inset below.
    guard !isEmbedded else {
      if collectionView.contentInset != .zero { collectionView.contentInset = .zero }
      return
    }
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
      let recipe = TVPageCellMetrics.recipe(kind: section.kind, itemWidth: width, caption: section.caption)
      switch self.itemsByID[id] {
      case .card(let card)?:
        cell.configure(card: card, recipe: recipe, caption: section.caption, showsRating: section.showsRating)
      case .tile(let tile)?:
        cell.configure(tile: tile, recipe: recipe, caption: section.caption)
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
      case .tile(let tile)?:
        cell.configure(TVUIKitMediaItem(tile: tile), captionOnFocus: captionOnFocus)
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
      cell.onSelection = { [weak self] selection in
        self?.onChipSelection?(chip.id, selection)
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

    let banner = UICollectionView.CellRegistration<TVPageBannerCarouselCell, TVPageItemID> {
      [weak self] cell, _, id in
      guard let self, case .banner(let features)? = self.itemsByID[id] else { return }
      cell.configure(features: features)
      cell.onSelect = { [weak self] feature in
        guard let self, let section = self.sectionsByID[id.section] else { return }
        self.onSelect?(section, .feature(feature))
      }
      cell.contextMenuEntries = { [weak self] card in
        self?.contextMenuProvider?(card) ?? []
      }
    }

    let masthead = UICollectionView.CellRegistration<TVPageMastheadCell, TVPageItemID> {
      [weak self] cell, _, id in
      guard let self, case .masthead(let header)? = self.itemsByID[id] else { return }
      cell.configure(header)
    }

    let groupTitle = UICollectionView.CellRegistration<TVPageGroupTitleCell, TVPageItemID> {
      [weak self] cell, indexPath, id in
      guard let self, case .groupTitle(_, let text)? = self.itemsByID[id] else { return }
      // Under a heading of the strip's own, a group's title is a subheading.
      var subheading = false
      if self.sections.indices.contains(indexPath.section),
         let (group, _) = self.sections[indexPath.section].stripGroup(ofItem: indexPath.item) {
        subheading = self.sections[indexPath.section].groups[group].isSubheading
      }
      cell.configure(text: text, subheading: subheading)
      cell.setStickyShift(self.stickyShifts[indexPath.section]?[indexPath.item] ?? 0)
    }

    // The info cards: one registration per content, one platter recipe per envelope size.
    let rating = UICollectionView.CellRegistration<TVPageRatingCell, TVPageItemID> {
      [weak self] cell, indexPath, id in
      guard let self, case .info(.rating(let rating))? = self.itemsByID[id] else { return }
      cell.apply(recipe: self.infoRecipe(at: indexPath, cell: cell))
      cell.configure(rating)
    }
    let review = UICollectionView.CellRegistration<TVPageReviewCell, TVPageItemID> {
      [weak self] cell, indexPath, id in
      guard let self, case .info(.review(let review))? = self.itemsByID[id] else { return }
      cell.apply(recipe: self.infoRecipe(at: indexPath, cell: cell))
      cell.configure(review)
    }
    let fact = UICollectionView.CellRegistration<TVPageFactCell, TVPageItemID> {
      [weak self] cell, indexPath, id in
      guard let self, case .info(.fact(let fact))? = self.itemsByID[id] else { return }
      cell.apply(recipe: self.infoRecipe(at: indexPath, cell: cell))
      cell.configure(fact)
    }
    let gallery = UICollectionView.CellRegistration<TVPageGalleryCell, TVPageItemID> {
      [weak self] cell, indexPath, id in
      guard let self, case .info(.gallery(let gallery))? = self.itemsByID[id] else { return }
      let recipe = self.infoRecipe(at: indexPath, cell: cell)
      cell.apply(recipe: recipe)
      cell.configure(gallery, artSize: recipe.artSize)
    }
    let spec = UICollectionView.CellRegistration<TVPageSpecCell, TVPageItemID> {
      [weak self] cell, indexPath, id in
      guard let self, case .info(.spec(let spec))? = self.itemsByID[id] else { return }
      cell.apply(recipe: self.infoRecipe(at: indexPath, cell: cell))
      cell.configure(spec)
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
      // An info card's cell follows from what it says, wherever it sits.
      func dequeueInfo(_ info: TVPageInfoCard) -> UICollectionViewCell {
        switch info {
        case .rating: return collectionView.dequeueConfiguredReusableCell(using: rating, for: indexPath, item: id)
        case .review: return collectionView.dequeueConfiguredReusableCell(using: review, for: indexPath, item: id)
        case .fact: return collectionView.dequeueConfiguredReusableCell(using: fact, for: indexPath, item: id)
        case .gallery: return collectionView.dequeueConfiguredReusableCell(using: gallery, for: indexPath, item: id)
        case .spec: return collectionView.dequeueConfiguredReusableCell(using: spec, for: indexPath, item: id)
        }
      }
      switch section.kind {
      case .poster, .square:
        return collectionView.dequeueConfiguredReusableCell(using: poster, for: indexPath, item: id)
      case .still:
        return collectionView.dequeueConfiguredReusableCell(using: still, for: indexPath, item: id)
      case .person:
        return collectionView.dequeueConfiguredReusableCell(using: person, for: indexPath, item: id)
      case .chip:
        return collectionView.dequeueConfiguredReusableCell(using: chip, for: indexPath, item: id)
      case .card:
        return collectionView.dequeueConfiguredReusableCell(using: card, for: indexPath, item: id)
      case .banner:
        return collectionView.dequeueConfiguredReusableCell(using: banner, for: indexPath, item: id)
      case .masthead:
        return collectionView.dequeueConfiguredReusableCell(using: masthead, for: indexPath, item: id)
      case .infoCard, .strip:
        // A strip is a rail of families: each item says which cell it is.
        switch self.itemsByID[id] {
        case .info(let info)?: return dequeueInfo(info)
        case .groupTitle?: return collectionView.dequeueConfiguredReusableCell(using: groupTitle, for: indexPath, item: id)
        case .chip?: return collectionView.dequeueConfiguredReusableCell(using: chip, for: indexPath, item: id)
        default: return collectionView.dequeueConfiguredReusableCell(using: card, for: indexPath, item: id)
        }
      }
    }
    let loadingFooter = UICollectionView.SupplementaryRegistration<TVPageLoadingFooterView>(
      elementKind: TVPageLayout.loadingFooterKind
    ) { _, _, _ in }

    dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
      kind == TVPageLayout.loadingFooterKind
        ? collectionView.dequeueConfiguredReusableSupplementary(using: loadingFooter, for: indexPath)
        : collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
    }
  }

  /// The platter recipe for the card at `indexPath`: the cell only knows the envelope the
  /// layout gave it, so look the recipe up by that. Every one the layout hands out is
  /// cached first, so this is a hit for any cell on screen.
  private func infoRecipe(at indexPath: IndexPath, cell: UICollectionViewCell) -> TVPageCellRecipe {
    let size = collectionView.layoutAttributesForItem(at: indexPath)?.size ?? cell.bounds.size
    return TVPageCellMetrics.cardRecipe(itemSize: size)
  }

  // MARK: - Input

  public func apply(sections newSections: [TVPageSection], status: TVPageStatus, animated: Bool) {
    givenSections = newSections
    applyGivenSections(status: status, animated: animated)
  }

  /// How tall the sections are at `width` — what an embedded page tells its host. The
  /// layout answers it: lay the collection out at that width and read the content size,
  /// so the host's number can never disagree with what the cells are given.
  public func contentHeight(forWidth width: CGFloat) -> CGFloat {
    loadViewIfNeeded()
    if abs(view.bounds.width - width) > 0.5 {
      view.frame = CGRect(x: 0, y: 0, width: width, height: max(view.bounds.height, 1))
    }
    view.layoutIfNeeded()
    collectionView.layoutIfNeeded()
    return ceil(collectionView.collectionViewLayout.collectionViewContentSize.height)
  }

  /// The sections as the owner gave them; `sections` is these plus each grid's loading
  /// tail (`withLoadingTail`).
  private var givenSections: [TVPageSection] = []
  /// The column count each loading tail was padded for, to re-pad when it changes.
  private var tailColumns: [String: Int] = [:]

  private func applyGivenSections(status: TVPageStatus, animated: Bool) {
    tailColumns = [:]
    let newSections = givenSections.map(withLoadingTail)
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
      // Section indexes may mean other strips now; the next scroll says where titles stand.
      stickyShifts = [:]
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
    focusFirstPosterIfNeeded()
  }

  /// Entry focus is a poster, once the grid has real cells. A sort chip is the first
  /// focusable view while the page is still a header and skeletons. Remembering that
  /// index path makes `indexPathForPreferredFocusedView` lose, so the chip stays
  /// focused after the posters arrive.
  private var didPlacePosterFocus = false
  /// One request only — retrying after the remote moves Up into the masthead yanks
  /// focus back to the poster.
  private var didRequestPosterFocus = false

  private func focusFirstPosterIfNeeded() {
    guard prefersFirstPosterFocus, !didPlacePosterFocus, isViewLoaded else { return }
    guard firstPosterIndexPath != nil else { return }
    if let index = focusedSectionIndex,
       sections.indices.contains(index),
       sections[index].kind == .poster,
       !sections[index].isPlaceholder {
      didPlacePosterFocus = true
      collectionView.remembersLastFocusedIndexPath = remembersFocus
      return
    }
    // Masthead / chips may hold focus while posters are still skeletons. Once a
    // real poster exists, ask once — then stop. Fighting the remote after Up into
    // the header is how focus "jumps" after init.
    guard !didRequestPosterFocus else { return }
    didRequestPosterFocus = true
    collectionView.remembersLastFocusedIndexPath = false
    setNeedsFocusUpdate()
    collectionView.setNeedsFocusUpdate()
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.collectionView.updateFocusIfNeeded()
      self.didPlacePosterFocus = true
      self.collectionView.remembersLastFocusedIndexPath = self.remembersFocus
    }
  }

  private var pendingReconfigure: [TVPageItemID] = []
  private var hasAppliedOnce = false

  /// A grid with more pages coming ends on a full row: its last row is topped up with
  /// skeleton tiles (a full row of them when it is already full), and the layout puts a
  /// spinner under it. A ragged last row with the next section right under it read as
  /// the end of the list. Complete lists (collections) keep their short last row — the
  /// layout sizes every cell at the measured envelope, so a short row no longer grows.
  private func withLoadingTail(_ section: TVPageSection) -> TVPageSection {
    guard section.loadsMore, section.flow == .grid, !section.items.isEmpty, !section.isPlaceholder
    else { return section }
    let columns = gridColumns(for: section)
    tailColumns[section.id] = columns
    let remainder = section.items.count % columns
    return section.appendingPlaceholders(remainder == 0 ? columns : columns - remainder)
  }

  /// How many columns the layout gives a grid at the collection's current width — the
  /// same formula `TVPageLayout.grid` runs.
  private func gridColumns(for section: TVPageSection) -> Int {
    let width = isViewLoaded ? collectionView.bounds.width : 0
    guard width > 0 else { return max(section.columns, 1) }
    let inset = max(resolvedSideInset - currentLeading(), 0)
    return TVHIGGrid.resolve(columns: section.columns, contentWidth: max(width - inset * 2, 1)).columns
  }

  /// The width moved and a tail was padded for another column count: pad again.
  private func refreshLoadingTails() {
    let stale = givenSections.contains { section in
      guard let used = tailColumns[section.id] else { return false }
      return used != gridColumns(for: section)
    }
    if stale { applyGivenSections(status: status, animated: false) }
  }

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
    var signature = "\(section.id)|\(section.kind)|\(section.flow)|\(section.columns)|\(section.caption)|\(section.title != nil)|\(section.rows)|\(section.loadsMore)|\(section.kind == .chip ? chipSignature(section) : "")"
    // Grid height is one custom group sized from item count — a page of results
    // must remeasure. Masthead rest geometry is fixed per style; detail / bio /
    // stats text must not invalidate (that jump stole focus off the first poster).
    if section.flow == .grid {
      signature += "|\(section.items.count)"
    }
    if case .masthead(let header) = section.items.first {
      signature += "|\(header.style)|\(header.stats.isEmpty ? 0 : 1)"
    }
    // A strip places every cell by hand from what the cards are: a column of specs is as
    // tall as its rows, a pill as wide as its title, a group as wide as its heading.
    if section.kind == .strip {
      signature += "|" + section.groups.map { group in
        let items = group.items.map { item -> String in
          switch item {
          case .info(let card): return card.layoutToken
          case .chip(let chip): return chip.title
          default: return "item"
          }
        }.joined(separator: ",")
        return "\(group.id):\(group.columns):\(group.title ?? ""):\(items)"
      }.joined(separator: ";")
    }
    return signature
  }

  /// The status shows when the page has nothing but chrome: no sections, or only chip
  /// rows. A filter row stays on screen above "No Results" / "Try Again" — a filter or
  /// sort that emptied the page has to be undoable from where it was set.
  private func applyStatus() {
    guard isViewLoaded else { return }
    let onlyChrome = sections.allSatisfy { $0.kind == .chip || $0.kind == .masthead }
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
    guard let index = sections.firstIndex(where: {
      $0.kind == .poster && !$0.isPlaceholder && !$0.items.isEmpty
    }) else { return nil }
    let item = sections[index].items.firstIndex { item in
      if case .placeholder = item { return false }
      return true
    }
    guard let item else { return nil }
    return IndexPath(item: item, section: index)
  }

  // MARK: - Staged Menu back

  /// The cell the engine last reported, including a nested banner title walked
  /// up to its page cell. `nil` when focus has left the collection (tab bar,
  /// a pushed page).
  private var focusedPath: IndexPath?
  /// One-shot: `indexPathForPreferredFocusedView` answers the top row, then
  /// `didUpdateFocus` clears it. Same shape as `didRequestPosterFocus`.
  private var wantsTopFocus = false
  /// Pair a Menu `.began` we consumed with its `.ended` / `.cancelled` so the
  /// tab bar does not see a half press. Scoped to this controller's responder
  /// methods — not `UIWindow.sendEvent`.
  private var consumedMenuPress = false
  private var lastPublishedBelowTop = false

  /// True when this collection currently owns focus and that focus is below
  /// the first row. Used to arm `.onExitCommand` only then.
  public var isBelowTopRow: Bool {
    guard returnsToTopOnMenu, !isEmbedded, ownsFocus else { return false }
    guard let top = topSectionIndex else { return false }
    return StagedMenuBack.shouldReturnToTop(
      focusedSection: focusedPath?.section,
      focusedItem: focusedPath.flatMap { nestedItemIndex(at: $0) },
      topSection: top,
      firstRowItemCount: topSectionFirstRowItemCount
    )
  }

  /// Scrolls and focuses the top row. Returns `true` when the press should be
  /// consumed; `false` passes through to the tab bar.
  @discardableResult
  public func returnToTopRow() -> Bool {
    guard isBelowTopRow, topIndexPath != nil else { return false }
    wantsTopFocus = true
    collectionView.remembersLastFocusedIndexPath = false
    lastPublishedBelowTop = false
    onBelowTopRowChange?(false)
    setNeedsFocusUpdate()
    collectionView.setNeedsFocusUpdate()
    collectionView.updateFocusIfNeeded()
    return true
  }

  public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if presses.contains(where: { $0.type == .menu }), returnToTopRow() {
      consumedMenuPress = true
      return
    }
    super.pressesBegan(presses, with: event)
  }

  public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if consumedMenuPress, presses.contains(where: { $0.type == .menu }) {
      consumedMenuPress = false
      return
    }
    super.pressesEnded(presses, with: event)
  }

  public override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if consumedMenuPress, presses.contains(where: { $0.type == .menu }) {
      consumedMenuPress = false
      return
    }
    super.pressesCancelled(presses, with: event)
  }

  private var ownsFocus: Bool {
    guard let item = UIFocusSystem.focusSystem(for: collectionView)?.focusedItem else { return false }
    guard let view = item as? UIView else { return false }
    return view === collectionView || view.isDescendant(of: collectionView)
  }

  private var topSectionIndex: Int? {
    sections.firstIndex { section in
      section.items.contains { item in
        if case .placeholder = item { return false }
        return true
      }
    }
  }

  private var topIndexPath: IndexPath? {
    guard let section = topSectionIndex else { return nil }
    let item = sections[section].items.firstIndex { item in
      if case .placeholder = item { return false }
      return true
    }
    guard let item else { return nil }
    return IndexPath(item: item, section: section)
  }

  private var topSectionFirstRowItemCount: Int {
    guard let section = topSectionIndex else { return 1 }
    let page = sections[section]
    let loaded = page.items.filter { item in
      if case .placeholder = item { return false }
      return true
    }.count
    return StagedMenuBack.firstRowItemCount(
      flowIsGrid: page.flow == .grid,
      columns: page.columns,
      itemCount: loaded
    )
  }

  /// A banner is one page item; its titles are a nested collection. Reporting
  /// item `0` would look like the first row, which is correct. A wrapping grid
  /// uses the real item index.
  private func nestedItemIndex(at path: IndexPath) -> Int? {
    guard sections.indices.contains(path.section) else { return path.item }
    if sections[path.section].kind == .banner { return nil }
    return path.item
  }

  private func resolveFocusedPath(from context: UICollectionViewFocusUpdateContext) -> IndexPath? {
    if let path = context.nextFocusedIndexPath { return path }
    var node: UIView? = context.nextFocusedView
    while let view = node {
      if view === collectionView { return nil }
      if let cell = view as? UICollectionViewCell,
         let path = collectionView.indexPath(for: cell) {
        return path
      }
      node = view.superview
    }
    return nil
  }

  private func publishBelowTopIfNeeded() {
    let next = isBelowTopRow
    guard next != lastPublishedBelowTop else { return }
    lastPublishedBelowTop = next
    onBelowTopRowChange?(next)
  }
}

// MARK: - Delegate

extension TVPageCollectionViewController: UICollectionViewDelegate {
  public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard let id = dataSource.itemIdentifier(for: indexPath),
          let section = sectionsByID[id.section],
          let item = itemsByID[id] else { return }
    if case .placeholder = item { return }
    onSelect?(section, item)
  }

  public func collectionView(_ collectionView: UICollectionView,
                             willDisplay cell: UICollectionViewCell,
                             forItemAt indexPath: IndexPath) {
    if DebugLaunch.layoutDebug { cell.contentView.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.25) }
    guard sections.indices.contains(indexPath.section) else { return }
    let section = sections[indexPath.section]
    // A chip row or the banner has no pages, and skeleton tiles are not data.
    guard section.kind != .chip, section.kind != .masthead, section.kind != .banner,
          section.kind != .strip, section.kind != .infoCard,
          !section.isPlaceholder else { return }
    let loaded = section.loadedCount
    guard indexPath.item >= loaded - 1 else { return }
    // Once per length: re-displaying the same last card (a snapshot rebuild, a relayout)
    // asks for nothing. The next ask needs the section to have grown, or its end to
    // have gone off screen and come back — see `didEndDisplaying`. Before this, every
    // rebuild of a short section asked for another page: a one-letter filter over the
    // search listing ran it to page 44 in a couple of seconds (2026-09-27).
    guard nearEndReported[section.id] != loaded else { return }
    nearEndReported[section.id] = loaded
    onNearEnd?(section)
  }

  public func collectionView(_ collectionView: UICollectionView,
                             didEndDisplaying cell: UICollectionViewCell,
                             forItemAt indexPath: IndexPath) {
    guard sections.indices.contains(indexPath.section) else { return }
    let section = sections[indexPath.section]
    guard indexPath.item >= section.loadedCount - 1 else { return }
    // The end scrolled away; coming back to it may ask again (a failed page retries).
    nearEndReported[section.id] = nil
  }

  public func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
    // Skeleton tiles are not destinations. The masthead is: Up from the grid reaches
    // person / collection detail. Empty grid keeps its escape on the sort chip. The
    // banner's titles take focus inside its own row, never the row itself.
    guard let id = dataSource.itemIdentifier(for: indexPath), let item = itemsByID[id] else { return false }
    switch item {
    case .placeholder, .banner, .groupTitle: return false
    default: return true
    }
  }

  public func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
    if wantsTopFocus { return topIndexPath }
    if prefersFirstPosterFocus { return firstPosterIndexPath }
    // A banner on top takes the first focus; its row hands it to its middle title
    // (`TVPageBannerCarouselCell.preferredFocusEnvironments`).
    guard let first = sections.first, first.kind == .banner, !first.items.isEmpty else { return nil }
    return IndexPath(item: 0, section: 0)
  }

  public func collectionView(_ collectionView: UICollectionView,
                             didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                             with coordinator: UIFocusAnimationCoordinator) {
    let previousSection = context.previouslyFocusedIndexPath?.section
    let resolved = resolveFocusedPath(from: context)
    focusedPath = resolved
    let nextSection = resolved?.section ?? context.nextFocusedIndexPath?.section
    focusedSectionIndex = nextSection
    if wantsTopFocus, context.nextFocusedView != nil {
      wantsTopFocus = false
      collectionView.remembersLastFocusedIndexPath = remembersFocus
    }
    publishBelowTopIfNeeded()
    if prefersFirstPosterFocus, !didPlacePosterFocus,
       let nextSection,
       sections.indices.contains(nextSection),
       sections[nextSection].kind == .poster,
       !sections[nextSection].isPlaceholder {
      didPlacePosterFocus = true
      collectionView.remembersLastFocusedIndexPath = remembersFocus
    }
    coordinator.addCoordinatedAnimations({ [weak self] in
      guard let self else { return }
      if let previousSection, previousSection != nextSection {
        self.header(at: previousSection)?.transform = .identity
      }
      if let nextSection {
        self.header(at: nextSection)?.transform = self.headerDodge(for: nextSection)
      }
      // A strip's titles are cells, one per group: the group holding focus lifts its own.
      if let previous = context.previouslyFocusedIndexPath, previous.section != resolved?.section {
        self.stripTitleCells(over: previous).forEach { $0.transform = .identity }
      }
      if let resolved {
        let dodge = self.stripTitleDodge(over: resolved)
        self.stripTitleCells(over: resolved).forEach { $0.transform = dodge }
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
  //
  // Stills and vertical posters both focus the *cell* (poster lockup subtree is
  // non-interactive). UIKit then fills `indexPaths`. One menu path: this collection
  // delegate — the cell does not install a second `UIContextMenuInteraction`.
  public func collectionView(_ collectionView: UICollectionView,
                             contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                             point: CGPoint) -> UIContextMenuConfiguration? {
    PosterContextMenuLog.log(
      "collection request indexPaths=\(indexPaths.map { "\($0.section):\($0.item)" }) point=\(Int(point.x)),\(Int(point.y)) focused=\(PosterContextMenuLog.focusedChainDescription(startingFrom: PosterContextMenuLog.focusedView(in: collectionView)))"
    )
    guard let indexPath = TVUIKitContextMenuIndexPath.resolve(
            in: collectionView, indexPaths: indexPaths, point: point) else {
      PosterContextMenuLog.log("collection menu → nil (no indexPath)")
      return nil
    }
    guard let id = dataSource.itemIdentifier(for: indexPath) else {
      PosterContextMenuLog.log("collection menu → nil (no item id at \(indexPath.section):\(indexPath.item))")
      return nil
    }
    guard let card = itemsByID[id]?.card else {
      PosterContextMenuLog.log("collection menu → nil (no card for \(id.item) section=\(id.section))")
      return nil
    }
    let entries = contextMenuProvider?(card) ?? []
    PosterContextMenuLog.log(
      "collection resolved \(indexPath.section):\(indexPath.item) title=\(card.title) id=\(card.id) entries=\(entries.count)"
    )
    guard !entries.isEmpty else {
      PosterContextMenuLog.log("collection menu → nil (empty entries)")
      return nil
    }
    PosterContextMenuLog.log("collection menu → UIContextMenuConfiguration")
    return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { _ in
      TVUIKitContextMenuBuilder.menu(from: entries)
    }
  }

  public func collectionView(
    _ collectionView: UICollectionView,
    willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
    animator: (any UIContextMenuInteractionAnimating)?
  ) {
    let reset: () -> Void = { [weak self] in self?.resetStrandedFocusAppearance() }
    if let animator {
      animator.addCompletion(reset)
    } else {
      reset()
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
    case .feature(let feature):
      return URL(string: feature.card.backdropImageURL)
    case .masthead(let header):
      return header.photoURL
    case .info(.gallery(let gallery)):
      return gallery.images.first
    // The banner warms its own titles' art.
    case .banner, .chip, .tile, .placeholder, .info, .groupTitle:
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

// MARK: - Loading footer

/// Under a grid with more pages coming: the system spinner, centred. The skeleton row
/// above it already says what is loading, so it carries no label.
@MainActor
final class TVPageLoadingFooterView: UICollectionReusableView {
  private let spinner = UIActivityIndicatorView(style: .large)

  override init(frame: CGRect) {
    super.init(frame: frame)
    spinner.translatesAutoresizingMaskIntoConstraints = false
    addSubview(spinner)
    NSLayoutConstraint.activate([
      spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: centerYAnchor)
    ])
    spinner.startAnimating()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func prepareForReuse() {
    super.prepareForReuse()
    spinner.startAnimating()
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
