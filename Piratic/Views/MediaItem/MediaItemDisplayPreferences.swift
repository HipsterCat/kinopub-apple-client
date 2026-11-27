//
//  MediaItemDisplayPreferences.swift
//  Piratic
//
//  Title-page upper info strip chrome (playback / facts meta line). Settings › Details › Info.
//

import Foundation

/// What the title page paints on the upper info strip — quality, voicing, captions, age.
/// Catalog card chrome stays in `MediaCardDisplayPreferences` (Appearance).
enum MediaItemDisplayPreferences {

  static let showAgeRatingBadgeKey = "showAgeRatingBadge"
  static let showForeignAgeRatingKey = "settings.details.infoStrip.showForeignAgeRating"
  static let convertAgeRatingKey = "settings.details.infoStrip.convertAgeRating"
  static let showQualityBadgesKey = "settings.details.infoStrip.showQualityBadges"
  static let showVoicingBadgesKey = "settings.details.infoStrip.showVoicingBadges"
  static let showCaptionsBadgeKey = "settings.details.infoStrip.showCaptionsBadge"

  /// Certification chip(s) on the upper info strip. Default on — off hid R/16+ entirely
  /// (Sasha, 2026-11-25). Still listed in the information table when off.
  static var showAgeRatingBadge: Bool {
    bool(forKey: showAgeRatingBadgeKey, default: true)
  }

  /// Keep the MPA / TV foreign mark (R, PG-13…). With convert on, that is the *second*
  /// chip beside the local age; with convert off it is the only chip for a foreign source.
  static var showForeignAgeRating: Bool {
    bool(forKey: showForeignAgeRatingKey, default: true)
  }

  /// Map MPA / TV Parental Guidelines to a Russian-style age («16+») when we can.
  /// With foreign also on, both chips show (16+ and R).
  static var convertAgeRatingToLocal: Bool {
    bool(forKey: convertAgeRatingKey, default: true)
  }

  /// 4K / HD / SD / 3D on the upper strip.
  static var showQualityBadges: Bool {
    bool(forKey: showQualityBadgesKey, default: true)
  }

  /// DUB / MVO / VO mark beside the languages.
  static var showVoicingBadges: Bool {
    bool(forKey: showVoicingBadgesKey, default: true)
  }

  /// Closed-captions mark when the title has subtitles the viewer reads.
  static var showCaptionsBadge: Bool {
    bool(forKey: showCaptionsBadgeKey, default: true)
  }

  /// Certifications for the upper strip / matching modal, after prefs.
  /// Order: local age first («16+»), then foreign («R») when both apply. Empty → nothing.
  static func ageRatingsForInfoStrip(_ raw: String?) -> [String] {
    guard showAgeRatingBadge else { return [] }
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
      return []
    }

    if !AgeRatingPresentation.isForeign(raw) {
      return [AgeRatingPresentation.localEquivalent(raw) ?? raw]
    }

    var ratings: [String] = []
    if convertAgeRatingToLocal, let local = AgeRatingPresentation.localEquivalent(raw) {
      ratings.append(local)
    }
    if showForeignAgeRating {
      let already = ratings.contains { AgeRatingPresentation.same($0, raw) }
      if !already { ratings.append(raw) }
    }
    return ratings
  }

  /// First strip rating, for call sites that still take one string.
  static func ageRatingForInfoStrip(_ raw: String?) -> String? {
    ageRatingsForInfoStrip(raw).first
  }

  private static func bool(forKey key: String, default defaultValue: Bool) -> Bool {
    UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
  }
}

/// Foreign certification → local age ladder helpers for the info strip.
enum AgeRatingPresentation {
  /// MPA / TV / AU codes — anything that is not already a plain «N+» age.
  static func isForeign(_ rating: String) -> Bool {
    let key = normalize(rating)
    if key.hasSuffix("+"), key.dropLast().allSatisfy(\.isNumber) { return false }
    if key.allSatisfy(\.isNumber) { return false }
    return true
  }

  /// Best-effort map to a Russian-style age. Nil when we have no mapping.
  static func localEquivalent(_ rating: String) -> String? {
    let key = normalize(rating)
    if let direct = localByKey[key] { return direct }
    if key.hasSuffix("+"), key.dropLast().allSatisfy(\.isNumber) {
      return "\(key.dropLast())+"
    }
    if key.allSatisfy(\.isNumber) { return "\(key)+" }
    return nil
  }

  static func same(_ lhs: String, _ rhs: String) -> Bool {
    normalize(lhs) == normalize(rhs)
  }

  private static func normalize(_ rating: String) -> String {
    let bare = rating.split(separator: "/").last.map(String.init) ?? rating
    return bare.uppercased().filter { $0 != " " && $0 != "_" }
  }

  private static let localByKey: [String: String] = [
    // MPA
    "G": "0+", "PG": "6+", "PG-13": "12+", "PG13": "12+",
    "R": "16+", "NC-17": "18+", "NC17": "18+", "X": "18+",
    "NR": "18+", "NOTRATED": "18+", "UNRATED": "18+",
    // US TV
    "TV-Y": "0+", "TVY": "0+",
    "TV-Y7": "6+", "TVY7": "6+",
    "TV-G": "0+", "TVG": "0+",
    "TV-PG": "12+", "TVPG": "12+",
    "TV-14": "16+", "TV14": "16+",
    "TV-MA": "18+", "TVMA": "18+",
    // Australia
    "M": "12+", "MA": "16+", "MA15+": "16+", "MA15": "16+",
  ]
}
