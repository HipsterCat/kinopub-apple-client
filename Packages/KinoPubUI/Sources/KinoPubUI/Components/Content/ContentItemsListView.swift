//
//  ContentItemsListView.swift
//
//
//  Created by Kirill Kunst on 24.07.2023.
//

import Foundation
import SwiftUI
import KinoPubBackend

public struct ContentItemsListView<Header: View>: View {

  @Binding public var items: [MediaItem]
  public var onLoadMoreContent: (MediaItem) -> Void
  public var navigationLinkProvider: (MediaItem) -> any Hashable
  /// Long-press / secondary-click menu. Empty array leaves the poster without one.
  public var contextMenuProvider: ((MediaItem) -> [MediaCardContextEntry])?
  /// Poster tiles drawn while the first page is still unknown, so the grid's
  /// shape is on screen before the response arrives.
  private let placeholderCount: Int
  private let emptyMessage: LocalizedStringKey?
  /// A page past the first failed to load: the grid keeps its items and shows an
  /// inline retry where the missing page would have appeared — never a full-screen
  /// error in place of loaded content.
  /// Loading / failed / complete for the page after the last one shown.
  private let pagination: PaginationState
  private let onRetryPagination: (() -> Void)?
  private let header: Header
  /// A line under the last row (a collection's count). Shown with room to spare below it,
  /// so the end of a list reads as an end, not a cut.
  private let footer: Text?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.usesTVUIKitPosters) private var usesTVUIKitPosters
  @Environment(\.mediaNavigation) private var mediaNavigation
  /// Posters grid or list/table rows, where the page offers the switch (`MediaGridLayout`).
  @Environment(\.mediaGridLayout) private var gridLayout
  @State private var containerWidth: CGFloat = 1920

#if os(tvOS)
  @FocusState private var focusedItemID: Int?
#endif

  /// A grid has no preview above it, so the focused card is what names the item.
#if os(tvOS)
  static var cardCaption: MediaCardCaption { .onFocus }
#else
  static var cardCaption: MediaCardCaption { .always }
#endif

  private var usesListLayout: Bool { gridLayout == .list }

  private var metrics: ShelfMetrics {
    .posters(width: containerWidth, typeSize: dynamicTypeSize)
  }

  private var gridColumns: [GridItem] {
#if os(tvOS)
    // Pinned, not flexible: a poster is the same size in this grid as in every rail,
    // and the leftover becomes slack rather than quietly resizing the artwork per
    // screen. Flexible columns are still right everywhere else, where the card is
    // meant to track the container.
    let size = GridItem.Size.fixed(metrics.cardWidth(in: containerWidth))
#else
    let size = GridItem.Size.flexible()
#endif
    return Array(
      repeating: GridItem(size, spacing: metrics.gutter, alignment: .top),
      count: metrics.columns
    )
  }

  private var cards: [MediaCard] {
    items.map(MediaCard.init)
  }

  public init(items: Binding<[MediaItem]>,
              onLoadMoreContent: @escaping (MediaItem) -> Void,
              navigationLinkProvider: @escaping (MediaItem) -> any Hashable,
              contextMenuProvider: ((MediaItem) -> [MediaCardContextEntry])? = nil,
              placeholderCount: Int = 0,
              emptyMessage: LocalizedStringKey? = nil,
              pagination: PaginationState = .idle,
              onRetryPagination: (() -> Void)? = nil,
              footer: Text? = nil,
              @ViewBuilder header: () -> Header) {
    self._items = items
    self.onLoadMoreContent = onLoadMoreContent
    self.navigationLinkProvider = navigationLinkProvider
    self.contextMenuProvider = contextMenuProvider
    self.placeholderCount = placeholderCount
    self.emptyMessage = emptyMessage
    self.pagination = pagination
    self.onRetryPagination = onRetryPagination
    self.header = header()
    self.footer = footer
  }

  public var body: some View {
#if os(tvOS)
    if usesTVUIKitPosters {
      tvUIKitBody
    } else {
      swiftUIBody
    }
#else
    swiftUIBody
#endif
  }

