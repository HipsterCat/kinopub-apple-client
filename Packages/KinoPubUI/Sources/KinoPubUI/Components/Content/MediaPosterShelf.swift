//
//  MediaPosterShelf.swift
//  KinoPubUI
//
//  One horizontal poster section for Home rows, detail Similar / person shelves,
//  Library shelves — same metrics, same card, optional navigable title.
//

import SwiftUI
import KinoPubBackend

/// Horizontal poster (or landscape) shelf. Home Hot Movies and detail "More from
/// director" are the same component; only title / destination / data differ.
public struct MediaPosterShelf<FocusKey: Hashable>: View {

  private let title: String
  private let count: String?
  private let cards: [MediaCard]
  private let destination: (any Hashable)?
  /// The header leads somewhere a `NavigationLink` cannot reach — another tab, most of
  /// all. Same chevron, same hover treatment; a `Button` instead of a link. Ignored
  /// when `destination` is set, so a row never claims two ways out.
  private let onOpen: (() -> Void)?
  private let navigationLinkProvider: (MediaCard) -> any Hashable
  private let onPlay: ((MediaCard) -> Void)?
  private let contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])?
  private let caption: MediaCardCaption
  private let focusedCard: FocusState<FocusKey?>.Binding?
  private let focusKey: ((MediaCard) -> FocusKey)?
  private let onCardFocused: (() -> Void)?
  /// The rail reached its last loaded card. The shelf does not know what "more" means
  /// — it reports the edge and the owner decides whether there is a next page.
  private let onNearEnd: ((MediaCard) -> Void)?
  /// Whether the next page is loading, failed, or there is no next page.
  private let pagination: PaginationState
  private let onRetryPagination: (() -> Void)?
  /// DEBUG `-KINOPUBFocusFirstPoster`: Continue Watching must not take focus.
  private let allowsFocus: Bool
  /// DEBUG: this shelf is Hot Movies — first 2:3 cell is the landing.
  private let prefersInitialFocus: Bool

  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.usesTVUIKitPosters) private var usesTVUIKitPosters
  @Environment(\.mediaNavigation) private var mediaNavigation
  @State private var containerWidth: CGFloat = 1920
  /// The container's own horizontal safe-area inset. Zero on a screen that already
  /// sits inside the safe area; the overscan margin on one that ignores it (the detail
  /// page does, horizontally). `ShelfMetrics` takes the larger of the two.
  @State private var containerSafeArea: CGFloat = 0
#if os(tvOS)
  /// 80 pt from the **screen**, not 80 on top of an already-inset host.
  @State private var contentLeadingInset: CGFloat = ShelfMetrics.tvContentMargin
