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
  //  band hands off downward to the search bar and container; `preferredFocusEnvironments`
//  and a declined-press rescue cover keyboard ⇄ results the same way Rivulet does for
//  UIKit tabs (technique only — PolyForm Noncommercial).
//

import UIKit

@MainActor
final class TVSearchPageHostViewController: UIViewController {
  private let searchContainer: UISearchContainerViewController
  private let searchController: UISearchController
  private weak var results: TVPageCollectionViewController?

  /// Bridges the tab bar row into the search chrome on the vertical axis.
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
    tabEntryGuideHeight?.constant = max(view.safeAreaInsets.top, 1)
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

  /// Down from the keyboard when the engine finds nothing below; Up from the top
  /// results row when the collapsed keyboard is off screen. Tab bar → content is
  /// handled by `tabEntryGuide`, not here — this controller does not receive those
  /// presses while the bar still holds focus.
  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    let down = presses.contains { $0.type == .downArrow }
    let up = presses.contains { $0.type == .upArrow }
    if down, !focusIsInResults {
      rescueDownFromKeyboard()
    } else if up, focusIsInResults {
      rescueUpFromResults()
    }
    super.pressesBegan(presses, with: event)
  }

  private func rescueDownFromKeyboard() {
    let before = UIFocusSystem.focusSystem(for: view)?.focusedItem
    DispatchQueue.main.async { [weak self] in
      guard let self,
            UIFocusSystem.focusSystem(for: self.view)?.focusedItem === before else { return }
      guard !self.focusIsInResults else { return }
      self.move(to: .results)
    }
  }

  private func rescueUpFromResults() {
    let before = UIFocusSystem.focusSystem(for: view)?.focusedItem
    DispatchQueue.main.async { [weak self] in
      guard let self,
            UIFocusSystem.focusSystem(for: self.view)?.focusedItem === before else { return }
      guard self.focusIsInResults else { return }
      self.move(to: .keyboard)
    }
  }

  private func move(to half: Half) {
    preferredHalf = half
    if half == .keyboard {
      reopenKeyboard()
    }
    setNeedsFocusUpdate()
    updateFocusIfNeeded()
  }

  private func reopenKeyboard() {
    guard !searchController.searchBar.isFirstResponder else { return }
    searchController.searchBar.becomeFirstResponder()
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
