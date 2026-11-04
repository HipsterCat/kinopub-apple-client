//
//  View+PlatformNavigationTitle.swift
//  KinoPubAppleClient
//

import SwiftUI

public extension View {
  /// On tvOS the tab bar already says where you are, and a large title below it just
  /// eats the top of the screen. Everywhere else the title carries its usual weight.
  @ViewBuilder
  func platformNavigationTitle(_ title: LocalizedStringKey) -> some View {
#if os(tvOS)
    self
#else
    // Inline large on every page: the large title sits in the bar, beside its buttons,
    // not on a line of its own under them (Sasha, 2026-10-30). On the Mac the same mode
    // is the TV app's: a big title in the window toolbar beside Back, shrinking to the
    // ordinary toolbar title as the page scrolls (Sasha, 2026-11-04).
    navigationTitle(title)
      .toolbarTitleDisplayMode(.inlineLarge)
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
#else
    // Inline large on every page: the large title sits in the bar, beside its buttons,
    // not on a line of its own under them (Sasha, 2026-10-30). On the Mac the same mode
    // is the TV app's: a big title in the window toolbar beside Back, shrinking to the
    // ordinary toolbar title as the page scrolls (Sasha, 2026-11-04).
    navigationTitle(title)
      .toolbarTitleDisplayMode(.inlineLarge)
#endif
  }

#if os(macOS)
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
