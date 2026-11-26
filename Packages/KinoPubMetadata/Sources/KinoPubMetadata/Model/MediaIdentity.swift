import Foundation

/// Everything needed to identify a title in external catalogs.
/// Built once from kino.pub's `MediaItem`. The worker's `/v2/title` call sends
/// these as query hints so a cold kino.pub id can still match TMDB.
public struct MediaIdentity: Hashable, Sendable {
  public let kinopubId: Int
  /// IMDb id as `tt0903747`. Nil when kino.pub has no imdb field.
  public let imdb: String?
  public let kinopoisk: Int?
  public let title: String
  public let originalTitle: String
  public let year: Int
  public let isSeries: Bool
  /// Average runtime in minutes, when kino.pub sent one. Helps the worker tell two
  /// same-year titles apart.
  public let runtimeMinutes: Int?
  /// The TMDB id an admin linked in the worker, `tv/343022` or `movie/550`. Looked up
  /// directly; nil means the title is found by its IMDb id.
  public let linkedTMDB: String?
  /// MyAnimeList anime id when already known (Wikidata / Trakt link / prior resolve).
  public let mal: Int?
  /// From `MediaPresentationProfile.isAnime` — gates MAL search so non-anime titles
  /// do not burn Client ID quota on fuzzy title lookups.
  public let isAnime: Bool

  public init(
    kinopubId: Int,
    imdb: String?,
    kinopoisk: Int?,
    title: String,
    originalTitle: String,
    year: Int,
    isSeries: Bool,
    runtimeMinutes: Int? = nil,
    linkedTMDB: String? = nil,
    mal: Int? = nil,
    isAnime: Bool = false
  ) {
    self.kinopubId = kinopubId
    self.imdb = imdb
    self.kinopoisk = kinopoisk
    self.title = title
    self.originalTitle = originalTitle
    self.year = year
    self.isSeries = isSeries
    self.runtimeMinutes = runtimeMinutes
    self.linkedTMDB = linkedTMDB
    self.mal = mal
    self.isAnime = isAnime
  }

  /// The same title with the ids the worker holds: its TMDB id, and its IMDb id where
  /// kino.pub has none.
  public func withLinked(imdb: String?, tmdb: String?) -> MediaIdentity {
    MediaIdentity(
      kinopubId: kinopubId,
      imdb: self.imdb ?? imdb,
      kinopoisk: kinopoisk,
      title: title,
      originalTitle: originalTitle,
      year: year,
      isSeries: isSeries,
      runtimeMinutes: runtimeMinutes,
      linkedTMDB: tmdb ?? linkedTMDB,
      mal: mal,
      isAnime: isAnime
    )
  }

  /// The same title with a Kinopoisk id the title card supplied.
  public func withKinopoisk(_ id: Int) -> MediaIdentity {
    MediaIdentity(
      kinopubId: kinopubId,
      imdb: imdb,
      kinopoisk: id,
      title: title,
      originalTitle: originalTitle,
      year: year,
      isSeries: isSeries,
      runtimeMinutes: runtimeMinutes,
      linkedTMDB: linkedTMDB,
      mal: mal,
      isAnime: isAnime
    )
  }

  /// The same title with a MyAnimeList anime id from Wikidata / Trakt / a prior resolve.
  public func withMAL(_ id: Int?) -> MediaIdentity {
    guard let id, id > 0 else { return self }
    return MediaIdentity(
      kinopubId: kinopubId,
      imdb: imdb,
      kinopoisk: kinopoisk,
      title: title,
      originalTitle: originalTitle,
      year: year,
      isSeries: isSeries,
      runtimeMinutes: runtimeMinutes,
      linkedTMDB: linkedTMDB,
      mal: mal ?? id,
      isAnime: isAnime || true
    )
  }
}
