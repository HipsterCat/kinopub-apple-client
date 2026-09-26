#if os(tvOS)
//
//  TVSearchPage.swift
//  KinoPubUI
//
//  The tvOS search screen, the way UIKit ships it: a `UISearchContainerViewController`
//  presenting a `UISearchController` — the system keyboard, the dictation hint, the
//  suggestion row, the scope bar — over a results controller. The results controller is
//  the same `TVPageCollectionViewController` every other page uses, so a result is the
//  same poster at the same size as on Watch Now.
//
//  Everything on this screen is the system's except the results and what we *feed* it:
//  - suggestions: `searchSuggestions` of `UISearchSuggestionItem` with an icon — a clock
//    for a recent query, a magnifying glass for a suggestion (HIG: "provide popular and
//    context-specific search suggestions, including recent searches when available");
//  - scope: `scopeButtonTitles` on the search bar — the native segmented control;
//  - minimising: the results controller reports its collection through
//    `setContentScrollView(_:for:)` (the replacement for the deprecated
//    `searchControllerObservedScrollView`), so the keyboard scrolls away with results.
//  Remembering recent queries is the app's job — the system keeps no search history.
//

import SwiftUI
import UIKit

/// One entry in the suggestion row.
public struct TVSearchSuggestion: Hashable, Sendable {
  public enum Kind: Hashable, Sendable {
    /// Something the user searched before — clock glyph.
    case recent
    /// A starter or a completion — magnifying glass.
    case suggested
  }

  public let text: String
  public let kind: Kind

  public init(_ text: String, kind: Kind) {
    self.text = text
    self.kind = kind
  }

  var systemImage: String {
    switch kind {
    case .recent: "clock.arrow.circlepath"
    case .suggested: "magnifyingglass"
    }
  }
}

