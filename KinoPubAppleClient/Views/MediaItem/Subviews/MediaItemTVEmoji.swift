#if os(tvOS)
//
//  MediaItemTVEmoji.swift
//  KinoPubAppleClient
//
//  The small marks in front of the detail page's pills and language rows: a flag before a
//  country or a language, a glyph before a genre — emoji, drawn as text in the pill's own
//  title, the same way a collection's mark rides in a chip's title in the section gallery,
//  so a pill is still a plain system button with a plain title. A *type* is the exception
//  (Sasha, 2026-10-06): it wears an SF Symbol (`TypeSymbol`), the pill's own image.
//
//  Tables, not logic: kino.pub numbers its countries and genres (`filter.countries`,
//  `filter.genres` of `kpapp.link/config.json`, kept as a test fixture), and a title the
//  table does not know simply has no mark.
//

import Foundation

enum Emoji {

  /// "🇺🇸 США" — the mark, a space, the words; the words alone when there is no mark.
  static func decorated(_ emoji: String?, _ title: String) -> String {
    emoji.map { "\($0) \(title)" } ?? title
  }

  // MARK: Flags

  /// The flag for an ISO 3166-1 alpha-2 code: its two letters as regional indicators.
  static func flag(isoCode code: String) -> String? {
    let letters = code.uppercased().unicodeScalars
    guard letters.count == 2, letters.allSatisfy({ $0.value >= 0x41 && $0.value <= 0x5A }) else { return nil }
    var flag = ""
    for letter in letters {
      guard let scalar = Unicode.Scalar(0x1F1E6 + letter.value - 0x41) else { return nil }
      flag.unicodeScalars.append(scalar)
    }
    return flag
  }

  /// kino.pub's country id → flag. The Soviet Union, Czechoslovakia and Yugoslavia have no
  /// emoji; Scotland's is a tag sequence rather than a pair of letters.
  static func flag(countryID id: Int) -> String? {
    if id == 91 { return "🏴󠁧󠁢󠁳󠁣󠁴󠁿" }
    return countryCodes[id].flatMap { flag(isoCode: $0) }
  }

  private static let countryCodes: [Int: String] = [
    10: "AU", 16: "AT", 79: "AZ", 82: "AL", 89: "DZ", 41: "AR", 55: "AM", 69: "AF", 70: "BS",
    47: "BY", 27: "BE", 42: "BG", 78: "BO", 81: "BA", 71: "BW", 50: "BR", 83: "BF", 5: "GB",
    32: "HU", 67: "VE", 66: "VN", 88: "GH", 4: "DE", 17: "HK", 65: "GR", 56: "GE", 21: "DK",
    72: "EG", 24: "IL", 38: "IN", 49: "ID", 39: "IR", 20: "IE", 40: "IS", 9: "ES", 19: "IT",
    64: "KZ", 14: "CA", 87: "CY", 6: "CN", 98: "CO", 97: "CR", 43: "CU", 94: "KW", 44: "LV",
    93: "LB", 92: "LY", 45: "LT", 25: "LU", 95: "MR", 77: "MG", 53: "MK", 48: "MY", 90: "MT",
    86: "MA", 18: "MX", 73: "MD", 99: "MN", 100: "NP", 112: "NG", 11: "NL", 15: "NZ", 12: "NO",
    63: "AE", 84: "PK", 96: "PA", 74: "PE", 13: "PL", 85: "PT", 2: "RU", 33: "RO", 75: "SA",
    80: "KP", 51: "RS", 29: "SG", 76: "SK", 31: "SI", 1: "US", 36: "TH", 68: "TW", 59: "TN",
    30: "TR", 106: "UZ", 23: "UA", 60: "UY", 57: "PH", 37: "FI", 8: "FR", 35: "HR", 52: "ME",
    62: "CZ", 58: "CL", 26: "CH", 22: "SE", 46: "EE", 28: "ZA", 34: "KR", 7: "JP"
  ]

  /// A language's flag — approximate and deliberately so: a language is not a country, and
  /// English has no one flag. The pick is the one the viewer expects beside the word.
  static func languageFlag(_ key: String) -> String? {
    languageRegions[key.lowercased()].flatMap { flag(isoCode: $0) }
  }

  private static let languageRegions: [String: String] = [
    "en": "US", "ru": "RU", "uk": "UA", "de": "DE", "fr": "FR", "es": "ES", "it": "IT",
    "pt": "PT", "pl": "PL", "tr": "TR", "ja": "JP", "ko": "KR", "zh": "CN", "cs": "CZ",
    "sv": "SE", "nl": "NL", "fi": "FI", "hu": "HU", "ro": "RO", "bg": "BG", "el": "GR",
    "he": "IL", "ar": "SA", "hi": "IN", "th": "TH", "vi": "VN", "id": "ID", "kk": "KZ",
    "be": "BY", "ka": "GE", "hy": "AM", "az": "AZ", "lt": "LT", "lv": "LV", "et": "EE",
    "hr": "HR", "sr": "RS", "sk": "SK", "sl": "SI", "uz": "UZ", "da": "DK", "no": "NO",
    "is": "IS", "fa": "IR", "ms": "MY", "fil": "PH", "ca": "ES", "mn": "MN", "ne": "NP"
  ]

  // MARK: Genres

  /// kino.pub's film genres by id (`filter.genres.movie`); its documentary, TV-show and
  /// music sets are not marked.
  static func genre(id: Int) -> String? {
    genreMarks[id]
  }

  private static let genreMarks: [Int: String] = [
    25: "🎌", 3: "📖", 2: "💥", 14: "🤠", 116: "🎭", 15: "🪖", 13: "🕵️", 24: "🎥",
    107: "💫", 9: "🎭", 18: "🏛", 1: "😂", 26: "⏱", 17: "🚨", 10: "❤️", 11: "🔮",
    19: "🎵", 23: "🧸", 105: "🎩", 8: "🏕", 6: "👨‍👩‍👧", 27: "🎟", 20: "⚽", 101: "🎤",
    7: "😱", 12: "👻", 4: "🧬", 5: "🧙"
  ]
}

/// The SF Symbol in front of a title's type — Movie, Series, Concert — in the pill that
/// opens the catalogue narrowed to it. Every kind has one: a type pill without a mark
/// would be the odd one out beside the flags and genre marks.
enum TypeSymbol {
  static func name(for raw: String) -> String {
    switch raw {
    case "movie": return "film"
    case "serial": return "tv"
    case "3D": return "view.3d"
    case "concert": return "music.mic"
    case "documovie": return "film.stack"
    case "docuserial": return "tv.and.mediabox"
    case "tvshow": return "sparkles.tv"
    default: return "play.rectangle"
    }
  }

  /// Every type kino.pub has, for the test that every symbol above exists on the system.
  static let known = ["movie", "serial", "3D", "concert", "documovie", "docuserial", "tvshow"]
}
#endif
