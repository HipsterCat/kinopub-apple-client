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
  /// Leading/trailing content inset. 80 for a full-width page; a pane beside a
  /// sidebar passes what the sidebar already leaves.
  public let sideInset: CGFloat
  public let onSelect: (TVPageSection, TVPageItem) -> Void
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
              onNearEnd: ((TVPageSection) -> Void)? = nil,
              contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])? = nil,
              onRetry: (() -> Void)? = nil,
              prefersFirstPosterFocus: Bool = false) {
    self.sections = sections
    self.status = status
    self.sideInset = sideInset
    self.accessibilityID = accessibilityID
    self.onSelect = onSelect
    self.onNearEnd = onNearEnd
    self.contextMenuProvider = contextMenuProvider
    self.onRetry = onRetry
    self.prefersFirstPosterFocus = prefersFirstPosterFocus
  }

  /// Present when the enclosing stack offers the zoom transition (`RouteStack(zoom:)`).
  @Environment(\.zoomSourceStore) private var zoomSources
  @Environment(\.zoomTransitionNamespace) private var zoomNamespace
  @State private var zoomOwner = UUID()

  public var body: some View {
    TVPageRepresentable(page: self, onZoomSource: zoomSourceReporter)
      .overlay(alignment: .topLeading) {
        if let zoomSources, let zoomNamespace {
          TVZoomSourceOverlay(store: zoomSources, owner: zoomOwner, namespace: zoomNamespace)
        }
      }
  }

  private var zoomSourceReporter: ((String, CGRect, URL?) -> Void)? {
    guard let zoomSources, zoomNamespace != nil else { return nil }
    let owner = zoomOwner
    return { id, frame, art in zoomSources.register(id: id, frame: frame, owner: owner, art: art) }
  }
}

/// The collection itself. `TVPage` wraps it so the zoom source can sit over it in SwiftUI.
private struct TVPageRepresentable: UIViewControllerRepresentable {
  let page: TVPage
  let onZoomSource: ((String, CGRect, URL?) -> Void)?

  func makeUIViewController(context: Context) -> TVPageCollectionViewController {
    let controller = TVPageCollectionViewController(sideInset: page.sideInset,
                                                    prefersFirstPosterFocus: page.prefersFirstPosterFocus)
    bind(controller)
    controller.apply(sections: page.sections, status: page.status, animated: false)
    return controller
  }

  func updateUIViewController(_ controller: TVPageCollectionViewController, context: Context) {
    bind(controller)
    controller.apply(sections: page.sections, status: page.status, animated: true)
  }

  private func bind(_ controller: TVPageCollectionViewController) {
    controller.accessibilityID = page.accessibilityID
    controller.onSelect = page.onSelect
    controller.onNearEnd = page.onNearEnd
    controller.contextMenuProvider = page.contextMenuProvider
    controller.onRetry = page.onRetry
    controller.onZoomSource = onZoomSource
  }
}
#endif
