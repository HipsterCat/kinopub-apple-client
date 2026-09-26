//
//  CatalogKind.swift
//  KinoPubBackend
//
//  What a person means by "a kind of thing to watch" — kino.pub's own sections
//  (`config.json` → `sections` / `home_blocks`), not the API's raw content types:
//  anime, cartoons, stand-up and shorts are a type plus a genre on the server
//  (`home_blocks`: cartoons `movie`+23 / `serial`+23, anime `movie,serial`+25,
//  stand-up `movie`+101), documentary films and series are one kind here.
//
//  Two axes, because the API ANDs parameters and ORs inside one: kinds picked by
//  *type* combine freely (`type=movie,serial`), kinds picked by *genre* combine among
//  themselves (`genre=25,23`), but "films + anime" is not one request — so a pick from
//  the other axis starts a new selection. And a genre kind owns the `genre` parameter:
//  the genre filter is off while one is on (there is no genre AND — `genre[]` → 502).
//

import Foundation

public enum CatalogKind: String, CaseIterable, Hashable, Sendable, Identifiable {
  case movies, series, shorts, documentaries, anime, cartoons, standup, tvShows, concerts

  public var id: String { rawValue }

  public enum Axis: Hashable, Sendable { case type, genre }

  public var axis: Axis { genreID == nil ? .type : .genre }

  /// The content types the kind spans on the server.
  public var types: [MediaType] {
    switch self {
    case .movies, .shorts, .standup: [.movie]
    case .series: [.serial]
    case .documentaries: [.documovie, .docuserial]
    case .anime, .cartoons: [.movie, .serial]
    case .tvShows: [.tvshow]
    case .concerts: [.concert]
    }
  }

  /// The genre that makes the kind, for the genre axis.
  public var genreID: Int? {
    switch self {
    case .shorts: 26
    case .anime: 25
    case .cartoons: 23
    case .standup: 101
    default: nil
    }
  }

  /// The genre sets its titles are filed under.
  public var genreKinds: Set<GenreKind> { Set(types.map(\.genreKind)) }

  /// Has episodes — "finished only" means something.
  public var isEpisodic: Bool {
    types.contains { [.serial, .docuserial, .tvshow].contains($0) }
  }

  /// "Фильмы" — filters, section titles.
  public var titleKey: String { "Kind_\(rawValue)" }
  /// "Фильм" — one title's kind, on its detail page.
  public var singularTitleKey: String { "Kind_\(rawValue)_One" }
  /// "Без фильмов" — every type kind but this one.
  public var withoutTitleKey: String { "Kind_\(rawValue)_Without" }
}
