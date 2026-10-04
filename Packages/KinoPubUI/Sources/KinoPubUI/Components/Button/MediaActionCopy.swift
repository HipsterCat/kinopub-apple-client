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
  /// `seasonCount`: a show with only its first season says `E2` / `2 серия`.
  @available(*, deprecated, message: "Use EpisodeText(season:number:seasonCount:).text(for: .heroAction).")
  public static func episodeLabel(season: Int, episode: Int, seasonCount: Int? = nil) -> String {
    EpisodeText(season: season, number: episode, seasonCount: seasonCount).text(for: .heroAction)
  }

  /// What VoiceOver reads for the same episode: «Season 1, Episode 2».
  @available(*, deprecated, message: "Use EpisodeText(season:number:seasonCount:).accessibilityLabel().")
  public static func episodeAccessibilityLabel(season: Int, episode: Int,
                                               seasonCount: Int? = nil) -> String {
    EpisodeText(season: season, number: episode, seasonCount: seasonCount).accessibilityLabel()
  }

  /// Fresh Play on an unwatched episode — EN includes the verb (`Play S1, E1`);
  /// RU is the full episode phrase alone (`1 сезон, 1 серия`). Compact `S1, E1`
  /// without a verb is only for the resume capsule (progress bar).
  public static func playEpisodeTitle(season: Int, episode: Int, seasonCount: Int? = nil) -> String {
    let format = localizedFormat("MediaAction_PlayEpisodeRef", fallback: "Play %@")
    return String(format: format, reference(season, episode, seasonCount))
  }

  /// Replay capsule title — EN `Replay S1, E1`; RU keeps the episode phrase (↻ is the glyph).
  public static func replayEpisodeTitle(season: Int, episode: Int, seasonCount: Int? = nil) -> String {
    let format = localizedFormat("MediaAction_ReplayEpisodeRef", fallback: "Replay %@")
    return String(format: format, reference(season, episode, seasonCount))
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
    kind: MediaPresentationKind,
    seasonCount: Int? = nil
  ) -> (title: String, progress: Double?, accessibility: String) {
    switch playback {
    case .play(let season, let episode):
      if let season, let episode {
        let title = playEpisodeTitle(season: season, episode: episode, seasonCount: seasonCount)
        return (title, nil, title)
      }
      let title = playTitle(kind: kind)
      return (title, nil, title)

    case .resume(let progress, let season, let episode, let durationSeconds):
      if let season, let episode {
        // Progress bar is showing — compact episode only, no Play/Resume verb.
        let text = EpisodeText(season: season, number: episode, seasonCount: seasonCount)
        let title = text.text(for: .heroAction)
        let spoken = text.accessibilityLabel()
        return (title, progress, localized("Resume") + " " + spoken)
      }
      let remaining = RemainingText(progress: progress, durationSeconds: durationSeconds)
      return (remaining.formatted(MediaSurface.heroAction.runtimeLength), progress,
              remaining.accessibilityLabel())

    case .playAgain(let season, let episode):
      if let season, let episode {
        let title = replayEpisodeTitle(season: season, episode: episode, seasonCount: seasonCount)
        return (title, nil, title)
      }
      let title = localized("Play Again")
      return (title, nil, title)
    }
  }

  private static func reference(_ season: Int, _ episode: Int, _ seasonCount: Int?) -> String {
    EpisodeText(season: season, number: episode, seasonCount: seasonCount).text(for: .heroAction)
  }

  public static func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
  }

  private static func localizedFormat(_ key: String, fallback: String) -> String {
    let value = NSLocalizedString(key, comment: "")
    return value == key ? fallback : value
  }
}
