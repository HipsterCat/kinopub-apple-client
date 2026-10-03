//
//  TracklistEntry.swift
//  KinoPubBackend
//

import Foundation

/// One song of a concert's `tracklist`, as kino.pub sends it.
///
/// The API documentation names the field `artist`; the live payload (item 126187) sends
/// `artists`, empty, with an empty `url` and an unknown song called `"N/A"`
/// (`docs/providers/kinopub/video.md`). Both spellings are read; blanks stay nil.
public struct TracklistEntry: Codable, Hashable, Sendable {
  public let title: String?
  public let artists: String?
  public let url: String?

  public init(title: String?, artists: String? = nil, url: String? = nil) {
    self.title = title
    self.artists = artists
    self.url = url
  }

  private enum CodingKeys: String, CodingKey {
    case title, artists, artist, url
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    title = try c.decodeIfPresent(String.self, forKey: .title)
    artists = try c.decodeIfPresent(String.self, forKey: .artists)
      ?? c.decodeIfPresent(String.self, forKey: .artist)
    url = try c.decodeIfPresent(String.self, forKey: .url)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(title, forKey: .title)
    try c.encodeIfPresent(artists, forKey: .artists)
    try c.encodeIfPresent(url, forKey: .url)
  }
}
