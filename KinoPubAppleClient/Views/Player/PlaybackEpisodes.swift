//
//  PlaybackEpisodes.swift
//  KinoPubAppleClient
//
//  The tvOS player's **Season N** / **Сезон N** Info tab: the season playing, in the same
//  episode cells the series detail page draws. Movies have none.
//

import Foundation
import KinoPubBackend
#if os(tvOS)
import SwiftUI
import KinoPubMedia
import KinoPubUI
#endif

/// The series episode list the player Info strip can show. Nil for a film, a trailer,
/// or a series payload with no seasons yet.
struct PlaybackEpisodes {

  struct SeasonGroup: Equatable {
    let id: Int
    let number: Int
    let displayNumber: Int
    let episodeIDs: [Int]
  }

  let seriesID: Int
  let seasons: [SeasonGroup]
  let openingEpisodeID: Int
  /// The episode on screen — its tile wears the now-playing look.
  let playingEpisodeID: Int
  let selectedSeasonID: Int
  /// Stamped playable episodes, keyed by id — Select on a tile plays this object.
  let episodeByID: [Int: Episode]
  let seasonByID: [Int: Season]

  /// - Parameters:
  ///   - playing: what is on screen. Only an `Episode` produces a list.
  ///   - series: the title payload with seasons. Empty or missing seasons → nil.
  init?(playing: any PlayableItem, series: MediaItem?) {
    guard let episode = playing as? Episode,
          let series,
          let raw = series.seasons, !raw.isEmpty else { return nil }
    raw.forEach { $0.mediaId = series.id }
    let seasons = raw.sorted { $0.number < $1.number }
    var episodeByID: [Int: Episode] = [:]
    var seasonByID: [Int: Season] = [:]
    var groups: [SeasonGroup] = []
    for season in seasons {
      seasonByID[season.id] = season
      let ordered = season.episodes.sorted { $0.number < $1.number }
      for item in ordered {
        item.seasonNumber = season.number
        item.mediaId = series.id
        item.seriesTitle = series.localizedTitle
        episodeByID[item.id] = item
      }
      groups.append(SeasonGroup(id: season.id,
                                number: season.number,
                                displayNumber: KinoPubMediaMapping.seasonNumber(season),
                                episodeIDs: ordered.map(\.id)))
    }
    guard !episodeByID.isEmpty else { return nil }
    let selected = groups.first { $0.episodeIDs.contains(episode.id) }
      ?? groups.first { $0.number == episode.seasonNumber }
      ?? groups.first
    guard let selected else { return nil }
    let openingID = selected.episodeIDs.contains(episode.id)
      ? episode.id
      : (selected.episodeIDs.first ?? episode.id)
    self.seriesID = series.id
    self.seasons = groups
    self.openingEpisodeID = openingID
    self.playingEpisodeID = episode.id
    self.selectedSeasonID = selected.id
    self.episodeByID = episodeByID
    self.seasonByID = seasonByID
  }

  /// Tab / rail identity so a rebuild with the same episodes does not replace a tab
  /// the viewer may be standing in.
  var signature: [String] {
    [String(openingEpisodeID), String(selectedSeasonID)]
      + seasons.flatMap { ["s\($0.id)"] + $0.episodeIDs.map(String.init) }
  }
}

#if os(tvOS)

extension PlaybackEpisodes {

  /// The tab's name: the season playing, «Сезон 2» — the tab holds that season alone.
  var seasonTitle: String {
    let number = seasons.first { $0.id == selectedSeasonID }?.displayNumber ?? 1
    return String(format: "MediaItem_SeasonSingle".localized, number)
  }

  /// The season playing, as the tiles of one rail — the same cells the title page's
  /// episode rail draws. Other seasons are on the title page; the player's strip keeps
  /// one season so the tab is one row, as tall as Up Next (Sasha, 2026-10-20).
  ///
  /// Watched and part-watched come from `viewer`, not the payload: the series snapshot is
  /// the one cached when the player opened, so after auto-play has gone through episodes
  /// 2–4 its flags still say only episode 1 was seen. This device's progress records each
  /// of them as it plays, and the tab is built afresh for every episode the player swaps
  /// in — so it is read once per episode, with nothing recounted while one plays.
  @MainActor
  func seasonItems(viewer: ViewerStateReading) -> [TVUIKitMediaItem] {
    guard let group = seasons.first(where: { $0.id == selectedSeasonID }) else { return [] }
    let season = seasonByID[group.id]
    return group.episodeIDs.compactMap { id in
      guard let episode = episodeByID[id] else { return nil }
      let state = viewer.state(for: .episode(seriesID, season: group.number, number: episode.number),
                               reported: ViewerState(reportedBy: episode))
      return Self.railItem(episode: episode, in: season, state: state,
                           isNowPlaying: id == playingEpisodeID)
    }
  }

  /// Same mapping as `SeasonsRailView.railItem` for a playable kino.pub episode, its
  /// watched state from `state`.
  private static func railItem(episode: Episode, in season: Season?, state: ViewerState,
                               isNowPlaying: Bool) -> TVUIKitMediaItem {
    let name = EpisodeTitle.meaningful(episode.title) ?? ""
    let card = MediaCard(episode: episode, in: season, title: name)
    let base = TVUIKitMediaItem(card: card)
    let status: TVUIKitMediaItemStatus = state.isWatched
      ? .watched
      : state.resumeFraction.map { .inProgress($0) } ?? .ready
    return TVUIKitMediaItem(id: episode.id,
                            imageURL: base.imageURL,
                            caption: EpisodeText(season: nil, number: episode.number, name: name)
                              .text(for: .episodeTile),
                            status: status,
                            // The tile on screen shows no bar, so it shows the runtime.
                            timeLabel: TVUIKitMediaItem.timeLabel(for: card,
                                                                  status: isNowPlaying ? .ready : status),
                            badgeText: base.badgeText,
                            isNowPlaying: isNowPlaying)
  }
}

#endif
