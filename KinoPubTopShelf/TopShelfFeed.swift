//
//  TopShelfFeed.swift
//  KinoPubAppleClient + KinoPubTopShelf
//

import Foundation

/// What the Top Shelf shows: the rows Watch Now last painted, worded and ordered by the
/// app. The extension only reads it — it never signs in or goes to the network, so the
/// shelf is exactly what the viewer saw on Home, and an empty feed means the app icon.
///
/// Compiled into both the app and the extension; the App Group is the only thing they
/// share.
struct TopShelfFeed: Codable, Equatable, Sendable {

  struct Item: Codable, Equatable, Sendable {
    /// The kino.pub title id — what both links open.
    let itemID: Int
    let title: String
    let imageURL: URL
    /// 0…1 while the title is in progress; the system draws the bar.
    let progress: Double?
    /// Select plays (Continue Watching); otherwise it opens the title.
    let plays: Bool
  }

  struct Section: Codable, Equatable, Sendable {
    enum Shape: String, Codable, Sendable {
      /// 16:9 episode stills — Continue Watching.
      case wide
      /// 2:3 posters — catalog shelves.
      case poster
    }

    let title: String
    let shape: Shape
    let items: [Item]
  }

  var sections: [Section]

  static let empty = TopShelfFeed(sections: [])

  // MARK: - App Group

  static let appGroup = "group.com.soda.kinopub"
  private static let key = "topShelfFeed.v1"

  private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

  /// The last feed the app wrote, or nil when there is none (or the group is missing).
  static func load() -> TopShelfFeed? {
    guard let data = defaults?.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(TopShelfFeed.self, from: data)
  }

  /// Writes the feed; false when it is what the shelf already holds, so the caller does
  /// not wake the system for nothing.
  @discardableResult
  func save() -> Bool {
    guard let defaults = Self.defaults,
          let data = try? JSONEncoder().encode(self),
          defaults.data(forKey: Self.key) != data else { return false }
    defaults.set(data, forKey: Self.key)
    return true
  }
}

/// `kinopub://` — the links a Top Shelf item carries into the app.
enum TopShelfLink: Equatable, Sendable {
  /// The title's detail page.
  case title(Int)
  /// Resume what the Continue Watching card offers; the detail page when it is gone.
  case play(Int)

  static let scheme = "kinopub"

  var url: URL {
    switch self {
    case .title(let id): URL(string: "\(Self.scheme)://title/\(id)")!
    case .play(let id): URL(string: "\(Self.scheme)://play/\(id)")!
    }
  }

  init?(url: URL) {
    guard url.scheme == Self.scheme,
          let id = url.pathComponents.dropFirst().first.flatMap(Int.init) else { return nil }
    switch url.host {
    case "title": self = .title(id)
    case "play": self = .play(id)
    default: return nil
    }
  }
}
