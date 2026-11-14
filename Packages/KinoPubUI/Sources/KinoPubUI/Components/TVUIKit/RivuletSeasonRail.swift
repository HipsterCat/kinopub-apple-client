#if os(tvOS)
//
//  RivuletSeasonRail.swift
//  KinoPubUI
//
//  The season row Rivulet draws under a show, in place of the numbered tabs and the
//  wide cell. The title logo sits centered above the tabs. Tabs read "Season 2"
//  (the selected one a gray capsule while focus is on an episode). Seasons are split
//  by a hairline "S2".
//
//  Focus is the same two stops as Rivulet's episode card. The still is a `TVCardView`:
//  the row lands on it, and Select plays. The text under it is not a focus target
//  until that still has focus, so Down is the only way onto it, and Select there is
//  the caller's info sheet. While the still is focused the text gets the companion
//  tint; the frosted plate is the text's own focus.
//

import SwiftUI
import TVUIKit
import UIKit

public extension Notification.Name {
  /// Menu on the season block. The detail page scrolls back to the hero.
  static let rivuletSeasonRailRequestsHero = Notification.Name("rivulet.seasonRail.requestsHero")
  /// The page is about to move focus to the hero. Unlock the scroll and drop the
  /// stills out of the focus graph first, or the engine scrolls back to the card.
  static let rivuletSeasonRailPrepareForHero = Notification.Name("rivulet.seasonRail.prepareForHero")
}

public struct RivuletRailTab: Identifiable, Equatable {
  public let id: Int
  /// "Season 2" / "Сезон 2".
  public let label: String
  /// "S2", drawn in the gap before this season's first still.
  public let divider: String

  public init(id: Int, label: String, divider: String) {
    self.id = id
    self.label = label
    self.divider = divider
  }
}

public struct RivuletRailItem: Identifiable, Equatable {
  public let id: Int
  public let tabID: Int
  public let divider: String
  public let stillURL: URL?
  /// kino.pub's own episode thumb when the worker still 404s (year-named seasons,
  /// cold miss). Same idea as `SeasonCardInfo.fallbackPosterURL`.
  public let fallbackStillURL: URL?
  public let duration: String?
  public let eyebrow: String
  public let title: String
  public let year: String?
  public let rating: String?
  /// 0…1 while an episode is in progress. Nil hides the bar.
  public let progress: Double?

  public init(id: Int, tabID: Int, divider: String, stillURL: URL?,
              fallbackStillURL: URL? = nil, duration: String?,
              eyebrow: String, title: String, year: String?, rating: String?, progress: Double?) {
    self.id = id
    self.tabID = tabID
    self.divider = divider
    self.stillURL = stillURL
    self.fallbackStillURL = fallbackStillURL
    self.duration = duration
    self.eyebrow = eyebrow
    self.title = title
    self.year = year
    self.rating = rating
    self.progress = progress
  }
}

@MainActor
public final class RivuletSeasonRailFocus {
  weak var controller: RivuletSeasonRailController?
  public init() {}

  /// Menu closed the episode sheet. Put focus back on that episode's text.
  public func restoreDescription(_ id: Int) {
    controller?.restoreDescriptionFocus(id)
  }

  /// The sheet is opening from this episode's text. Remember it before focus leaves.
  public func armReturn(to id: Int) {
    controller?.armDescriptionReturn(id)
  }
}

public struct RivuletSeasonRail: UIViewControllerRepresentable {
  private let tabs: [RivuletRailTab]
  private let items: [RivuletRailItem]
  private let entryByTab: [Int: Int]
  private let openingItemID: Int?
  private let contentInset: CGFloat
  private let logoURL: URL?
  private let onPlay: (Int) -> Void
  private let onInspect: (Int) -> Void
  private let onTabSelected: ((Int) -> Void)?
  /// 0 at the hero, 1 when this block has settled in the center. Nil when the rail leaves.
  private let onFoldProgress: ((CGFloat?) -> Void)?
  /// The page scroll's content offset. SwiftUI's geometry reader stays at 0 while
  /// this rail drives the scroll, so Menu cannot read the fold from it.
  private let onPageOffset: ((CGFloat) -> Void)?
  private let focus: RivuletSeasonRailFocus?

  public init(tabs: [RivuletRailTab],
              items: [RivuletRailItem],
              entryByTab: [Int: Int],
              openingItemID: Int?,
              contentInset: CGFloat,
              logoURL: URL? = nil,
              onPlay: @escaping (Int) -> Void,
              onInspect: @escaping (Int) -> Void,
              onTabSelected: ((Int) -> Void)? = nil,
              onFoldProgress: ((CGFloat?) -> Void)? = nil,
              onPageOffset: ((CGFloat) -> Void)? = nil,
              focus: RivuletSeasonRailFocus? = nil) {
    self.tabs = tabs
    self.items = items
    self.entryByTab = entryByTab
    self.openingItemID = openingItemID
    self.contentInset = contentInset
    self.logoURL = logoURL
    self.onPlay = onPlay
    self.onInspect = onInspect
    self.onTabSelected = onTabSelected
    self.onFoldProgress = onFoldProgress
    self.onPageOffset = onPageOffset
    self.focus = focus
  }

  public func makeUIViewController(context: Context) -> RivuletSeasonRailController {
    let controller = RivuletSeasonRailController(contentInset: contentInset)
    update(controller)
    return controller
  }

  public func updateUIViewController(_ controller: RivuletSeasonRailController, context: Context) {
    update(controller)
  }

  private func update(_ controller: RivuletSeasonRailController) {
    controller.apply(tabs: tabs, items: items, entryByTab: entryByTab, openingItemID: openingItemID,
                     logoURL: logoURL, onPlay: onPlay, onInspect: onInspect, onTabSelected: onTabSelected,
                     onFoldProgress: onFoldProgress)
    controller.onPageOffset = onPageOffset
    focus?.controller = controller
  }

  public func sizeThatFits(_ proposal: ProposedViewSize,
                           uiViewController: RivuletSeasonRailController,
                           context: Context) -> CGSize? {
    guard let width = proposal.width, width > 1 else { return nil }
    let height = RivuletSeasonRailMetrics.height(containerWidth: width, inset: contentInset,
                                                hasItems: !items.isEmpty, hasLogo: logoURL != nil)
    return CGSize(width: width, height: height)
  }
}

@MainActor
enum RivuletSeasonRailMetrics {
  static let columns: CGFloat = 4
  /// Visible gap between resting thumbnails. The focus envelope is extra and
  /// is not part of this gap.
  static let gutter: CGFloat = 40
  static let dividerWidth: CGFloat = 100
  static let metaHeight: CGFloat = 108
  /// Rivulet's description sits 8pt under the thumbnail.
  static let metaGap: CGFloat = 8
  static let tabsToRail: CGFloat = 16
  /// Rivulet's small title logo: 110pt, centered, no wider than 520, then 20pt to the pills.
  static let logoHeight: CGFloat = 110
  static let logoMaxWidth: CGFloat = 520
  static let logoToTabs: CGFloat = 40
  /// Where the logo sits once the block is focused: clear of the screen edge.
  static let logoTopInset: CGFloat = 80
  /// Air between the episode row and the next section (ratings).
  static let ratingsGap: CGFloat = 80
  static let tabFontSize: CGFloat = 29
  static let tabPadV: CGFloat = 10
  static let tabPadH: CGFloat = 18
  static let tabGap: CGFloat = 6

