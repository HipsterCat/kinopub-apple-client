//
//  PlaybackEpisodes.swift
//  KinoPubAppleClient
//
//  The tvOS player's **Season N** / **Сезон N** Info tab: the season playing, in the same
//  episode cells the series detail page draws. Movies have none.
//

import Foundation
import KinoPubBackend
import KinoPubMetadata
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

  /// The tab's name, the same for every series: «Серии» / «Episodes» (Sasha, 2026-10-21).
  var seasonTitle: String { "Episodes".localized }

  /// The kino.pub season number of the season playing — what a TMDB schedule is asked by.
  var selectedSeasonNumber: Int? {
    seasons.first { $0.id == selectedSeasonID }?.number
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
  ///
  /// `schedule` is TMDB's list for the season: the episodes it has that kino.pub has not
  /// uploaded stand in their place, with their date or a lock, as on the title page —
  /// shown, not playable (Sasha, 2026-10-21: the row looked empty without them).
  @MainActor
  func seasonItems(viewer: ViewerStateReading, schedule: [EpisodeSchedule] = []) -> [TVUIKitMediaItem] {
    guard let group = seasons.first(where: { $0.id == selectedSeasonID }) else { return [] }
    let season = seasonByID[group.id]
    var numbered: [(number: Int, item: TVUIKitMediaItem)] = group.episodeIDs.compactMap { id in
      guard let episode = episodeByID[id] else { return nil }
      let state = viewer.state(for: .episode(seriesID, season: group.number, number: episode.number),
                               reported: ViewerState(reportedBy: episode))
      return (episode.number, Self.railItem(episode: episode, in: season, state: state,
                                            isNowPlaying: id == playingEpisodeID))
    }
    let onKinoPub = Set(numbered.map(\.number))
    for announced in schedule where !onKinoPub.contains(announced.episodeNumber) {
      numbered.append((announced.episodeNumber, Self.announcedItem(announced, season: group.number)))
    }
    return numbered.sorted { $0.number < $1.number }.map(\.item)
  }

  /// Ids of tiles that are not kino.pub episodes — negative, so they never meet one.
  static func announcedID(season: Int, number: Int) -> Int { -(season * 1_000_000 + number) }

  /// An episode TMDB lists and kino.pub does not have, as `SeasonsRailView` draws it: its
  /// date in the corner while it is ahead, the lock once it has aired.
  @MainActor
  private static func announcedItem(_ schedule: EpisodeSchedule, season: Int) -> TVUIKitMediaItem {
    let status: TVUIKitMediaItemStatus = MissingEpisodeAirState(airDate: schedule.airDate)
      .badgeText.map { .upcoming($0) } ?? .locked
    return TVUIKitMediaItem(id: announcedID(season: season, number: schedule.episodeNumber),
                            imageURL: schedule.still,
                            caption: EpisodeText(season: nil, number: schedule.episodeNumber,
                                                 name: schedule.name)
                              .text(for: .episodeTile),
                            status: status)
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
