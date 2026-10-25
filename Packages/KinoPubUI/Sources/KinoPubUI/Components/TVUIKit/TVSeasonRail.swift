#if os(tvOS)
//
//  TVSeasonRail.swift
//  KinoPubUI
//
//  A series' season tabs over one rail of every episode, as one UIKit controller, so
//  where the remote lands is decided by the engine's own hooks rather than by SwiftUI
//  focus state chasing it:
//
//  * **Down from the hero** passes the tabs and lands on the episode the hero's main
//    button stands for (`openingItemID`), whose art the rail has already parked on the
//    page margin — on opening. After that the rail stays where the remote left it, and
//    Down from the hero is the episode you left (Sasha, 2026-10-11).
//  * **Up from an episode** lands on the selected tab — never a neighbour that happens to
//    be nearer — and the rail does not move.
//  * **Left / Right on the tabs** selects as it goes, and the rail goes to that tab's
//    entry (`entryByTab`: the season's resume episode, or its first).
//  * **Down from the tabs** comes back to the episode you left, or to the new tab's entry.
//  * **Up from the tabs** leaves for the hero, whose action row takes it to its main
//    button (`defaultFocus` there).
//
//  The seasons that are not the selected one stand back (`otherSeasonAlpha`): the one
//  you are in is the bright run on a rail with no gaps between seasons.
//
//  The tabs are the system's list cell in a row, like the Library's sidebar rows: focus,
//  selection and their colours are the cell's own, not a button style of ours. One tab is
//  not a choice, so a single season is the title alone («Сезон 1»), with nothing focusable.
//
//  How: a focus guide over the tab row and one over the rail redirect a move into this
//  controller to the collection view that should take it, whose
//  `indexPathForPreferredFocusedView` names the item; `canFocusItemAt` keeps the remote
//  off the items it must not land on (every tab while focus is outside, every episode but
//  the entry while it is on the tabs).
//

import SwiftUI
import UIKit

/// One stop on the tab row: a season, or a run of seasons standing in one place.
public struct TVSeasonTab: Identifiable, Equatable {
  public let id: Int
  /// «4», or «4–7» for a run.
  public let label: String
  /// A glyph after the label — a clock for an announced season, a lock for one kino.pub lacks.
  public let symbol: String?
  /// False for a season with nothing to watch: its label is secondary at rest.
  public let isAvailable: Bool
  public let accessibilityLabel: String

  public init(id: Int, label: String, symbol: String?, isAvailable: Bool, accessibilityLabel: String) {
    self.id = id
    self.label = label
    self.symbol = symbol
    self.isAvailable = isAvailable
    self.accessibilityLabel = accessibilityLabel
  }
}

public struct TVSeasonRail: UIViewControllerRepresentable {
  private let title: String
  private let tabs: [TVSeasonTab]
  private let items: [TVUIKitMediaItem]
  private let tabOfItem: [Int: Int]
  private let entryByTab: [Int: Int]
  private let openingItemID: Int?
  private let contentInset: CGFloat
  private let columns: Int
  private let onSelect: (Int) -> Void
  private let onTabSelected: ((Int) -> Void)?
  private let contextMenuProvider: ((Int) -> [MediaCardContextEntry])?

  /// - Parameters:
  ///   - title: the word before the tabs («Сезон»), or the whole line for one season.
  ///   - tabs: more than one draws the row; one or none draws `title` alone.
  ///   - items: every episode of every tab, in order, and the trailing cards.
  ///   - tabOfItem: item id → the tab it sits under. Items of the tabs that are not
  ///     selected stand back.
  ///   - entryByTab: tab id → the item the rail goes to when that tab is picked.
  ///   - openingItemID: where the rail sits and focus lands coming down from the hero,
  ///     until the remote has been in the rail.
  ///   - onTabSelected: a tab became the selected one, by the remote or by an episode.
  public init(title: String,
              tabs: [TVSeasonTab],
              items: [TVUIKitMediaItem],
              tabOfItem: [Int: Int],
              entryByTab: [Int: Int],
              openingItemID: Int?,
              contentInset: CGFloat,
              columns: Int,
              onSelect: @escaping (Int) -> Void,
              onTabSelected: ((Int) -> Void)? = nil,
              contextMenuProvider: ((Int) -> [MediaCardContextEntry])? = nil) {
    self.title = title
    self.tabs = tabs
    self.items = items
    self.tabOfItem = tabOfItem
    self.entryByTab = entryByTab
    self.openingItemID = openingItemID
    self.contentInset = contentInset
    self.columns = columns
    self.onSelect = onSelect
    self.onTabSelected = onTabSelected
    self.contextMenuProvider = contextMenuProvider
  }