  static func tabFont(selected: Bool) -> UIFont {
    .systemFont(ofSize: tabFontSize, weight: selected ? .semibold : .medium)
  }

  static func tabRowHeight() -> CGFloat {
    (tabFont(selected: true).lineHeight + tabPadV * 2).rounded(.up)
  }

  /// One episode slot. `art` is the resting thumbnail (`TVCardView`'s platter).
  /// The cell is the focused envelope around it, so an unfocused card is not a
  /// shrunken copy of its frame.
  struct CardSlot {
    var art: CGSize
    var envelope: CGSize
    var artInsets: NSDirectionalEdgeInsets
    var contentSize: CGSize
    var cellHeight: CGFloat
  }

  static func cardSlot(containerWidth: CGFloat, inset: CGFloat) -> CardSlot {
    let content = max(containerWidth - inset * 2, 1)
    let artWidth = ((content - gutter * (columns - 1)) / columns).rounded(.down)
    let artHeight = (artWidth * 9 / 16).rounded(.up)
    let recipe = TVPageCellMetrics.cardRecipe(artWidth: artWidth, height: artHeight)
    let cellHeight = recipe.artInsets.top + artHeight + metaGap + metaHeight
    return CardSlot(art: CGSize(width: artWidth, height: artHeight),
                    envelope: recipe.itemSize,
                    artInsets: recipe.artInsets,
                    contentSize: recipe.posterContentSize,
                    cellHeight: cellHeight)
  }

  static func height(containerWidth: CGFloat, inset: CGFloat, hasItems: Bool, hasLogo: Bool) -> CGFloat {
    let logo = hasLogo ? logoHeight + logoToTabs : 0
    let cards = hasItems ? cardSlot(containerWidth: containerWidth, inset: inset).cellHeight : 0
    return logo + tabRowHeight() + (hasItems ? tabsToRail + cards + ratingsGap : 0)
  }
}

