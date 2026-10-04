//
//  PlaybackButtonContent.swift
//

import Foundation

/// What the detail page's primary play control should show.
///
/// Prefer the resume case with a mini progress bar (same capsule as Continue
/// Watching cards). Season/episode are numbers — the UI formats them via
/// `MediaActionCopy` (`1 сезон, 2 серия` / `S1, E2`).
public enum PlaybackButtonContent: Equatable, Sendable {
  /// Mid-title: progress bar + episode label *or* remaining minutes (not both).
  case resume(progress: Double, season: Int?, episode: Int?, durationSeconds: Int)
  /// Fresh start, or the next unwatched episode after finishing a previous one.
  case play(season: Int?, episode: Int?)
  /// Fully watched. Series carry the episode Replay would reopen (usually S1E1).
  case playAgain(season: Int?, episode: Int?)
}

public extension MediaItem {
  /// Season + episode the primary button would open — `EpisodeQueue.continueTarget` (the
  /// episode touched last) on the payload's own word. The detail page's Play, Continue Watching with details and the
  /// card menu all read this.
  var primaryEpisode: (season: Season, episode: Episode)? {
    guard isSeries else { return nil }
    return EpisodeQueue(series: self).continueTarget.map { ($0.season, $0.episode) }
  }

  var playbackButtonContent: PlaybackButtonContent {
    if playbackAction == .playAgain {
      if let (season, episode) = primaryEpisode {
        return .playAgain(season: season.number, episode: episode.number)
      }
      return .playAgain(season: nil, episode: nil)
    }

    if isSeries {
      guard let (season, episode) = primaryEpisode else {
        return .play(season: nil, episode: nil)
      }
      if let progress = Self.progress(watched: episode.watched,
                                      time: episode.watching.time,
                                      duration: episode.duration) {
        return .resume(progress: progress,
                       season: season.number,
                       episode: episode.number,
                       durationSeconds: episode.duration)
      }
      return .play(season: season.number, episode: episode.number)
    }

    guard let video = videos?.first else { return .play(season: nil, episode: nil) }
    if let progress = Self.progress(watched: video.watched,
                                    time: video.watching.time,
                                    duration: video.duration) {
      return .resume(progress: progress,
                     season: nil,
                     episode: nil,
                     durationSeconds: video.duration)
    }
    return .play(season: nil, episode: nil)
  }

  static func progress(watched: Int, time: Int, duration: Int) -> Double? {
    guard watched == 0 else { return nil }
    let watch = WatchProgress(position: Double(time), duration: Double(duration))
    return watch.resumeFraction
  }
}

public extension PlaybackVariant {
  /// The same three states as the film's own button, for this one version — its own
  /// position, never its sibling's. Two versions are two buttons on the detail page,
  /// and each says how far into *that* version you are.
  var playbackButtonContent: PlaybackButtonContent {
    if video.isWatched { return .playAgain(season: nil, episode: nil) }
    if let progress = MediaItem.progress(watched: video.watched,
                                         time: video.watching.time,
                                         duration: video.duration) {
      return .resume(progress: progress, season: nil, episode: nil, durationSeconds: video.duration)
    }
    return .play(season: nil, episode: nil)
  }
}