  public func makeUIViewController(context: Context) -> TVSeasonRailController {
    let controller = TVSeasonRailController(contentInset: contentInset, columns: columns)
    update(controller)
    return controller
  }

  public func updateUIViewController(_ controller: TVSeasonRailController, context: Context) {
    update(controller)
  }

  private func update(_ controller: TVSeasonRailController) {
    controller.apply(title: title,
                     tabs: tabs,
                     items: items,
                     tabOfItem: tabOfItem,
                     entryByTab: entryByTab,
                     openingItemID: openingItemID,
                     onSelect: onSelect,
                     onTabSelected: onTabSelected,
                     contextMenuProvider: contextMenuProvider)
  }

  public func sizeThatFits(_ proposal: ProposedViewSize,
                           uiViewController: TVSeasonRailController,
                           context: Context) -> CGSize? {
    guard let width = proposal.width, width > 1 else { return nil }
    let rail = items.isEmpty ? 0 : TVPageLayout.stillRailHeight(columns: columns, caption: .always,
                                                                containerWidth: width,
                                                                sideInset: contentInset)
    return CGSize(width: width,
                  height: TVSeasonRailController.tabRowHeight() + TVSeasonRailController.tabsToRail + rail)
  }
}

// MARK: - Controller

@MainActor
public final class TVSeasonRailController: UIViewController {

  /// The tiles of the seasons that are not the selected one (Sasha, 2026-10-11).
  static let otherSeasonAlpha: CGFloat = 0.8

  /// Between the tab row and the rail. The rail's own top inset (room for the focus lift)
  /// adds 9; together they are the 22 pt Sasha asked for (2026-10-11).
  public static let tabsToRail: CGFloat = 16
  /// Headline text plus this above and below is a tab's height — and the row's.
  static let tabVerticalPadding: CGFloat = 10
  /// Each side of a tab's text. A tab is never narrower than tall, so one digit is a circle.
  static let tabHorizontalPadding: CGFloat = 20
  /// Between the title and the first tab (Sasha, 2026-10-11).
  static let titleGap: CGFloat = 20

