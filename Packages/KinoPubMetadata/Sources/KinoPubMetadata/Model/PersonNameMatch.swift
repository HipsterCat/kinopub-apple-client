//
//  PersonNameMatch.swift
//
//  Closed-pool person-name scoring for kino.pub credit ↔ TMDB cast (~20).
//  Stage 1: normalize + rough latinize + Levenshtein + token prefix + bigrams.
//  `soundKey` covers RU phonetic fold; alias dictionaries stay a later stage.
//

import Foundation

public enum PersonNameMatch: Sendable {

  /// Minimum combined score (0…100) to accept a closed-pool hit.
  public static let acceptScore: Double = 72
  /// Winner must beat the runner-up by at least this many points.
  public static let acceptMargin: Double = 8

  public struct Ranked: Sendable, Hashable {
    public var index: Int
    public var score: Double
  }

  /// Best candidate in `candidates` for `query`, or `nil` below threshold / margin.
  ///
  /// `excluding` skips already-claimed pool rows as winners, but they still compete
  /// for the runner-up margin — so surname-only «Уилсон» stays ambiguous after one
  /// Wilson was matched, instead of collapsing onto the leftover sibling.
  public static func bestIndex(
    query: String,
    in candidates: [String],
    excluding: Set<Int> = []
  ) -> Ranked? {
    pickBest(scores: candidates.map { score(query, $0) }, excluding: excluding)
  }

  /// Pick the best unused index from precomputed per-candidate scores.
  public static func pickBest(scores: [Double], excluding: Set<Int> = []) -> Ranked? {
    var best: Ranked?
    for (index, value) in scores.enumerated() where !excluding.contains(index) {
      if let current = best {
        if value > current.score {
          best = Ranked(index: index, score: value)
        }
      } else {
        best = Ranked(index: index, score: value)
      }
    }
    guard let hit = best, hit.score >= acceptScore else { return nil }
    let second = scores.enumerated()
      .filter { $0.offset != hit.index }
      .map(\.element)
      .max() ?? 0
    guard hit.score - second >= acceptMargin else { return nil }
    return hit
  }

  /// Combined score 0…100. Suitable for small closed pools only.
  public static func score(_ a: String, _ b: String) -> Double {
    let qa = tokens(a)
    let qb = tokens(b)
    guard !qa.isEmpty, !qb.isEmpty else { return 0 }

    let full = tokenSetRatio(qa.joined(separator: " "), qb.joined(separator: " "))
    let surname = tokenScore(qa[qa.count - 1], qb[qb.count - 1])

    let givenA = Array(qa.dropLast())
    let givenB = Array(qb.dropLast())
    let given: Double
    if givenA.isEmpty && givenB.isEmpty {
      given = 100
    } else if givenA.isEmpty || givenB.isEmpty {
      // One side missing a given name — soft penalty, surname still carries.
      given = 70
    } else {
      var used = Set<Int>()
      var parts: [Double] = []
      for token in givenA {
        var best: (Double, Int) = (-1, -1)
        for (index, other) in givenB.enumerated() where !used.contains(index) {
          let value = tokenScore(token, other)
          if value > best.0 { best = (value, index) }
        }
        if best.1 >= 0 {
          used.insert(best.1)
          parts.append(best.0)
        } else {
          parts.append(0)
        }
      }
      given = parts.reduce(0, +) / Double(parts.count)
    }

    let grams = bigramJaccard(qa.joined(), qb.joined())
    var total = 0.35 * full + 0.35 * surname + 0.20 * given + 0.10 * grams
    // Matching credit initials (С.↔C.) are a strong closed-pool signal; a clash
    // (С. vs K.) should not win the other Hall.
    total += initialAdjustment(givenA, givenB)
    return min(100, max(0, total))
  }

  /// +15 when both sides share an exact single-letter initial; −20 when both have
  /// initials and none match (Майкл С. must not accept Michael K.).
  private static func initialAdjustment(_ givenA: [String], _ givenB: [String]) -> Double {
    let ia = givenA.filter { $0.count == 1 }
    let ib = givenB.filter { $0.count == 1 }
    guard !ia.isEmpty, !ib.isEmpty else { return 0 }
    var used = Set<Int>()
    var matched = 0
    for token in ia {
      if let index = ib.enumerated().first(where: { !used.contains($0.offset) && $0.element == token })?.offset {
        used.insert(index)
        matched += 1
      }
    }
    if matched > 0 { return 15 }
    return -20
  }

  // MARK: - Tokens / normalize

  /// Letters-only latin comparison form: diacritics off, `ё`→`е`, Cyrillic roughly latinized,
  /// hyphens/spaces collapsed. Not a Kinopoisk table — enough for closed-pool fuzzy.
  public static func latinKey(_ name: String) -> String {
    tokens(name).joined(separator: " ")
  }

  static func tokens(_ name: String) -> [String] {
    let folded = name
      .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
      .lowercased()
      .replacingOccurrences(of: "ё", with: "е")
    var buffered = ""
    var origins: [UnicodeScalar] = []
    var out: [String] = []
    func flush() {
      guard !buffered.isEmpty else { return }
      // Lone Cyrillic initials mirror Latin *glyphs* (С. → C, not phonetic /s/).
      if origins.count == 1, let initial = initialLatinize(origins[0]) {
        out.append(String(Character(initial)))
      } else {
        out.append(buffered)
      }
      buffered = ""
      origins.removeAll(keepingCapacity: true)
    }
    for scalar in folded.unicodeScalars {
      if scalar == "ъ" || scalar == "ь" { continue }
      if let mapped = latinize(scalar) {
        buffered.append(Character(mapped))
        origins.append(scalar)
      } else if scalar == "-" || CharacterSet.whitespacesAndNewlines.contains(scalar) {
        flush()
      }
      // other punctuation dropped
    }
    flush()
    return out
  }

