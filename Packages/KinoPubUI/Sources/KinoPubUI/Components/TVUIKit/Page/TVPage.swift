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

public struct TVPage: View {
  public let sections: [TVPageSection]
  public let status: TVPageStatus
  /// Leading/trailing content inset. Defaults to the HIG 80 pt example; the
  /// collection reads live `safeAreaInsets` and only uses this while they are 0.
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
  /// Catalog tab roots: Menu below the top row returns there first. Off on
  /// Search and pushed pages so Menu still pops.
  public let returnsToTopOnMenu: Bool

  @State private var belowTop = false
  @StateObject private var bridge = TVPageMenuBackBridge()

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
              prefersFirstPosterFocus: Bool = false,
              returnsToTopOnMenu: Bool = false) {
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
    self.returnsToTopOnMenu = returnsToTopOnMenu
  }

  public var body: some View {
    // `.onExitCommand(perform: nil)` is the pass-through: at the top row the
    // system TabView moves focus to the tab bar. Non-nil only while this page
    // owns focus below the top row, so a pushed detail still pops on Menu.
    TVPageRepresentable(
      sections: sections,
      status: status,
      sideInset: sideInset,
      accessibilityID: accessibilityID,
      onSelect: onSelect,
      onChipOption: onChipOption,
      onChipSelection: onChipSelection,
      onNearEnd: onNearEnd,
      contextMenuProvider: contextMenuProvider,
      onRetry: onRetry,
      prefersFirstPosterFocus: prefersFirstPosterFocus,
      returnsToTopOnMenu: returnsToTopOnMenu,
      belowTop: $belowTop,
      bridge: bridge
    )
    .onExitCommand(perform: returnsToTopOnMenu && belowTop ? { [bridge] in
      _ = bridge.controller?.returnToTopRow()
    } : nil)
  }
}

/// Holds the page controller so `.onExitCommand` can ask it to return to the
/// top row without making `TVPage` a representable itself.
@MainActor
final class TVPageMenuBackBridge: ObservableObject {
  weak var controller: TVPageCollectionViewController?
}

private struct TVPageRepresentable: UIViewControllerRepresentable {
  let sections: [TVPageSection]
  let status: TVPageStatus
  let sideInset: CGFloat
  let accessibilityID: String?
  let onSelect: (TVPageSection, TVPageItem) -> Void
  let onChipOption: (String, String) -> Void
  let onChipSelection: (String, Set<String>) -> Void
  let onNearEnd: ((TVPageSection) -> Void)?
  let contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])?
  let onRetry: (() -> Void)?
  let prefersFirstPosterFocus: Bool
  let returnsToTopOnMenu: Bool
  @Binding var belowTop: Bool
  let bridge: TVPageMenuBackBridge

  func makeUIViewController(context: Context) -> TVPageCollectionViewController {
    let controller = TVPageCollectionViewController(sideInset: sideInset,
                                                    prefersFirstPosterFocus: prefersFirstPosterFocus)
    bind(controller)
    controller.apply(sections: sections, status: status, animated: false)
    bridge.controller = controller
    return controller
  }

  func updateUIViewController(_ controller: TVPageCollectionViewController, context: Context) {
    bind(controller)
    controller.apply(sections: sections, status: status, animated: true)
    bridge.controller = controller
  }

  private func bind(_ controller: TVPageCollectionViewController) {
    controller.accessibilityID = accessibilityID
    controller.onSelect = onSelect
    controller.onChipOption = onChipOption
    controller.onChipSelection = onChipSelection
    controller.onNearEnd = onNearEnd
    controller.contextMenuProvider = contextMenuProvider
    controller.onRetry = onRetry
    controller.returnsToTopOnMenu = returnsToTopOnMenu
    controller.onBelowTopRowChange = { below in
      belowTop = below
    }
  }
}
#endif
