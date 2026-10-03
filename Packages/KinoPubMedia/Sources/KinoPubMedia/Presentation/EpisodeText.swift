import Foundation

/// **An episode's reference** — «S1, E1», «1 сезон, 1 серия: Name» — one value, one set of
/// rules, every surface (user's spec, 2026-10-03):
///
/// | Length | en | ru |
/// | --- | --- | --- |
/// | short | `S1, E1` | `1 сезон, 1 серия` |
/// | medium | `Season 1, Episode 1` · `S1, E1: Name` | `1 сезон, 1 серия` · `1 сезон, 1 серия: Name` |
/// | long | `Season 1, Episode 1` · `Season 1, Episode 1: Name` | as medium |
///
/// **Only one season known, and it is the first** — or the season goes without saying, as on
/// a season's own rail: the season drops out. `E1` / `Episode 1` / `1 серия`, and with a
/// name `Episode 1: Name` / `1 серия: Name`.
///
/// The name is shown only when it is one (`EpisodeTitle.meaningful`): «Эпизод 1» is the
/// number again.
public struct EpisodeText: Hashable, Sendable {
  /// Nil when the season goes without saying.
  public let season: Int?
  public let number: Int
  public let name: String?

  /// - Parameters:
  ///   - seasonCount: how many seasons the show has that we know of. One, and it is season
  ///     1 → the season is not said. Nil when unknown: the season is said.
  public init(season: Int?, number: Int, name: String? = nil, seasonCount: Int? = nil) {
    let isSoleFirstSeason = seasonCount == 1 && season == 1
    self.season = isSoleFirstSeason ? nil : season
    self.number = number
    self.name = EpisodeTitle.meaningful(name)
  }

  public func formatted(_ length: TextLength, language: MediaLanguage = .current) -> String {
    switch length {
    case .short:
      return reference(.short, language)
    case .medium:
      // A name needs the room, so a season-and-episode reference shrinks to make it; a
      // bare episode reference has room as it is.
      guard let name else { return reference(.long, language) }
      return "\(reference(season == nil ? .long : .short, language)): \(name)"
    case .long:
      return [reference(.long, language), name].compactMap { $0 }.joined(separator: ": ")
    }
  }

  /// What VoiceOver reads, whatever the screen shows.
  public func accessibilityLabel(language: MediaLanguage = .current) -> String {
    formatted(.long, language: language)
  }

  public func text(for surface: MediaSurface, language: MediaLanguage = .current) -> String {
    formatted(surface.episodeLength, language: language)
  }

  private func reference(_ length: TextLength, _ language: MediaLanguage) -> String {
    switch (language, season) {
    case (.ru, let season?):
      return "\(season) сезон, \(number) серия"
    case (.ru, nil):
      return "\(number) серия"
    case (.en, let season?):
      return length == .short ? "S\(season), E\(number)" : "Season \(season), Episode \(number)"
    case (.en, nil):
      return length == .short ? "E\(number)" : "Episode \(number)"
    }
  }
}

/// A season on its own: settings rows, download menus.
/// TODO(decision): Russian follows the episode reference («2 сезон»); kino.pub's own season
/// titles («Сезон 2») stay as kino.pub writes them on the season tabs.
public struct SeasonText: Hashable, Sendable {
  public let number: Int

  public init(_ number: Int) {
    self.number = number
  }

  public func formatted(_ length: TextLength, language: MediaLanguage = .current) -> String {
    switch language {
    case .ru: return "\(number) сезон"
    case .en: return length == .short ? "S\(number)" : "Season \(number)"
    }
  }
}
