import Foundation

/// **Which thing** — the one key every store and every list agrees on: a title, one
/// episode of it, or one version of a multi-version film.
///
/// Before this, each store keyed a thing its own way (`"id:m"`, `"id:s:e"`,
/// `"id|video|season"`, an episode's own server id, a card's five ints). Those stay as the
/// stores' private encodings; what crosses between layers is a `MediaRef`.
///
/// `itemID` is **our** title id. Today that is kino.pub's item id, the only catalogue the
/// app plays from. TODO(decision): when `/v1/title` issues ids of its own, this becomes
/// that id and kino.pub's moves to `ExternalID`.
public struct MediaRef: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {

  public enum Kind: String, Hashable, Codable, Sendable {
    /// A film, a series, a show as a whole.
    case title
    /// One episode: season and number within it.
    case episode
    /// One version of a multi-version film ("48 fps") — kino.pub's `video` number.
    case version
  }

  public let itemID: Int
  /// The season's real number (kino.pub's block number, as `/v1/watching` takes it).
  /// Set for an episode only.
  public let season: Int?
  /// The episode's number within its season, or a film version's video number.
  public let number: Int?

  /// Raw parts as an API hands them. A season without a number is not an episode: it
  /// reads as the title, the way a film's resume point has always been keyed.
  public init(itemID: Int, season: Int?, number: Int?) {
    self.itemID = itemID
    if let season, let number {
      self.season = season
      self.number = number
    } else {
      self.season = nil
      self.number = season == nil ? number : nil
    }
  }

  public static func title(_ itemID: Int) -> MediaRef {
    MediaRef(itemID: itemID, season: nil, number: nil)
  }

  public static func episode(_ itemID: Int, season: Int, number: Int) -> MediaRef {
    MediaRef(itemID: itemID, season: season, number: number)
  }

  public static func version(_ itemID: Int, number: Int) -> MediaRef {
    MediaRef(itemID: itemID, season: nil, number: number)
  }

  public var kind: Kind {
    if season != nil { return .episode }
    return number == nil ? .title : .version
  }

  /// The title this belongs to.
  public var title: MediaRef { .title(itemID) }

  /// What a **watch state** — resume point, watched mark — is kept under. An episode is its
  /// own; a film's versions share the film's, because the viewer watched *the film*. (A
  /// download is kept under the ref itself: there the version matters.)
  /// TODO(decision): a 48 fps and a 24 fps copy have the same runtime, so one resume point
  /// serves both today. Separate them if editions ever differ in length (a director's cut).
  public var watchRef: MediaRef { kind == .episode ? self : title }

  public var description: String {
    switch kind {
    case .title: return "\(itemID)"
    case .episode: return "\(itemID):s\(season ?? 0)e\(number ?? 0)"
    case .version: return "\(itemID):v\(number ?? 0)"
    }
  }

  /// Title, then season, then number — reading order within a title.
  public static func < (lhs: MediaRef, rhs: MediaRef) -> Bool {
    (lhs.itemID, lhs.season ?? -1, lhs.number ?? -1) < (rhs.itemID, rhs.season ?? -1, rhs.number ?? -1)
  }
}
