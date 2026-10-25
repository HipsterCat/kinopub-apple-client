//
//  KinoPubBilingualTitle.swift
//  KinoPubBackend
//
//  kino.pub lists titles as `Localized / Original`. Only that spaced slash
//  separates languages — bare `/` appears inside names (`9/11`, dates, …).
//

import Foundation

enum KinoPubBilingualTitle {
  static let catalogSeparator = " / "

  static func parts(from fullTitle: String) -> (localized: String, original: String) {
    guard let range = fullTitle.range(of: catalogSeparator) else {
      let trimmed = fullTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      return (trimmed, trimmed)
    }
    let localized = String(fullTitle[..<range.lowerBound])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let original = String(fullTitle[range.upperBound...])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return (localized, original)
  }

  static func hasSeparateOriginal(_ fullTitle: String) -> Bool {
    fullTitle.contains(catalogSeparator)
  }
}