@MainActor
public final class RivuletSeasonRailController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
  private enum Zone { case outside, tabs, rail }
  private enum Slot {
    case divider(String)
    case episode(Int)
  }

  private let contentInset: CGFloat
  private var tabs: [RivuletRailTab] = []
  private var items: [RivuletRailItem] = []
  private var slots: [Slot] = []
  private var entryByTab: [Int: Int] = [:]
  private var openingItemID: Int?
  private var onPlay: ((Int) -> Void)?
  private var onInspect: ((Int) -> Void)?
  private var onTabSelected: ((Int) -> Void)?
  private var onFoldProgress: ((CGFloat?) -> Void)?
  var onPageOffset: ((CGFloat) -> Void)?
  private weak var pageScroll: UIScrollView?
  private var offsetObservation: NSKeyValueObservation?
  private var scrollLink: CADisplayLink?
  private var scrollStartY: CGFloat = 0
  private var scrollTargetY: CGFloat = 0
  private var scrollStartTime: CFTimeInterval = 0
  /// Offset before the focus engine's own scroll. That scroll jumps the model
  /// immediately, so the settle has to start from here or the slide never plays.
  private var settledY: CGFloat = 0
  private var tracksOffset = false
  private var scrollCompletion: (() -> Void)?
  /// The page scroll is ours while focus is in this block, so the focus engine
  /// cannot center the still on its own and drag the logo off the top.
  private var holdsPageScroll = false
  private var pinning = false
  /// Set while Menu should land back on an episode's text. A focus move to the
  /// hero in that window is pulled back here instead of scrolling the page up.
  private var restoringDescriptionID: Int?
  private var selectedTabID: Int?
  private var preferredItemID: Int?
  private var zone: Zone = .outside
  private var hasHadFocus = false
  private var laidOutWidth: CGFloat = 0

  private let tabsGuide = UIFocusGuide()
  private let railGuide = UIFocusGuide()
  private let titleLabel = UILabel()
  private let logoView = UIImageView()
  private var logoHeightConstraint: NSLayoutConstraint?
  private var logoGapConstraint: NSLayoutConstraint?
  private var requestedLogoURL: URL?
  private var loadedLogoURL: URL?
  private var logoToken: UInt64 = 0

  private lazy var tabsView = makeCollection()
  private lazy var railView = makeCollection()

  private var showsTabs: Bool { tabs.count > 1 }

  init(contentInset: CGFloat) {
    self.contentInset = contentInset
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  public override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    view.clipsToBounds = false

    logoView.translatesAutoresizingMaskIntoConstraints = false
    logoView.contentMode = .scaleAspectFit
    logoView.isUserInteractionEnabled = false
    view.addSubview(logoView)

    tabsView.dataSource = self
    tabsView.delegate = self
    tabsView.register(RivuletRailTabCell.self, forCellWithReuseIdentifier: RivuletRailTabCell.reuseID)
    tabsView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(tabsView)

    titleLabel.font = RivuletSeasonRailMetrics.tabFont(selected: false)
    titleLabel.textColor = UIColor.white.withAlphaComponent(0.58)
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(titleLabel)

    railView.dataSource = self
    railView.delegate = self
    railView.register(RivuletRailEpisodeCell.self, forCellWithReuseIdentifier: RivuletRailEpisodeCell.reuseID)
    railView.register(RivuletRailDividerCell.self, forCellWithReuseIdentifier: RivuletRailDividerCell.reuseID)
    railView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(railView)

    view.addLayoutGuide(tabsGuide)
    view.addLayoutGuide(railGuide)
    let tabHeight = tabsView.heightAnchor.constraint(equalToConstant: RivuletSeasonRailMetrics.tabRowHeight())
    let logoHeight = logoView.heightAnchor.constraint(equalToConstant: 0)
    let logoGap = tabsView.topAnchor.constraint(equalTo: logoView.bottomAnchor)
    logoHeightConstraint = logoHeight
    logoGapConstraint = logoGap
    NSLayoutConstraint.activate([
      logoView.topAnchor.constraint(equalTo: view.topAnchor),
      logoView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      logoView.widthAnchor.constraint(lessThanOrEqualToConstant: RivuletSeasonRailMetrics.logoMaxWidth),
      logoHeight,
      logoGap,
      tabsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tabsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tabHeight,
      titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: contentInset),
      titleLabel.centerYAnchor.constraint(equalTo: tabsView.centerYAnchor),
      railView.topAnchor.constraint(equalTo: tabsView.bottomAnchor, constant: RivuletSeasonRailMetrics.tabsToRail),
      railView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      railView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      railView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      tabsGuide.topAnchor.constraint(equalTo: tabsView.topAnchor),
      tabsGuide.bottomAnchor.constraint(equalTo: tabsView.bottomAnchor),
      tabsGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tabsGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      railGuide.topAnchor.constraint(equalTo: railView.topAnchor),
      railGuide.bottomAnchor.constraint(equalTo: railView.bottomAnchor),
      railGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      railGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor)
    ])
    installLayouts()
    updateGuides()
    NotificationCenter.default.addObserver(
      self, selector: #selector(prepareForHero),
      name: .rivuletSeasonRailPrepareForHero, object: nil
    )
    view.sendSubviewToBack(logoView)
    logoView.transform = CGAffineTransform(
      translationX: 0,
      y: RivuletSeasonRailMetrics.logoHeight + RivuletSeasonRailMetrics.logoToTabs
    )
    setLogo(requestedLogoURL)
  }

  public override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    railView.isHidden = false
    attachPageScroll()
  }

  public override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    // Popping the page animates the lifted platter back down. Hide the rail
    // first so that shrink is not on screen. A cover over the page is not a pop.
    guard isMovingFromParent || isBeingDismissed else { return }
    railView.isHidden = true
  }

  @objc private func prepareForHero() {
    zone = .outside
    updateGuides()
    for case let cell as RivuletRailEpisodeCell in railView.visibleCells {
      cell.setStillFocusable(false)
    }
    releaseEpisodePlatter(with: UIFocusAnimationCoordinator())
    releaseHold()
    guard let scroll = pageScroll else { return }
    let y = -scroll.adjustedContentInset.top
    scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: false)
    settledY = y
    tracksOffset = true
  }

  public override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    releasePageScroll()
    onFoldProgress?(nil)
  }

  public override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let width = view.bounds.width
    if width > 1, abs(width - laidOutWidth) > 0.5 {
      laidOutWidth = width
      tabsView.collectionViewLayout.invalidateLayout()
      railView.collectionViewLayout.invalidateLayout()
    }
    paintSelectedTab()
    if !hasHadFocus, let preferredItemID {
      align(to: preferredItemID, animated: false)
    }
  }

  func apply(tabs: [RivuletRailTab], items: [RivuletRailItem], entryByTab: [Int: Int], openingItemID: Int?,
             logoURL: URL?, onPlay: @escaping (Int) -> Void, onInspect: @escaping (Int) -> Void,
             onTabSelected: ((Int) -> Void)?, onFoldProgress: ((CGFloat?) -> Void)?) {
    let tabsChanged = self.tabs != tabs
    let itemsChanged = self.items != items
    let openingMoved = self.openingItemID != openingItemID
    self.tabs = tabs
    self.items = items
    self.entryByTab = entryByTab
    self.openingItemID = openingItemID
    self.onPlay = onPlay
    self.onInspect = onInspect
    self.onTabSelected = onTabSelected
    self.onFoldProgress = onFoldProgress
    slots = Self.slots(for: items)
    setLogo(logoURL)
    titleLabel.text = tabs.count == 1 ? tabs.first?.label : nil
    titleLabel.isHidden = showsTabs
    tabsView.isHidden = !showsTabs
    if tabsChanged {
      tabsView.collectionViewLayout.invalidateLayout()
      tabsView.reloadData()
    }
    if itemsChanged {
      railView.collectionViewLayout.invalidateLayout()
      railView.reloadData()
    }
    if !hasHadFocus, itemsChanged || openingMoved || tabsChanged {
      let opening = openingItemID ?? items.first?.id
      preferredItemID = opening
      selectedTabID = items.first { $0.id == opening }?.tabID ?? tabs.first?.id
      if isViewLoaded, let opening { align(to: opening, animated: false) }
      paintSelectedTab()
    }
  }

  private func setLogo(_ url: URL?) {
    requestedLogoURL = url
    guard isViewLoaded, logoHeightConstraint != nil else { return }
    let show = url != nil
    logoHeightConstraint?.constant = show ? RivuletSeasonRailMetrics.logoHeight : 0
    logoGapConstraint?.constant = show ? RivuletSeasonRailMetrics.logoToTabs : 0
    guard url != loadedLogoURL else { return }
    loadedLogoURL = url
    logoToken &+= 1
    let token = logoToken
    logoView.image = nil
    guard let url else { return }
    Task { [weak self] in
      let image = try? await Artwork.image(for: url)
      guard let self, self.logoToken == token else { return }
      self.logoView.image = image
    }
  }

  // MARK: - Below-fold settle

  /// The page's vertical scroll, not the rail's own horizontal collections.
  private func outermostScrollView() -> UIScrollView? {
    var found: UIScrollView?
    var cursor = view.superview
    while let current = cursor {
      if let scroll = current as? UIScrollView, scroll !== tabsView, scroll !== railView {
        found = scroll
      }
      cursor = current.superview
    }
    return found
  }

  private func attachPageScroll() {
    guard pageScroll == nil, let scroll = outermostScrollView() else { return }
    pageScroll = scroll
    settledY = scroll.contentOffset.y
    tracksOffset = true
    offsetObservation = scroll.observe(\.contentOffset, options: [.initial]) { [weak self] _, _ in
      MainActor.assumeIsolated { self?.foldMoved() }
    }
  }

  private func releasePageScroll() {
    scrollLink?.invalidate()
    scrollLink = nil
    releaseHold()
    offsetObservation = nil
    pageScroll = nil
  }

  private func holdPageScroll() {
    guard let pageScroll, !holdsPageScroll else { return }
    pageScroll.isScrollEnabled = false
    holdsPageScroll = true
  }

  private func releaseHold() {
    guard holdsPageScroll else { return }
    pageScroll?.isScrollEnabled = true
    holdsPageScroll = false
  }

  /// Pin the logo to the screen's top inset. The cards stay under it and the
  /// next section (ratings, related) stays in the bottom of the screen.
  private func centerBlock() {
    guard let scroll = pageScroll, let target = logoPinOffset(in: scroll) else { return }
    scroll.layoutIfNeeded()
    view.layoutIfNeeded()
    let start = tracksOffset ? settledY : scroll.contentOffset.y
    if abs(scroll.contentOffset.y - start) > 1 {
      scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: start), animated: false)
    }
    animatePage(to: target, completion: nil)
  }

  /// Content offset that puts the logo's layout top on the scroll view's top inset.
  /// The logo's parallax transform is ignored: that slides it out from under the tabs.
  private func logoPinOffset(in scroll: UIScrollView) -> CGFloat? {
    let railTop = view.convert(CGPoint.zero, to: scroll).y
    return clampedOffset(railTop - RivuletSeasonRailMetrics.logoTopInset, in: scroll)
  }

  /// Rivulet's hero-to-details slide: quadratic ease-in-out over 0.6s, one
  /// offset per frame, so the blur and the logo ride the same clock.
  private func animatePage(to target: CGFloat, completion: (() -> Void)?) {
    guard let scroll = pageScroll else { completion?(); return }
    let start = scroll.contentOffset.y
    guard abs(target - start) > 1 else {
      completion?()
      return
    }
    scrollLink?.invalidate()
    scrollCompletion = nil
    scrollStartY = start
    scrollTargetY = target
    scrollStartTime = CACurrentMediaTime()
    scrollCompletion = completion
    let link = CADisplayLink(target: self, selector: #selector(stepScroll))
    link.add(to: .main, forMode: .common)
    scrollLink = link
  }

  @objc private func stepScroll(_ link: CADisplayLink) {
    let elapsed = CACurrentMediaTime() - scrollStartTime
    let duration: CFTimeInterval = 0.6
    let t = min(1, elapsed / duration)
    // Quadratic ease-in-out, the same curve as Rivulet's slide into the details.
    let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    let y = scrollStartY + (scrollTargetY - scrollStartY) * eased
    pageScroll?.setContentOffset(CGPoint(x: pageScroll?.contentOffset.x ?? 0, y: y), animated: false)
    settledY = y
    tracksOffset = true
    if t >= 1 {
      link.invalidate()
      scrollLink = nil
      pageScroll?.setContentOffset(CGPoint(x: pageScroll?.contentOffset.x ?? 0, y: scrollTargetY), animated: false)
      settledY = scrollTargetY
      let completion = scrollCompletion
      scrollCompletion = nil
      completion?()
    }
  }

  /// How far the block has risen from the hero toward the center. Drives the
  /// backdrop blur and the logo, which starts tucked under the tabs and rises
  /// out from behind them.
  private func foldMoved() {
    guard let scroll = pageScroll, view.window != nil else { return }
    defer { onPageOffset?(scroll.contentOffset.y) }
    // The focus engine's own scroll only peeks the block. While focus is in
    // the row, put the logo back on its pin.
    if zone == .rail, scrollLink == nil, !pinning, blockIsOffscreen() {
      pinning = true
      holdPageScroll()
      centerBlock()
      pinning = false
      return
    }
    if holdsPageScroll, scroll.isScrollEnabled {
      scroll.isScrollEnabled = false
    }
    let y = scroll.contentOffset.y
    // A downward jump is the focus engine taking the model offset straight to
    // the end. Put it back and play the slide ourselves.
    // Not once focus has gone on to a section under the block: the page's scroll is the
    // engine's again, and replaying each of its jumps as a slide cut every move short —
    // the page stopped at Similar while focus walked on below the screen (2026-11-05).
    if scrollLink == nil, tracksOffset, y > settledY + 30, !focusIsBelowBlock() {
      let target = clampedOffset(y, in: scroll)
      scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: settledY), animated: false)
      animatePage(to: target, completion: nil)
      return
    }
    if scrollLink == nil {
      settledY = y
      tracksOffset = true
    }
    let railTop = view.convert(CGPoint.zero, to: scroll).y
    let settle = railTop - RivuletSeasonRailMetrics.logoTopInset
    let progress = min(1, max(0, settle > 1 ? scroll.contentOffset.y / settle : 0))
    let travel = RivuletSeasonRailMetrics.logoHeight + RivuletSeasonRailMetrics.logoToTabs
    logoView.transform = CGAffineTransform(translationX: 0, y: (1 - progress) * travel)
    onFoldProgress?(progress)
  }

  /// The focused view is a section under this block (ratings, cast, Similar …).
  private func focusIsBelowBlock() -> Bool {
    guard let scroll = pageScroll,
          let focused = UIFocusSystem.focusSystem(for: view)?.focusedItem as? UIView,
          !focused.isDescendant(of: view) else { return false }
    let ours = view.convert(view.bounds, to: scroll)
    return focused.convert(focused.bounds, to: scroll).minY >= ours.maxY - 1
  }

  private func clampedOffset(_ y: CGFloat, in scroll: UIScrollView) -> CGFloat {
    let minY = -scroll.adjustedContentInset.top
    let maxY = max(minY, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
    return min(max(y, minY), maxY)
  }

  /// Focus left downward, while the page scroll was locked. Bring the next
  /// row on screen ourselves; the engine's own scroll was switched off.
  private func revealContent(below next: UIFocusEnvironment?) {
    guard let scroll = pageScroll, let next = next as? UIView, !next.isDescendant(of: view) else {
      releaseHold()
      return
    }
    let nextFrame = next.convert(next.bounds, to: scroll)
    let ours = view.convert(view.bounds, to: scroll)
    guard nextFrame.midY > ours.maxY else {
      releaseHold()
      return
    }
    animatePage(to: clampedOffset(nextFrame.midY - scroll.bounds.height / 2, in: scroll)) { [weak self] in
      self?.releaseHold()
    }
  }

  private static func slots(for items: [RivuletRailItem]) -> [Slot] {
    var slots: [Slot] = []
    var previous: Int?
    for (index, item) in items.enumerated() {
      if let previous, previous != item.tabID {
        slots.append(.divider(item.divider))
      }
      slots.append(.episode(index))
      previous = item.tabID
    }
    return slots
  }

  private func align(to id: Int, animated: Bool) {
    guard let slot = slots.firstIndex(where: {
      if case .episode(let index) = $0 { return items[index].id == id }
      return false
    }) else { return }
    railView.layoutIfNeeded()
    guard let first = railView.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)),
          let target = railView.layoutAttributesForItem(at: IndexPath(item: slot, section: 0)) else { return }
    let maxX = max(railView.contentSize.width - railView.bounds.width, 0)
    let x = min(max(target.frame.minX - first.frame.minX, 0), maxX)
    railView.setContentOffset(CGPoint(x: x, y: railView.contentOffset.y), animated: animated)
  }

  private func paintSelectedTab() {
    guard isViewLoaded, showsTabs, let index = tabs.firstIndex(where: { $0.id == selectedTabID }),
          tabsView.numberOfItems(inSection: 0) > index else { return }
    let path = IndexPath(item: index, section: 0)
    if tabsView.indexPathsForSelectedItems?.first != path {
      tabsView.selectItem(at: path, animated: false, scrollPosition: [])
    }
    for case let cell as RivuletRailTabCell in tabsView.visibleCells {
      cell.setSelectedTab(cell.tabIndex == index)
    }
  }

  private func focusedEpisode(_ id: Int) {
    preferredItemID = id
    guard let tab = items.first(where: { $0.id == id })?.tabID, tab != selectedTabID else { return }
    selectedTabID = tab
    paintSelectedTab()
    onTabSelected?(tab)
  }

  private func focusedTab(at index: Int) {
    guard tabs.indices.contains(index), tabs[index].id != selectedTabID else { return }
    let tab = tabs[index]
    selectedTabID = tab.id
    paintSelectedTab()
    let entry = entryByTab[tab.id] ?? items.first { $0.tabID == tab.id }?.id
    if let entry {
      preferredItemID = entry
      align(to: entry, animated: true)
    }
    onTabSelected?(tab.id)
  }

  private func updateGuides() {
    switch zone {
    case .outside:
      tabsGuide.isEnabled = true
      tabsGuide.preferredFocusEnvironments = [railView]
      railGuide.isEnabled = false
    case .rail:
      tabsGuide.isEnabled = showsTabs
      tabsGuide.preferredFocusEnvironments = [tabsView]
      railGuide.isEnabled = false
    case .tabs:
      tabsGuide.isEnabled = false
      railGuide.isEnabled = true
      railGuide.preferredFocusEnvironments = [railView]
    }
  }

  public override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    let next = context.nextFocusedItem
    let inTabs = Self.contains(next, tabsView)
    let inRail = Self.contains(next, railView)
    // The episode sheet covers the page. Anything else that leaves the block —
    // the hero, the ratings — has to drop the scroll lock and the lifted platter.
    // Leaving the lock on is what made the next Down land on the platter and stop.
    if !inTabs, !inRail, pageIsCovered {
      return
    }
    if !inTabs, !inRail, restoringDescriptionID != nil {
      holdPageScroll()
      centerBlock()
      moveFocusToDescription(restoringDescriptionID!)
      return
    }
    if !inTabs, !inRail, Self.isLiftedCard(next) {
      recoverOffscreenFocus()
      return
    }
    let newZone: Zone = inTabs ? .tabs : (inRail ? .rail : .outside)
    if let restoringDescriptionID, newZone == .rail,
       let nextView = context.nextFocusedView, episodeCell(for: restoringDescriptionID)?.isDescription(nextView) == true {
      self.restoringDescriptionID = nil
    }
    if newZone == zone {
      if newZone == .rail, blockIsOffscreen() {
        holdPageScroll()
        centerBlock()
      }
      if newZone == .outside {
        // prepareForHero turned the stills off and this update does not change
        // zone, so nothing was turning the entry still back on.
        refreshEpisodeFocus()
        DispatchQueue.main.async { [weak self] in
          guard let self, self.zone == .outside else { return }
          self.releaseEpisodePlatter(with: UIFocusAnimationCoordinator())
        }
      }
      return
    }
    if newZone == .outside, let restoringDescriptionID {
      holdPageScroll()
      centerBlock()
      moveFocusToDescription(restoringDescriptionID)
      return
    }
    zone = newZone
    if newZone != .outside { hasHadFocus = true }
    updateGuides()
    refreshEpisodeFocus()
    if newZone == .outside {
      releaseEpisodePlatter(with: coordinator)
      // TVUIKit sets ancestorFocused during this same update, because the hero
      // button's container is an ancestor of the card. Clear it again once that
      // write has landed, or the next Down focuses the lifted platter off screen.
      DispatchQueue.main.async { [weak self] in
        guard let self, self.zone == .outside else { return }
        self.releaseEpisodePlatter(with: UIFocusAnimationCoordinator())
      }
      if context.focusHeading.contains(.up) {
        // Up out of the block is the hero, the top of the page. The engine's own scroll
        // was switched off for this move, so Play took focus 500 pt above the screen
        // (2026-11-05). Slide back the way Menu does.
        releaseHold()
        if let scroll = pageScroll {
          animatePage(to: clampedOffset(-scroll.adjustedContentInset.top, in: scroll), completion: nil)
        }
      } else {
        revealContent(below: context.nextFocusedView)
      }
    } else {
      holdPageScroll()
      centerBlock()
    }
  }

  /// The logo's layout top, in the viewport. Content position does not change
  /// as the page scrolls; the offset does.
  private func blockIsOffscreen() -> Bool {
    guard let scroll = pageScroll else { return false }
    let visibleTop = view.convert(CGPoint.zero, to: scroll).y - scroll.contentOffset.y
    return visibleTop > RivuletSeasonRailMetrics.logoTopInset + 24
      || visibleTop + view.bounds.height < 0
  }

  private static func contains(_ item: UIFocusEnvironment?, _ container: UIView) -> Bool {
    var current = item
    while let environment = current {
      if let view = environment as? UIView { return view.isDescendant(of: container) }
      current = environment.parentFocusEnvironment
    }
    return false
  }

  /// TVUIKit draws the focused card as a material platter that can leave the
  /// scroll view. That platter is the off-screen square Down lands on.
  private static func isLiftedCard(_ item: UIFocusEnvironment?) -> Bool {
    guard let view = item as? UIView else { return false }
    var current: UIView? = view
    while let view = current {
      if view is TVCardView { return true }
      let name = String(describing: type(of: view))
      if name.contains("FloatingContent") || name.contains("TVCard") { return true }
      current = view.superview
    }
    return false
  }

  /// Menu while the block is on screen scrolls back to the hero. The press is
  /// eaten here: a UIKit card never delivers it to the page's `onExitCommand`,
  /// so the navigation controller would pop instead.
  private var consumedMenuPress = false

  @discardableResult
  private func scrollHomeOnMenu() -> Bool {
    guard let scroll = pageScroll else { return false }
    let minY = -scroll.adjustedContentInset.top
    if scroll.contentOffset.y <= minY + 40 { return false }
    zone = .outside
    hasHadFocus = true
    updateGuides()
    refreshEpisodeFocus()
    releaseEpisodePlatter(with: UIFocusAnimationCoordinator())
    releaseHold()
    // The hero button is SwiftUI. Asking UIKit to focus it is refused, so the
    // page moves its own focus and scrolls. The press stays eaten either way.
    NotificationCenter.default.post(name: .rivuletSeasonRailRequestsHero, object: nil)
    return true
  }

  public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if presses.contains(where: { $0.type == .menu }), scrollHomeOnMenu() {
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

  /// A presented cover (the episode sheet) is the only focus that may leave the
  /// page without the block following it.
  private var pageIsCovered: Bool {
    sequence(first: parent, next: { $0?.parent }).contains { $0?.presentedViewController != nil }
  }

  /// Down landed on the card platter that TVUIKit lifted out of the scroll.
  /// Bring the block back and put focus on the episode still itself.
  private func recoverOffscreenFocus() {
    zone = .rail
    hasHadFocus = true
    updateGuides()
    refreshEpisodeFocus()
    holdPageScroll()
    guard let scroll = pageScroll, let target = logoPinOffset(in: scroll) else { return }
    animatePage(to: target) { [weak self] in
      self?.focusEntryStill()
    }
  }

  private func focusEntryStill() {
    let id = preferredItemID ?? items.first?.id
    guard let id, let cell = episodeCell(for: id) else { return }
    cell.prepareStillFocus()
    UIFocusSystem.focusSystem(for: view)?.requestFocusUpdate(to: cell.stillFocusTarget)
    view.window?.updateFocusIfNeeded()
  }

  private func releaseEpisodePlatter(with coordinator: UIFocusAnimationCoordinator) {
    for case let cell as RivuletRailEpisodeCell in railView.visibleCells {
      cell.releaseStill(with: coordinator)
    }
  }

  func armDescriptionReturn(_ id: Int) {
    restoringDescriptionID = id
  }

  /// Menu dismissed the episode sheet. Focus the text that opened it, and keep
  /// the block where it was instead of letting the hero scroll the page up.
  public func restoreDescriptionFocus(_ id: Int) {
    restoringDescriptionID = id
    preferredItemID = id
    holdPageScroll()
    align(to: id, animated: false)
    railView.layoutIfNeeded()
    episodeCell(for: id)?.prepareDescriptionFocus()
    centerBlock()
    moveFocusToDescription(id)
  }

  private func moveFocusToDescription(_ id: Int) {
    guard let cell = episodeCell(for: id) else { return }
    cell.prepareDescriptionFocus()
    UIFocusSystem.focusSystem(for: view)?.requestFocusUpdate(to: cell.descriptionFocusTarget)
    view.window?.updateFocusIfNeeded()
  }

  private func episodeCell(for id: Int) -> RivuletRailEpisodeCell? {
    for case let cell as RivuletRailEpisodeCell in railView.visibleCells where cell.itemID == id {
      return cell
    }
    return nil
  }

  private func refreshEpisodeFocus() {
    for case let cell as RivuletRailEpisodeCell in railView.visibleCells {
      let isEntry = preferredItemID == nil || cell.itemID == preferredItemID
      cell.setStillFocusable(zone == .rail || isEntry)
    }
  }

  private func makeCollection() -> UICollectionView {
    let flow = UICollectionViewFlowLayout()
    flow.scrollDirection = .horizontal
    let view = UICollectionView(frame: .zero, collectionViewLayout: flow)
    view.backgroundColor = .clear
    view.clipsToBounds = false
    view.contentInsetAdjustmentBehavior = .never
    view.remembersLastFocusedIndexPath = false
    view.showsHorizontalScrollIndicator = false
    return view
  }

  private func installLayouts() {
    tabsView.collectionViewLayout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] _, _ in
      self?.tabSection()
    }, configuration: horizontalConfiguration())
    railView.collectionViewLayout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] _, _ in
      self?.railSection()
    }, configuration: horizontalConfiguration())
  }

  private func horizontalConfiguration() -> UICollectionViewCompositionalLayoutConfiguration {
    let configuration = UICollectionViewCompositionalLayoutConfiguration()
    configuration.scrollDirection = .horizontal
    configuration.contentInsetsReference = .none
    return configuration
  }

  private func tabSection() -> NSCollectionLayoutSection {
    let font = RivuletSeasonRailMetrics.tabFont(selected: true)
    let height = RivuletSeasonRailMetrics.tabRowHeight()
    let pad = RivuletSeasonRailMetrics.tabPadH
    var frames: [CGRect] = []
    var x: CGFloat = 0
    for tab in tabs {
      let text = (tab.label as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
      let width = text + pad * 2
      frames.append(CGRect(x: x, y: 0, width: width, height: height))
      x += width + RivuletSeasonRailMetrics.tabGap
    }
    let total = max(x - RivuletSeasonRailMetrics.tabGap, 1)
    let group = NSCollectionLayoutGroup.custom(
      layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(total), heightDimension: .absolute(height))
    ) { _ in frames.map { NSCollectionLayoutGroupCustomItem(frame: $0) } }
    let section = NSCollectionLayoutSection(group: group)
    let leading = max(contentInset - pad, 0)
    section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: leading, bottom: 0, trailing: leading)
    return section
  }

  private func railSection() -> NSCollectionLayoutSection {
    let slot = RivuletSeasonRailMetrics.cardSlot(containerWidth: max(view.bounds.width, 1), inset: contentInset)
    var frames: [CGRect] = []
    var artX: CGFloat = 0
    for item in slots {
      switch item {
      case .divider:
        frames.append(CGRect(x: artX, y: 0, width: RivuletSeasonRailMetrics.dividerWidth, height: slot.cellHeight))
        artX += RivuletSeasonRailMetrics.dividerWidth + RivuletSeasonRailMetrics.gutter
      case .episode:
        frames.append(CGRect(x: artX - slot.artInsets.leading, y: 0,
                             width: slot.envelope.width, height: slot.cellHeight))
        artX += slot.art.width + RivuletSeasonRailMetrics.gutter
      }
    }
    let total = max(artX - RivuletSeasonRailMetrics.gutter, 1)
    let group = NSCollectionLayoutGroup.custom(
      layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(total), heightDimension: .absolute(slot.cellHeight))
    ) { _ in frames.map { NSCollectionLayoutGroupCustomItem(frame: $0) } }
    let section = NSCollectionLayoutSection(group: group)
    section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: contentInset, bottom: 0, trailing: contentInset)
    return section
  }

  public func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

  public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    collectionView === tabsView ? (showsTabs ? tabs.count : 0) : slots.count
  }

  public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    if collectionView === tabsView {
      let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RivuletRailTabCell.reuseID, for: indexPath) as! RivuletRailTabCell
      cell.configure(tabs[indexPath.item], index: indexPath.item, selected: tabs[indexPath.item].id == selectedTabID)
      cell.onMenu = { [weak self] in self?.scrollHomeOnMenu() ?? false }
      return cell
    }
    switch slots[indexPath.item] {
    case .divider(let label):
      let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RivuletRailDividerCell.reuseID, for: indexPath) as! RivuletRailDividerCell
      let slot = RivuletSeasonRailMetrics.cardSlot(containerWidth: max(view.bounds.width, 1), inset: contentInset)
      cell.configure(label: label, artTop: slot.artInsets.top, artHeight: slot.art.height)
      return cell
    case .episode(let index):
      let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RivuletRailEpisodeCell.reuseID, for: indexPath) as! RivuletRailEpisodeCell
      let item = items[index]
      let slot = RivuletSeasonRailMetrics.cardSlot(containerWidth: max(view.bounds.width, 1), inset: contentInset)
      cell.apply(slot: slot)
      cell.configure(item)
      let isEntry = preferredItemID == nil || item.id == preferredItemID
      cell.setStillFocusable(zone == .rail || isEntry)
      cell.stillAccessibilityIdentifier = "kinopub.rivulet.still.\(item.id)"
      cell.onPlay = { [weak self] in self?.onPlay?(item.id) }
      cell.onInspect = { [weak self] in self?.onInspect?(item.id) }
      cell.onMenu = { [weak self] in self?.scrollHomeOnMenu() ?? false }
      cell.onFocused = { [weak self] in self?.focusedEpisode(item.id) }
      return cell
    }
  }

  public func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
    if collectionView === tabsView {
      guard showsTabs else { return false }
      switch zone {
      case .tabs: return true
      case .rail: return tabs[indexPath.item].id == selectedTabID
      case .outside: return false
      }
    }
    // The still and the text are the focus targets. The cell itself is not.
    return false
  }

  public func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
    if collectionView === tabsView {
      return tabs.firstIndex { $0.id == selectedTabID }.map { IndexPath(item: $0, section: 0) }
    }
    let id = preferredItemID
    let slot = slots.firstIndex {
      if case .episode(let index) = $0 { return items[index].id == id }
      return false
    }
    return slot.map { IndexPath(item: $0, section: 0) }
  }

  public func collectionView(_ collectionView: UICollectionView,
                             didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                             with coordinator: UIFocusAnimationCoordinator) {
    guard collectionView === tabsView, let path = context.nextFocusedIndexPath, tabs.indices.contains(path.item) else { return }
    focusedTab(at: path.item)
  }
}

