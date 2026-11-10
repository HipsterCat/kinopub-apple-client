//
//  CastRanking.swift
//  KinoPubAppleClient
//
//  Who is worth a card on the cast rail / Featured tab — shared by the SwiftUI rail
//  and the tvOS page sections.
//

import Foundation
import KinoPubMetadata

enum CastRanking {
  /// The most people the cast row holds. A billing runs to dozens; past a dozen it is a
  /// list of names nobody is looking for.
  static let castLimit = 12

  /// Who is worth a card, the most important first — "sort the stars by episodes or
  /// popularity and drop the insignificant" (Sasha, 2026-10-06).
  ///
  /// A series ranks by how many of its episodes a person is in (TMDB's aggregate credits). A
  /// film keeps kino.pub's own list order and only uses TMDB billing to drop bit parts
  /// (`order >= castLimit`). Reordering a film by billing is what put Jason Statham tenth
  /// in *Mutiny* and an unknown ahead of Bondarchuk in *Трудно быть богом*. kino.pub's order
  /// also stands in for a title TMDB has nothing on. In a series, someone in fewer than a
  /// fifth of the episodes the most-seen person is in — and never fewer than two, once
  /// anyone has more than one — is a guest and is dropped; so is everything past `castLimit`.
  ///
  /// **Except the first of kino.pub's own list, who is never dropped** (Sasha, 2026-10-11):
  /// that is the lead, and a name TMDB could not match (no episode count) was dropped as a
  /// guest — Dexter's own Dexter. If ranking would have left them out they open the row.
  static func ranked(_ members: [CastMember], isEpisodic: Bool) -> [CastMember] {
    let ranked = ranking(members, isEpisodic: isEpisodic)
    guard let lead = members.first, !ranked.contains(where: { $0.name == lead.name }) else { return ranked }
    return [lead] + ranked.prefix(castLimit - 1)
  }

  private static func ranking(_ members: [CastMember], isEpisodic: Bool) -> [CastMember] {
    var ranked = Array(members.enumerated())
    let most = members.compactMap(\.episodeCount).max() ?? 0
    if isEpisodic, most > 0 {
      let floor = most > 1 ? max(2, Int((Double(most) * 0.2).rounded(.up))) : 1
      ranked = ranked.filter { ($0.element.episodeCount ?? 0) >= floor }
      ranked.sort { lhs, rhs in
        let (left, right) = (lhs.element, rhs.element)
        if (left.episodeCount ?? 0) != (right.episodeCount ?? 0) {
          return (left.episodeCount ?? 0) > (right.episodeCount ?? 0)
        }
        if (left.order ?? .max) != (right.order ?? .max) {
          return (left.order ?? .max) < (right.order ?? .max)
        }
        return lhs.offset < rhs.offset
      }
    } else if members.contains(where: { $0.order != nil }) {
      ranked = ranked.filter { ($0.element.order ?? 0) < castLimit }
    }
    return ranked.prefix(castLimit).map(\.element)
  }
}
