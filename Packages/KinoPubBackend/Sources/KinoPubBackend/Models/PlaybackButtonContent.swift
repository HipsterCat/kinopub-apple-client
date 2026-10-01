//
//  PlaybackButtonContent.swift
//

import Foundation

/// What the detail page's primary play control should show.
///
/// Prefer the resume case with a mini progress bar (same capsule as Continue
/// Watching cards). Season/episode are numbers — the UI formats them as
/// `1 сезон, 2 серия` / `Season 1, Episode 2`, never `S1, E2`.
public enum PlaybackButtonContent: Equatable, Sendable {
  /// Mid-title: progress bar + episode label *or* remaining minutes (not both).
  case resume(progress: Double, season: Int?, episode: Int?, durationSeconds: Int)
  /// Fresh start, or the next unwatched episode after finishing a previous one.
  case play(season: Int?, episode: Int?)
  case playAgain
}

public extension MediaItem {
  /// Season + episode the primary button would open — first unfinished, else the first.
  var primaryEpisode: (season: Season, episode: Episode)? {
    guard isSeries, let seasons, !seasons.isEmpty else { return nil }
    for season in seasons {
      if let episode = season.episodes.first(where: { !$0.isWatched }) {
        return (season, episode)
      }
    }
    if let season = seasons.first, let episode = season.episodes.first {
      return (season, episode)
    }
    return nil
  }

  var playbackButtonContent: PlaybackButtonContent {
    if playbackAction == .playAgain { return .playAgain }

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

  private static func progress(watched: Int, time: Int, duration: Int) -> Double? {
    guard watched == 0 else { return nil }
    let watch = WatchProgress(position: Double(time), duration: Double(duration))
    return watch.resumeFraction
  }
}
