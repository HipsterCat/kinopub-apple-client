//
//  LibrarySection.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend

/// Following header: Unwatched (default) hides caught-up series; All keeps them
/// in a section below.
enum LibraryFollowingScope: Equatable, Sendable {
  case unwatched
  case all
}

/// One entry of the Library sidebar. Sections are the *destinations* of the Library
/// tab — each shows its own vertical poster grid, none of them is a shelf row.
///
/// Order (Sasha, 2026-10-11): Подписки, Продолжить, Все закладки, bookmark folders,
/// История at the bottom.
///
/// `folder` carries only the id on purpose. A `Bookmark` value changes whenever its
/// item count or `updated` stamp does, so selecting on the whole model would drop the
/// user's selection every time the folder list refreshes. Titles and counts come from
/// `LibraryModel.folders` at draw time.
enum LibrarySection: Hashable, Codable {
  case watchlist
  case unwatched
  case allBookmarks
  case history
  case downloads
  case folder(Int)

  /// Fixed rows above the folders, in sidebar order. History is not here — it sits
  /// under the folders. Downloads stays behind `FeatureFlags.downloadsEnabled`.
  static var leadingFixed: [LibrarySection] {
    [.watchlist, .unwatched, .allBookmarks]
  }

  static var trailingFixed: [LibrarySection] {
    FeatureFlags.downloadsEnabled ? [.downloads, .history] : [.history]
  }

  /// Legacy name used by macOS's `List` of non-folder rows.
  static var fixed: [LibrarySection] { leadingFixed + trailingFixed }

  /// SF Symbol for a fixed row. Folders have none — the slot stays so labels align.
  var systemImage: String? {
    switch self {
    case .watchlist: return "bell.fill"
    case .unwatched: return "play.circle.fill"
    case .allBookmarks: return "bookmark.fill"
    case .history: return "clock.fill"
    case .downloads: return "arrow.down.to.line"
    case .folder: return nil
    }
  }

  /// Title for everything but folders — a folder's title is whatever the user named
  /// it, so it comes from `LibraryModel.title(for:)`.
  var fixedTitle: String? {
    switch self {
    case .watchlist: return "Library_Subscriptions".localized
    case .unwatched: return "Continue".localized
    case .allBookmarks: return "Library_AllBookmarks".localized
    case .history: return "History".localized
    case .downloads: return "Downloaded".localized
    case .folder: return nil
    }
  }

  /// Where this section's first page lives in `ContentStore`. `nil` for Downloads —
  /// those are local files owned by `DownloadsCatalog`, nothing to cache from network.
  var rowKey: RowKey? {
    switch self {
    case .watchlist: return .watchlist
    case .unwatched: return .unfinishedSerials
    case .allBookmarks: return .allBookmarks
    case .history: return .history
    case .downloads: return nil
    case .folder(let id): return .folder(id)
    }
  }

  /// History, folders, and the combined bookmarks list keep paging; watching endpoints
  /// answer in one shot.
  var isPaginated: Bool {
    switch self {
    case .history, .folder, .allBookmarks: return true
    case .watchlist, .unwatched, .downloads: return false
    }
  }

  var usesCardGrid: Bool {
    self != .downloads
  }

  // MARK: - Persistence

  /// Stable string for remembering the last selection across the session. Must not
  /// encode anything that changes with a refresh.
  var persistenceID: String {
    switch self {
    case .watchlist: return "watchlist"
    case .unwatched: return "unwatched"
    case .allBookmarks: return "allBookmarks"
    case .history: return "history"
    case .downloads: return "downloads"
    case .folder(let id): return "folder:\(id)"
    }
  }

  init?(persistenceID: String) {
    switch persistenceID {
    case "watchlist": self = .watchlist
    case "unwatched": self = .unwatched
    case "allBookmarks": self = .allBookmarks
    case "history": self = .history
    case "downloads": self = .downloads
    default:
      guard persistenceID.hasPrefix("folder:"),
            let id = Int(persistenceID.dropFirst("folder:".count)) else { return nil }
      self = .folder(id)
    }
  }
}