#endif

  public init(
    title: String,
    count: String? = nil,
    cards: [MediaCard],
    destination: (any Hashable)? = nil,
    onOpen: (() -> Void)? = nil,
    navigationLinkProvider: @escaping (MediaCard) -> any Hashable,
    onPlay: ((MediaCard) -> Void)? = nil,
    contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])? = nil,
    caption: MediaCardCaption? = nil,
    focusedCard: FocusState<FocusKey?>.Binding? = nil,
    focusKey: ((MediaCard) -> FocusKey)? = nil,
    onCardFocused: (() -> Void)? = nil,
    onNearEnd: ((MediaCard) -> Void)? = nil,
    pagination: PaginationState = .idle,
    onRetryPagination: (() -> Void)? = nil,
    allowsFocus: Bool = true,
    prefersInitialFocus: Bool = false
  ) {
    self.title = title
    self.count = count
    self.cards = cards
    self.destination = destination
    self.onOpen = onOpen
    self.navigationLinkProvider = navigationLinkProvider
    self.onPlay = onPlay
    self.contextMenuProvider = contextMenuProvider
#if os(tvOS)
    self.caption = caption ?? .onFocus
#else
    self.caption = caption ?? .always
#endif
    self.focusedCard = focusedCard
    self.focusKey = focusKey
    self.onCardFocused = onCardFocused
    self.onNearEnd = onNearEnd
    self.pagination = pagination
    self.onRetryPagination = onRetryPagination
    self.allowsFocus = allowsFocus
    self.prefersInitialFocus = prefersInitialFocus
  }

  private var isLandscape: Bool {
    cards.first?.isLandscape == true
  }

  /// Both TVUIKit rails call their `onNearEnd` from `willDisplay` — that is **every**
  /// cell, not the last one. Passing it straight through would page the whole catalogue
  /// the moment a shelf first drew. Filtering here rather than in each caller is what
  /// makes `onNearEnd` mean the same thing on tvOS as it does on the SwiftUI rail.
  private func reportIfLast(_ id: Int) {
    guard CatalogLoadMore.isThresholdID(id, lastID: cards.last?.id),
          let card = cards.last else { return }
    onNearEnd?(card)
  }

  private var metrics: ShelfMetrics {
    isLandscape
      ? .landscape(width: containerWidth, typeSize: typeSize, safeArea: containerSafeArea)
      : .posters(width: containerWidth, typeSize: typeSize, safeArea: containerSafeArea)
  }

  /// The artwork box only: captions sit under the card, and the tile has no caption.
  private var tailTileHeight: CGFloat {
    let width = metrics.cardWidth(in: containerWidth)
    return isLandscape ? width / CardAspect.landscape.ratio : width / CardAspect.poster.ratio
  }

  private var railFocusPadding: CGFloat {
    isLandscape ? Metrics.landscapeFocusPadding : Metrics.focusPadding
  }

  private var leadingInset: CGFloat {
#if os(tvOS)
    contentLeadingInset
#else
    metrics.inset
#endif
  }

  /// Header → cards. tvOS extra is Sketch **8 pt**, not 28. Section also spaces
  /// header→content; the rail no longer keeps a spare focus strip above posters.
  /// Do not subtract focus padding here — that collapsed chrome and left the void
  /// inside the collection.
  private var headerSpacing: CGFloat {
    Metrics.sectionHeaderSpacing
  }

  public var body: some View {
    // CURRENT.md: `Section(title) { rail }`. Header is the Section title
    // (`.headline.bold()` + `.secondary`, system dodge) — not a VStack sibling, not UIKit.
    Section {
      rail
        .padding(.top, headerSpacing)
    } header: {
      sectionTitle
    }
#if os(tvOS)
    .modifier(MediaPosterShelfFocusSection(enabled: allowsFocus))
#endif
    .onGeometryChange(for: ShelfGeometry.self) { proxy in
      ShelfGeometry(
        width: proxy.size.width,
        safeArea: max(proxy.safeAreaInsets.leading, proxy.safeAreaInsets.trailing)
      )
    } action: { geometry in
      if geometry.width > 0 { containerWidth = geometry.width }
      containerSafeArea = max(0, geometry.safeArea)
    }
#if os(tvOS)
    .onGeometryChange(for: CGRect.self) { proxy in
      proxy.frame(in: .global)
    } action: { frame in
      contentLeadingInset = max(0, ShelfMetrics.tvContentMargin - frame.minX)
    }
#endif
  }

  /// tvOS: native `Section` header, leading on the same inset as the first card.
  /// iOS/macOS keep the navigable `header`.
  @ViewBuilder
  private var sectionTitle: some View {
#if os(tvOS)
    // tvOS `Section` measures the header's *ideal* size and centers a compact hug
    // (light shots landed ~795 pt). `frame(maxWidth: .infinity)` still hugs when
    // the proposal is unspecified — that is not a licence for a 1920-wide
    // screen-space canvas. Pin the header to the shelf's measured width (the
    // same `containerWidth` the rail uses) so centering is a no-op, then pad
    // with `leadingInset` (80-from-screen, shared with the first poster).
    SectionHeader(
      title: title,
      count: count,
      showsChevron: false,
      leadingInset: leadingInset
    )
    .frame(width: max(containerWidth, 1), alignment: .leading)
    .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
#else
    header
#endif
  }

  @ViewBuilder
  private var rail: some View {
#if os(tvOS)
    if usesTVUIKitPosters {
      tvUIKitRail
    } else {
      swiftUIRail
    }
#else
    swiftUIRail
#endif
  }

