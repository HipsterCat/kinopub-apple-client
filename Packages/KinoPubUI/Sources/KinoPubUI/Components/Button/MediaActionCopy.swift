//
//  MediaActionCopy.swift
//  KinoPubUI
//
//  Human labels for media action controls. See `docs/product/media-actions.md`.
//

import Foundation
import KinoPubBackend

public enum MediaActionCopy {

  /// RU `1 сезон, 2 серия` · EN `S1, E2`.
  public static func episodeLabel(season: Int, episode: Int) -> String {
    let format = localizedFormat("MediaAction_SeasonEpisode",
                                 fallback: "S%lld, E%lld")
    return String(format: format, locale: .current, Int64(season), Int64(episode))
  }

  /// Compact remaining runtime core: `53 мин` / `53m`, `1ч 24м` / `1h 24m`.
  public static func compactDuration(seconds: Int) -> String {
    let totalMinutes = max(1, Int((Double(seconds) / 60.0).rounded()))
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours == 0 {
      let format = localizedFormat("MediaAction_Minutes", fallback: "%lldm")
      return String(format: format, locale: .current, Int64(totalMinutes))
    }
    let format = localizedFormat("MediaAction_HoursMinutes",
                                 fallback: "%lldh %lldm")
    return String(format: format, locale: .current, Int64(hours), Int64(minutes))
  }

  /// `Ещё 53 мин` / `53 min left`.
  public static func remainingLabel(progress: Double, durationSeconds: Int) -> String {
    let clamped = min(max(progress, 0), 1)
    let remaining = max(60, Int((Double(durationSeconds) * (1.0 - clamped)).rounded()))
    let core = compactDuration(seconds: remaining)
    let format = localizedFormat("MediaAction_TimeLeft", fallback: "%@ left")
    return String(format: format, locale: .current, core)
  }

  /// Fresh Play on a non-episodic title.
  public static func playTitle(kind: MediaPresentationKind) -> String {
    switch kind {
    case .concert, .standup:
      let value = localized("MediaAction_WatchNow")
      return value == "MediaAction_WatchNow" ? "Watch Now" : value
    case .documentary, .fiction, .animation:
      return localized("Watch Movie")
    case .show:
      return localized("Play")
    }
  }

  public static func followTitle(isFollowing: Bool) -> String {
    isFollowing
      ? localized("Tracking")
      : localized("Track")
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
      let title = remainingLabel(progress: progress, durationSeconds: durationSeconds)
      return (title, progress, title)

    case .playAgain(let season, let episode):
      if let season, let episode {
        let title = episodeLabel(season: season, episode: episode)
        return (title, nil, localized("Play Again") + " " + title)
      }
      let title = localized("Play Again")
      return (title, nil, title)
    }
  }

  public static func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
  }

  private static func localizedFormat(_ key: String, fallback: String) -> String {
    let value = NSLocalizedString(key, comment: "")
    return value == key ? fallback : value
  }
}
