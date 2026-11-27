//
//  PageMargins.swift
//  PiraticUI
//

import SwiftUI

/// The one side margin of a page that runs edge to edge (Sasha, 2026-11-16: «разная
/// сейфареа … надо систематизировать»).
///
/// A page whose pictures and rails bleed past the safe area still has to set its words
/// and its first card clear of what covers the screen there: the iPad's open sidebar,
/// the iPhone's Dynamic Island in landscape. Each page used to solve that on its own —
/// the title page with a fixed 20 pt that ignored both, Home with the shelf inset that
/// ignored them too, Search by dropping the horizontal safe area altogether — so the
/// same iPad showed 40 pt beside the top tab bar and words flush against the sidebar,
/// and an iPhone turned sideways put text under the island.
///
/// One rule now, for every bleeding page: **margin = what covers that edge + the shelf
/// inset for the width that is left** (`ShelfMetrics.posters`: 20 pt on a phone in
/// portrait, 40 pt from 520 pt up). The root measures it once, outside its
/// `ignoresSafeArea`, and hands it down; text pads by it, rails take it as their scroll
/// content margin so they still run to the screen edge.
public struct PageMargins: Equatable, Sendable {
  /// From the page's leading edge to its content.
  public var leading: CGFloat
  /// From the page's trailing edge to its content.
  public var trailing: CGFloat
  /// The page's width minus what covers its sides — the width a grid or a shelf lays
  /// its columns out in.
  public var contentWidth: CGFloat
  /// The shelf inset alone, without the safe area under it.
  public var base: CGFloat

  /// What covers the leading edge (sidebar, notch), without the shelf inset.
  public var coveredLeading: CGFloat { leading - base }
  /// What covers the trailing edge, without the shelf inset.
  public var coveredTrailing: CGFloat { trailing - base }

  public init(leading: CGFloat, trailing: CGFloat, contentWidth: CGFloat, base: CGFloat) {
    self.leading = leading
    self.trailing = trailing
    self.contentWidth = contentWidth
    self.base = base
  }

  /// Margins for a page `width` wide whose sides are covered by `safeLeading` and
  /// `safeTrailing`.
  public static func resolve(width: CGFloat,
                             safeLeading: CGFloat,
                             safeTrailing: CGFloat,
                             typeSize: DynamicTypeSize) -> PageMargins {
    let contentWidth = max(1, width - safeLeading - safeTrailing)
    let base = ShelfMetrics.posters(width: contentWidth, typeSize: typeSize).inset
    return PageMargins(leading: safeLeading + base,
                       trailing: safeTrailing + base,
                       contentWidth: contentWidth,
                       base: base)
  }
}

public extension EnvironmentValues {
  /// Set by `providesPageMargins()` on a page that bleeds; `nil` elsewhere, where the
  /// caller's own inset still applies.
  @Entry var pageMargins: PageMargins? = nil
}

private struct PageGeometry: Equatable {
  var width: CGFloat
  var leading: CGFloat
  var trailing: CGFloat

  /// Changes under this are layout noise, not something covering the page.
  static let threshold: CGFloat = 2

  func differsNoticeably(from other: PageGeometry) -> Bool {
    abs(width - other.width) >= Self.threshold
      || abs(leading - other.leading) >= Self.threshold
      || abs(trailing - other.trailing) >= Self.threshold
  }

  /// Whole points: no float residue (5.7e-14) reaches the margins.
  var snapped: PageGeometry {
    PageGeometry(width: width.rounded(), leading: max(0, leading.rounded()),
                 trailing: max(0, trailing.rounded()))
  }
}

private struct PageMarginsProvider: ViewModifier {
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var geometry: PageGeometry?

  func body(content: Content) -> some View {
    content
      .environment(\.pageMargins, geometry.map {
        PageMargins.resolve(width: $0.width, safeLeading: $0.leading,
                            safeTrailing: $0.trailing, typeSize: typeSize)
      })
      // Read on the page's own frame, which spans the screen: its safe area insets are
      // exactly the parts of it that something covers. Inside the page they are zero.
      .onGeometryChange(for: PageGeometry.self) { proxy in
        PageGeometry(width: proxy.size.width,
                     leading: proxy.safeAreaInsets.leading,
                     trailing: proxy.safeAreaInsets.trailing)
      } action: { value in
        guard value.width > 0 else { return }
        // Only a real change: a sidebar, a turn, a notch — tens of points. Measured
        // inside a page whose content it pads, the value also moved by fractions of a
        // point with that content, and on an iPhone turned on a title page the hero and
        // these margins resized each other for good: 352.0 ↔ 352.99 pt every frame, the
        // main thread at 95 % and the turn never finishing (2026-11-17).
        if let geometry, !geometry.differsNoticeably(from: value) { return }
        geometry = value.snapped
      }
  }
}

public extension View {
  /// Measures the page's side margins and hands them to everything inside. Apply it
  /// *after* (outside) the page's `ignoresSafeArea`.
  func providesPageMargins() -> some View {
    modifier(PageMarginsProvider())
  }

  /// Leading and trailing padding by the page margins, or `fallback` on both sides on a
  /// page that does not provide them.
  func pageMarginPadding(fallback: CGFloat) -> some View {
    modifier(PageMarginPadding(fallback: fallback))
  }

  /// `safeAreaPadding` by the page margins (for a scroll target layout that aligns to
  /// the safe area), or `fallback` on both sides.
  func pageSafeAreaPadding(fallback: CGFloat) -> some View {
    modifier(PageSafeAreaPadding(fallback: fallback))
  }

  /// A horizontal rail's scroll content margins: the first card on the page margin, the
  /// rail itself running on to the screen edge.
  func pageContentMargins(fallback: CGFloat) -> some View {
    modifier(PageContentMargins(fallback: fallback))
  }
}

private struct PageMarginPadding: ViewModifier {
  @Environment(\.pageMargins) private var margins
  let fallback: CGFloat

  func body(content: Content) -> some View {
    content
      .padding(.leading, margins?.leading ?? fallback)
      .padding(.trailing, margins?.trailing ?? fallback)
  }
}

private struct PageContentMargins: ViewModifier {
  @Environment(\.pageMargins) private var margins
  let fallback: CGFloat

  func body(content: Content) -> some View {
    content
      .contentMargins(.leading, margins?.leading ?? fallback, for: .scrollContent)
      .contentMargins(.trailing, margins?.trailing ?? fallback, for: .scrollContent)
  }
}

private struct PageSafeAreaPadding: ViewModifier {
  @Environment(\.pageMargins) private var margins
  let fallback: CGFloat

  func body(content: Content) -> some View {
    content
      .safeAreaPadding(.leading, margins?.leading ?? fallback)
      .safeAreaPadding(.trailing, margins?.trailing ?? fallback)
  }
}
