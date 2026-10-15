//
//  PlaybackEpisodes.swift
//  KinoPubAppleClient
//
//  The tvOS player's **Episodes** / **Серии** Info tab: the same kino.pub seasons and
//  episode cells the series detail page draws, current season selected. Movies have none.
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

  /// Season pills + one rail of every episode, the same `TVSeasonRail` the title page
  /// uses. One season is not a choice — the line says which and nothing is focusable.
  func seasonRail(onSelect: @escaping (Int) -> Void) -> TVSeasonRail {
    let tabs = seasons.map { group in
      TVSeasonTab(id: group.id,
                  label: "\(group.displayNumber)",
                  symbol: nil,
                  isAvailable: true,
                  accessibilityLabel: String(format: "MediaItem_SeasonSingle".localized,
                                             group.displayNumber))
    }
    var items: [TVUIKitMediaItem] = []
    var tabOfItem: [Int: Int] = [:]
    var entryByTab: [Int: Int] = [:]
    for group in seasons {
      let season = seasonByID[group.id]
      for id in group.episodeIDs {
        guard let episode = episodeByID[id] else { continue }
        items.append(Self.railItem(episode: episode, in: season))
        tabOfItem[id] = group.id
      }
      if group.id == selectedSeasonID {
        entryByTab[group.id] = openingEpisodeID
      } else {
        let firstUnseen = group.episodeIDs.first { episodeByID[$0]?.isWatched == false }
        entryByTab[group.id] = firstUnseen ?? group.episodeIDs.first
      }
    }
    let title: String
    if tabs.count == 1, let only = seasons.first {
      title = String(format: "MediaItem_SeasonSingle".localized, only.displayNumber)
    } else {
      title = "Season".localized
    }
    return TVSeasonRail(
      title: title,
      tabs: tabs,
      items: items,
      tabOfItem: tabOfItem,
      entryByTab: entryByTab,
      openingItemID: openingEpisodeID,
      contentInset: 0,
      // Home's still row, size and all — the title page's episode rail (Sasha, 2026-10-04).
      columns: MainView.stillColumns,
      onSelect: onSelect
    )
  }

  /// Same mapping as `SeasonsRailView.railItem` for a playable kino.pub episode.
  private static func railItem(episode: Episode, in season: Season?) -> TVUIKitMediaItem {
    let name = EpisodeTitle.meaningful(episode.title) ?? ""
    let card = MediaCard(episode: episode, in: season, title: name)
    let base = TVUIKitMediaItem(card: card)
    return TVUIKitMediaItem(id: episode.id,
                            imageURL: base.imageURL,
                            caption: EpisodeText(season: nil, number: episode.number, name: name)
                              .text(for: .episodeTile),
                            status: base.status,
                            timeLabel: base.timeLabel,
                            badgeText: base.badgeText)
  }
}

#endif