final class RivuletRailTabCell: UICollectionViewCell {
  static let reuseID = "RivuletRailTabCell"
  private let label = UILabel()
  private var selectedTab = false
  private(set) var tabIndex = 0
  var onMenu: (() -> Bool)?
  private var consumedMenu = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.layer.cornerCurve = .continuous
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .center
    contentView.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: RivuletSeasonRailMetrics.tabPadH),
      label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -RivuletSeasonRailMetrics.tabPadH),
      label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ tab: RivuletRailTab, index: Int, selected: Bool) {
    tabIndex = index
    label.text = tab.label
    accessibilityLabel = tab.label
    setSelectedTab(selected)
  }

  func setSelectedTab(_ selected: Bool) {
    selectedTab = selected
    apply(focused: isFocused)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    contentView.layer.cornerRadius = bounds.height / 2
  }

  override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    let on = context.nextFocusedView === self
    coordinator.addCoordinatedAnimations { [weak self] in self?.apply(focused: on) }
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if presses.contains(where: { $0.type == .menu }), onMenu?() == true {
      consumedMenu = true
      return
    }
    super.pressesBegan(presses, with: event)
  }

  override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if consumedMenu, presses.contains(where: { $0.type == .menu }) {
      consumedMenu = false
      return
    }
    super.pressesEnded(presses, with: event)
  }

  override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if consumedMenu, presses.contains(where: { $0.type == .menu }) {
      consumedMenu = false
      return
    }
    super.pressesCancelled(presses, with: event)
  }

  private func apply(focused: Bool) {
    label.font = RivuletSeasonRailMetrics.tabFont(selected: focused || selectedTab)
    if focused {
      contentView.backgroundColor = UIColor.white.withAlphaComponent(0.92)
      label.textColor = .black
    } else if selectedTab {
      contentView.backgroundColor = UIColor(white: 0.62, alpha: 0.92)
      label.textColor = UIColor(white: 0.12, alpha: 1)
    } else {
      contentView.backgroundColor = .clear
      label.textColor = UIColor.white.withAlphaComponent(0.58)
    }
  }
}