#if !os(tvOS)
  @ViewBuilder
  private var header: some View {
    if let destination {
      NavigationLink(value: destination) {
        SectionHeader(title: title, count: count, showsChevron: true)
      }
      .buttonStyle(RowHeaderButtonStyle())
    } else if let onOpen {
      Button(action: onOpen) {
        SectionHeader(title: title, count: count, showsChevron: true)
      }
      .buttonStyle(RowHeaderButtonStyle())
    } else {
      SectionHeader(title: title, count: count, showsChevron: false)
    }
  }
#endif

#if os(tvOS)
  /// Wide rails ride the system's media-item cell; posters stay on `TVPosterView`
  /// (`TVMediaItemContentConfiguration` ships a 16:9 `wideCell()` only).
  @ViewBuilder
  private var tvUIKitRail: some View {
    if isLandscape {
      TVUIKitMediaItemRail(
        items: cards.map(TVUIKitMediaItem.init(card:)),
        contentInset: leadingInset,
        onSelect: { id in
          if let card = cards.first(where: { $0.id == id }) { open(card) }
        },
        onNearEnd: onNearEnd.map { _ in
          { id in reportIfLast(id) }
        },
        contextMenuProvider: contextMenuProvider.map { provider in
          { id in cards.first(where: { $0.id == id }).map(provider) ?? [] }
        },
        allowsFocus: allowsFocus
      )
      .modifier(MediaPosterShelfFocusSection(enabled: allowsFocus))
    } else {
      tvUIKitPosterRail
    }
  }

  private var tvUIKitPosterRail: some View {
    TVUIKitMediaCollection(
      cards: cards,
      axis: .horizontal,
      containerWidth: containerWidth,
      safeArea: containerSafeArea,
      leadingInset: leadingInset,
      typeSize: typeSize,
      onSelect: { card in open(card) },
      onNearEnd: onNearEnd.map { _ in { card in reportIfLast(card.id) } },
      contextMenuProvider: contextMenuProvider,
      prefersInitialFocus: prefersInitialFocus
    )
    .frame(height: TVUIKitPosterMetrics.railHeight(
      isLandscape: isLandscape,
      containerWidth: containerWidth,
      typeSize: typeSize,
      safeArea: containerSafeArea
    ))
    .scrollClipDisabled()
    .focusSection()
  }
#endif

  private var swiftUIRail: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      // LazyHStack: only on-screen cards decode (Home CW can be 20+ wide stills).
      // Width from `ShelfMetrics`; `scrollClipDisabled` keeps focus lift visible.
      LazyHStack(alignment: .top, spacing: metrics.gutter) {
        ForEach(cards) { card in
          cardLink(card)
            .mediaZoomSource(id: "media-\(card.id)")
            .frame(width: metrics.cardWidth(in: containerWidth))
#if !os(tvOS)
            .buttonStyle(MediaCardButtonStyle())
#endif
            .modifier(MediaPosterShelfFocusModifier(
              focusedCard: allowsFocus ? focusedCard : nil,
              key: focusKey?(card)
            ))
#if os(tvOS)
            .modifier(MediaPosterShelfFocusReporter(onCardFocused: onCardFocused))
#endif
            .modifier(MediaCardContextMenuModifier(
              isEnabled: contextMenuProvider != nil,
              entriesProvider: { contextMenuProvider?(card) ?? [] }
            ))
            // Last loaded card came into view. `isThresholdID` rather than an index
            // lookup on purpose: `firstIndex(of:)` over `MediaCard` from every card's
            // `onAppear` is the O(n^2) deep-compare `CatalogLoadMore` exists to prevent.
            .onAppear {
              guard CatalogLoadMore.isThresholdID(card.id, lastID: cards.last?.id) else { return }
              onNearEnd?(card)
            }
        }

        // Where "still loading" / "that's all" / "tap to retry" lives on a rail. Sized
        // like a card so the row keeps its rhythm, and absent entirely when there is
        // nothing to say — a permanent tail tile would read as a broken last card.
        if pagination.isWorthShowing {
          PaginationTailTile(state: pagination, onRetry: onRetryPagination)
            .wrapped()
            .frame(width: metrics.cardWidth(in: containerWidth))
            .frame(height: tailTileHeight)
        }
      }
