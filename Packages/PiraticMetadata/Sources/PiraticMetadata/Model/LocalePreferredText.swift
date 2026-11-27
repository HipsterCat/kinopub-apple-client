//
//  LocalePreferredText.swift
//  PiraticMetadata
//
//  Display strings for people and titles: always prefer RU↔EN (Cyrillic, then
//  Latin) over a primary original-script form (Korean Hangul, CJK, kana) when a
//  RU or EN spelling exists — Sasha, person page 2026-11-26.
//

import Foundation

public enum LocalePreferredText {
  /// First Cyrillic candidate, else first Latin (EN) candidate, else the first
  /// non-empty string. Original-script-only names stay only when nothing RU/EN
  /// was offered.
  public static func preferRuEn(_ candidates: [String]) -> String? {
    var seen = Set<String>()
    var list: [String] = []
    for raw in candidates {
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
      list.append(trimmed)
    }
    if let ru = list.first(where: { $0.containsCyrillic }) { return ru }
    if let en = list.first(where: { $0.isLatinScript }) { return en }
    return list.first
  }

  /// Localized (app language) → English → original, still demoting non-RU/EN
  /// scripts when a RU or EN form is present.
  public static func preferTitle(localized: String?,
                                 english: String?,
                                 original: String?) -> String? {
    preferRuEn([localized, english, original].compactMap { $0 })
  }
}

extension String {
  var containsCyrillic: Bool {
    unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
  }

  /// Hangul, CJK ideographs, hiragana, katakana — scripts we never lead with when
  /// a RU or EN spelling exists.
  var containsEastAsianScript: Bool {
    unicodeScalars.contains { scalar in
      let v = scalar.value
      return (0x1100...0x11FF).contains(v)   // Hangul Jamo
        || (0x3040...0x309F).contains(v)    // Hiragana
        || (0x30A0...0x30FF).contains(v)    // Katakana
        || (0x3130...0x318F).contains(v)    // Hangul Compatibility Jamo
        || (0xAC00...0xD7AF).contains(v)    // Hangul Syllables
        || (0x4E00...0x9FFF).contains(v)    // CJK Unified Ideographs
        || (0x3400...0x4DBF).contains(v)    // CJK Extension A
    }
  }

  /// Has Latin letters and no Cyrillic / East-Asian script.
  var isLatinScript: Bool {
    let hasLatin = unicodeScalars.contains {
      (0x0041...0x005A).contains($0.value) || (0x0061...0x007A).contains($0.value)
    }
    return hasLatin && !containsCyrillic && !containsEastAsianScript
  }
}
