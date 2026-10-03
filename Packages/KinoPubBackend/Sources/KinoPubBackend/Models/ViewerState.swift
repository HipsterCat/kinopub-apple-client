//
//  ViewerState.swift
//  KinoPubBackend
//
//  What the viewer has done with one thing — the other half of every card, button and list
//  beside the facts of the media model. One value, read in one place.
//

import Foundation
import KinoPubMedia

/// **What the viewer has done with one thing** (`MediaRef`): how far they got, whether it
/// is watched, on their watchlist, in which bookmark folders, downloaded, voted on.
///
/// Built in two steps, both here so every surface agrees:
/// 1. `ViewerState(reportedBy:)` — what a kino.pub payload says;
/// 2. `overlaid(_:)` — this device's own, newer knowledge on top (`ViewerOverlay`).
///
/// The stores that own each piece stay as they are (AGENTS.md "One store ownership
/// model"); the app's `ViewerStateReader` gathers their answers into the overlay.
public struct ViewerState: Hashable, Codable, Sendable {

  public enum Download: Hashable, Codable, Sendable {
    case none
    /// 0…1.
    case downloading(Double)
    case downloaded
  }

  public enum Vote: String, Hashable, Codable, Sendable {
    case up, down
  }

  /// The resume point. Nil when nobody reported one.
  public var progress: WatchProgress?
  /// The server's flag, or watched to the credits, or a local mark.
  public var isWatched: Bool
  /// kino.pub's "Я смотрю" — following a series, keeping a film to watch. Nil when the
  /// payload did not say (catalogue listings never do).
  /// TODO(decision): the UI calls this Follow on a series and Watchlist on a film. One
  /// word for both, or keep two?
  public var isInWatchlist: Bool?
  /// Bookmark folders holding the title. Nil when unknown — a listing payload carries none.
  public var bookmarkFolderIDs: Set<Int>?
  public var download: Download
  /// The viewer's own like or dislike. kino.pub's votes are write-only, so only this
  /// device ever knows it.
  public var vote: Vote?
  /// When this was last played, for history.
  public var lastWatchedAt: Date?

  public init(progress: WatchProgress? = nil,
              isWatched: Bool = false,
              isInWatchlist: Bool? = nil,
              bookmarkFolderIDs: Set<Int>? = nil,
              download: Download = .none,
              vote: Vote? = nil,
              lastWatchedAt: Date? = nil) {
    self.progress = progress
    self.isWatched = isWatched
    self.isInWatchlist = isInWatchlist
    self.bookmarkFolderIDs = bookmarkFolderIDs
    self.download = download
    self.vote = vote
    self.lastWatchedAt = lastWatchedAt
  }

  public static let unknown = ViewerState()

  public var isBookmarked: Bool { !(bookmarkFolderIDs ?? []).isEmpty }

  /// 0…1 while in progress; nil when unwatched or finished (`WatchProgress.resumeFraction`).
  public var resumeFraction: Double? { isWatched ? nil : progress?.resumeFraction }
}

// MARK: - What kino.pub reports

public extension ViewerState {

  /// A title as the details or listing payload describes it. A series' progress is its
  /// episodes', not its own — ask each `Episode`.
  init(reportedBy item: MediaItem) {
    let video = item.isSeries || item.isEpisodicType ? nil : item.primaryVideo
    self.init(progress: video.map(\.watchProgress),
              isWatched: item.playbackAction == .playAgain,
              isInWatchlist: item.inWatchlist ?? item.subscribed,
              bookmarkFolderIDs: item.bookmarks.map { Set($0.map(\.id)) })
  }

  /// One episode as its season lists it.
  init(reportedBy episode: Episode) {
    self.init(progress: episode.watchProgress, isWatched: episode.isWatched)
  }
}

// MARK: - This device's knowledge on top

/// What this device knows that the payload may not yet: the stores' optimistic writes.
/// **Every field present wins** — a local write is authoritative until the server agrees
/// and the store drops it (AGENTS.md "Local optimistic writes").
public struct ViewerOverlay: Hashable, Sendable {
  public var progress: WatchProgress?
  public var progressUpdatedAt: Date?
  public var isWatched: Bool?
  public var isInWatchlist: Bool?
  public var bookmarkFolderIDs: Set<Int>?
  public var download: ViewerState.Download?
  public var vote: ViewerState.Vote?

  public init(progress: WatchProgress? = nil,
              progressUpdatedAt: Date? = nil,
              isWatched: Bool? = nil,
              isInWatchlist: Bool? = nil,
              bookmarkFolderIDs: Set<Int>? = nil,
              download: ViewerState.Download? = nil,
              vote: ViewerState.Vote? = nil) {
    self.progress = progress
    self.progressUpdatedAt = progressUpdatedAt
    self.isWatched = isWatched
    self.isInWatchlist = isInWatchlist
    self.bookmarkFolderIDs = bookmarkFolderIDs
    self.download = download
    self.vote = vote
  }
}

public extension ViewerState {

  /// The rules, in one place:
  /// - a **local resume point** replaces the reported one — this device played it last.
  ///   TODO(decision): a newer position from another device only reaches us through the
  ///   payload, which carries no time to compare. Until it does, local wins.
  /// - a resume point that is **finished** marks the thing watched, as the server will
  ///   once it sees the position (`WatchProgress`);
  /// - a local **watched** mark, watchlist toggle, folder set, vote and download state
  ///   win over the payload's.
  func overlaid(_ overlay: ViewerOverlay) -> ViewerState {
    var state = self
    if let progress = overlay.progress {
      state.progress = progress
      if progress.isFinished { state.isWatched = true }
    }
    if let updatedAt = overlay.progressUpdatedAt {
      state.lastWatchedAt = max(state.lastWatchedAt ?? .distantPast, updatedAt)
    }
    if let isWatched = overlay.isWatched { state.isWatched = isWatched }
    if let isInWatchlist = overlay.isInWatchlist { state.isInWatchlist = isInWatchlist }
    if let folders = overlay.bookmarkFolderIDs { state.bookmarkFolderIDs = folders }
    if let download = overlay.download { state.download = download }
    if let vote = overlay.vote { state.vote = vote }
    return state
  }
}
