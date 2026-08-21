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
  /// Combined Watchlist + History + Bookmarks. No longer a browse tab — Watching
  /// and Bookmarks are separate. Kept so leftover selection can remap.
  case library
  /// Serials being followed, unfinished movies, and recently watched — the Watching tab.
  case watchlist
  case recentlyWatched
  case downloads
  case bookmarks
  /// A bookmark folder pinned as its own sidebar tab (macOS).
  case bookmark(Int)
  case settings
}
