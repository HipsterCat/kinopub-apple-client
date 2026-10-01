#if os(tvOS)
//
//  TVPage.swift
//  KinoPubUI
//
//  SwiftUI face of `TVPageCollectionViewController`: one representable per page
//  (Watch Now, Movies, Series, a person, a collection, Library's grid pane). The page's
//  sections are the only input; width, heights and focus come from UIKit inside.
//

import SwiftUI
import UIKit

public struct TVPage: UIViewControllerRepresentable {
  public let sections: [TVPageSection]
  public let status: TVPageStatus
  /// Leading/trailing content inset. 80 for a full-width page; a pane beside a
  /// sidebar passes what the sidebar already leaves.
  public let sideInset: CGFloat
  public let onSelect: (TVPageSection, TVPageItem) -> Void
  /// A pull-down chip's option was picked: (chip id, option id). Search's filter row.
  public let onChipOption: (String, String) -> Void
  /// A multi-select pull-down closed with a new selection: (chip id, option ids).
  public let onChipSelection: (String, Set<String>) -> Void
  public let onNearEnd: ((TVPageSection) -> Void)?
  public let contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])?
  public let onRetry: (() -> Void)?
  public let prefersFirstPosterFocus: Bool
  /// Surfaces as `kinopub.page.<name>` on the collection view for UI tests.
  public let accessibilityID: String?

  public init(sections: [TVPageSection],
              status: TVPageStatus = .content,
              sideInset: CGFloat = TVHIGGrid.sideInset,
              accessibilityID: String? = nil,
              onSelect: @escaping (TVPageSection, TVPageItem) -> Void,
              onChipOption: @escaping (String, String) -> Void = { _, _ in },
              onChipSelection: @escaping (String, Set<String>) -> Void = { _, _ in },
              onNearEnd: ((TVPageSection) -> Void)? = nil,
              contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])? = nil,
              onRetry: (() -> Void)? = nil,
              prefersFirstPosterFocus: Bool = false) {
    self.sections = sections
    self.status = status
    self.sideInset = sideInset
    self.accessibilityID = accessibilityID
    self.onSelect = onSelect
    self.onChipOption = onChipOption
    self.onChipSelection = onChipSelection
    self.onNearEnd = onNearEnd
    self.contextMenuProvider = contextMenuProvider
    self.onRetry = onRetry
    self.prefersFirstPosterFocus = prefersFirstPosterFocus
  }

  public func makeUIViewController(context: Context) -> TVPageCollectionViewController {
    let controller = TVPageCollectionViewController(sideInset: sideInset,
                                                    prefersFirstPosterFocus: prefersFirstPosterFocus)
    bind(controller)
    controller.apply(sections: sections, status: status, animated: false)
    return controller
  }

  public func updateUIViewController(_ controller: TVPageCollectionViewController, context: Context) {
    bind(controller)
    controller.apply(sections: sections, status: status, animated: true)
  }

  private func bind(_ controller: TVPageCollectionViewController) {
    controller.accessibilityID = accessibilityID
    controller.onSelect = onSelect
    controller.onChipOption = onChipOption
    controller.onChipSelection = onChipSelection
    controller.onNearEnd = onNearEnd
    controller.contextMenuProvider = contextMenuProvider
    controller.onRetry = onRetry
  }
}
#endif
