import Foundation

/// **How many seasons** — «3 сезона», «1 season». Plural-correct in both languages; the
/// Apple TV app's own count where a series has no single runtime.
public struct SeasonCountText: Hashable, Sendable {
  public let count: Int

  public init?(_ count: Int?) {
    guard let count, count > 0 else { return nil }
    self.count = count
  }

  public func formatted(language: MediaLanguage = .current) -> String {
    switch language {
    case .en:
      return count == 1 ? "1 season" : "\(count) seasons"
    case .ru:
      let lastTwo = count % 100
      let last = count % 10
      let word: String
      if (11...14).contains(lastTwo) {
        word = "сезонов"
      } else if last == 1 {
        word = "сезон"
      } else if (2...4).contains(last) {
        word = "сезона"
      } else {
        word = "сезонов"
      }
      return "\(count) \(word)"
    }
  }
}

/// **A title in one line** — «2025   1ч 55м   Боевик, Драма   Япония»: when, how long (a
/// series: how many seasons), what, where. The focus preview's line.
public struct TitleMetaLine: Hashable, Sendable {
  public let entity: MediaEntity

  public init(_ entity: MediaEntity) {
    self.entity = entity
  }

  /// When and how long: the year, then a series' season count or a film's runtime.
  /// A series with no count (a listing) says no runtime — every episode summed is none.
  public func releaseParts(language: MediaLanguage = .current) -> [String] {
    var parts: [String] = []
    if let year = entity.release?.year { parts.append(String(year)) }
    switch entity.kind {
    case .show:
      if let seasons = SeasonCountText(entity.seasonCount) {
        parts.append(seasons.formatted(language: language))
      }
    case .movie, .episode, .season, .extra:
      if let runtime = entity.runtime,
         let text = RuntimeText(seconds: runtime).text(for: .detailRuntime, language: language) {
        parts.append(text)
      }
    }
    return parts
  }

  /// - Parameter genreCount: how many genres. TODO(decision) D7: one (the primary, as the
  ///   player says) or two (the focus preview today)?
  public func formatted(genreCount: Int = 2, language: MediaLanguage = .current) -> String {
    var parts = releaseParts(language: language)
    let genres = entity.genres.prefix(genreCount)
      .map { $0.name.value(languageCode: language.rawValue) }
    if !genres.isEmpty { parts.append(genres.joined(separator: ", ")) }
    if let country = entity.countries.first { parts.append(country) }
    return parts.joined(separator: "   ")
  }
}
