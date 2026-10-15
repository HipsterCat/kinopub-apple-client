//
//  TopShelfPublisher.swift
//  KinoPubAppleClient
//

#if os(tvOS)
import Foundation
import TVServices
import KinoPubMedia
import KinoPubUI
import OSLog
import KinoPubLogging

/// Hands Watch Now's rows to the Top Shelf extension (`TopShelfFeed`): Continue Watching
/// as painted on Home — local progress already over it — then the first catalog shelves.
/// The cards are already worded, so the shelf says what Home says.
///
/// Called whenever Watch Now assembles its rows; an unchanged feed writes nothing and
/// does not wake the system.
@MainActor
enum TopShelfPublisher {
  /// Catalog shelves after Continue Watching — Hot Movies and Hot Series today.
  private static let catalogSections = 2
  /// The shelf scrolls sideways; past this many it is a catalog, not a shelf.
  private static let itemsPerSection = 12

  static func publish(rows: [MediaRow], store: ContentStore) {
    var sections: [TopShelfFeed.Section] = []
    if let row = rows.first(where: { $0.id == HomeCatalog.continueWatchingRowID }) {
      sections.append(section(row, shape: .wide, store: store))
    }
    let catalog = rows.filter {
      $0.id != HomeCatalog.continueWatchingRowID && $0.id != HomeCatalog.collectionsRowID
    }
    sections += catalog.prefix(catalogSections).map { section($0, shape: .poster, store: store) }
    update(TopShelfFeed(sections: sections.filter { !$0.items.isEmpty }))
  }

  /// Signed out: the shelf goes back to the static image instead of the last account's titles.
  static func clear() {
    update(.empty)
  }

  private static func update(_ feed: TopShelfFeed) {
    guard feed.save() else { return }
    Logger.app.debug("TopShelf: wrote \(feed.sections.map { "\($0.title) ×\($0.items.count)" })")
    TVTopShelfContentProvider.topShelfContentDidChange()
  }

  private static func section(_ row: MediaRow, shape: TopShelfFeed.Section.Shape,
                              store: ContentStore) -> TopShelfFeed.Section {
    let items = row.cards.compactMap { card -> TopShelfFeed.Item? in
      guard let url = imageURL(for: card, shape: shape, store: store) else { return nil }
      return TopShelfFeed.Item(itemID: card.itemID,
                               title: card.title,
                               imageURL: url,
                               progress: card.progress,
                               plays: card.primaryAction == .play)
    }
    return TopShelfFeed.Section(title: row.title, shape: shape, items: Array(items.prefix(itemsPerSection)))
  }

  /// A card paints the poster preview (250 pt wide); a shelf poster is wider than that,
  /// so it takes the record's full poster when the row holds one.
  private static func imageURL(for card: MediaCard, shape: TopShelfFeed.Section.Shape,
                               store: ContentStore) -> URL? {
    switch shape {
    case .wide:
      return URL(string: card.landscapeImageURL ?? card.backdropImageURL)
    case .poster:
      return store.records.record(for: card.ref)?.entity.artwork.poster ?? URL(string: card.posterURL)
    }
  }
}
#endif
