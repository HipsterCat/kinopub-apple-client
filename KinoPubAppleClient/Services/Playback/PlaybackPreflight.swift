//
//  PlaybackPreflight.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend
import KinoPubLogging
import OSLog

/// **What a surface can know about playback before the player exists.**
///
/// Two jobs, and they are the same subject seen from either side of a tap:
///
/// - *Which dub and subtitles will this open with.* `TrackResolver` is pure and takes a
///   menu, so the answer does not need a player — a card, a Play button or a diagnostics
///   screen can ask for it while drawing. The player asks the same way, so nothing can
///   disagree with what actually plays.
/// - *Have the links ready before they are needed.* A series episode arrives without them
///   and the player fetches `/v1/items/media-links` on open, which is dead time the viewer
///   spends looking at a spinner. Warming it while the detail page is on screen moves that
///   request out of the tap.
///
/// Warming is safe to call repeatedly: `MediaLinksResolver` runs one request per media id
/// however many callers ask, and `Episode` is a class, so a filled one is filled for
/// everybody already holding it.
@MainActor
final class PlaybackPreflight {

  static let shared = PlaybackPreflight()

  private let preferences: TrackPreferenceStore
  private let contentServiceOverride: VideoContentService?

  /// The content service is resolved when it is first needed rather than held, so asking
  /// what a title would play never builds the app context. That matters for a test, which
  /// wants the decision without a network stack behind it.
  private var contentService: VideoContentService {
    contentServiceOverride ?? AppContext.shared.contentService
  }

  init(preferences: TrackPreferenceStore = AppContext.shared.trackPreferences,
       contentService: VideoContentService? = nil) {
    self.preferences = preferences
    self.contentServiceOverride = contentService
  }

  // MARK: - Knowing

  /// The scopes this item's history lives under. `WatchingMetadata.id` is the **series**
  /// for an episode, so the title scope is the series either way.
  ///
  /// Empty for an unresolved item: a preference stored under id 0 would pool every such
  /// title into one bucket.
  func scopes(for item: any PlayableItem, profile: TitleTrackProfile) -> [TrackMemoryScope] {
    guard item.metadata.isResolved else { return [] }
    return TrackMemoryScope.chain(titleID: item.metadata.id,
                                  season: item.metadata.season,
                                  episode: item.metadata.video,
                                  isAnime: profile.isAnime)
  }

  /// Which tracks this would open with, from what is already loaded. No network, so it is
  /// safe to call while drawing.
  ///
  /// The player passes its own `audioMenu` because it can see the real renditions — which
  /// is the better menu when the API gave no track metadata. Everyone else gets the API's.
  func decision(for item: any PlayableItem,
                profile: TitleTrackProfile,
                audioMenu: [AudioTrackInfo]? = nil,
                subtitles: [SubtitleTrack]? = nil) -> TrackDecision {
    TrackResolver.resolve(audio: audioMenu ?? item.audioTracks,
                          subtitles: subtitles ?? SubtitleTracks.catalog(item.subtitles),
                          ledgers: preferences.ledgers(for: scopes(for: item, profile: profile)),
                          settings: PlaybackLanguagePreferences.current,
                          profile: profile)
  }

  /// The dub this would play, as a label — "Русский ∙ Дубляж, LostFilm".
  ///
  /// `nil` when there is nothing worth saying: no tracks, or a single one, where naming it
  /// tells the viewer nothing they can act on.
  func audioSummary(for item: any PlayableItem, profile: TitleTrackProfile) -> String? {
    guard item.audioTracks.count > 1,
          let track = decision(for: item, profile: profile).audio else { return nil }
    return AudioTracks.baseLabel(track)
  }

  // MARK: - Warming

  /// Fetch what playing this item will need, before it is asked for.
  ///
  /// A no-op for anything that already has a playable link, so calling it on every render
  /// costs nothing. Failures are deliberately silent — this is an optimisation, and the
  /// player still does its own resolve and still owns reporting a stream it cannot play.
  func warm(_ item: any PlayableItem) async {
    guard let episode = item as? Episode else { return }
    guard !episode.files.hasPlayableURLs else { return }
    let filled = await MediaLinksResolver.shared.fill(episode, using: contentService)
    Logger.app.debug("preflight warmed episode \(episode.id) playable=\(filled)")
  }
}
