import Foundation

/// **How long something runs**, at three lengths (user's spec, 2026-10-03):
///
/// | Length | ru | en |
/// | --- | --- | --- |
/// | short | `1ч 53м` · `53м` | `1h 53m` · `53m` |
/// | medium | `1ч 53 мин` · `53 мин` | `1h 53 min` · `53 min` |
/// | long | `1 час 53 минуты` | `1 hour, 53 minutes` |
///
/// **Long is the system's own** (`Duration.UnitsFormatStyle`, wide): plural forms and word
/// order are Foundation's, per locale, and it is what VoiceOver reads for every length.
/// Short and medium are ours, because no system width writes «1ч 53м».
///
/// Rounded to the minute; anything under a minute is one. Past a day, short and medium
/// count days too (`1д 12ч 4м`) — a whole series end to end.
public struct RuntimeText: Hashable, Sendable {
  public let seconds: Int

  public init(seconds: Int) {
    self.seconds = seconds
  }

  public init(seconds: Double) {
    self.seconds = seconds.isFinite ? Int(seconds.rounded()) : 0
  }

  /// Whole minutes, at least one. Zero only when there is no runtime at all.
  public var minutes: Int {
    guard seconds > 0 else { return 0 }
    return max(1, Int((Double(seconds) / 60).rounded()))
  }

  /// Nil when there is no runtime — better an empty slot than «0м».
  public func formatted(_ length: TextLength, language: MediaLanguage = .current) -> String? {
    guard minutes > 0 else { return nil }
    if length == .long { return system(language) }
    let days = minutes / (60 * 24)
    let hours = minutes % (60 * 24) / 60
    let rest = minutes % 60
    let unit = Self.units(language)
    var parts: [String] = []
    if days > 0 { parts.append("\(days)\(unit.day)") }
    if hours > 0 { parts.append("\(hours)\(unit.hour)") }
    if rest > 0 || parts.isEmpty {
      parts.append("\(rest)\(length == .short ? unit.shortMinute : unit.mediumMinute)")
    }
    return parts.joined(separator: " ")
  }

  /// Only minutes, however many: «105 мин» — the parenthesised total beside `1ч 45м`.
  public func minutesOnly(language: MediaLanguage = .current) -> String? {
    guard minutes > 0 else { return nil }
    return "\(minutes)\(Self.units(language).mediumMinute)"
  }

  /// What VoiceOver reads, whatever the screen shows.
  public func accessibilityLabel(language: MediaLanguage = .current) -> String? {
    formatted(.long, language: language)
  }

  public func text(for surface: MediaSurface, language: MediaLanguage = .current) -> String? {
    formatted(surface.runtimeLength, language: language)
  }

  private func system(_ language: MediaLanguage) -> String {
    let style = Swift.Duration.UnitsFormatStyle(allowedUnits: [.hours, .minutes], width: .wide)
      .locale(language.locale)
    return Swift.Duration.seconds(minutes * 60).formatted(style)
  }

  private static func units(_ language: MediaLanguage)
    -> (day: String, hour: String, shortMinute: String, mediumMinute: String) {
    switch language {
    case .ru: return ("д", "ч", "м", " мин")
    case .en: return ("d", "h", "m", " min")
    }
  }
}

/// **Time left** in something started: «Ещё 53 мин» / «53 min left».
public struct RemainingText: Hashable, Sendable {
  public let runtime: RuntimeText

  /// - Parameters:
  ///   - progress: 0…1, how far through. Clamped. At least a minute is always left.
  public init(progress: Double, durationSeconds: Int) {
    let clamped = min(max(progress, 0), 1)
    let left = Int((Double(durationSeconds) * (1 - clamped)).rounded())
    runtime = RuntimeText(seconds: max(60, left))
  }

  public func formatted(_ length: TextLength, language: MediaLanguage = .current) -> String {
    let time = runtime.formatted(length, language: language) ?? ""
    switch language {
    case .ru: return "Ещё \(time)"
    case .en: return "\(time) left"
    }
  }

  public func accessibilityLabel(language: MediaLanguage = .current) -> String {
    formatted(.long, language: language)
  }
}
