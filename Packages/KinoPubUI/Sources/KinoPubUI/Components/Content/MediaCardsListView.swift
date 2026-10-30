//
//  MediaCardsListView.swift
//

import Foundation
import SwiftUI

/// Vertical poster-column grid of `MediaCard`s — History, Watchlist, and any other
/// card-backed catalog that is not a full `MediaItem` list.
public struct MediaCardsListView: View {

  public var cards: [MediaCard]
  public var onLoadMoreContent: (MediaCard) -> Void
  public var navigationLinkProvider: (MediaCard) -> any Hashable
  public var contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])?
  /// Loading / failed / complete for the page after the last one shown.
  private let pagination: PaginationState
  /// Optional headed groups. Empty means one flat grid — the shape every caller had
  /// before, and still the default.
  private let sections: [MediaCardSection]
  private let onRetryPagination: (() -> Void)?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.usesTVUIKitPosters) private var usesTVUIKitPosters
  @Environment(\.mediaNavigation) private var mediaNavigation
  @State private var containerWidth: CGFloat = 1920

#if os(tvOS) || os(macOS)
  @FocusState private var focusedItemID: Int?
#endif
#if os(macOS)
  @Environment(\.pageKeyboardEntry) private var keyboardEntry
  @Environment(\.pageKeyboardExit) private var keyboardExit
#endif

#if os(tvOS)
  static var cardCaption: MediaCardCaption { .onFocus }
#else
  static var cardCaption: MediaCardCaption { .always }
#endif

  /// Same column count as `ContentItemsListView` / Movies — landscape tiles are just shorter.
  private var metrics: ShelfMetrics {
    .posters(width: containerWidth, typeSize: dynamicTypeSize)
  }

  private var gridColumns: [GridItem] {
    Array(
      repeating: GridItem(.flexible(), spacing: metrics.gutter, alignment: .top),
      count: metrics.columns
    )
  }

  public init(cards: [MediaCard],
              onLoadMoreContent: @escaping (MediaCard) -> Void,
              navigationLinkProvider: @escaping (MediaCard) -> any Hashable,
              contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])? = nil,
              sections: [MediaCardSection] = [],
              pagination: PaginationState = .idle,
              onRetryPagination: (() -> Void)? = nil) {
    self.cards = cards
    self.onLoadMoreContent = onLoadMoreContent
    self.navigationLinkProvider = navigationLinkProvider
    self.contextMenuProvider = contextMenuProvider
    self.sections = sections
    self.pagination = pagination
    self.onRetryPagination = onRetryPagination
  }

  public var body: some View {
#if os(tvOS)
    if usesTVUIKitPosters {
      tvUIKitGrid
    } else {
      swiftUIGrid
    }
#else
    swiftUIGrid
#endif
  }

#if os(tvOS)
  private var tvUIKitGrid: some View {
    VStack(spacing: 0) {
      TVUIKitMediaCollection(
        cards: cards,
        axis: .vertical,
        containerWidth: containerWidth,
        typeSize: dynamicTypeSize,
        onSelect: { card in
          mediaNavigation?(navigationLinkProvider(card))
        },
        onNearEnd: { card in
          onLoadMoreContent(card)
        },
        contextMenuProvider: contextMenuProvider
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      PaginationFooter(state: pagination, onRetry: onRetryPagination)
    }
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { width in
      if width > 0 { containerWidth = width }
    }
  }
#endif

  private func grid(of cards: [MediaCard]) -> some View {
    LazyVGrid(columns: gridColumns, spacing: metrics.gutter) {
      ForEach(cards) { card in
        NavigationLink(value: navigationLinkProvider(card)) {
          MediaCardView(card: card, caption: Self.cardCaption)
            .onAppear { onLoadMoreContent(card) }
        }
#if os(tvOS)
        .buttonStyle(.borderless)
        .focused($focusedItemID, equals: card.id)
#else
        .buttonStyle(MediaCardButtonStyle())
        .macKeyboardCard { mediaNavigation?(navigationLinkProvider(card)) }
#if os(macOS)
        .focused($focusedItemID, equals: card.id)
        .id(card.id)
#endif
#endif
        .modifier(MediaCardContextMenuModifier(
          isEnabled: contextMenuProvider != nil,
          entriesProvider: { contextMenuProvider?(card) ?? [] }
        ))
      }
    }
  }

  private var swiftUIGrid: some View {
#if os(macOS)
    ScrollViewReader { proxy in
      gridScroll
        .onChange(of: keyboardEntry) { _, request in
          guard request != nil, let first = cards.first else { return }
          focusedItemID = first.id
          proxy.scrollTo(first.id, anchor: nil)
        }
        .onKeyPress(keys: .arrows) { press in
          guard let current = focusedItemID, let direction = press.moveDirection else { return .ignored }
          let rows = keyboardRows
          switch PageKeyboardTravel.next(from: current, rows: rows, direction: direction) {
          case .some(.some(let id)):
            focusedItemID = id
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: nil) }
          case .some(.none):
            focusedItemID = nil
            keyboardExit?()
          case .none: break
          }
          return .handled
        }
    }
#else
    gridScroll
#endif
  }

#if os(macOS)
  /// The grid as the keyboard sees it: its rows of card ids, section by section.
  private var keyboardRows: [[Int]] {
    let groups = sections.isEmpty ? [cards] : sections.map(\.cards)
    let columns = max(metrics.columns, 1)
    return groups.flatMap { group in
      stride(from: 0, to: group.count, by: columns).map { start in
        group[start..<min(start + columns, group.count)].map(\.id)
      }
    }
  }
#endif

  private var gridScroll: some View {
    ScrollView {
      if sections.isEmpty {
        grid(of: cards)
          .safeAreaPadding(.horizontal, metrics.inset)
          .padding(.vertical, Metrics.focusPadding)
      } else {
        // One `LazyVGrid` per section rather than pinned headers over a single grid:
        // a section header inside a grid spans one column, not the row.
        LazyVStack(alignment: .leading, spacing: metrics.gutter) {
          ForEach(sections) { section in
            SectionHeader(title: section.title, leadingInset: metrics.inset)
            grid(of: section.cards)
              .safeAreaPadding(.horizontal, metrics.inset)
          }
        }
        .padding(.vertical, Metrics.focusPadding)
      }

      PaginationFooter(state: pagination, onRetry: onRetryPagination)
    }
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { width in
      if width > 0 { containerWidth = width }
    }
#if os(tvOS)
    .defaultFocus($focusedItemID, cards.first?.id)
#endif
  }

}

/// One headed group in a card grid — history broken up by day or month.
///
/// The heading is a plain string, already formatted: the package has no business
/// knowing this app's date rules, the same reason `MediaCard+Episode` takes its
/// `dateLabel` pre-formatted.
public struct MediaCardSection: Identifiable {
  public let id: String
  public let title: String
  public let cards: [MediaCard]

  public init(id: String, title: String, cards: [MediaCard]) {
    self.id = id
    self.title = title
    self.cards = cards
  }
}
