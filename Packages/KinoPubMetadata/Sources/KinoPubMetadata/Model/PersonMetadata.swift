import Foundation

/// One title from a person's TMDB filmography (`combined_credits`). Carries the TMDB
/// id so a later pass can join to Kinopub by id rather than by title string.
public struct PersonCredit: Sendable, Hashable, Identifiable {
  public var id: String { "\(mediaType):\(tmdbId)" }

  public let tmdbId: Int
  /// `"movie"` or `"tv"`.
  public let mediaType: String
  public let title: String
  public let originalTitle: String?
  public let character: String?
  public let job: String?
  public let releaseDate: Date?
  public let posterURL: URL?
  public let voteAverage: Double?
  public let popularity: Double?

  public var year: Int? {
    guard let releaseDate else { return nil }
    return Calendar.current.component(.year, from: releaseDate)
  }

  public init(
    tmdbId: Int,
    mediaType: String,
    title: String,
    originalTitle: String? = nil,
    character: String? = nil,
    job: String? = nil,
    releaseDate: Date? = nil,
    posterURL: URL? = nil,
    voteAverage: Double? = nil,
    popularity: Double? = nil
  ) {
    self.tmdbId = tmdbId
    self.mediaType = mediaType
    self.title = title
    self.originalTitle = originalTitle
    self.character = character
    self.job = job
    self.releaseDate = releaseDate
    self.posterURL = posterURL
    self.voteAverage = voteAverage
    self.popularity = popularity
  }
}

/// External person overlay for the credits page. Empty when TMDB is unset or
/// the person id is unknown — the page then draws name + role from kino.pub alone.
public struct PersonMetadata: Sendable, Hashable {
  public var biography: String?
  public var birthday: Date?
  public var placeOfBirth: String?
  public var photo: URL?
  public var knownForDepartment: String?
  /// TMDB's canonical name for this person (usually English / original script).
  public var name: String?
  /// Alternate spellings (`also_known_as`) — tried as Kinopub `cast=` / `director=` queries.
  public var alsoKnownAs: [String] = []
  /// Combined cast+crew filmography from TMDB, newest / most popular first.
  public var credits: [PersonCredit] = []
  public var attribution: Set<MetadataSourceID> = []

  public init(
    biography: String? = nil,
    birthday: Date? = nil,
    placeOfBirth: String? = nil,
    photo: URL? = nil,
    knownForDepartment: String? = nil,
    name: String? = nil,
    alsoKnownAs: [String] = [],
    credits: [PersonCredit] = [],
    attribution: Set<MetadataSourceID> = []
  ) {
    self.biography = biography
    self.birthday = birthday
    self.placeOfBirth = placeOfBirth
    self.photo = photo
    self.knownForDepartment = knownForDepartment
    self.name = name
    self.alsoKnownAs = alsoKnownAs
    self.credits = credits
    self.attribution = attribution
  }

  public mutating func merge(_ other: PersonMetadata) {
    if biography == nil || biography?.isEmpty == true { biography = other.biography }
    if birthday == nil { birthday = other.birthday }
    if placeOfBirth == nil || placeOfBirth?.isEmpty == true { placeOfBirth = other.placeOfBirth }
    if photo == nil { photo = other.photo }
    if knownForDepartment == nil { knownForDepartment = other.knownForDepartment }
    if name == nil || name?.isEmpty == true { name = other.name }
    if alsoKnownAs.isEmpty { alsoKnownAs = other.alsoKnownAs }
    else if !other.alsoKnownAs.isEmpty {
      var seen = Set(alsoKnownAs.map { $0.lowercased() })
      for alias in other.alsoKnownAs where seen.insert(alias.lowercased()).inserted {
        alsoKnownAs.append(alias)
      }
    }
    if credits.isEmpty { credits = other.credits }
    attribution.formUnion(other.attribution)
  }
}
