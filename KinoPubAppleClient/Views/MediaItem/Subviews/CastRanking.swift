//
//  CastRanking.swift
//  KinoPubAppleClient
//
//  Who is worth a card on the cast rail / «В главных ролях» — shared by the SwiftUI
//  rail and the tvOS page sections.
//

import Foundation
import KinoPubMetadata

enum CastRanking {
  /// How many cards the row fills up to. kino.pub's own list is never cut to it; the
  /// metadata worker's people only fill what kino.pub left (`ranked`).
  static let castLimit = 12

  /// The rail for a title: kino.pub's names enriched from the metadata worker, then the
  /// worker's people kino.pub did not name.
  static func rail(names: [String], metadata: TitleMetadata, isEpisodic: Bool) -> [CastMember] {
    let listed = TitleMetadata.enrich(names: names, roleDepartment: "Acting", from: metadata)
    return ranked(listed: listed, others: unlisted(metadata.cast, besides: listed), isEpisodic: isEpisodic)
  }

  /// Who is worth a card, in the order the row shows them (Sasha, 2026-11-24):
  ///
  /// 1. **everyone kino.pub lists, in kino.pub's order** — matched or not, a guest by episode
  ///    count or not. That list is what kino.pub's own «В ролях» shows; dropping a name from
  ///    it (an unmatched transliteration had no episode count and went as a guest) is what
  ///    left a 40-person series with two faces;
  /// 2. then the rest of the cast, up to `castLimit` in all: a series by how many episodes a
  ///    person is in, guests (under a fifth of the most-seen person's episodes, and never
  ///    fewer than two once anyone has more than one) left out; a film by TMDB billing, bit
  ///    parts (`order >= castLimit`) left out.
  ///
  /// Reordering kino.pub's list by billing is what once put Jason Statham tenth in *Mutiny*.
  static func ranked(listed: [CastMember], others: [CastMember], isEpisodic: Bool) -> [CastMember] {
    let room = max(0, castLimit - listed.count)
    guard room > 0 else { return listed }
    var fill = Array(others.enumerated())
    let most = (listed + others).compactMap(\.episodeCount).max() ?? 0
    if isEpisodic, most > 0 {
      let floor = most > 1 ? max(2, Int((Double(most) * 0.2).rounded(.up))) : 1
      fill = fill.filter { ($0.element.episodeCount ?? 0) >= floor }
      fill.sort { lhs, rhs in
        let (left, right) = (lhs.element, rhs.element)
        if (left.episodeCount ?? 0) != (right.episodeCount ?? 0) {
          return (left.episodeCount ?? 0) > (right.episodeCount ?? 0)
        }
        if (left.order ?? .max) != (right.order ?? .max) {
          return (left.order ?? .max) < (right.order ?? .max)
        }
        return lhs.offset < rhs.offset
      }
    } else {
      fill = fill.filter { ($0.element.order ?? .max) < castLimit }
      fill.sort { ($0.element.order ?? .max, $0.offset) < ($1.element.order ?? .max, $1.offset) }
    }
    return listed + fill.prefix(room).map(\.element)
  }

  /// The worker's cast without anyone `listed` already holds — by person id, or by name in
  /// either spelling — each person once.
  static func unlisted(_ cast: [CastMember], besides listed: [CastMember]) -> [CastMember] {
    var ids = Set(listed.compactMap(\.tmdbPersonId))
    var names = Set(listed.flatMap { [$0.name, $0.localizedName].compactMap { $0 } }.map(TitleMetadata.normalize))
    return cast.filter { member in
      if let id = member.tmdbPersonId, !ids.insert(id).inserted { return false }
      let spellings = [member.name, member.localizedName].compactMap { $0 }.map(TitleMetadata.normalize)
      guard spellings.allSatisfy({ !names.contains($0) }) else { return false }
      names.formUnion(spellings)
      return true
    }
  }
}
