//
//  RowKey.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend

/// Identifies one cacheable row of cards in `ContentStore` — Watch Now / tvOS Movies
/// / Series shortcut shelves, the Library's watchlist/history/folders. iOS/macOS
/// Movies/Series grids and Search still fetch page-by-page through `MediaCatalog`.
enum RowKey: Hashable, Codable {
  case continueWatching
  case shortcut(MediaShortcut, MediaType)
  case watchlist
  /// Every unfinished series — `/v1/watching/serials?subscribed=0`, the Library's
  /// Continue. Separate from `watchlist` (`subscribed=1`) because the Library sidebar
  /// shows them as their own section (kino.pub's "Недосмотренные").
  case unfinishedSerials
  case history
  /// Every bookmark folder's titles, combined. One cache row so switching back to
  /// *All bookmarks* paints from the store like a single folder does.
  case allBookmarks
  case folder(Int)
  /// Home's "Collections" preview row — a handful of curated collection covers.
  /// The full browser is a paginated cover grid and does not go through the store.
  case collections
  /// A filter-backed shelf on Watch Now (`new-arrivals`, `weekly-top`, `binge-worthy`, etc.).
  case homeSection(String)

  /// Group for prefix invalidation: clearing history shouldn't blow away catalog
  /// shelves, and toggling a bookmark shouldn't touch continue-watching.
  enum Family {
    case watch
    case catalog
    case bookmarks
  }

  var family: Family {
    switch self {
    case .continueWatching, .history, .watchlist, .unfinishedSerials: return .watch
    case .shortcut, .collections, .homeSection: return .catalog
    case .folder, .allBookmarks: return .bookmarks
    }
  }

  /// How long a cached row is trusted before a background refresh is worth doing.
  /// Continue watching/history change after every session; catalog shelves barely
  /// change at all.
  var ttl: TimeInterval {
    switch self {
    case .continueWatching, .history: return 60
    case .watchlist, .unfinishedSerials: return 120
    case .shortcut, .collections, .homeSection: return 15 * 60
    case .folder, .allBookmarks: return 10 * 60
    }
  }
}
