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
  /// When set, play-primary landscape cards open the player from the still.
  public var onPlay: ((MediaCard) -> Void)?
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

#if os(tvOS)
  @FocusState private var focusedItemID: Int?
#endif

#if os(tvOS)
  static var cardCaption: MediaCardCaption { .onFocus }
#else
  static var cardCaption: MediaCardCaption { .always }
#endif

  /// Poster cards: the same columns as `ContentItemsListView` / Movies. A grid of
  /// landscape stills (Continue Watching, History) takes the landscape shelf's columns
  /// instead, so a card here is the size of the same card on the Home rail: two
  /// across on an iPhone, not three postage stamps (Sasha, 2026-11-28).
  private var metrics: ShelfMetrics {
    isLandscapeGrid
      ? .landscape(width: containerWidth, typeSize: dynamicTypeSize)
      : .posters(width: containerWidth, typeSize: dynamicTypeSize)
  }

  /// First card decides, as on `MediaPosterShelf`: a list is all stills or all posters,
  /// and `metrics` is read per cell, so no walk over the whole list here.
  private var isLandscapeGrid: Bool {
    (cards.first ?? sections.first?.cards.first)?.isLandscape == true
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
              onPlay: ((MediaCard) -> Void)? = nil,
              contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])? = nil,
              sections: [MediaCardSection] = [],
              pagination: PaginationState = .idle,
              onRetryPagination: (() -> Void)? = nil) {
    self.cards = cards
    self.onLoadMoreContent = onLoadMoreContent
    self.navigationLinkProvider = navigationLinkProvider
    self.onPlay = onPlay
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
          if card.primaryAction == .play, let onPlay {
            onPlay(card)
          } else {
            mediaNavigation?(navigationLinkProvider(card))
          }
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
        cardCell(card)
          .onAppear { onLoadMoreContent(card) }
          // Same source id as Home shelves (`media-{id}`) so a stack with
          // `RouteStack(…, zoom: true)` can morph into the title page on iPhone/iPad.
          .mediaZoomSource(id: "media-\(card.id)")
#if os(tvOS)
          .focused($focusedItemID, equals: card.id)
#endif
          .modifier(MediaCardContextMenuModifier(
            isEnabled: contextMenuProvider != nil,
            entriesProvider: { contextMenuProvider?(card) ?? [] },
            previewCard: card,
            previewSurface: .shelf
          ))
      }
    }
  }

  @ViewBuilder
  private func cardCell(_ card: MediaCard) -> some View {
    if card.primaryAction == .play, card.isLandscape, let onPlay {
      MediaCardPlaySplitLink(
        card: card,
        caption: Self.cardCaption,
        detail: navigationLinkProvider(card),
        onPlay: { onPlay(card) }
      )
    } else if card.primaryAction == .play, let onPlay {
      Button {
        onPlay(card)
      } label: {
        MediaCardView(card: card, caption: Self.cardCaption)
      }
#if os(tvOS)
      .buttonStyle(.borderless)
#else
      .buttonStyle(MediaCardButtonStyle())
#endif
    } else {
      NavigationLink(value: navigationLinkProvider(card)) {
        MediaCardView(card: card, caption: Self.cardCaption)
      }
#if os(tvOS)
      .buttonStyle(.borderless)
#else
      .buttonStyle(MediaCardButtonStyle())
#endif
    }
  }

  private var swiftUIGrid: some View {
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
#if !os(tvOS)
    .remembersScroll()
#endif

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
