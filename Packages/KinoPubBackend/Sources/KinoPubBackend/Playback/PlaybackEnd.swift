//
//  PlaybackEnd.swift
//  KinoPubBackend
//
//  What happens when a stream reaches the end: dismiss, or play the next episode.
//  Policy comes from Settings; this type does not read UserDefaults.
//

import Foundation

/// The two Settings toggles that steer end-of-episode behaviour.
public struct PlaybackEndPolicy: Equatable, Sendable {
  /// Play the next episode in the same season. Default on.
  public var autoPlayNextEpisode: Bool
  /// Also play the first episode of the next season. Default off — end of a
  /// season dismisses, the same as end of a series, unless the viewer asks.
  public var autoPlayNextSeason: Bool

  public static let `default` = PlaybackEndPolicy(autoPlayNextEpisode: true,
                                                  autoPlayNextSeason: false)

  public init(autoPlayNextEpisode: Bool, autoPlayNextSeason: Bool) {
    self.autoPlayNextEpisode = autoPlayNextEpisode
    self.autoPlayNextSeason = autoPlayNextSeason
  }
}

/// The player either leaves or swaps in the next episode.
public enum PlaybackEndAction: Equatable {
  case dismiss
  case playNext(Episode)

  public static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.dismiss, .dismiss): return true
    case (.playNext(let a), .playNext(let b)): return a.id == b.id
    default: return false
    }
  }
}

/// Pure decision: given what is playing, the series payload, and the viewer's
/// Settings, what should the player do at the end of the stream.
public enum PlaybackEnd {

  /// Movies always dismiss. A series follows `policy`. A next episode that is
  /// missing from the payload, or listed with no files ladder, counts as
  /// unavailable and dismisses — we do not skip past it to a later season.
  public static func action(playing item: any PlayableItem,
                            series: MediaItem?,
                            policy: PlaybackEndPolicy) -> PlaybackEndAction {
    guard policy.autoPlayNextEpisode, let episode = item as? Episode else {
      return .dismiss
    }
    let queue = EpisodeQueue(series: series)
    if let sameSeason = queue.nextInSeason(after: episode) {
      return isAvailable(sameSeason.episode) ? .playNext(sameSeason.episode) : .dismiss
    }
    if policy.autoPlayNextSeason,
       let next = queue.next(after: episode),
       isAvailable(next.episode) {
      return .playNext(next.episode)
    }
    return .dismiss
  }

  /// Listed on kino.pub: a `nolinks=1` payload still names a files ladder, with
  /// no URLs yet. An empty ladder is nothing we can ask `media-links` for.
  private static func isAvailable(_ episode: Episode) -> Bool {
    !episode.files.isEmpty
  }
}
