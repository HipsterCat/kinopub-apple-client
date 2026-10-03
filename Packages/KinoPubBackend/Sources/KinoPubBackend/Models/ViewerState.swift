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
/// is watched, whether they follow it, in which bookmark folders, downloaded, voted on.
/// For a series or a season, also how much of it is watched and downloaded (`Tally`).
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
  /// Following a series — kino.pub's "Я смотрю" (`in_watchlist` / `subscribed`). **Series
  /// only**: a film has bookmarks and no follow (user's call, 2026-10-03). Nil for a film,
  /// and when the payload did not say (catalogue listings never do).
  public var isFollowing: Bool?
  /// Bookmark folders holding the title. Nil when unknown — a listing payload carries none.
  public var bookmarkFolderIDs: Set<Int>?
  public var download: Download
  /// The viewer's own like or dislike. kino.pub's votes are write-only, so only this
  /// device ever knows it.
  public var vote: Vote?
  /// When this was last played, for history.
  public var lastWatchedAt: Date?
  /// A series or a season: how many of its episodes are watched. Drawn as a ring or a
  /// percentage (user's call, 2026-10-03). Nil for a single episode or film.
  public var watchedEpisodes: Tally?
  /// A series or a season: how much of it is on this device, partial downloads counted by
  /// their progress.
  public var downloadedEpisodes: Tally?

  public init(progress: WatchProgress? = nil,
              isWatched: Bool = false,
              isFollowing: Bool? = nil,
              bookmarkFolderIDs: Set<Int>? = nil,
              download: Download = .none,
              vote: Vote? = nil,
              lastWatchedAt: Date? = nil,
              watchedEpisodes: Tally? = nil,
              downloadedEpisodes: Tally? = nil) {
    self.progress = progress
    self.isWatched = isWatched
    self.isFollowing = isFollowing
    self.bookmarkFolderIDs = bookmarkFolderIDs
    self.download = download
    self.vote = vote
    self.lastWatchedAt = lastWatchedAt
    self.watchedEpisodes = watchedEpisodes
    self.downloadedEpisodes = downloadedEpisodes
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
    let isSeries = item.isSeries || item.isEpisodicType
    let video = isSeries ? nil : item.primaryVideo
    self.init(progress: video.map(\.watchProgress),
              isWatched: item.playbackAction == .playAgain,
              isFollowing: isSeries ? item.inWatchlist ?? item.subscribed : nil,
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
  public var isFollowing: Bool?
  public var bookmarkFolderIDs: Set<Int>?
  public var download: ViewerState.Download?
  public var vote: ViewerState.Vote?

  public init(progress: WatchProgress? = nil,
              progressUpdatedAt: Date? = nil,
              isWatched: Bool? = nil,
              isFollowing: Bool? = nil,
              bookmarkFolderIDs: Set<Int>? = nil,
              download: ViewerState.Download? = nil,
              vote: ViewerState.Vote? = nil) {
    self.progress = progress
    self.progressUpdatedAt = progressUpdatedAt
    self.isWatched = isWatched
    self.isFollowing = isFollowing
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
    if let isFollowing = overlay.isFollowing { state.isFollowing = isFollowing }
    if let folders = overlay.bookmarkFolderIDs { state.bookmarkFolderIDs = folders }
    if let download = overlay.download { state.download = download }
    if let vote = overlay.vote { state.vote = vote }
    return state
  }
}

// MARK: - A series, a season

/// How much of a container is done — «7 of 10 watched», «40% downloaded».
public struct Tally: Hashable, Codable, Sendable {
  /// Sum of each part's own completion: a watched episode is 1, a download at 40% is 0.4.
  public let completed: Double
  public let total: Int

  public init(completed: Double, total: Int) {
    self.completed = min(max(completed, 0), Double(max(total, 0)))
    self.total = max(total, 0)
  }

  /// 0…1; nil for an empty container.
  public var fraction: Double? { total > 0 ? completed / Double(total) : nil }
  public var isComplete: Bool { total > 0 && completed >= Double(total) }
  public var isEmpty: Bool { completed <= 0 }
}

public extension ViewerState {

  /// A series or a season from its episodes' states, on top of the title's own (follow,
  /// folders, vote). Watched when every episode is.
  ///
  /// TODO(decision): an episode half-watched counts as not watched in the ring today; a
  /// download half-done counts by its progress. Count watching by progress too?
  func aggregating(episodes: [ViewerState]) -> ViewerState {
    var state = self
    let watched = episodes.filter(\.isWatched).count
    state.watchedEpisodes = Tally(completed: Double(watched), total: episodes.count)
    let downloaded = episodes.reduce(0.0) { sum, episode in
      switch episode.download {
      case .downloaded: return sum + 1
      case .downloading(let progress): return sum + min(max(progress, 0), 1)
      case .none: return sum
      }
    }
    state.downloadedEpisodes = Tally(completed: downloaded, total: episodes.count)
    state.isWatched = !episodes.isEmpty && watched == episodes.count
    state.progress = nil
    state.lastWatchedAt = episodes.compactMap(\.lastWatchedAt).max() ?? state.lastWatchedAt
    return state
  }
}
