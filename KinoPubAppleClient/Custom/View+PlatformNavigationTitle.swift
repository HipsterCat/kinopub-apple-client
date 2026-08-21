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
    navigationTitle(title)
#endif
  }

  @ViewBuilder
  func platformNavigationTitle(_ title: String) -> some View {
#if os(tvOS)
    self
#else
    navigationTitle(title)
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

#if os(iOS)
extension View {
  /// Root browse chrome: title lives in the Liquid Glass bar (`inlineLarge`),
  /// not as a content-area large title that overlays posters with no fill.
  /// On 27 the bar itself minimizes on scroll-down and restores on scroll-up.
  func browseNavigationChrome() -> some View {
    modifier(BrowseNavigationChromeModifier())
  }

  /// Gear in the trailing navigation bar, presenting Settings as a sheet that
  /// zooms out of the button. Only at tab root — a pushed title already owns
  /// the trailing slot (overflow / More). macOS uses the Settings window;
  /// tvOS keeps Settings as a glyph tab.
  func iosSettingsToolbar(for tab: NavigationTabs) -> some View {
    modifier(IOSSettingsToolbarModifier(tab: tab))
  }
}

private struct BrowseNavigationChromeModifier: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 27, *) {
      content
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
    } else {
      content
        .toolbarTitleDisplayMode(.inlineLarge)
    }
  }
}

private struct IOSSettingsToolbarModifier: ViewModifier {
  let tab: NavigationTabs

  @Environment(\.appContext) private var appContext
  @Environment(ErrorHandler.self) private var errorHandler
  @EnvironmentObject private var authState: AuthState
  @EnvironmentObject private var navigationState: NavigationState

  @State private var showSettings = false
  @Namespace private var settingsNamespace

  func body(content: Content) -> some View {
    content
      .toolbar {
        if isTabRoot {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              showSettings = true
            } label: {
              Label("Settings", systemImage: "gearshape")
            }
            .matchedTransitionSource(id: Self.transitionID, in: settingsNamespace)
          }
        }
      }
      .sheet(isPresented: $showSettings) {
        ProfileView(model: ProfileModel(userService: appContext.userService,
                                        errorHandler: errorHandler,
                                        authState: authState))
          .navigationTransition(.zoom(sourceID: Self.transitionID, in: settingsNamespace))
      }
  }

  private static let transitionID = "settingsChrome"

  private var isTabRoot: Bool {
    switch tab {
    case .home: navigationState.mainRoutes.isEmpty
    case .library: navigationState.libraryRoutes.isEmpty
    case .movies: navigationState.moviesRoutes.isEmpty
    case .series: navigationState.seriesRoutes.isEmpty
    default: true
    }
  }
}
#endif

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