  static func tabFont(compatibleWith traits: UITraitCollection? = nil) -> UIFont {
    let base = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traits)
    return UIFont.systemFont(ofSize: base.pointSize, weight: .semibold)
  }

  public static func tabRowHeight(compatibleWith traits: UITraitCollection? = nil) -> CGFloat {
    (tabFont(compatibleWith: traits).lineHeight + tabVerticalPadding * 2).rounded(.up)
  }

  private enum Zone: String { case outside, tabs, rail }

  private let contentInset: CGFloat
  private let columns: Int
  private let rail: TVUIKitMediaItemRailController

  private var rowTitle = ""
  private var tabs: [TVSeasonTab] = []
  private var items: [TVUIKitMediaItem] = []
  private var tabOfItem: [Int: Int] = [:]
  private var entryByTab: [Int: Int] = [:]
  private var openingItemID: Int?
  private var onTabSelected: ((Int) -> Void)?

  private var selectedTabID: Int?
  private var zone: Zone = .outside
  /// Until focus has been in here, the rail follows `openingItemID` as data arrives;
  /// after, it stays where the remote left it until the page is opened again.
  private var hasHadFocus = false

  /// A tab row only when there is a choice.
  private var showsTabs: Bool { tabs.count > 1 }

  private lazy var tabsView: UICollectionView = {
    let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] index, environment in
      self?.tabSection(index, environment: environment)
    }, configuration: {
      let configuration = UICollectionViewCompositionalLayoutConfiguration()
      configuration.scrollDirection = .horizontal
      configuration.contentInsetsReference = .none
      return configuration
    }())
    let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
    view.backgroundColor = .clear
    view.clipsToBounds = false
    view.contentInsetAdjustmentBehavior = .never
    // By identity, from `indexPathForPreferredFocusedView`: the selected tab.
    view.remembersLastFocusedIndexPath = false
    view.showsHorizontalScrollIndicator = false
    view.dataSource = self
    view.delegate = self
    view.register(TVSeasonTitleCell.self, forCellWithReuseIdentifier: TVSeasonTitleCell.reuseID)
    view.register(TVSeasonTabCell.self, forCellWithReuseIdentifier: TVSeasonTabCell.reuseID)
    return view
  }()

  /// Over the tab row, full width. From outside it sends focus down past the tabs to the
  /// rail's entry; from the rail, up to the selected tab.
  private let tabsGuide = UIFocusGuide()
  /// Over the rail, full width, while focus is on the tabs: Down goes to the rail's entry,
  /// not to whichever episode is under the tab.
  private let railGuide = UIFocusGuide()

  init(contentInset: CGFloat, columns: Int) {
    self.contentInset = contentInset
    self.columns = columns
    self.rail = TVUIKitMediaItemRailController(contentInset: contentInset, columns: columns, caption: .always)
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  public override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    view.clipsToBounds = false
    view.insetsLayoutMarginsFromSafeArea = false

    tabsView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(tabsView)

    addChild(rail)
    rail.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(rail.view)
    rail.didMove(toParent: self)
    rail.canFocusItem = { [weak self] id in self?.canFocusRailItem(id) ?? true }
    rail.itemAlpha = { [weak self] id in self?.alpha(ofItem: id) ?? 1 }

    view.addLayoutGuide(tabsGuide)
    view.addLayoutGuide(railGuide)

    NSLayoutConstraint.activate([
      tabsView.topAnchor.constraint(equalTo: view.topAnchor),
      tabsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tabsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tabsView.heightAnchor.constraint(equalToConstant: Self.tabRowHeight(compatibleWith: traitCollection)),

      rail.view.topAnchor.constraint(equalTo: tabsView.bottomAnchor, constant: Self.tabsToRail),
      rail.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      rail.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      rail.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      tabsGuide.topAnchor.constraint(equalTo: tabsView.topAnchor),
      tabsGuide.bottomAnchor.constraint(equalTo: tabsView.bottomAnchor),
      tabsGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tabsGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),

      railGuide.topAnchor.constraint(equalTo: rail.view.topAnchor),
      railGuide.bottomAnchor.constraint(equalTo: rail.view.bottomAnchor),
      railGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      railGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor)
    ])
    updateGuides()
  }

  public override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // The first pass is the first time the rail has a width to align in — and the tabs have
    // cells to select: the first `apply` comes before the view loads, and on tvOS 26.5 no
    // second one followed, so no tab was selected (2026-10-11).
    paintSelectedTab()
    if !hasHadFocus, let openingItemID {
      rail.align(to: openingItemID, animated: false)
    }
  }

  func apply(title: String,
             tabs: [TVSeasonTab],
             items: [TVUIKitMediaItem],
             tabOfItem: [Int: Int],
             entryByTab: [Int: Int],
             openingItemID: Int?,
             onSelect: @escaping (Int) -> Void,
             onTabSelected: ((Int) -> Void)?,
             contextMenuProvider: ((Int) -> [MediaCardContextEntry])?) {
    let tabsChanged = self.tabs != tabs || rowTitle != title
    let openingMoved = self.openingItemID != openingItemID
    let itemsChanged = self.items != items
    rowTitle = title
    self.tabs = tabs
    self.items = items
    self.tabOfItem = tabOfItem
    self.entryByTab = entryByTab
    self.openingItemID = openingItemID
    self.onTabSelected = onTabSelected

    rail.configure(items: items,
                   onSelect: onSelect,
                   onFocusedItem: { [weak self] id in self?.railFocused(id) },
                   contextMenuProvider: contextMenuProvider)

    if tabsChanged {
      tabsView.collectionViewLayout.invalidateLayout()
      tabsView.reloadData()
    }
    // Data lands after the page opens (TMDB schedules, the awaited episode): until the
    // remote has been here, the rail keeps standing where the hero's button points. After
    // that it is the user's, coming back from the player included.
    if !hasHadFocus, itemsChanged || openingMoved || tabsChanged {
      parkOnOpening(animated: false)
    } else if tabsChanged {
      applyTabSelection()
    }
  }

  // MARK: - Where things stand

  /// On the episode the hero's main button stands for: the rail aligned on it, its tab
  /// selected, and the entry for the first move down.
  private func parkOnOpening(animated: Bool) {
    guard let opening = openingItemID ?? items.first?.id else { return }
    rail.preferredItemID = opening
    selectedTabID = tabOfItem[opening] ?? tabs.first?.id
    applyTabSelection()
    if isViewLoaded {
      rail.align(to: opening, animated: animated)
    }
  }

  private var selectedTabIndex: Int? {
    selectedTabID.flatMap { id in tabs.firstIndex { $0.id == id } }
  }

  /// Paints the selected tab, and the selected season's tiles bright.
  private func applyTabSelection() {
    guard isViewLoaded else { return }
    rail.refreshItemAlpha(animated: hasHadFocus)
    paintSelectedTab()
  }

  private func paintSelectedTab() {
    guard isViewLoaded, showsTabs else { return }
    guard let index = selectedTabIndex else { return }
    let path = IndexPath(item: index, section: 1)
    guard tabsView.numberOfSections > 1, tabsView.numberOfItems(inSection: 1) > index else { return }
    if tabsView.indexPathsForSelectedItems?.first != path {
      tabsView.selectItem(at: path, animated: false, scrollPosition: [])
    }
  }

  /// The engine stood on an episode: its tab is the selected one (the rail does not
  /// move — the engine has already framed it), and it is where Down from the tabs returns.
  private func railFocused(_ id: Int) {
    rail.preferredItemID = id
    guard let tab = tabOfItem[id], tab != selectedTabID else { return }
    selectedTabID = tab
    applyTabSelection()
    onTabSelected?(tab)
  }

  /// The remote moved onto another tab: select it and take the rail to its entry.
  private func tabFocused(at index: Int) {
    guard tabs.indices.contains(index) else { return }
    let tab = tabs[index]
    guard tab.id != selectedTabID else { return }
    selectedTabID = tab.id
    applyTabSelection()
    let entry = entryByTab[tab.id] ?? items.first { tabOfItem[$0.id] == tab.id }?.id
    FocusLog.seasonTab(tab.label, entryItem: entry, animated: true)
    if let entry {
      rail.preferredItemID = entry
      rail.align(to: entry, animated: true)
    }
    onTabSelected?(tab.id)
  }

  private func alpha(ofItem id: Int) -> CGFloat {
    guard showsTabs, let selectedTabID, let tab = tabOfItem[id] else { return 1 }
    return tab == selectedTabID ? 1 : Self.otherSeasonAlpha
  }

  // MARK: - Focus

  private func canFocusRailItem(_ id: Int) -> Bool {
    zone == .rail || id == rail.preferredItemID
  }

  private func canFocusTab(at index: Int) -> Bool {
    switch zone {
    case .tabs: return true
    case .rail: return index == selectedTabIndex
    case .outside: return false
    }
  }

  private func updateGuides() {
    switch zone {
    case .outside:
      tabsGuide.isEnabled = true
      tabsGuide.preferredFocusEnvironments = [rail.focusTarget]
      railGuide.isEnabled = false
    case .rail:
      tabsGuide.isEnabled = showsTabs
      tabsGuide.preferredFocusEnvironments = [tabsView]
      railGuide.isEnabled = false
    case .tabs:
      tabsGuide.isEnabled = false
      railGuide.isEnabled = true
      railGuide.preferredFocusEnvironments = [rail.focusTarget]
    }
  }

  public override func didUpdateFocus(in context: UIFocusUpdateContext,
                                      with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    let next = context.nextFocusedItem
    let newZone: Zone
    if Self.environment(next, isInside: tabsView) {
      newZone = .tabs
    } else if Self.environment(next, isInside: rail.view) {
      newZone = .rail
    } else {
      newZone = .outside
    }
    guard newZone != zone else { return }
    zone = newZone
    if newZone != .outside { hasHadFocus = true }
    FocusLog.enteredSection("season-rail:\(newZone.rawValue)")
    updateGuides()
  }

  /// Walks the focus-environment chain: SwiftUI's items are not always views.
  private static func environment(_ item: UIFocusEnvironment?, isInside container: UIView) -> Bool {
    var current = item
    while let environment = current {
      if let view = environment as? UIView { return view.isDescendant(of: container) }
      current = environment.parentFocusEnvironment
    }
    return false
  }
}