final class RivuletRailDividerCell: UICollectionViewCell {
  static let reuseID = "RivuletRailDividerCell"
  private let topLine = UIView()
  private let bottomLine = UIView()
  private let chip = UILabel()
  private var artTop: CGFloat = 0
  private var artHeight: CGFloat = 200

  override var canBecomeFocused: Bool { false }

  override init(frame: CGRect) {
    super.init(frame: frame)
    for line in [topLine, bottomLine] {
      line.backgroundColor = UIColor.white.withAlphaComponent(0.28)
      contentView.addSubview(line)
    }
    chip.font = .systemFont(ofSize: 22, weight: .semibold)
    chip.textColor = UIColor.white.withAlphaComponent(0.55)
    chip.textAlignment = .center
    contentView.addSubview(chip)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(label: String, artTop: CGFloat, artHeight: CGFloat) {
    chip.text = label
    self.artTop = artTop
    self.artHeight = artHeight
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let mid = artTop + artHeight / 2
    chip.sizeToFit()
    chip.center = CGPoint(x: bounds.midX, y: mid)
    let lineW: CGFloat = 2
    topLine.frame = CGRect(x: bounds.midX - lineW / 2, y: artTop + 8, width: lineW,
                           height: max(chip.frame.minY - 12 - (artTop + 8), 0))
    let bottomY = chip.frame.maxY + 12
    bottomLine.frame = CGRect(x: bounds.midX - lineW / 2, y: bottomY, width: lineW,
                              height: max(artTop + artHeight - 8 - bottomY, 0))
  }
}

final class RivuletRailEpisodeCell: UICollectionViewCell {
  static let reuseID = "RivuletRailEpisodeCell"
  private(set) var itemID: Int?
  var onPlay: (() -> Void)?
  var onInspect: (() -> Void)?
  var onFocused: (() -> Void)?
  var onMenu: (() -> Bool)? {
    didSet {
      still.onMenu = onMenu
      meta.onMenu = onMenu
    }
  }