  /// Rough RU→LAT letter, or the scalar itself for Latin/digits. `nil` = separator/skip.
  private static func latinize(_ scalar: UnicodeScalar) -> UnicodeScalar? {
    // Digraphs collapsed to one letter — bigrams + `soundKey` cover the rest.
    switch scalar {
    case "а": return "a"
    case "б": return "b"
    case "в": return "v"
    case "г": return "g"
    case "д": return "d"
    case "е", "э": return "e"
    case "ж", "з": return "z"
    case "и", "й", "ы": return "i"
    case "к": return "k"
    case "л": return "l"
    case "м": return "m"
    case "н": return "n"
    case "о": return "o"
    case "п": return "p"
    case "р": return "r"
    case "с": return "s"
    case "т": return "t"
    case "у": return "u"
    case "ф": return "f"
    case "х": return "h"
    case "ц": return "t"
    case "ч": return "c"
    case "ш", "щ": return "s"
    case "ю": return "u"
    case "я": return "a"
    default:
      if CharacterSet.alphanumerics.contains(scalar) { return scalar }
      return nil
    }
  }

  /// Single-letter Cyrillic credit initials as Latin letters (Майкл С. ↔ Michael C.).
  private static func initialLatinize(_ scalar: UnicodeScalar) -> UnicodeScalar? {
    switch scalar {
    case "с": return "c"
    case "к": return "k"
    case "а": return "a"
    case "в": return "v"
    case "е", "э": return "e"
    case "м": return "m"
    case "н": return "n"
    case "о": return "o"
    case "р": return "r"
    case "т": return "t"
    case "х": return "h"
    case "у": return "u"
    case "и": return "i"
    case "д": return "d"
    case "г": return "g"
    case "б": return "b"
    case "п": return "p"
    case "л": return "l"
    case "ф": return "f"
    case "з": return "z"
    case "ж": return "z"
    case "ч": return "c"
    case "ш", "щ": return "s"
    case "я": return "a"
    case "ю": return "u"
    case "ы", "й": return "y"
    default:
      return nil
    }
  }

  // MARK: - Distances

  static func tokenScore(_ a: String, _ b: String) -> Double {
    if a == b { return 100 }
    // Diminutives / truncations: Ray ↔ Raymond
    if a.hasPrefix(b) || b.hasPrefix(a) {
      let shorter = a.count <= b.count ? a : b
      let longer = a.count <= b.count ? b : a
      if shorter.count >= 2 {
        return 85 + 15 * (Double(shorter.count) / Double(longer.count))
      }
    }
    var ratio = levenshteinRatio(a, b)
    // RU phonetic fold (existing cast key) — equal keys boost.
    if TitleMetadata.soundKey(a) == TitleMetadata.soundKey(b),
       !TitleMetadata.soundKey(a).isEmpty {
      ratio = max(ratio, 90)
    }
    return ratio
  }

  /// 100 * (1 - dist / maxLen)
  static func levenshteinRatio(_ a: String, _ b: String) -> Double {
    if a == b { return 100 }
    if a.isEmpty || b.isEmpty { return 0 }
    let aa = Array(a), bb = Array(b)
    let n = aa.count, m = bb.count
    var prev = Array(0...m)
    var cur = Array(repeating: 0, count: m + 1)
    for i in 1...n {
      cur[0] = i
      for j in 1...m {
        let cost = aa[i - 1] == bb[j - 1] ? 0 : 1
        cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
      }
      prev = cur
    }
    let dist = prev[m]
    return 100 * (1 - Double(dist) / Double(max(n, m)))
  }

  /// RapidFuzz-style token set ratio on already-tokenized latin strings joined by space.
  static func tokenSetRatio(_ a: String, _ b: String) -> Double {
    let sa = Set(a.split(separator: " ").map(String.init))
    let sb = Set(b.split(separator: " ").map(String.init))
    if sa.isEmpty || sb.isEmpty { return 0 }
    let inter = sa.intersection(sb).sorted().joined(separator: " ")
    let aRest = sa.subtracting(sb).sorted().joined(separator: " ")
    let bRest = sb.subtracting(sa).sorted().joined(separator: " ")
    let combinedA = [inter, aRest].filter { !$0.isEmpty }.joined(separator: " ")
    let combinedB = [inter, bRest].filter { !$0.isEmpty }.joined(separator: " ")
    let r1 = levenshteinRatio(inter.isEmpty ? a : combinedA, inter.isEmpty ? b : combinedB)
    let r2 = levenshteinRatio(a, b)
    return max(r1, r2)
  }

  static func bigramJaccard(_ a: String, _ b: String) -> Double {
    let ga = bigrams(a), gb = bigrams(b)
    guard !ga.isEmpty, !gb.isEmpty else { return 0 }
    let inter = ga.intersection(gb).count
    let union = ga.union(gb).count
    return 100 * Double(inter) / Double(union)
  }

  private static func bigrams(_ s: String) -> Set<String> {
    let chars = Array(s)
    guard chars.count >= 2 else { return chars.isEmpty ? [] : [String(chars)] }
    var out = Set<String>()
    for i in 0..<(chars.count - 1) {
      out.insert(String(chars[i...i + 1]))
    }
    return out
  }
}
