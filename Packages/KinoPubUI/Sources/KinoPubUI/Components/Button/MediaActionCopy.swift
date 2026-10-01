//
//  MediaActionCopy.swift
//  KinoPubUI
//
//  Human labels for media action controls. Numbers come from
//  `PlaybackButtonContent`; this is the only place that turns them into
//  `1 сезон, 2 серия` / `34 мин` / `Смотреть фильм`. See
//  `docs/product/media-actions.md`.
//

import Foundation
import KinoPubBackend

public enum MediaActionCopy {

  /// `1 сезон, 2 серия` / `Season 1, Episode 2`. Never `S1, E2`.
  public static func episodeLabel(season: Int, episode: Int) -> String {
    let format = localizedFormat("MediaAction_SeasonEpisode",
                                 fallback: "Season %lld, Episode %lld")
    return String(format: format, locale: .current, Int64(season), Int64(episode))
  }

  /// Remaining (or total when progress is unknown) minutes: `34 мин` / `34 min`.
  public static func minutesLabel(seconds: Int) -> String {
    let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
    let format = localizedFormat("MediaAction_Minutes", fallback: "%lld min")
    return String(format: format, locale: .current, Int64(minutes))
  }

  /// Remaining time from a resume progress fraction.
  public static func remainingMinutesLabel(progress: Double, durationSeconds: Int) -> String {
    let clamped = min(max(progress, 0), 1)
    let remaining = Int((Double(durationSeconds) * (1.0 - clamped)).rounded())
    return minutesLabel(seconds: max(60, remaining))
  }

  /// Fresh Play on a non-episodic title — kind-specific. Series use `episodeLabel` instead.
  public static func playTitle(kind: MediaPresentationKind) -> String {
    switch kind {
    case .concert:
      return localized("Watch Concert")
    case .documentary:
      return localized("Watch Documentary")
    case .standup, .show:
      return localized("Play")
    case .fiction, .animation:
      return localized("Watch Movie")
    }
  }

  /// Primary play capsule title for a given playback state + presentation kind.
  public static func playCaption(
    playback: PlaybackButtonContent,
    kind: MediaPresentationKind
  ) -> (title: String, progress: Double?, accessibility: String) {
    switch playback {
    case .play(let season, let episode):
      if let season, let episode {
        let title = episodeLabel(season: season, episode: episode)
        return (title, nil, localized("Play") + " " + title)
      }
      let title = playTitle(kind: kind)
      return (title, nil, title)

    case .resume(let progress, let season, let episode, let durationSeconds):
      if let season, let episode {
        let title = episodeLabel(season: season, episode: episode)
        return (title, progress, localized("Resume") + " " + title)
      }
      let title = remainingMinutesLabel(progress: progress, durationSeconds: durationSeconds)
      return (title, progress, localized("Resume") + " " + title)

    case .playAgain:
      let title = localized("Play Again")
      return (title, nil, title)
    }
  }

  static func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
  }

  /// Prefer the app catalogue; fall back so package tests still produce English copy.
  private static func localizedFormat(_ key: String, fallback: String) -> String {
    let value = NSLocalizedString(key, comment: "")
    return value == key ? fallback : value
  }
}