#if os(tvOS)
      // Leading 80 pt content column (aligned with the header). Trailing stays
      // open so the next card peeks past that box — not a matching 80 pt pad.
      // Top gap is Section’s, not another focus strip.
      .padding(.leading, leadingInset)
      .padding(.bottom, railFocusPadding)
#else
      .padding(.horizontal, metrics.inset)
      .padding(.vertical, railFocusPadding)
#endif
    }
#if os(tvOS)
    .buttonStyle(.borderless)
    .scrollClipDisabled()
    .modifier(MediaPosterShelfFocusSection(enabled: allowsFocus))
#endif
  }

  @ViewBuilder
  private func cardLink(_ card: MediaCard) -> some View {
    if card.primaryAction == .play, let onPlay {
      Button {
        onPlay(card)
      } label: {
        MediaCardView(card: card, caption: caption)
      }
    } else {
      NavigationLink(value: navigationLinkProvider(card)) {
        MediaCardView(card: card, caption: caption)
      }
    }
  }

  private func open(_ card: MediaCard) {
    if card.primaryAction == .play, let onPlay {
      onPlay(card)
      return
    }
    mediaNavigation?(navigationLinkProvider(card))
  }
}

/// Convenience when the caller does not need cross-row `@FocusState` keys.
public extension MediaPosterShelf where FocusKey == Int {
  init(
    title: String,
    count: String? = nil,
    cards: [MediaCard],
    destination: (any Hashable)? = nil,
    onOpen: (() -> Void)? = nil,
    navigationLinkProvider: @escaping (MediaCard) -> any Hashable,
    onPlay: ((MediaCard) -> Void)? = nil,
    contextMenuProvider: ((MediaCard) -> [MediaCardContextEntry])? = nil,
    caption: MediaCardCaption? = nil,
    onCardFocused: (() -> Void)? = nil
  ) {
    self.init(
      title: title,
      count: count,
      cards: cards,
      destination: destination,
      onOpen: onOpen,
      navigationLinkProvider: navigationLinkProvider,
      onPlay: onPlay,
      contextMenuProvider: contextMenuProvider,
      caption: caption,
      focusedCard: nil,
      focusKey: nil,
      onCardFocused: onCardFocused
    )
  }
}

// MARK: - Focus helpers

private struct MediaPosterShelfFocusModifier<FocusKey: Hashable>: ViewModifier {
  var focusedCard: FocusState<FocusKey?>.Binding?
  var key: FocusKey?

  @ViewBuilder
  func body(content: Content) -> some View {
    if let focusedCard, let key {
      content.focused(focusedCard, equals: key)
    } else {
      content
    }
  }
}

#if os(tvOS)
private struct MediaPosterShelfFocusSection: ViewModifier {
  var enabled: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if enabled {
      content.focusSection()
    } else {
      content
    }
  }
}

private struct MediaPosterShelfFocusReporter: ViewModifier {
  let onCardFocused: (() -> Void)?
  @Environment(\.isFocused) private var isFocused

  func body(content: Content) -> some View {
    content.onChange(of: isFocused) { _, focused in
      if focused { onCardFocused?() }
    }
  }
}
#endif
