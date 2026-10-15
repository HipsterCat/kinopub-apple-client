//
//  ContentProvider.swift
//  KinoPubTopShelf
//

import TVServices

/// Hands the system the feed the app last wrote (`TopShelfFeed`) as sectioned content:
/// Continue Watching as 16:9 stills with the system's progress bar, catalog shelves as
/// posters. Select goes where the same card on Home goes; Play always plays.
final class ContentProvider: TVTopShelfContentProvider {

  // The completion-handler form: the `async` one returns a non-Sendable content object
  // across an isolation boundary, which Swift 6 rejects. Nothing here awaits anything.
  override func loadTopShelfContent(completionHandler: @escaping ((any TVTopShelfContent)?) -> Void) {
    completionHandler(Self.content())
  }

  private static func content() -> (any TVTopShelfContent)? {
    guard let feed = TopShelfFeed.load() else { return nil }
    let collections = feed.sections.compactMap(collection(for:))
    // Nil, not an empty shelf: the system falls back to the app's static Top Shelf image.
    guard !collections.isEmpty else { return nil }
    return TVTopShelfSectionedContent(sections: collections)
  }

  private static func collection(for section: TopShelfFeed.Section)
    -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? {
    guard !section.items.isEmpty else { return nil }
    let collection = TVTopShelfItemCollection(items: section.items.map { item(for: $0, shape: section.shape) })
    collection.title = section.title
    return collection
  }

  private static func item(for entry: TopShelfFeed.Item,
                           shape: TopShelfFeed.Section.Shape) -> TVTopShelfSectionedItem {
    let item = TVTopShelfSectionedItem(identifier: "\(entry.itemID)")
    item.title = entry.title
    item.imageShape = shape == .wide ? .hdtv : .poster
    item.setImageURL(entry.imageURL, for: .screenScale1x)
    item.setImageURL(entry.imageURL, for: .screenScale2x)
    if let progress = entry.progress {
      item.playbackProgress = progress
    }
    let open = TopShelfLink.title(entry.itemID)
    item.displayAction = TVTopShelfAction(url: (entry.plays ? TopShelfLink.play(entry.itemID) : open).url)
    item.playAction = TVTopShelfAction(url: TopShelfLink.play(entry.itemID).url)
    return item
  }
}
