//
//  TitleInfoStripFacts.swift
//  KinoPubAppleClient
//
//  Shared title-page upper strip facts — hero and the synopsis modal use the same
//  blocks, genres and capability chips (Sasha, 2026-11-25).
//

import SwiftUI
import KinoPubBackend
import KinoPubMedia
import KinoPubMetadata
import KinoPubUI

/// Text blocks and badges for the title info strip / matching modal line.
enum TitleInfoStripFacts {

  /// Kind / years / volume / genres / country — same wording as the hero facts line.
  /// `genreLimit` nil → every useful genre (kino.pub returns a handful; do not truncate
  /// when they fit — Sasha, 2026-11-25).
  static func textBlocks(
    mediaItem: MediaItem,
    metadata: TitleMetadata,
    genreLimit: Int? = nil,
    showsPlace: Bool = true,
    dropsSeriesKind: Bool = false
  ) -> [String] {
    let card = MediaCard(mediaItem)
    let profile = mediaItem.presentation
    let isSeries = mediaItem.isSeries
    var blocks: [String] = []

    let kindKey = profile.kindTitleKey(isSeries: isSeries)
    let dropsKind = kindKey == "Kind_movies_One" || (dropsSeriesKind && isSeries)
    let kind = dropsKind ? nil : kindKey.localized
    let years = isSeries
      ? SeriesFacts.heroYears(mediaItem, metadata, fallbackSpan: card.bannerYearSpan)
      : (mediaItem.year > 0 ? String(mediaItem.year) : nil)
    let statusKey = isSeries ? SeriesFacts.shortStatusKey(mediaItem, metadata) : nil
    let status = statusKey?.localized
    let statusJoins = statusKey != "MediaItem_StatusReturningShort"
    let head = [kind, years, statusJoins ? status : nil].compactMap { $0 }
    if !head.isEmpty { blocks.append(head.joined(separator: " ")) }
    if !statusJoins, let status { blocks.append(status) }

    if isSeries {
      let seasons = mediaItem.seasons ?? []
      let episodes = seasons.reduce(0) { $0 + $1.episodes.count }
      if seasons.count > 1, let text = SeasonCountText(seasons.count)?.formatted() {
        blocks.append(text)
      } else if let text = EpisodesLeftText(episodes)?.formatted() {
        blocks.append(text)
      }
    }

    let restated = kind == nil ? [] : Set(card.genres.filter { profile.kindGenreIDs.contains($0.id) }
      .map { $0.name.value(languageCode: MediaLanguage.current.rawValue) })
    let ask = (genreLimit ?? 24) + restated.count
    var genres = card.usefulGenres(limit: ask,
                                   omittingDocumentary: kind != nil && profile.kind == .documentary)
      .filter { !restated.contains($0) }
    if let genreLimit {
      genres = Array(genres.prefix(genreLimit))
    }
    let place = showsPlace
      ? mediaItem.countryNames.first.flatMap { $0.isEmpty ? nil : $0 }
      : nil
    let placeLeads = profile.kind == .concert
    if placeLeads, let place { blocks.append(place) }
    if let first = genres.first {
      let rest = genres.dropFirst().map { $0.lowercased() }
      blocks.append(([first] + rest).joined(separator: ", "))
    }
    if !placeLeads, let place { blocks.append(place) }
    return blocks
  }

  /// How many useful genres the strip can name (after kind-restated filtering).
  static func usefulGenreCount(mediaItem: MediaItem) -> Int {
    let card = MediaCard(mediaItem)
    let profile = mediaItem.presentation
    let kindKey = profile.kindTitleKey(isSeries: mediaItem.isSeries)
    let dropsKind = kindKey == "Kind_movies_One"
    let kind = dropsKind ? nil : kindKey.localized
    let restated = kind == nil ? [] : Set(card.genres.filter { profile.kindGenreIDs.contains($0.id) }
      .map { $0.name.value(languageCode: MediaLanguage.current.rawValue) })
    return card.usefulGenres(limit: 24 + restated.count,
                             omittingDocumentary: kind != nil && profile.kind == .documentary)
      .filter { !restated.contains($0) }
      .count
  }

  /// Quality marks the playback strip shows (4K / HD / …), when the pref is on.
  static func qualityBadgeAssets(mediaItem: MediaItem) -> [String] {
    guard MediaItemDisplayPreferences.showQualityBadges else { return [] }
    return MediaCapabilityBadges.from(item: mediaItem).detailBadgeAssets
  }
}

/// Drawn age marks for the strip / modal — local then foreign when both apply.
struct TitleInfoStripAgeBadges: View {
  let ratings: [String]

  var body: some View {
    let assets = ratings.compactMap(MediaBadgeImages.ageRatingAssetName)
    let typed = ratings.filter { MediaBadgeImages.ageRatingAssetName($0) == nil }
    if !assets.isEmpty || !typed.isEmpty {
      HStack(spacing: MediaCapabilityBadgesView.spacing) {
        if !assets.isEmpty {
          MediaBadgeImages(assets)
        }
        ForEach(typed, id: \.self) { rating in
          Text(verbatim: rating)
            .lineLimit(1)
        }
      }
    }
  }
}
