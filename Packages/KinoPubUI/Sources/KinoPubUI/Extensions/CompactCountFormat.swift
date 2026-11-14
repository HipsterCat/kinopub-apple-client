//
//  CompactCountFormat.swift
//  KinoPubUI
//
//  Short vote / view counts for score chips and detail tiles.
//  Always Latin `k` / `M` — never locale compact names (тыс. / млн).
//  Rounds; does not truncate (1_100_000 → "1.1M", not "1M").
//

import Foundation

public enum CompactCountFormat {

  /// Compact form for vote chips and similar: `999` · `1.2k` · `554.6k` · `1.1M` · `15.56M`.
  /// Thousands keep up to one decimal; millions up to two. Trailing zeros are dropped.
  public static func string(_ value: Int) -> String {
    guard value >= 0 else { return string(0) }
    switch value {
    case ..<1_000:
      return "\(value)"
    case ..<1_000_000:
      let thousands = Double(value) / 1_000
      let rounded = round(thousands, fractionDigits: 1)
      // 999_950… round to 1_000k — promote to millions.
      if rounded >= 1_000 {
        return format(Double(value) / 1_000_000, fractionDigits: 2) + "M"
      }
      return format(rounded, fractionDigits: 1) + "k"
    default:
      return format(Double(value) / 1_000_000, fractionDigits: 2) + "M"
    }
  }

  /// View counts on a score tile: full grouped number under 100_000, then `string(_:)`.
  public static func views(_ value: Int) -> String {
    guard value >= 0 else { return views(0) }
    if value < 100_000 {
      return value.formatted(.number.grouping(.automatic))
    }
    return string(value)
  }

  // MARK: - Private

  private static func round(_ value: Double, fractionDigits: Int) -> Double {
    let factor = pow(10.0, Double(fractionDigits))
    return (value * factor).rounded() / factor
  }

  private static func format(_ value: Double, fractionDigits: Int) -> String {
    let rounded = round(value, fractionDigits: fractionDigits)
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = fractionDigits
    return formatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
  }
}
