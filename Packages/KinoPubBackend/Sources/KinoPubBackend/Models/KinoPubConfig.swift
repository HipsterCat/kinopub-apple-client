//
//  KinoPubConfig.swift
//  KinoPubBackend
//
//  kino.pub's public client config — `https://www.kpapp.link/config.json`, keyless
//  (docs/providers/kinopub/references.md). What the filters need from it: content types
//  with the genre set each uses, the genres by set in kino.pub's order, countries,
//  sorts and subtitle languages. One request instead of `/v1/genres` + `/v1/countries`,
//  and the genre sets come labelled.
//

import Foundation

public struct KinoPubConfig: Decodable, Sendable {
  public struct TypeEntry: Decodable, Sendable {
    public let id: String
    public let title: String
    /// The genre set this type uses: `movie` / `docu` / `tvshow` / `music`.
    public let genres: String
  }

  public struct Entry: Decodable, Sendable, Hashable {
    public let id: Int
    public let title: String
  }

  public struct StringEntry: Decodable, Sendable, Hashable {
    public let id: String
    public let title: String
  }

  public struct Filter: Decodable, Sendable {
    public let types: [TypeEntry]
    public let genres: [String: [Entry]]
    public let countries: [Entry]
    public let sort: [StringEntry]?
    public let subtitles: [StringEntry]?
  }

  public let version: String?
  public let filter: Filter

  public static let url = URL(string: "https://www.kpapp.link/config.json")!

  /// Genres with their set, sets in `GenreKind` order, each set largest-first
  /// (`GenrePopularity`).
  public var genres: [MediaGenre] {
    GenreKind.allCases.flatMap { kind in
      GenrePopularity.sorted((filter.genres[kind.rawValue] ?? []).map { MediaGenre(id: $0.id, title: $0.title, kind: kind) })
    }
  }

  /// Countries in kino.pub's popularity order (`CountryPopularity`).
  public var countries: [Country] {
    CountryPopularity.sorted(filter.countries.map { Country(id: $0.id, title: $0.title) })
  }

  private static var cached: KinoPubConfig?

  /// Memory, then a copy in Caches, then the network. The file changes rarely; a stale
  /// copy is better than empty pickers.
  public static func load(session: URLSession = .shared) async -> KinoPubConfig? {
    if let cached { return cached }
    let disk = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("kinopub-config.json")
    var request = URLRequest(url: url)
    request.timeoutInterval = 8
    if let (data, response) = try? await session.data(for: request),
       (response as? HTTPURLResponse)?.statusCode == 200,
       let config = try? JSONDecoder().decode(KinoPubConfig.self, from: data) {
      if let disk { try? data.write(to: disk) }
      cached = config
      return config
    }
    if let disk, let data = try? Data(contentsOf: disk),
       let config = try? JSONDecoder().decode(KinoPubConfig.self, from: data) {
      cached = config
      return config
    }
    return nil
  }
}
