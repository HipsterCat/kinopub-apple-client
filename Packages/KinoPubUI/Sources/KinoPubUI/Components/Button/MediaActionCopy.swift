//
//  MediaActionCopy.swift
//  KinoPubUI
//
//  Human labels for media action controls. See `docs/product/media-actions.md`.
//

import Foundation
import KinoPubBackend
import KinoPubMedia

public enum MediaActionCopy {

  /// Compact episode id for mid-title (progress bar present): RU `1 сезон, 2 серия` · EN
  /// `S1, E2` — `EpisodeText` at the hero's length.
  /// TODO(decision): the hero is not told the season count, so a show with only its first
  /// season still says the season here.
  public static func episodeLabel(season: Int, episode: Int) -> String {
    EpisodeText(season: season, number: episode).text(for: .heroAction)
  }

  /// What VoiceOver reads for the same episode: «Season 1, Episode 2».
  public static func episodeAccessibilityLabel(season: Int, episode: Int) -> String {
    EpisodeText(season: season, number: episode).accessibilityLabel()
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

  /// Time left at the hero's length: `Ещё 53 мин` / `53 min left` (`RemainingText`).
  public static func remainingLabel(progress: Double, durationSeconds: Int) -> String {
    RemainingText(progress: progress, durationSeconds: durationSeconds)
      .formatted(MediaSurface.heroAction.runtimeLength)
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

  /// A menu item does, where the hero's capsule says what is: «Отслеживать» / «Не
  /// отслеживать». Series only.
  public static func followMenuTitle(isFollowing: Bool) -> String {
    isFollowing ? localized("Stop Tracking") : localized("Track")
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
        let spoken = episodeAccessibilityLabel(season: season, episode: episode)
        return (title, progress, localized("Resume") + " " + spoken)
      }
      let remaining = RemainingText(progress: progress, durationSeconds: durationSeconds)
      return (remaining.formatted(MediaSurface.heroAction.runtimeLength), progress,
              remaining.accessibilityLabel())

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
