//
//  CoverArtwork.swift
//  KinoPubUI
//
//  Appearance › Covers and images. Unset, the choice follows the app language:
//  Russian → Russian covers, every other language → English. An explicit choice
//  stays put when the interface language changes.
//
//  "In Russian" replaces kino.pub's vertical covers when the title has a Kinopoisk
//  id. `big` and `medium` (what Apple TV asks for — about 667 pt wide) become
//  https://kinopoiskapiunofficial.tech/images/posters/kp/{id}.jpg (667×1000).
//  `small` becomes kp_small (360×540), and only a request that already asked for
//  small takes that file. Wide stills are a different picture and stay kino.pub's.
//  The stored poster URL stays the kino.pub one, so switching back does not need
//  a refetch.
//

import Foundation

public enum CoverArtworkLanguage: String, CaseIterable, Identifiable, Sendable {
  case english
  case russian

  public var id: String { rawValue }

  public var titleKey: String {
    switch self {
    case .english: return "In English"
    case .russian: return "In Russian"
    }
  }
}

public enum CoverArtworkPreferences {
  public static let languageKey = "appearance.coverLanguage"
  public static let didChange = Notification.Name("kinopub.coverArtworkLanguage")

  /// The stored choice, or the language default when the viewer has not picked.
  public static var language: CoverArtworkLanguage {
    if let raw = UserDefaults.standard.string(forKey: languageKey),
       let value = CoverArtworkLanguage(rawValue: raw) {
      return value
    }
    return inferredDefault
  }

  /// Russian interface → Russian covers. English and any other language → English.
  public static var inferredDefault: CoverArtworkLanguage {
    let code = UserDefaults.standard.string(forKey: "selectedLanguage")
      ?? Locale.current.language.languageCode?.identifier
      ?? "en"
    return code == "ru" ? .russian : .english
  }

  public static func set(_ language: CoverArtworkLanguage) {
    guard UserDefaults.standard.string(forKey: languageKey) != language.rawValue else { return }
    UserDefaults.standard.set(language.rawValue, forKey: languageKey)
    NotificationCenter.default.post(name: didChange, object: nil)
  }
}

public enum CoverArtwork {
  /// The Kinopoisk one-sheet for a kino.pub vertical cover, when Russian covers
  /// are on and `kinopoiskID` is a real id. Anything else — wide art, a missing
  /// id, English covers — comes back unchanged.
  public static func resolve(url: String, kinopoiskID: Int?) -> String {
    guard CoverArtworkPreferences.language == .russian,
          let kinopoiskID, kinopoiskID > 0,
          let tier = tier(ofKinopubPoster: url) else { return url }
    return kinopoiskURL(id: kinopoiskID, tier: tier)
  }

  /// `small` is the 360×540 file. `medium` and `big` are the 667×1000 file.
  public static func kinopoiskURL(id: Int, tier: Tier) -> String {
    let folder = tier == .small ? "kp_small" : "kp"
    return "https://kinopoiskapiunofficial.tech/images/posters/\(folder)/\(id).jpg"
  }

  public enum Tier {
    case regular
    case small
  }

  static func tier(ofKinopubPoster url: String) -> Tier? {
    if url.contains("/item/small/") { return .small }
    if url.contains("/item/medium/") || url.contains("/item/big/") { return .regular }
    return nil
  }
}

public extension MediaCard {
  /// Vertical cover to decode. Landscape cards keep `landscapeImageURL`.
  var coverURL: String {
    CoverArtwork.resolve(url: posterURL, kinopoiskID: kinopoiskID)
  }
}
