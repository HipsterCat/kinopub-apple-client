//
//  EpisodeQueue.swift
//  KinoPubBackend
//
//  **Which episode** — the one place that answers it, for every surface: the hero's Play,
//  Continue Watching, the player's Up Next tab and its end-of-episode proposal.
//

import Foundation
import KinoPubMedia

/// A series' episodes in reading order, each with what the viewer has done with it.
///
/// Every "which episode" question is a named query here, so two surfaces asking the same
/// thing get the same answer, and two asking *different* things say so by name:
///
/// | Question | Query | Asked by |
/// | --- | --- | --- |
/// | what plays after this one, watched or not | `next(after:)` | the end-of-episode proposal |
/// | what to offer after this one | `nextUnwatched(after:)` | Up Next (never a watched one) |
/// | where the viewer is in the series | `continueTarget` | hero Play, Continue Watching |
///
/// Watched-ness comes from `ViewerState`, so a caller that passes the device's own state
/// (`ViewerStateReader`) gets local marks and resume points, not only the payload's.
public struct EpisodeQueue {

  public struct Entry {
    public let season: Season
    public let episode: Episode
    public let state: ViewerState

    public var ref: MediaRef? { episode.mediaRef }
  }

  /// Reading order: season number, then episode number within it.
  public let entries: [Entry]
  private let seriesID: Int?
  private let seriesTitle: String?

  /// - Parameters:
  ///   - series: the payload with seasons. Nil or seasonless is an empty queue.
  ///   - state: what the viewer has done with each episode. Default: what the payload
  ///     says (`ViewerState(reportedBy:)`).
  public init(series: MediaItem?,
              state: (MediaRef, Episode) -> ViewerState = { ViewerState(reportedBy: $1) }) {
    seriesID = series?.id
    seriesTitle = series?.localizedTitle
    guard let series, let seasons = series.seasons else {
      entries = []
      return
    }
    entries = seasons.sorted { $0.number < $1.number }.flatMap { season in
      season.episodes.sorted { $0.number < $1.number }.map { episode in
        let ref = MediaRef.episode(series.id, season: season.number, number: episode.number)
        return Entry(season: season, episode: episode, state: state(ref, episode))
      }
    }
  }

  /// An episode about to be **played** from a cached payload may lack its stamps, and an
  /// unresolved `WatchingMetadata` reports nothing to the server. `Episode` is a class —
  /// every holder sees the stamp.
  private func stamped(_ entry: Entry?) -> Entry? {
    guard let entry else { return nil }
    if entry.episode.mediaId == nil { entry.episode.mediaId = seriesID }
    if entry.episode.seasonNumber == nil { entry.episode.seasonNumber = entry.season.number }
    if entry.episode.seriesTitle == nil { entry.episode.seriesTitle = seriesTitle }
    return entry
  }

  // MARK: - After this one

  /// The episode after `current`, watched or not: the next number in the season, else the
  /// first of the season after. Matched by `id`, so an unstamped season cannot misplace it.
  public func next(after current: Episode) -> Entry? {
    guard let index = entries.firstIndex(where: { $0.episode.id == current.id }) else { return nil }
    return stamped(entries.dropFirst(index + 1).first)
  }

  /// The first episode after `current` the viewer has **not** watched. Nil when every one
  /// after it is watched — Up Next never offers a watched one (user's call, 2026-10-01).
  public func nextUnwatched(after current: Episode) -> Entry? {
    guard let index = entries.firstIndex(where: { $0.episode.id == current.id }) else { return nil }
    return stamped(entries.dropFirst(index + 1).first { !$0.state.isWatched })
  }

  // MARK: - Where the viewer is

  /// An episode started and not finished — first in reading order.
  public var inProgress: Entry? {
    entries.first { !$0.state.isWatched && $0.state.resumeFraction != nil }
  }

  /// The first episode not watched, from the start.
  public var firstUnwatched: Entry? {
    entries.first { !$0.state.isWatched }
  }

  /// The episode after the furthest one watched — skipped episodes before it stay skipped.
  public var afterFurthestWatched: Entry? {
    guard let furthest = entries.lastIndex(where: { $0.state.isWatched }) else {
      return entries.first
    }
    return entries.dropFirst(furthest + 1).first
  }

  /// **Where the viewer is in the series** — what Play opens and what Continue Watching
  /// offers: the first episode not watched; with everything watched, the first one again
  /// (Replay). The hero's behavior since it existed, kept as is until D17 is decided.
  ///
  /// TODO(decision) D17: with E1, E2, E4, E5 watched (E3 skipped) and E6 half-way, which is
  /// "where the viewer is"?
  /// - E3, the first unwatched — this, today, on the hero and on a card with details;
  /// - E6, the one in progress (`inProgress`) — what the viewer was last doing;
  /// - E6 also as "after the furthest watched" (`afterFurthestWatched`) — what a Continue
  ///   Watching card infers when it has no episode list (`ContinueWatchingEpisode.forSeries`).
  /// One answer here and the card's inference follows it.
  public var continueTarget: Entry? {
    firstUnwatched ?? entries.first
  }

  /// Every episode watched.
  public var isFinished: Bool {
    !entries.isEmpty && entries.allSatisfy(\.state.isWatched)
  }
}