  private let still = RivuletRailThumbCard()
  private let meta = RivuletRailMeta()
  private var loadToken: UInt64 = 0
  private var thumbFocused = false
  private var textFocused = false
  private var slot: RivuletSeasonRailMetrics.CardSlot?

  override var canBecomeFocused: Bool { false }
  override var preferredFocusEnvironments: [any UIFocusEnvironment] { [still] }

  func prepareStillFocus() {
    still.isFocusable = true
  }

  var stillFocusTarget: UIFocusEnvironment { still }

  var stillAccessibilityIdentifier: String? {
    get { still.accessibilityIdentifier }
    set {
      still.isAccessibilityElement = true
      still.accessibilityIdentifier = newValue
    }
  }

  func releaseStill(with coordinator: UIFocusAnimationCoordinator) {
    still.releaseFocusedLook(with: coordinator)
  }

  func prepareDescriptionFocus() {
    meta.isFocusEligible = true
  }

  var descriptionFocusTarget: UIFocusEnvironment { meta }

  func isDescription(_ view: UIView) -> Bool {
    view === meta || view.isDescendant(of: meta)
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.clipsToBounds = false
    contentView.addSubview(still)
    contentView.addSubview(meta)
    still.onSelect = { [weak self] in self?.onPlay?() }
    meta.onSelect = { [weak self] in self?.onInspect?() }
    still.onFocusChange = { [weak self] focused, next, coordinator in
      guard let self else { return }
      self.thumbFocused = focused
      self.applyReachability(next: next)
      self.updateTextPlate(coordinator)
      if focused { self.onFocused?() }
    }
    meta.onFocusChange = { [weak self] focused, next, coordinator in
      guard let self else { return }
      self.textFocused = focused
      self.applyReachability(next: next)
      self.updateTextPlate(coordinator)
      if focused { self.onFocused?() }
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func setStillFocusable(_ on: Bool) {
    still.isFocusable = on
    // The platter's internal floating view stays focusable after the first
    // visit unless the whole card stops accepting interaction.
    still.isUserInteractionEnabled = on
  }

  /// The text is a target only while this card is the active one. Coming into the
  /// row, or moving sideways, can land only on the still, so Select plays.
  private func applyReachability(next: UIView?) {
    let stayingInside = next?.isDescendant(of: self) ?? false
    meta.isFocusEligible = thumbFocused || textFocused || stayingInside
  }

  private func updateTextPlate(_ coordinator: UIFocusAnimationCoordinator?) {
    let apply = { [self] in
      if textFocused {
        meta.plate.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        meta.plate.effect = Self.frostedPlate()
      } else if thumbFocused {
        meta.plate.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        meta.plate.effect = nil
      } else {
        meta.plate.backgroundColor = .clear
        meta.plate.effect = nil
      }
    }
    if let coordinator {
      coordinator.addCoordinatedAnimations(apply, completion: nil)
    } else {
      apply()
    }
  }

  private static func frostedPlate() -> UIVisualEffect {
    if #available(tvOS 26.0, *) { return UIGlassEffect() }
    return UIBlurEffect(style: .regular)
  }

  func apply(slot: RivuletSeasonRailMetrics.CardSlot) {
    self.slot = slot
    guard still.contentSize != slot.contentSize else { return }
    UIView.performWithoutAnimation {
      still.contentSize = slot.contentSize
      still.layoutIfNeeded()
    }
    setNeedsLayout()
  }

  func configure(_ item: RivuletRailItem) {
    itemID = item.id
    meta.apply(eyebrow: item.eyebrow, title: item.title, year: item.year, rating: item.rating)
    still.apply(duration: item.duration, progress: item.progress)
    loadToken &+= 1
    let token = loadToken
    still.image = nil
    let urls = [item.stillURL, item.fallbackStillURL].compactMap { $0 }
    guard !urls.isEmpty else { return }
    Task { [weak self] in
      var image: UIImage?
      for url in urls {
        image = try? await Artwork.image(for: url)
        if image != nil { break }
      }
      guard let self, self.loadToken == token else { return }
      self.still.image = image
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let slot = slot ?? RivuletSeasonRailMetrics.cardSlot(containerWidth: 1920, inset: contentInsetGuess)
    still.frame = CGRect(origin: .zero, size: slot.envelope)
    if still.contentSize != slot.contentSize {
      UIView.performWithoutAnimation {
        still.contentSize = slot.contentSize
      }
    }
    // The title sits 8pt under the resting thumbnail, where the duration is,
    // not under the focus envelope. That envelope is empty until the card grows.
    let metaY = slot.artInsets.top + slot.art.height + RivuletSeasonRailMetrics.metaGap
    meta.frame = CGRect(x: slot.artInsets.leading, y: metaY,
                        width: slot.art.width, height: max(bounds.height - metaY, 0))
  }

  /// Used only before the rail has handed the measured slot over.
  private var contentInsetGuess: CGFloat { 80 }

  override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    if let next = context.nextFocusedView, still.isDescendant(of: next) {
      still.releaseFocusedLook(with: coordinator)
    }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    loadToken &+= 1
    itemID = nil
    still.image = nil
    thumbFocused = false
    textFocused = false
    meta.isFocusEligible = false
    meta.plate.backgroundColor = .clear
    meta.plate.effect = nil
    onPlay = nil
    onInspect = nil
    onFocused = nil
  }
}

private final class RivuletRailThumbCard: TVCardView {
  var onSelect: (() -> Void)?
  var onMenu: (() -> Bool)?
  var onFocusChange: ((Bool, UIView?, UIFocusAnimationCoordinator) -> Void)?
  private var consumedMenu = false
  var image: UIImage? {
    get { imageView.image }
    set { imageView.image = newValue }
  }

  private let imageView = UIImageView()
  private let play = UIImageView()
  private let duration = UILabel()
  private let track = UIView()
  private let fill = UIView()
  private var fraction: CGFloat = 0
  var isFocusable = true

  override var canBecomeFocused: Bool { isFocusable }

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.backgroundColor = UIColor(white: 0.15, alpha: 1)
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    contentView.addSubview(imageView)
    play.image = UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .medium))
    play.tintColor = .white
    contentView.addSubview(play)
    duration.font = .systemFont(ofSize: 17, weight: .semibold)
    duration.textColor = .white
    contentView.addSubview(duration)
    track.backgroundColor = UIColor.black.withAlphaComponent(0.5)
    track.isHidden = true
    contentView.addSubview(track)
    fill.backgroundColor = UIColor.white.withAlphaComponent(0.9)
    track.addSubview(fill)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(duration text: String?, progress: Double?) {
    duration.text = text
    let showsTime = text?.isEmpty == false
    duration.isHidden = !showsTime
    play.isHidden = !showsTime
    if let progress, progress > 0, progress < 1 {
      fraction = CGFloat(progress)
      track.isHidden = false
    } else {
      fraction = 0
      track.isHidden = true
    }
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let box = contentView.bounds
    imageView.frame = box
    play.frame = CGRect(x: 12, y: box.height - 10 - 12, width: 12, height: 12)
    duration.sizeToFit()
    duration.frame = CGRect(x: play.frame.maxX + 4, y: play.frame.midY - duration.bounds.height / 2,
                            width: duration.bounds.width, height: duration.bounds.height)
    track.frame = CGRect(x: 0, y: box.height - 3, width: box.width, height: 3)
    fill.frame = CGRect(x: 0, y: 0, width: box.width * fraction, height: 3)
  }

