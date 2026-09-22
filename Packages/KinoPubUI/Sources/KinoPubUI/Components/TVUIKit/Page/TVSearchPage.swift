#if os(tvOS)
//
//  TVSearchPage.swift
//  KinoPubUI
//
//  The tvOS search screen, the way UIKit ships it: a `UISearchContainerViewController`
//  presenting a `UISearchController` — the system keyboard, the dictation hint, the
//  suggestion list — over a results controller. The results controller is the same
//  `TVPageCollectionViewController` every other page uses, so a result is the same
//  poster at the same size as on Watch Now; only its flow (a grid) differs.
//
//  Docs: `UISearchContainerViewController` ("In tvOS … embed an instance of this class
//  and let it manage the presentation of the search controller's content") and
//  `UISearchController.searchSuggestions` (tvOS 14). The results controller reports its
//  collection through `setContentScrollView(_:for:)`, which is how the search field
//  scrolls away with the results (`searchControllerObservedScrollView` is deprecated).
//

import SwiftUI
import UIKit

public struct TVSearchPage: UIViewControllerRepresentable {
  public let sections: [TVPageSection]
  public let status: TVPageStatus
  /// What the field shows. Set from outside for a jump into search ("more by this
  /// director"); typing reports back through `onTextChange`.
  public let text: String
  public let placeholder: String
  /// Offered while the field is empty — recents, starters.
  public let suggestions: [String]
  public let onTextChange: (String) -> Void
  public let onSelect: (TVPageSection, TVPageItem) -> Void
  public let onNearEnd: ((TVPageSection) -> Void)?
  public let contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])?
  public let onRetry: (() -> Void)?

  public init(sections: [TVPageSection],
              status: TVPageStatus = .content,
              text: String,
              placeholder: String,
              suggestions: [String] = [],
              onTextChange: @escaping (String) -> Void,
              onSelect: @escaping (TVPageSection, TVPageItem) -> Void,
              onNearEnd: ((TVPageSection) -> Void)? = nil,
              contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])? = nil,
              onRetry: (() -> Void)? = nil) {
    self.sections = sections
    self.status = status
    self.text = text
    self.placeholder = placeholder
    self.suggestions = suggestions
    self.onTextChange = onTextChange
    self.onSelect = onSelect
    self.onNearEnd = onNearEnd
    self.contextMenuProvider = contextMenuProvider
    self.onRetry = onRetry
  }

  public func makeCoordinator() -> Coordinator { Coordinator() }

  public func makeUIViewController(context: Context) -> UISearchContainerViewController {
    let results = TVPageCollectionViewController()
    results.accessibilityID = "kinopub.page.search"
    let search = UISearchController(searchResultsController: results)
    search.searchResultsUpdater = context.coordinator
    search.searchBar.placeholder = placeholder
    search.searchBar.text = text
    context.coordinator.results = results
    context.coordinator.search = search
    context.coordinator.lastReported = text
    update(context.coordinator, animated: false)
    return UISearchContainerViewController(searchController: search)
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
    guard let results = coordinator.results, let search = coordinator.search else { return }
    results.onSelect = onSelect
    results.onNearEnd = onNearEnd
    results.contextMenuProvider = contextMenuProvider
    results.onRetry = onRetry
    results.apply(sections: sections, status: status, animated: animated)

    let empty = (search.searchBar.text ?? "").isEmpty
    let wanted = empty ? suggestions : []
    if coordinator.shownSuggestions != wanted {
      coordinator.shownSuggestions = wanted
      search.searchSuggestions = wanted.isEmpty
        ? nil
        : wanted.map { UISearchSuggestionItem(localizedSuggestion: $0) }
    }
  }

  @MainActor
  public final class Coordinator: NSObject, UISearchResultsUpdating {
    var results: TVPageCollectionViewController?
    var search: UISearchController?
    var onTextChange: ((String) -> Void)?
    var lastReported = ""
    var shownSuggestions: [String] = []

    public func updateSearchResults(for searchController: UISearchController) {
      report(searchController.searchBar.text ?? "")
    }

    public func updateSearchResults(for searchController: UISearchController,
                                    selecting searchSuggestion: any UISearchSuggestion) {
      let text = searchSuggestion.localizedSuggestion ?? ""
      searchController.searchBar.text = text
      shownSuggestions = []
      report(text)
    }

    private func report(_ text: String) {
      guard text != lastReported else { return }
      lastReported = text
      onTextChange?(text)
    }
  }
}
#endif
