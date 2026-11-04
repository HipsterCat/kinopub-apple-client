//
//  View+PlatformNavigationTitle.swift
//  KinoPubAppleClient
//

import SwiftUI
#if os(macOS)
import KinoPubUI
#endif

public extension View {
  /// On tvOS the tab bar already says where you are, and a large title below it just
  /// eats the top of the screen. Everywhere else the title carries its usual weight.
  @ViewBuilder
  func platformNavigationTitle(_ title: LocalizedStringKey) -> some View {
#if os(tvOS)
    self
#elseif os(iOS)
    // Inline large on every page: the large title sits in the bar, beside its buttons,
    // not on a line of its own under them (Sasha, 2026-10-30).
    navigationTitle(title)
      .toolbarTitleDisplayMode(.inlineLarge)
#else
    macPageTitle(Text(title))
#endif
  }

  /// Disfavoured, so a literal (`"Recently Watched"`) takes the localized overload above:
  /// it took this one and showed the English key verbatim. Runtime strings (a folder's
  /// name) still land here.
  @_disfavoredOverload
  @ViewBuilder
  func platformNavigationTitle(_ title: String) -> some View {
#if os(tvOS)
    self
#elseif os(iOS)
    // Inline large on every page: the large title sits in the bar, beside its buttons,
    // not on a line of its own under them (Sasha, 2026-10-30).
    navigationTitle(title)
      .toolbarTitleDisplayMode(.inlineLarge)
#else
    macPageTitle(Text(title), isBlank: title.isEmpty)
#endif
  }

#if os(macOS)
  /// The Apple TV app's page title: large, under Back, as the page's first line; it
  /// scrolls away with the page and the window toolbar takes the ordinary title once it
  /// has gone under it. macOS has no system large title (`.large` is unavailable there
  /// and `.inlineLarge` draws the inline one), so this is the one piece we draw.
  /// Off outside the main window's pages (the Settings window keeps its plain title),
  /// and blank over the Home hero.
  func macPageTitle(_ title: Text, isBlank: Bool = false) -> some View {
    modifier(MacLargePageTitle(title: title, isBlank: isBlank))
  }

  /// Keeps the window toolbar the same height on every sidebar destination by
  /// reserving the accessory strip (Search fills it with filters). Back/forward
  /// stay system-owned — only appear when the stack can actually go.
  func macStableToolbarChrome(reserveAccessorySlot: Bool = true) -> some View {
    modifier(MacStableToolbarChromeModifier(reserveAccessorySlot: reserveAccessorySlot))
  }
#endif
}

#if os(macOS)
enum MacToolbarChrome {
  /// Shared accessory-bar id — Search filters and empty placeholders must match
  /// or the window grows a second strip.
  static let accessoryID = "mac-detail-accessory"
  static let accessoryMinHeight: CGFloat = 36
}

private struct MacStableToolbarChromeModifier: ViewModifier {
  var reserveAccessorySlot: Bool

  func body(content: Content) -> some View {
    content.toolbar {
      if reserveAccessorySlot {
        ToolbarItem(placement: .accessoryBar(id: MacToolbarChrome.accessoryID)) {
          Color.clear
            .frame(height: MacToolbarChrome.accessoryMinHeight)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
        }
      }
    }
  }
}
#endif

#if os(macOS)
extension EnvironmentValues {
  /// Pages under the main window's sidebar draw `MacLargePageTitle`; elsewhere (the
  /// Settings window) the title is the toolbar's alone.
  @Entry var macLargePageTitles = false
  /// Off where the page is a column beside another (Genres): the toolbar's title sits at
  /// the window's leading edge, over the other column, not over the page it names.
  @Entry var macLargePageTitleInToolbar = true
}

/// The scroll distance the large title has travelled, read by the header alone: the page
/// around it re-renders only when the toolbar title flips.
@Observable
private final class MacLargeTitleTravel {
  var offset: CGFloat = 0
  var height: CGFloat = 0
}

private struct MacLargePageTitle: ViewModifier {
  let title: Text
  let isBlank: Bool
  @Environment(\.macLargePageTitles) private var enabled
  @Environment(\.macLargePageTitleInToolbar) private var showsInToolbar
  @State private var travel = MacLargeTitleTravel()
  @State private var isScrolledAway = false

  private var isActive: Bool { enabled && !isBlank }

  func body(content: Content) -> some View {
    // One structure whatever the state, so the page keeps its identity when the
    // Home hero arrives and blanks the title.
    //
    // Room for it as the scroll content's top margin, the title over that room: a
    // `safeAreaInset` drew the toolbar's scroll-edge blur over the title's band as well,
    // so the scrolled toolbar stood twice its height.
    content
      .contentMargins(.top, isActive ? travel.height : 0, for: .scrollContent)
      // Over the whole page, not whatever the page's root is: an empty state's centred
      // box took the title into itself, cut short.
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .overlay(alignment: .top) {
        if isActive {
          MacLargeTitleHeader(title: title, travel: travel)
        }
      }
      .onScrollGeometryChange(for: CGFloat.self) { geometry in
        // Clamped to the header's height: past it nothing changes and nothing re-renders.
        min(max(geometry.contentOffset.y + geometry.contentInsets.top, 0), travel.height)
      } action: { _, travelled in
        travel.offset = travelled
        let away = travel.height > 0 && travelled >= travel.height
        if away != isScrolledAway { isScrolledAway = away }
      }
      .navigationTitle(isBlank || (isActive && (!isScrolledAway || !showsInToolbar))
                       ? Text(verbatim: "") : title)
  }
}

private struct MacLargeTitleHeader: View {
  let title: Text
  let travel: MacLargeTitleTravel
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var width: CGFloat = 0

  /// The rows' own margin, as the shelves measure it.
  private var inset: CGFloat {
    ShelfMetrics.posters(width: max(width, 1), typeSize: typeSize).inset
  }

  var body: some View {
    title
      .font(.largeTitle.bold())
      .lineLimit(1)
      .accessibilityAddTraits(.isHeader)
      .padding(.leading, inset)
      .padding(.trailing, inset)
      .padding(.bottom, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
        width = size.width
        travel.height = size.height
      }
      // Moves with the page and is cut at the toolbar's edge, where the toolbar's own
      // title takes over.
      .offset(y: -travel.offset)
      .clipped()
      .allowsHitTesting(false)
  }
}
#endif
