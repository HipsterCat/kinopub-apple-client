//
//  PlaybackMediaContext.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend
import KinoPubMedia
import KinoPubMetadata

/// **What is playing, in our media model** — where the player's sources meet.
///
/// The player hands over the item and the title it belongs to, and gets back fragments:
/// kino.pub's at once (`draft`), the enrichment sources' after one round trip of calls the
/// detail page has usually cached already (`enrich`). Which source wins a field is
/// `MediaPrecedence`'s decision and what an episode borrows from its show is
/// `MediaContext`'s; this only knows which source to ask about which level.
///
/// App-side because it is the one piece that needs every source package at once. When
/// our own `/v1/title` document carries seasons and episodes, `enrich` becomes one call.
enum PlaybackMediaContext {

  /// Where the enrichment sources' answers attach. Read off the playing item while it is
  /// at hand, so nothing but Sendable values crosses into the async half.
  struct Enrichment: Sendable {
    struct EpisodeKey: Sendable, Equatable {
      /// kino.pub's block number, and the number in the block's name — TMDB matching
      /// needs both (`TMDBSeasonMatch`).
      let kinoSeason: Int
      let titleSeason: Int?
      let number: Int
    }

    let title: MediaItem
    /// Whether the title describes the item's parent (an episode's show, a trailer's
    /// film) rather than the item itself (a film, one of its editions).
    let titleIsParent: Bool
    let episode: EpisodeKey?
  }

  /// Everything kino.pub already told us. No network.
  static func draft(playing item: any PlayableItem, title: MediaItem?,
                    isTrailer: Bool) -> MediaContextDraft {
    if !isTrailer, let download = item as? DownloadMeta {
      return draft(download: download, title: title)
    }
    return KinoPubMediaMapping.draft(playing: item, title: title, isTrailer: isTrailer)
  }

  /// Nil when there is nothing to ask: TMDB is reached through the IMDb id, and a title
  /// without one gets no enrichment at all (known defect 1 in the `metadata-service` skill).
  static func enrichment(playing item: any PlayableItem, title: MediaItem?,
                         isTrailer: Bool) -> Enrichment? {
    guard let title, (title.imdb ?? 0) > 0 else { return nil }
    var key: Enrichment.EpisodeKey?
    if !isTrailer, let episode = item as? Episode {
      let season = KinoPubMediaMapping.seasonContaining(episode, in: title)
      if let kinoSeason = season?.number ?? episode.seasonNumber {
        key = Enrichment.EpisodeKey(kinoSeason: kinoSeason,
                                    titleSeason: season?.titleSeasonNumber,
                                    number: episode.number)
      }
    }
    let isEpisodeDownload = (item as? DownloadMeta)?.episode != nil
    return Enrichment(title: title,
                      titleIsParent: isTrailer || item is Episode || isEpisodeDownload,
                      episode: key)
  }

  /// Adds what TMDB knows about the title, the season and the episode itself.
  static func enrich(_ draft: MediaContextDraft, with enrichment: Enrichment,
                     service: MetadataService) async -> MediaContextDraft {
    var draft = draft
    let identity = MediaIdentity(mediaItem: enrichment.title)
    let meta = await service.metadata(for: identity)
    let kind = KinoPubMediaMapping.typeMapping(enrichment.title.type,
                                               hasSeasons: enrichment.title.isSeries).kind
    let titleFragment = meta.mediaFragment(kind: kind)
    if enrichment.titleIsParent {
      draft.parent.append(titleFragment)
    } else {
      draft.item.append(titleFragment)
    }

    guard let episode = enrichment.episode,
          let tmdbSeason = TMDBSeasonMatch.tmdbSeason(
            kinoNumber: episode.kinoSeason,
            titleNumber: episode.titleSeason,
            tmdbSeasons: Set(meta.seasonSummaries.map(\.seasonNumber)))
    else { return draft }

    if let season = meta.seasonFragment(number: tmdbSeason) {
      draft.season.append(season)
    }
    let schedule = await service.schedule(for: identity, season: tmdbSeason)
    if let match = schedule.first(where: { $0.episodeNumber == episode.number }) {
      draft.item.append(match.mediaFragment)
    }
    return draft
  }

  /// The words `PlayerInfo` needs, in the app's language: "Сезон 2, Серия 5".
  static var labels: PlayerInfo.Labels {
    let season = String(localized: "Season")
    let episode = String(localized: "Episode")
    let trailer = String(localized: "Trailer")
    return PlayerInfo.Labels(
      languageCode: Bundle.main.preferredLocalizations.first,
      episode: { seasonNumber, number in
        seasonNumber.map { "\(season) \($0), \(episode) \(number)" } ?? "\(episode) \(number)"
      },
      extra: { kind in kind == .trailer ? trailer : nil })
  }

  // MARK: - Downloads

  /// A download carries a name, a poster and an "S4E4" marker — the rest comes from the
  /// title when it is still cached.
  private static func draft(download: DownloadMeta, title: MediaItem?) -> MediaContextDraft {
    let poster = ArtworkSet.url(download.imageUrl)
    let titleFragments = title.map { [$0.mediaFragment] } ?? []
    guard let marker = download.episode, let numbers = episodeNumbers(marker) else {
      let movie = MediaFragment(.kinopub, .movie) { entity in
        entity.title = download.localizedTitle
        entity.artwork.poster = poster
      }
      return MediaContextDraft(item: [movie] + titleFragments)
    }
    let episode = MediaFragment(.kinopub, .episode) { entity in
      entity.seasonNumber = numbers.season
      entity.episodeNumber = numbers.episode
    }
    let show = MediaFragment(.kinopub, .show) { entity in
      entity.title = download.localizedTitle
      entity.artwork.poster = poster
    }
    return MediaContextDraft(item: [episode], parent: [show] + titleFragments)
  }

  /// "S4E4", the marker `MediaItem.downloadableItems` saves episodes under.
  static func episodeNumbers(_ marker: String) -> (season: Int, episode: Int)? {
    let numbers = marker.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    guard numbers.count == 2 else { return nil }
    return (numbers[0], numbers[1])
  }
}
