//
//  NextPlayableEpisode.swift
//
//

import Foundation

/// The episode after `current`, in watching order: the next number in the same
/// season, else the first of the season after.
///
/// Pure model work — it feeds the tvOS system's Up Next panel (`AVContentProposal`),
/// which needs the answer when the stream is prepared and must never trigger a fetch.
public enum NextPlayableEpisode {

  /// - Parameters:
  ///   - current: the episode playing now.
  ///   - series: the cached series payload (a `LocalWatchProgressStore` snapshot).
  ///     Nil or seasonless means no proposal — never a guess.
  @available(*, deprecated, message: "Use EpisodeQueue(series:).next(after:).")
  public static func after(_ current: Episode, in series: MediaItem?) -> Episode? {
    EpisodeQueue(series: series).next(after: current)?.episode
  }
}
