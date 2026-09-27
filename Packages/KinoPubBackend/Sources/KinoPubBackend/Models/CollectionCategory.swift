//
//  CollectionCategory.swift
//  KinoPubBackend
//
//  How kino.pub's curated collections group into categories ("Кинофраншизы",
//  "Фильмографии режиссёров"…). The API has no such field: `/v1/collections` returns a
//  flat list. kpapp.link ships the grouping as a static page, `categories.html`, and
//  `collection-categories.json` is that page as data (38 categories, 531 collection
//  ids, captured 2026-09-27). The last one, "Другие", is kpapp's own catch-all.
//
//  A snapshot, so a collection created later is in no category until the file is
//  refreshed; callers treat "not listed" as "uncategorised", never as "missing".
//

import Foundation

public struct CollectionCategory: Decodable, Hashable, Sendable, Identifiable {
  public struct Entry: Decodable, Hashable, Sendable, Identifiable {
    /// The id `/v1/collections/view?id=` takes.
    public let id: Int
    public let title: String
  }

  public let title: String
  public let collections: [Entry]

  public var id: String { title }

  /// Every category in kpapp's order. Loaded once from the bundle.
  public static let catalog: [CollectionCategory] = {
    struct File: Decodable { let categories: [CollectionCategory] }
    guard let url = Bundle.module.url(forResource: "collection-categories", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let file = try? JSONDecoder().decode(File.self, from: data)
    else { return [] }
    return file.categories
  }()

  /// The category a collection is filed under, if the snapshot lists it.
  public static func containing(collectionID: Int) -> CollectionCategory? {
    byCollectionID[collectionID]
  }

  private static let byCollectionID: [Int: CollectionCategory] = {
    var map: [Int: CollectionCategory] = [:]
    for category in catalog {
      for entry in category.collections where map[entry.id] == nil {
        map[entry.id] = category
      }
    }
    return map
  }()
}