  override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    onFocusChange?(context.nextFocusedView === self, context.nextFocusedView, coordinator)
  }

  // TVCardView cancels Select between began and ended. Play on began.
  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if presses.contains(where: { $0.type == .menu }), onMenu?() == true {
      consumedMenu = true
      return
    }
    if presses.contains(where: { $0.type == .select }) { onSelect?(); return }
    super.pressesBegan(presses, with: event)
  }

  override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if consumedMenu, presses.contains(where: { $0.type == .menu }) {
      consumedMenu = false
      return
    }
    if presses.contains(where: { $0.type == .select }) { return }
    super.pressesEnded(presses, with: event)
  }

  override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if consumedMenu, presses.contains(where: { $0.type == .menu }) {
      consumedMenu = false
      return
    }
    super.pressesCancelled(presses, with: event)
  }
}

private final class RivuletRailMeta: UIView {
  var onSelect: (() -> Void)?
  var onMenu: (() -> Bool)?
  var onFocusChange: ((Bool, UIView?, UIFocusAnimationCoordinator) -> Void)?
  let plate = UIVisualEffectView(effect: nil)
  private var consumedMenu = false

  private let eyebrow = UILabel()
  private let titleLabel = UILabel()
  private let yearLabel = UILabel()
  private let ratingLabel = UILabel()
  var isFocusEligible = false