// MARK: - Tab row

extension TVSeasonRailController: UICollectionViewDataSource, UICollectionViewDelegate {

  /// Data section 0 is the title, 1 the tabs, side by side. Widths come from the text, so
  /// a tab is its label plus padding and never narrower than tall.
  private func tabSection(_ index: Int, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
    let traits = environment.traitCollection
    let font = Self.tabFont(compatibleWith: traits)
    let height = Self.tabRowHeight(compatibleWith: traits)
    var frames: [CGRect] = []
    var x: CGFloat = 0
    if index == 0 {
      let titleWidth = (rowTitle as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
      x = titleWidth + (showsTabs ? Self.titleGap : 0)
      frames = [CGRect(x: 0, y: 0, width: x, height: height)]
    } else if showsTabs {
      for tab in tabs {
        let text = TVSeasonTabCell.text(for: tab, font: font).size().width.rounded(.up)
        let width = max(text + Self.tabHorizontalPadding * 2, height)
        frames.append(CGRect(x: x, y: 0, width: width, height: height))
        x += width
      }
    }
    let group = NSCollectionLayoutGroup.custom(
      layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(max(x, 1)),
                                         heightDimension: .absolute(height))
    ) { _ in frames.map { NSCollectionLayoutGroupCustomItem(frame: $0) } }
    let section = NSCollectionLayoutSection(group: group)
    section.contentInsets = NSDirectionalEdgeInsets(top: 0,
                                                    leading: index == 0 ? contentInset : 0,
                                                    bottom: 0,
                                                    trailing: index == 0 ? 0 : contentInset)
    return section
  }