#if os(tvOS)
  private var tvUIKitBody: some View {
    VStack(alignment: .leading, spacing: 0) {
      header

      if items.isEmpty, placeholderCount == 0, let emptyMessage {
        UnavailableView(title: emptyMessage, systemImage: "magnifyingglass")
          // Centred across the page. In a `.leading` stack it hugged its own words
          // and sat against the left edge with the rest of the window beside it,
          // which is not what an empty state looks like anywhere in the system.
          .frame(maxWidth: .infinity)
          .padding(.top, 40)
      } else if items.isEmpty, placeholderCount > 0 {
        LazyVGrid(columns: gridColumns, spacing: metrics.gutter) {
          ForEach(0..<placeholderCount, id: \.self) { _ in
            placeholderCard
          }
        }
        .safeAreaPadding(.horizontal, metrics.gridInset(in: containerWidth))
        .padding(.vertical, Metrics.focusPadding)
      } else {
        TVUIKitMediaCollection(
          cards: cards,
          axis: .vertical,
          containerWidth: containerWidth,
          typeSize: dynamicTypeSize,
          onSelect: { card in
            if let item = items.first(where: { $0.id == card.id }) {
              mediaNavigation?(navigationLinkProvider(item))
            }
          },
          onNearEnd: { card in
            if let item = items.first(where: { $0.id == card.id }) {
              onLoadMoreContent(item)
            }
          },
          contextMenuProvider: { card in
            guard let item = items.first(where: { $0.id == card.id }) else { return [] }
            return contextMenuProvider?(item) ?? []
          }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        PaginationFooter(state: pagination, onRetry: onRetryPagination)
      }
    }
    // Headers are supplied by callers; publishing the grid's own margin is what stops
    // each of them padding by a number of its own and landing off the first column.
    .environment(\.shelfGridInset, metrics.gridInset(in: containerWidth))
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { width in
      if width > 0 { containerWidth = width }
    }
  }
#endif

  private var swiftUIBody: some View {
    ScrollView {
      // Header (filters, sort) rides in the same scroll as the grid — never pinned
      // above a GeometryReader-sized remnant that steals half the screen.
      VStack(alignment: .leading, spacing: 0) {
        header

        if items.isEmpty, placeholderCount == 0, let emptyMessage {
          UnavailableView(title: emptyMessage, systemImage: "magnifyingglass")
            // Centred across the page. In a `.leading` stack it hugged its own words
            // and sat against the left edge with the rest of the window beside it,
            // which is not what an empty state looks like anywhere in the system.
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else if usesListLayout {
          listBody
        } else {
          gridBody
        }
      }
    }
#if !os(tvOS)
    .remembersScroll()
#endif

    // Headers are supplied by callers; publishing the grid's own margin is what stops
    // each of them padding by a number of its own and landing off the first column.
    .environment(\.shelfGridInset, metrics.gridInset(in: containerWidth))
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { width in
      if width > 0 { containerWidth = width }
    }
#if os(tvOS)
    // Default priority — `.userInitiated` yanked focus back to the first cell on every
    // return from a detail page.
    .defaultFocus($focusedItemID, items.first?.id)
#endif
  }

  private var gridBody: some View {
    Group {
      LazyVGrid(columns: gridColumns, spacing: metrics.gutter) {
        if items.isEmpty, placeholderCount > 0 {
          ForEach(0..<placeholderCount, id: \.self) { _ in
            placeholderCard
          }
        } else {
          ForEach(items, id: \.id) { item in
            NavigationLink(value: navigationLinkProvider(item)) {
              MediaCardView(card: MediaCard.card(for: item, in: gridLayout),
                            caption: Self.cardCaption)
                .onAppear {
                  onLoadMoreContent(item)
                }
            }
#if os(tvOS)
            .buttonStyle(.borderless)
            .focused($focusedItemID, equals: item.id)
#else
            .buttonStyle(MediaCardButtonStyle())
#endif
            .modifier(MediaCardContextMenuModifier(
              isEnabled: contextMenuProvider != nil,
              entriesProvider: { contextMenuProvider?(item) ?? [] }
            ))
          }
        }
      }
      .safeAreaPadding(.horizontal, metrics.gridInset(in: containerWidth))
      .padding(.vertical, Metrics.focusPadding)

      listFooter
    }
  }

  private var listBody: some View {
    Group {
      LazyVStack(alignment: .leading, spacing: 0) {
        if items.isEmpty, placeholderCount > 0 {
          ForEach(0..<min(placeholderCount, 8), id: \.self) { _ in
            placeholderListRow
            Divider().opacity(0.35)
          }
        } else {
          ForEach(items, id: \.id) { item in
            NavigationLink(value: navigationLinkProvider(item)) {
              CatalogMediaRow(item: item)
                .onAppear { onLoadMoreContent(item) }
            }
#if os(tvOS)
            .buttonStyle(.borderless)
            .focused($focusedItemID, equals: item.id)
#else
            .buttonStyle(.plain)
#endif
            .modifier(MediaCardContextMenuModifier(
              isEnabled: contextMenuProvider != nil,
              entriesProvider: { contextMenuProvider?(item) ?? [] }
            ))
            Divider().opacity(0.35)
          }
        }
      }
      .safeAreaPadding(.horizontal, metrics.gridInset(in: containerWidth))
      .padding(.vertical, Metrics.focusPadding)

      listFooter
    }
  }

  @ViewBuilder
  private var listFooter: some View {
    PaginationFooter(state: pagination, onRetry: onRetryPagination)

    if let footer, !items.isEmpty {
      footer
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, metrics.gutter)
        .padding(.bottom, Metrics.listFooterBottomSpace)
    }
  }

  /// Same footprint as a real poster card (tile + caption line), inert so focus
  /// stays on the filters / search field while the page is still loading.
  private var placeholderCard: some View {
    VStack(alignment: .leading, spacing: Metrics.cardCaptionSpacing) {
      Color.KinoPub.placeholder
        .aspectRatio(CardAspect.poster.ratio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous))

      Text(" ")
        .font(TypeScale.cardTitle)
        .opacity(0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityHidden(true)
  }

  private var placeholderListRow: some View {
    HStack(spacing: 14) {
      Color.KinoPub.placeholder
        .frame(width: 52, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      VStack(alignment: .leading, spacing: 6) {
        Color.KinoPub.placeholder.frame(height: 14).frame(maxWidth: 180)
        Color.KinoPub.placeholder.frame(height: 12).frame(maxWidth: 120)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 10)
    .accessibilityHidden(true)
  }

}

public extension ContentItemsListView where Header == EmptyView {
  init(items: Binding<[MediaItem]>,
       onLoadMoreContent: @escaping (MediaItem) -> Void,
       navigationLinkProvider: @escaping (MediaItem) -> any Hashable,
       contextMenuProvider: ((MediaItem) -> [MediaCardContextEntry])? = nil,
       placeholderCount: Int = 0,
       emptyMessage: LocalizedStringKey? = nil,
       pagination: PaginationState = .idle,
       onRetryPagination: (() -> Void)? = nil) {
    self.init(items: items,
              onLoadMoreContent: onLoadMoreContent,
              navigationLinkProvider: navigationLinkProvider,
              contextMenuProvider: contextMenuProvider,
              placeholderCount: placeholderCount,
              emptyMessage: emptyMessage,
              pagination: pagination,
              onRetryPagination: onRetryPagination,
              header: { EmptyView() })
  }
}

struct ContentItemsListView_Previews: PreviewProvider {

  struct Preview: View {
    @State private var items: [MediaItem] = [MediaItem.mock()]

    var body: some View {
      ContentItemsListView(items: $items, onLoadMoreContent: { _ in

      }, navigationLinkProvider: { _ in
        return ""
      })
    }
  }

  static var previews: some View {
    NavigationStack {
      Preview()
    }
  }
}