public struct TVSearchPage: UIViewControllerRepresentable {
  public let sections: [TVPageSection]
  public let status: TVPageStatus
  /// What the field shows. Set from outside for a jump into search ("more by this
  /// director"); typing reports back through `onTextChange`.
  public let text: String
  public let placeholder: String
  public let suggestions: [TVSearchSuggestion]
  /// Titles for the native scope bar; fewer than two hides it.
  public let scopes: [String]
  public let selectedScope: Int
  public let onTextChange: (String) -> Void
  public let onScopeChange: (Int) -> Void
  /// A query the user settled on (picked a suggestion) — worth remembering.
  public let onCommit: (String) -> Void
  public let onSelect: (TVPageSection, TVPageItem) -> Void
  /// A pull-down chip in the results (sort, filters): (chip id, option id).
  public let onChipOption: (String, String) -> Void
  /// A multi-select pull-down closed with a new selection: (chip id, option ids).
  public let onChipSelection: (String, Set<String>) -> Void
  public let onNearEnd: ((TVPageSection) -> Void)?
  public let contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])?
  public let onRetry: (() -> Void)?

  public init(sections: [TVPageSection],
              status: TVPageStatus = .content,
              text: String,
              placeholder: String,
              suggestions: [TVSearchSuggestion] = [],
              scopes: [String] = [],
              selectedScope: Int = 0,
              onTextChange: @escaping (String) -> Void,
              onScopeChange: @escaping (Int) -> Void = { _ in },
              onCommit: @escaping (String) -> Void = { _ in },
              onSelect: @escaping (TVPageSection, TVPageItem) -> Void,
              onChipOption: @escaping (String, String) -> Void = { _, _ in },
              onChipSelection: @escaping (String, Set<String>) -> Void = { _, _ in },
              onNearEnd: ((TVPageSection) -> Void)? = nil,
              contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])? = nil,
              onRetry: (() -> Void)? = nil) {
    self.sections = sections
    self.status = status
    self.text = text
    self.placeholder = placeholder
    self.suggestions = suggestions
    self.scopes = scopes
    self.selectedScope = selectedScope
    self.onTextChange = onTextChange
    self.onScopeChange = onScopeChange
    self.onCommit = onCommit
    self.onSelect = onSelect
    self.onChipOption = onChipOption
    self.onChipSelection = onChipSelection
    self.onNearEnd = onNearEnd
    self.contextMenuProvider = contextMenuProvider
    self.onRetry = onRetry
  }

  public func makeCoordinator() -> Coordinator { Coordinator() }

  public func makeUIViewController(context: Context) -> UISearchContainerViewController {
    let results = TVPageCollectionViewController()
    results.accessibilityID = "kinopub.page.search"
    results.claimsInitialFocus = false
    results.remembersFocus = false
    results.spansScreenWidth = true
    let search = UISearchController(searchResultsController: results)
    search.searchResultsUpdater = context.coordinator
    // Never take the search bar's delegate: the search controller drives its tvOS
    // keyboard through it. Ours left `_UISearchControllerTVKeyboardContainerView` with
    // user interaction off (UIFocusDebugger, 2026-09-23) — keyboard, suggestions and
    // scope unreachable, focus trapped in the results. Scope changes arrive through
    // `updateSearchResults(for:)` instead.
    search.searchBar.placeholder = placeholder
    search.searchBar.text = text
    context.coordinator.results = results
    context.coordinator.search = search
    context.coordinator.lastReported = text
    update(context.coordinator, animated: false)
    let container = UISearchContainerViewController(searchController: search)
    if DebugLaunch.layoutDebug {
      // Magenta: the search container's own view — where SwiftUI placed it.
      container.view.backgroundColor = UIColor.systemPink.withAlphaComponent(0.12)
      container.view.layer.borderColor = UIColor.systemPink.cgColor
      container.view.layer.borderWidth = 4
    }
    return container
  }

  public func updateUIViewController(_ controller: UISearchContainerViewController, context: Context) {
    let coordinator = context.coordinator
    guard let search = coordinator.search else { return }
    // Only an outside change is written into the field; echoing our own report back
    // would move the caret under the user mid-word.
    if text != coordinator.lastReported, search.searchBar.text != text {
      coordinator.lastReported = text
      search.searchBar.text = text
    }
    search.searchBar.placeholder = placeholder
    update(coordinator, animated: true)
  }

  private func update(_ coordinator: Coordinator, animated: Bool) {
    coordinator.onTextChange = onTextChange
    coordinator.onScopeChange = onScopeChange
    coordinator.onCommit = onCommit
    guard let results = coordinator.results, let search = coordinator.search else { return }
    results.onSelect = onSelect
    results.onChipOption = onChipOption
    results.onChipSelection = onChipSelection
    results.onNearEnd = onNearEnd
    results.contextMenuProvider = contextMenuProvider
    results.onRetry = onRetry
    // Never animated: results change on every keystroke, and a diff animation had the
    // cards hopping about while the list settled — a rebuild is cheaper on an Apple TV.
    results.apply(sections: sections, status: status, animated: false)

    let bar = search.searchBar
    if bar.scopeButtonTitles ?? [] != scopes {
      bar.scopeButtonTitles = scopes.count > 1 ? scopes : nil
      bar.showsScopeBar = scopes.count > 1
    }
    if scopes.indices.contains(selectedScope), bar.selectedScopeButtonIndex != selectedScope {
      bar.selectedScopeButtonIndex = selectedScope
      coordinator.lastScope = selectedScope
    }

    if coordinator.shownSuggestions != suggestions {
      coordinator.shownSuggestions = suggestions
      search.searchSuggestions = suggestions.isEmpty ? nil : suggestions.map {
        UISearchSuggestionItem(localizedSuggestion: $0.text,
                               localizedDescription: $0.text,
                               iconImage: UIImage(systemName: $0.systemImage))
      }
    }
  }

  @MainActor
  public final class Coordinator: NSObject, UISearchResultsUpdating {
    var results: TVPageCollectionViewController?
    var search: UISearchController?
    var onTextChange: ((String) -> Void)?
    var onScopeChange: ((Int) -> Void)?
    var onCommit: ((String) -> Void)?
    var lastReported = ""
    var shownSuggestions: [TVSearchSuggestion] = []

    var lastScope = 0

    public func updateSearchResults(for searchController: UISearchController) {
      let scope = searchController.searchBar.selectedScopeButtonIndex
      if scope != lastScope {
        lastScope = scope
        onScopeChange?(scope)
      }
      report(searchController.searchBar.text ?? "")
    }

    public func updateSearchResults(for searchController: UISearchController,
                                    selecting searchSuggestion: any UISearchSuggestion) {
      let text = searchSuggestion.localizedSuggestion ?? ""
      searchController.searchBar.text = text
      // The system clears the row on selection; let the next update rebuild it.
      shownSuggestions = []
      report(text)
      onCommit?(text)
    }

    private func report(_ text: String) {
      guard text != lastReported else { return }
      lastReported = text
      onTextChange?(text)
    }
  }
}
#endif
