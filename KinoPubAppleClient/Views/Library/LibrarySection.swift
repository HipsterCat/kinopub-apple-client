//
//  LibrarySection.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend

/// One entry of the Library sidebar. Sections are the *destinations* of the Library
/// tab — each shows its own vertical poster grid, none of them is a shelf row.
///
/// Order and membership are a product decision, not an implementation detail:
/// see `ROADMAP.md`.
///
/// `folder` carries only the id on purpose. A `Bookmark` value changes whenever its
/// item count or `updated` stamp does, so selecting on the whole model would drop the
/// user's selection every time the folder list refreshes. Titles and counts come from
/// `LibraryModel.folders` at draw time.
enum LibrarySection: Hashable, Codable {
  case watchlist
  case unwatched
  case history
  case downloads
  case folder(Int)

  /// The fixed sections, in sidebar order. Bookmark folders follow, from `LibraryModel`.
  ///
  /// Downloads is behind `FeatureFlags.downloadsEnabled` like every other downloads
  /// entry point — an off flag drops the row entirely, it does not show a dead one.
  static var fixed: [LibrarySection] {
    var sections: [LibrarySection] = [.watchlist, .unwatched, .history]
    if FeatureFlags.downloadsEnabled {
      sections.append(.downloads)
    }
    return sections
  }

  var systemImage: String {
    switch self {
    case .watchlist: return "bell.fill"
    case .unwatched: return "chevron.forward.dotted.chevron.forward"
//    case .movies: return "movieclapper"
//    case .downloads: return "arrow.down.circle"
    case .downloads: return "arrow.down.to.line"
    case .folder: return "bookmark"
    case .history: return "clock"
    }
  }

  /// Title for everything but folders — a folder's title is whatever the user named
  /// it, so it comes from `LibraryModel.title(for:)`.
  var fixedTitle: String? {
    switch self {
    case .watchlist: return "Following".localized
    case .unwatched: return "Continue".localized
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
    case .unwatched: return .watchingMovies
    case .history: return .history
    case .downloads: return nil
    case .folder(let id): return .folder(id)
    }
  }

  /// History and folder contents keep paging; the watching endpoints answer in one shot.
  var isPaginated: Bool {
    switch self {
    case .history, .folder: return true
    case .watchlist, .unwatched, .downloads: return false
    }
  }

  /// Downloads is drawn by the existing `DownloadsView`, not by `LibrarySectionCatalog`.
  var usesCardGrid: Bool {
    self != .downloads
  }

  // MARK: - Persistence

  /// Stable string for remembering the last selection across launches. Must not
  /// encode anything that changes with a refresh.
  var persistenceID: String {
    switch self {
    case .watchlist: return "watchlist"
    case .unwatched: return "unwatched"
    case .history: return "history"
    case .downloads: return "downloads"
    case .folder(let id): return "folder:\(id)"
    }
  }

  init?(persistenceID: String) {
    switch persistenceID {
    case "watchlist": self = .watchlist
    case "unwatched": self = .unwatched
    case "history": self = .history
    case "downloads": self = .downloads
    default:
      guard persistenceID.hasPrefix("folder:"),
            let id = Int(persistenceID.dropFirst("folder:".count)) else { return nil }
      self = .folder(id)
    }
  }
}
