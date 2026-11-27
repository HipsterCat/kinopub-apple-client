//
//  CompactCountFormat.swift
//  PiraticUI
//
//  Short vote / view counts for score chips and detail tiles.
//  Always Latin `K` / `M` — never locale compact names (тыс. / млн).
//  Rounds; does not truncate (1_100_000 → "1.1M", not "1M").
//
//  Poster / hero rules (KP-33): under 10K keep up to one decimal; from 10K
//  whole thousands only (`10K`); from 1M up to two decimals (`1.45M`).
//

import Foundation

public enum CompactCountFormat {

  /// Compact form for vote chips and similar: `999` · `1.2K` · `10K` · `555K` · `1.1M` · `15.56M`.
  public static func string(_ value: Int) -> String {
    guard value >= 0 else { return string(0) }
    switch value {
    case ..<1_000:
      return "\(value)"
    case ..<10_000:
      let thousands = Double(value) / 1_000
      let rounded = round(thousands, fractionDigits: 1)
      // 9_950… → 10.0K — promote into the no-decimal band.
      if rounded >= 10 {
        return format(Double(value) / 1_000, fractionDigits: 0) + "K"
      }
      return format(rounded, fractionDigits: 1) + "K"
    case ..<1_000_000:
      let thousands = Double(value) / 1_000
      let rounded = round(thousands, fractionDigits: 0)
      // 999_500… → 1000K — promote to millions.
      if rounded >= 1_000 {
        return format(Double(value) / 1_000_000, fractionDigits: 2) + "M"
      }
      return format(rounded, fractionDigits: 0) + "K"
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