  // Section 0 is the title, 1 the tabs, so index paths say which is which.
  public func numberOfSections(in collectionView: UICollectionView) -> Int { 2 }

  public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    section == 0 ? 1 : (showsTabs ? tabs.count : 0)
  }

  public func collectionView(_ collectionView: UICollectionView,
                             cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    if indexPath.section == 0 {
      let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TVSeasonTitleCell.reuseID,
                                                    for: indexPath) as! TVSeasonTitleCell
      cell.configure(title: rowTitle, font: Self.tabFont(compatibleWith: traitCollection))
      return cell
    }
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TVSeasonTabCell.reuseID,
                                                  for: indexPath) as! TVSeasonTabCell
    cell.configure(tabs[indexPath.item], font: Self.tabFont(compatibleWith: traitCollection))
    return cell
  }

  public func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
    indexPath.section == 1 && canFocusTab(at: indexPath.item)
  }

  public func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
    selectedTabIndex.map { IndexPath(item: $0, section: 1) }
  }

  public func collectionView(_ collectionView: UICollectionView,
                             didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                             with coordinator: UIFocusAnimationCoordinator) {
    guard let path = context.nextFocusedIndexPath, path.section == 1 else { return }
    tabFocused(at: path.item)
  }

  /// Select on a tab is the same as standing on it: the rail is already there.
  public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard indexPath.section == 1 else { return }
    tabFocused(at: indexPath.item)
  }

  // Selection is ours — it follows focus, and a deselect would leave no tab selected.
  public func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
    false
  }
}

// MARK: - Cells

/// «Сезон», or «Сезон 1» with nothing after it. Never focusable.
final class TVSeasonTitleCell: UICollectionViewCell {
  static let reuseID = "TVSeasonTitleCell"
  private let label = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    label.textColor = .secondaryLabel
    label.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(title: String, font: UIFont) {
    label.text = title
    label.font = font
    isAccessibilityElement = true
    accessibilityLabel = title
    accessibilityTraits = .header
  }
}

/// A season tab: the system list cell — its focused and selected looks are the cell's own,
/// as on the Library's sidebar rows — shaped as a pill. A season with nothing to watch is
/// secondary at rest.
final class TVSeasonTabCell: UICollectionViewListCell {
  static let reuseID = "TVSeasonTabCell"
  private var tab: TVSeasonTab?
  private var font: UIFont = .preferredFont(forTextStyle: .headline)

  /// The label with its glyph as a character of the text, not a separate image view.
  static func text(for tab: TVSeasonTab, font: UIFont) -> NSAttributedString {
    let text = NSMutableAttributedString(string: tab.label, attributes: [.font: font])
    if let symbol = tab.symbol,
       let image = UIImage(systemName: symbol,
                           withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote)) {
      text.append(NSAttributedString(string: " ", attributes: [.font: font]))
      text.append(NSAttributedString(attachment: NSTextAttachment(image: image.withRenderingMode(.alwaysTemplate))))
    }
    return text
  }

  func configure(_ tab: TVSeasonTab, font: UIFont) {
    self.tab = tab
    self.font = font
    accessibilityIdentifier = "kinopub.season.tab.\(tab.label)"
    accessibilityLabel = tab.accessibilityLabel
    setNeedsUpdateConfiguration()
  }

  override func updateConfiguration(using state: UICellConfigurationState) {
    guard let tab else { return }
    var content = UIListContentConfiguration.cell().updated(for: state)
    content.attributedText = Self.text(for: tab, font: font)
    content.textProperties.alignment = .center
    content.textProperties.numberOfLines = 1
    content.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: TVSeasonRailController.tabVerticalPadding, leading: 0,
      bottom: TVSeasonRailController.tabVerticalPadding, trailing: 0)
    if !tab.isAvailable, !state.isFocused {
      content.textProperties.color = .secondaryLabel
    }
    contentConfiguration = content

    var background = UIBackgroundConfiguration.listCell().updated(for: state)
    background.cornerRadius = bounds.height / 2
    backgroundConfiguration = background
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if var background = backgroundConfiguration, background.cornerRadius != bounds.height / 2 {
      background.cornerRadius = bounds.height / 2
      backgroundConfiguration = background
    }
  }
}
#endif