  override var canBecomeFocused: Bool { isFocusEligible }

  override init(frame: CGRect) {
    super.init(frame: frame)
    plate.isUserInteractionEnabled = false
    plate.clipsToBounds = true
    plate.layer.cornerRadius = 16
    plate.layer.cornerCurve = .continuous
    addSubview(plate)
    eyebrow.numberOfLines = 1
    addSubview(eyebrow)
    titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
    titleLabel.textColor = .white
    titleLabel.numberOfLines = 1
    addSubview(titleLabel)
    yearLabel.font = .systemFont(ofSize: 18, weight: .medium)
    yearLabel.textColor = UIColor.white.withAlphaComponent(0.78)
    addSubview(yearLabel)
    ratingLabel.font = .systemFont(ofSize: 13, weight: .bold)
    ratingLabel.textColor = UIColor.white.withAlphaComponent(0.86)
    ratingLabel.textAlignment = .center
    ratingLabel.layer.cornerRadius = 3
    ratingLabel.layer.borderWidth = 1
    ratingLabel.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
    addSubview(ratingLabel)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(eyebrow text: String, title: String, year: String?, rating: String?) {
    eyebrow.attributedText = NSAttributedString(string: text, attributes: [
      .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
      .foregroundColor: UIColor.white.withAlphaComponent(0.55),
      .kern: 0.8
    ])
    titleLabel.text = title
    yearLabel.text = year
    yearLabel.isHidden = year == nil
    ratingLabel.text = rating.map { " \($0) " }
    ratingLabel.isHidden = rating == nil
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    plate.frame = bounds
    let inset: CGFloat = 14
    let width = bounds.width - inset * 2
    eyebrow.frame = CGRect(x: inset, y: 10, width: width, height: 20)
    titleLabel.frame = CGRect(x: inset, y: eyebrow.frame.maxY + 2, width: width, height: 26)
    yearLabel.sizeToFit()
    yearLabel.frame = CGRect(x: inset, y: titleLabel.frame.maxY + 4, width: yearLabel.bounds.width, height: 22)
    ratingLabel.sizeToFit()
    let ratingX = yearLabel.isHidden ? inset : yearLabel.frame.maxX + 8
    ratingLabel.frame = CGRect(x: ratingX, y: yearLabel.frame.midY - 11, width: ratingLabel.bounds.width + 8, height: 22)
  }

  override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    onFocusChange?(context.nextFocusedView === self, context.nextFocusedView, coordinator)
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if presses.contains(where: { $0.type == .menu }), onMenu?() == true {
      consumedMenu = true
      return
    }
    if presses.contains(where: { $0.type == .select }) { return }
    super.pressesBegan(presses, with: event)
  }

  override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if consumedMenu, presses.contains(where: { $0.type == .menu }) {
      consumedMenu = false
      return
    }
    if presses.contains(where: { $0.type == .select }) { onSelect?(); return }
    super.pressesEnded(presses, with: event)
  }

  override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if consumedMenu, presses.contains(where: { $0.type == .menu }) {
      consumedMenu = false
      return
    }
    super.pressesCancelled(presses, with: event)
  }
}
#endif
