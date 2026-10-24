#if os(tvOS)
//
//  TVSearchPageHostViewController.swift
//  KinoPubUI
//
//  Owns a `UISearchContainerViewController` the way UIKit expects: a parent that
//  embeds the container with `addChild`, not a bare container returned from SwiftUI.
//  On tvOS 26.x a `TabView` tab whose root is only the search container loses the
//  spatial link from the tab bar into the search keyboard — Down from the Search tab
//  is a no-op while Select still enters the field. A `UIFocusGuide` in the tab-bar
//  band hands that Down off to the search bar and container. The guide is enabled
//  only while the tab bar has focus: left on, Up from the keyboard enters the same
//  band and is redirected into the results, onto a filter chip. `preferredFocusEnvironments`
//  covers keyboard ⇄ results. No press-delay rescue — that raced the focus animator
//  (AGENTS.md: no manual focus delays).
//

import UIKit

@MainActor
final class TVSearchPageHostViewController: UIViewController {
  private let searchContainer: UISearchContainerViewController
  private let searchController: UISearchController
  private weak var results: TVPageCollectionViewController?
  /// First appearance in the real tab (not the pre-warm parking window).
  var onFirstAppearance: (() -> Void)?
  private var didReportFirstAppearance = false

  /// Bridges Down from the tab bar into the search chrome. On only while the
  /// tab bar has focus — `syncEntryGuide`.
  private let tabEntryGuide = UIFocusGuide()
  private var tabEntryGuideHeight: NSLayoutConstraint?

  private enum Half { case keyboard, results }
  private var preferredHalf: Half = .keyboard

  init(searchController: UISearchController,
       searchContainer: UISearchContainerViewController,
       results: TVPageCollectionViewController) {
    self.searchController = searchController
    self.searchContainer = searchContainer
    self.results = results
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()

    searchController.obscuresBackgroundDuringPresentation = false

    addChild(searchContainer)
    searchContainer.view.frame = view.bounds
    searchContainer.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(searchContainer.view)
    searchContainer.didMove(toParent: self)

    view.addLayoutGuide(tabEntryGuide)
    tabEntryGuide.preferredFocusEnvironments = [searchController.searchBar, searchContainer]
    let height = tabEntryGuide.heightAnchor.constraint(equalToConstant: 1)
    tabEntryGuideHeight = height
    NSLayoutConstraint.activate([
      tabEntryGuide.topAnchor.constraint(equalTo: view.topAnchor),
      tabEntryGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tabEntryGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      height
    ])
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let height = max(view.safeAreaInsets.top, 1)
    if tabEntryGuideHeight?.constant != height {
      tabEntryGuideHeight?.constant = height
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // The pre-warm parking window is alpha 0 / hidden; the real tab's window is not.
    guard view.window?.alpha ?? 0 > 0.5, view.window?.isHidden == false else { return }
    // Pre-warm may have focused the keyboard in the parking window and left the
    // guide off. The real tab opens on the bar, and Down needs the guide on.
    syncEntryGuide()
    guard !didReportFirstAppearance else { return }
    didReportFirstAppearance = true
    onFirstAppearance?()
  }

  /// Pair a Menu `.began` we consumed with its `.ended` / `.cancelled`. Same
  /// contract as `TVPageCollectionViewController` — the search container can
  /// see the press before the results collection does.
  private var consumedMenuPress = false

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if presses.contains(where: { $0.type == .menu }), results?.returnToTopRow() == true {
      consumedMenuPress = true
      return
    }
    super.pressesBegan(presses, with: event)
  }

  override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if consumedMenuPress, presses.contains(where: { $0.type == .menu }) {
      consumedMenuPress = false
      return
    }
    super.pressesEnded(presses, with: event)
  }

  override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    if consumedMenuPress, presses.contains(where: { $0.type == .menu }) {
      consumedMenuPress = false
      return
    }
    super.pressesCancelled(presses, with: event)
  }

  override var preferredFocusEnvironments: [UIFocusEnvironment] {
    switch preferredHalf {
    case .keyboard:
      return [searchController.searchBar, searchContainer]
    case .results:
      if let results { return [results] }
      return [searchContainer]
    }
  }

  override func didUpdateFocus(in context: UIFocusUpdateContext,
                               with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    if let next = context.nextFocusedView {
      tabEntryGuide.isEnabled = !isInsidePage(next)
    }
    if focusIsInResults {
      preferredHalf = .results
      // Keep the focused poster through the keyboard-hide relayout. Off while the
      // keyboard has focus so Down from it lands on the filter row, not the last card.
      results?.remembersFocus = true
    } else if let next = context.nextFocusedView, isSearchChrome(next) || isTabBar(next) {
      preferredHalf = .keyboard
      results?.remembersFocus = false
    }
  }

  /// Keyboard, suggestions, search field — not the results collection. The tvOS
  /// keyboard is a private container and may sit outside the search bar.
  private func isSearchChrome(_ view: UIView) -> Bool {
    if let results, view.isDescendant(of: results.view) { return false }
    if view.isDescendant(of: searchController.searchBar) { return true }
    if view.isDescendant(of: searchContainer.view) { return true }
    if view.isDescendant(of: self.view) { return true }
    var current: UIView? = view
    while let node = current {
      let name = String(describing: type(of: node))
      if name.contains("Keyboard") || name.contains("Suggestion") { return true }
      current = node.superview
    }
    return false
  }

  /// The keyboard, the field, suggestions, or the results. The tab bar is not.
  private func isInsidePage(_ view: UIView) -> Bool {
    if isSearchChrome(view) { return true }
    if let results, view.isDescendant(of: results.view) { return true }
    return false
  }

  /// The guide catches Down from the tab bar. While anything on this page has
  /// focus it stays off, so Up from the keyboard reaches the bar instead of
  /// being redirected onto a filter chip.
  private func syncEntryGuide() {
    guard let focused = UIFocusSystem.focusSystem(for: view)?.focusedItem as? UIView else {
      tabEntryGuide.isEnabled = true
      return
    }
    tabEntryGuide.isEnabled = !isInsidePage(focused)
  }

  private func isTabBar(_ view: UIView) -> Bool {
    var current: UIView? = view
    while let node = current {
      if node is UITabBar { return true }
      current = node.superview
    }
    return false
  }

  private var focusIsInResults: Bool {
    guard let focused = UIFocusSystem.focusSystem(for: view)?.focusedItem else { return false }
    guard let results else { return false }
    var env: UIFocusEnvironment? = focused
    while let current = env {
      if let view = current as? UIView, view.isDescendant(of: results.view) { return true }
      if current === results { return true }
      env = current.parentFocusEnvironment
    }
    return false
  }
}
#endif
