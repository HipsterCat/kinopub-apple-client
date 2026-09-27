//
//  NavigationTabs.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 31.07.2023.
//

import Foundation

enum NavigationTabs: Hashable {
  case search
  case home
  case movies
  case series
  /// Combined Watchlist + History + Bookmarks (tvOS / iOS / iPad).
  case library
  case watchlist
  case recentlyWatched
  case downloads
  case bookmarks
  /// A bookmark folder pinned as its own sidebar tab (macOS).
  case bookmark(Int)
  case settings
#if os(tvOS) && DEBUG
  /// Library sidebar sandbox, one tab per engine (`TVSidebarSandbox.swift`). No stack —
  /// it pushes nothing.
  case sidebarLab(SBEngine)
#endif
}
