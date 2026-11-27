import Foundation

/// Which vocabulary a genre belongs to. Films, series and TV share one — Apple's film and
/// TV trees use the same words — and music has its own: a concert is filed under
/// Electronic or Rock, not under Drama.
public enum GenreDomain: String, Hashable, Sendable, Codable, CaseIterable {
  case video
  case music
}

/// One idea of genre, whoever named it. The id is **ours** ("comedy", "music.trance"),
/// never a source's number: kino.pub's 9, TMDB's 18 and Kinopoisk's «драма» are all
/// `drama`, and that is what lets two sources agree on what a title is.
///
/// A name no table knows yet is not dropped. It keeps the source's own name under an id
/// of the form `<source>:<key>`, so it still shows and still says it is unmapped —
/// `isMapped` is how a test or a log finds the gap.
public struct Genre: Hashable, Sendable, Identifiable, Codable {
  public let id: String
  public let domain: GenreDomain
  public let name: LocalizedName

  public init(id: String, domain: GenreDomain, name: LocalizedName) {
    self.id = id
    self.domain = domain
    self.name = name
  }

  public var isMapped: Bool { !id.contains(":") }

  public static func unmapped(source: MediaSource, key: String, name: String,
                              domain: GenreDomain) -> Genre {
    Genre(id: "\(source.rawValue):\(key)", domain: domain, name: LocalizedName(en: name, ru: name))
  }

  // Identity is the id alone: two sources naming `drama` differently are one genre.
  public static func == (lhs: Genre, rhs: Genre) -> Bool { lhs.id == rhs.id }
  public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The two languages the app speaks. Anything that is not Russian reads English.
public struct LocalizedName: Hashable, Sendable, Codable {
  public let en: String
  public let ru: String

  public init(en: String, ru: String) {
    self.en = en
    self.ru = ru
  }

  public func value(languageCode: String?) -> String {
    languageCode?.lowercased().hasPrefix("ru") == true ? ru : en
  }
}
