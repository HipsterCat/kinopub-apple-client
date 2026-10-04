//
//  MediaActionCopy.swift
//  KinoPubUI
//
//  Human labels for media action controls. See `docs/product/media-actions.md`.
//

import Foundation
import KinoPubBackend

public enum MediaActionCopy {

  /// Compact episode id for mid-title (progress bar present): RU `1 сезон, 2 серия` · EN `S1, E2`.
  public static func episodeLabel(season: Int, episode: Int) -> String {
    let format = localizedFormat("MediaAction_SeasonEpisode",
                                 fallback: "S%lld, E%lld")
    return String(format: format, locale: .current, Int64(season), Int64(episode))
  }

  /// Fresh Play on an unwatched episode — EN includes the verb (`Play S1, E1`);
  /// RU is the full episode phrase alone (`1 сезон, 1 серия`). Compact `S1, E1`
  /// without a verb is only for the resume capsule (progress bar).
  public static func playEpisodeTitle(season: Int, episode: Int) -> String {
    let format = localizedFormat("MediaAction_PlayEpisode",
                                 fallback: "Play S%lld, E%lld")
    return String(format: format, locale: .current, Int64(season), Int64(episode))
  }

  /// Replay capsule title — EN `Replay S1, E1`; RU keeps the episode phrase (↻ is the glyph).
  public static func replayEpisodeTitle(season: Int, episode: Int) -> String {
    let format = localizedFormat("MediaAction_ReplayEpisode",
                                 fallback: "Replay S%lld, E%lld")
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

  /// A version's play pill: kino.pub's name for it when there is one ("24 fps"), else
  /// «Смотреть» for the first and «Вторая версия» for the second.
  public static func versionTitle(name: String?, index: Int) -> String {
    if let name, !name.isEmpty { return name }
    return index == 0
      ? localizedFormat("Watch", fallback: "Watch")
      : localizedFormat("MediaAction_SecondVersion", fallback: "Second Version")
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
        let title = playEpisodeTitle(season: season, episode: episode)
        return (title, nil, title)
      }
      let title = playTitle(kind: kind)
      return (title, nil, title)

    case .resume(let progress, let season, let episode, let durationSeconds):
      if let season, let episode {
        // Progress bar is showing — compact episode only, no Play/Resume verb.
        let title = episodeLabel(season: season, episode: episode)
        return (title, progress, localized("Resume") + " " + title)
      }
      let title = remainingLabel(progress: progress, durationSeconds: durationSeconds)
      return (title, progress, title)

    case .playAgain(let season, let episode):
      if let season, let episode {
        let title = replayEpisodeTitle(season: season, episode: episode)
        return (title, nil, title)
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
