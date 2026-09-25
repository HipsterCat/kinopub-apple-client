//
//  MediaGenre.swift
//  
//
//  Created by Kirill Kunst on 28.07.2023.
//

import Foundation

public struct MediaGenre: Codable, Hashable, Identifiable {
  /// Int, not String: the API sends `"id": 25`, so the old `String` declaration made
  /// every genre response fail to decode.
  public let id: Int
  public let title: String
  /// Which genre set this belongs to. `/v1/genres` answers `type` with the *set*
  /// (`movie` / `docu` / `tvshow` / `music`), not a content type — decoding it as
  /// `MediaType` failed the whole list for documentary and concert genres. Unknown
  /// sets decode as `nil` rather than failing the response.
  public let kind: GenreKind?

  public init(id: Int, title: String, kind: GenreKind? = nil) {
    self.id = id
    self.title = title
    self.kind = kind
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, kind = "type"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    kind = (try? container.decodeIfPresent(String.self, forKey: .kind)).flatMap { $0 }.flatMap(GenreKind.init(rawValue:))
  }
}

/// The four genre sets kino.pub files genres under, and which content types use each —
/// `config.json` → `filter.types[].genres` (docs/providers/kinopub/references.md).
public enum GenreKind: String, Codable, CaseIterable, Hashable, Sendable {
  /// Films, series and 3D.
  case movie
  /// Documentary films and series.
  case docu
  case tvshow
  /// Concerts.
  case music

  public var contentTypes: [MediaType] {
    MediaType.allCases.filter { $0.genreKind == self }
  }
}

public extension MediaType {
  var genreKind: GenreKind {
    switch self {
    case .movie, .serial, .threeD: .movie
    case .documovie, .docuserial: .docu
    case .tvshow: .tvshow
    case .concert: .music
    }
  }
}
