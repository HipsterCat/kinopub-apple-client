//
//  MediaPerson+CastMember.swift
//  Piratic
//
//  Build a MediaPerson for catalog navigation from a CastMember that may carry
//  both a localized display name and an English / original spelling.
//

import Foundation
import KinoPubBackend
import PiraticMetadata

extension MediaPerson {
  /// Display keeps `member.name`; catalog queries try every known spelling so a
  /// TMDB-localized «Майки Мэдисон» still finds Kinopub credits under another form.
  static func from(_ member: CastMember,
                   role: Role,
                   photoURL: URL? = nil,
                   sourceItemID: Int? = nil) -> MediaPerson {
    var catalog: [String] = [member.name]
    if let localized = member.localizedName { catalog.append(localized) }
    // When TMDB put Russian in `name` and English in `localizedName`, prefer English
    // first for the Kinopub query — Kinopub's Russian transliteration often differs
    // from TMDB's, while the Latin form is stable. enrich() already put the kino.pub
    // spelling in `name` for listed cast, so that stays first.
    if let localized = member.localizedName,
       member.name.containsCyrillic,
       localized.containsLatinLetters,
       !localized.containsCyrillic {
      catalog = [localized, member.name]
    }
    return MediaPerson(
      name: member.name,
      role: role,
      photoURL: photoURL ?? member.photo,
      tmdbPersonId: member.tmdbPersonId,
      catalogNames: catalog,
      sourceItemID: sourceItemID
    )
  }
}

private extension String {
  var containsCyrillic: Bool {
    contains { ("А"..."я").contains($0) || $0 == "ё" || $0 == "Ё" }
  }

  var containsLatinLetters: Bool {
    contains { ("A"..."Z").contains($0) || ("a"..."z").contains($0) }
  }
}
