import Foundation

/// **How much room a surface gives a fact**, in one vocabulary for every formatter:
/// `EpisodeText`, `RuntimeText`, `SeasonText`. Which surface uses which length is
/// `MediaSurface`'s table — the one place to change it.
public enum TextLength: String, Hashable, Codable, Sendable, CaseIterable {
  /// A chip, a capsule, a corner: «S1, E1», «1ч 53м».
  case short
  /// A subtitle line: «S1, E1: Name», «1ч 53 мин».
  case medium
  /// Spelled out — and what VoiceOver always reads: «Season 1, Episode 1», «1 час 53 минуты».
  case long
}

/// The two languages the app speaks. Anything that is not Russian reads English — the
/// same rule as `LocalizedName`.
public enum MediaLanguage: String, Hashable, Codable, Sendable, CaseIterable {
  case en, ru

  public init(code: String?) {
    self = code?.lowercased().hasPrefix("ru") == true ? .ru : .en
  }

  /// The language the app is running in.
  public static var current: MediaLanguage {
    MediaLanguage(code: Bundle.main.preferredLocalizations.first)
  }

  var locale: Locale {
    Locale(identifier: self == .ru ? "ru_RU" : "en_US")
  }
}
