import Foundation

public enum MetadataSourceID: String, Sendable, Hashable, Codable {
  case tmdb
  case trakt
  /// omdbapi.com with the viewer's own key.
  case omdb
  /// Douban, through our worker's signed Frodo route.
  case douban
  /// Wikidata's public API: ids on other sites, box office, Wikipedia.
  case wikidata
  /// MyShows.me's public JSON-RPC API. Series only.
  case myShows
  case kinopoisk
  /// Keyless kpapp.link proxy (same unofficial Kinopoisk payload the community fork uses).
  case kinopoiskProxy
  /// One `/v2/title` card from our worker, by kino.pub id.
  case titleCard
  case introdb
}

public enum MetadataError: Error, Sendable, Equatable {
  case notConfigured
  case badURL
  case httpStatus(Int)
  case decodingFailed
  case notFound
}
