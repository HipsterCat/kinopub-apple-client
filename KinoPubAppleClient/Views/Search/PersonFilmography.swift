//
//  PersonFilmography.swift
//  KinoPubAppleClient
//
//  Merge Kinopub person listings with TMDB combined_credits: titles missing from
//  the catalog stay visible as dimmed «Not on Kinopub» cards, keyed by TMDB id for
//  a later ID join.
//

import Foundation
import KinoPubBackend
import KinoPubMetadata
import KinoPubUI

enum PersonFilmography {
  /// Synthetic card ids stay outside kino.pub's positive item ids.
  private static let externalIDBase = -9_100_000

  /// TMDB credits that do not already appear in the Kinopub listing — matched by
  /// normalized title / original title for now; design toward TMDB↔Kinopub id join.
  static func externalCards(credits: [PersonCredit],
                            kinopubItems: [MediaItem],
                            role: MediaPerson.Role) -> [MediaCard] {
    let known = Set(kinopubItems.flatMap { item -> [String] in
      [item.title, item.originalTitle].compactMap {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }.map(normalize)
    }.filter { !$0.isEmpty })

    let acting = role == .actor
    var out: [MediaCard] = []
    for (offset, credit) in credits.enumerated() {
      if acting, credit.character == nil, credit.job != nil { continue }
      if !acting, credit.job == nil, credit.character != nil { continue }
      let titles = [credit.title, credit.originalTitle].compactMap { $0 }.map(normalize)
      if titles.contains(where: { known.contains($0) }) { continue }
      var card = MediaCard(
        id: externalIDBase - offset,
        posterURL: credit.posterURL?.absoluteString ?? "",
        title: credit.title,
        subtitle: credit.originalTitle,
        scores: MediaScores(tmdb: credit.voteAverage),
        isSeries: credit.mediaType == "tv",
        year: credit.year,
        primaryAction: .openDetail
      )
      card.unavailableNotice = String(localized: "Not on Kinopub")
      out.append(card)
    }
    return out
  }

  private static func normalize(_ title: String) -> String {
    title
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
