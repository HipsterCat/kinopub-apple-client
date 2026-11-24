//
//  Season.swift
//
//
//  Created by Kirill Kunst on 21.07.2023.
//

import Foundation

/// A value, like `Episode`. Hashed by id and compared whole, for the same reason.
public struct Season: Codable, Hashable, Identifiable, Sendable {

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  public let id: Int
  public let title: String
  public let number: Int
  public let watching: SeasonWatching
  public var episodes: [Episode]
  /// The **item** id this season belongs to — the id every `/v1/watching*` call wants.
  /// Setting it stamps the episodes too: an `Episode` holds no reference to its season,
  /// and the one that forgot to be stamped fell back to its own media id and asked the
  /// API about a title that was not this one.
  public var mediaId: Int? = nil {
    didSet {
      for index in episodes.indices { episodes[index].mediaId = mediaId }
    }
  }
  /// Digits from the title, read once when the season is made. Not coded. Instruments
  /// showed the regex on every rail paint for every episode of every season (~1.6s of a
  /// 7s hang on long shows).
  public let titleSeasonNumber: Int?

  public init(id: Int,
       title: String,
       number: Int,
       watching: SeasonWatching,
       episodes: [Episode]) {
    self.id = id
    self.title = title
    self.number = number
    self.watching = watching
    self.episodes = episodes
    self.titleSeasonNumber = Self.parseTitleSeasonNumber(title)
  }

  private enum CodingKeys: String, CodingKey {
    case id = "id"
    case title = "title"
    case number = "number"
    case watching = "watching"
    case episodes = "episodes"
    case mediaId = "mediaId"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(id: try container.decode(Int.self, forKey: .id),
              title: try container.decode(String.self, forKey: .title),
              number: try container.decode(Int.self, forKey: .number),
              watching: try container.decode(SeasonWatching.self, forKey: .watching),
              episodes: try container.decode([Episode].self, forKey: .episodes))
    // Only a season that was encoded stamped has it, and its episodes were stamped then.
    if let mediaId = try container.decodeIfPresent(Int.self, forKey: .mediaId) {
      self.mediaId = mediaId
    }
  }

  public var fixedTitle: String {
    if title.isEmpty {
      return "Сезон \(number)"
    }
    return title
  }
}
