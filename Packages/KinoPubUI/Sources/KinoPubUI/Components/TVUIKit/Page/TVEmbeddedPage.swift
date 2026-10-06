#if os(tvOS)
//
//  TVEmbeddedPage.swift
//  KinoPubUI
//
//  A `TVPage` that is one region of someone else's scroll: the detail page's sections
//  under the hero. Same sections, same cells, same layout formula as Watch Now and
//  Search — but the collection is as tall as its content and does not scroll, so the
//  host's vertical `ScrollView` stays the page's only scroll. The hero, its artwork and
//  these sections remain one view graph and one focus graph, and the focus engine
//  scrolls the one page (AGENTS.md › The detail page). `TVPage` is a tab root and owns
//  its scroll; this is not that.
//

import SwiftUI
import UIKit

public struct TVEmbeddedPage: UIViewControllerRepresentable {
  public let sections: [TVPageSection]
  public let sideInset: CGFloat
  /// Surfaces as `kinopub.page.<name>` on the collection view for UI tests.
  public let accessibilityID: String?
  public let onSelect: (TVPageSection, TVPageItem) -> Void
  public let contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])?

  public init(sections: [TVPageSection],
              sideInset: CGFloat = TVHIGGrid.sideInset,
              accessibilityID: String? = nil,
              onSelect: @escaping (TVPageSection, TVPageItem) -> Void,
              contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])? = nil) {
    self.sections = sections
    self.sideInset = sideInset
    self.accessibilityID = accessibilityID
    self.onSelect = onSelect
    self.contextMenuProvider = contextMenuProvider
  }

  public func makeUIViewController(context: Context) -> TVPageCollectionViewController {
    let controller = TVPageCollectionViewController(sideInset: sideInset)
    controller.isEmbedded = true
    // The hero names the page's entry control; a page below it must never take first
    // focus from it.
    controller.claimsInitialFocus = false
    bind(controller)
    controller.apply(sections: sections, status: .content, animated: false)
    return controller
  }

  public func updateUIViewController(_ controller: TVPageCollectionViewController, context: Context) {
    bind(controller)
    // Never animated: enrichment lands row by row, and a diff animation had the cards
    // hopping while the page settled.
    controller.apply(sections: sections, status: .content, animated: false)
  }

  /// The host asks how tall the sections are at the width it has. The layout is the
  /// only thing that knows, so it is asked.
  public func sizeThatFits(_ proposal: ProposedViewSize,
                           uiViewController controller: TVPageCollectionViewController,
                           context: Context) -> CGSize? {
    let proposed = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    let width = proposed
      ?? (controller.view.bounds.width > 0 ? controller.view.bounds.width : TVHIGGrid.referenceContentWidth + sideInset * 2)
    return CGSize(width: width, height: controller.contentHeight(forWidth: width))
  }

  private func bind(_ controller: TVPageCollectionViewController) {
    controller.accessibilityID = accessibilityID
    controller.onSelect = onSelect
    controller.contextMenuProvider = contextMenuProvider
  }
}
#endif
