//
//  CollectionDetailModel.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend
import OSLog
import KinoPubLogging

/// One collection's full item grid — `/v1/collections/view` returns everything in
/// one response, so there is no pagination to drive here (unlike the paginated
/// catalog / search grids).
///
/// The endpoint takes no parameters. The page does not invent a local filter for
/// genre, year, or rating: the only control is sort, which reorders the list the
/// response already held. The curator's order is the rest state — it survives
/// until a sort is picked, because `recentlyAdded` applied blindly would scramble
/// a ranked list.
@MainActor
class CollectionDetailModel: ObservableObject {

  @Published public private(set) var collection: Collection
  @Published public private(set) var title: String
  /// The collection's items as fetched — the curator's order.
  @Published public private(set) var allItems: [MediaItem] = []
  /// What the grid shows: `allItems` after the sort control.
  @Published public var items: [MediaItem] = []
  @Published public private(set) var isLoading: Bool = true
  @Published public private(set) var loadFailed: Bool = false
  @Published public private(set) var loadError: Error?

  /// Sort only. Other fields stay at their defaults; the page does not offer them.
  @Published public private(set) var filter = LibraryFilter()

  private let collectionID: Int
  private let collectionsService: CollectionsService
  private let errorHandler: ErrorHandler

  init(collection: Collection, collectionsService: CollectionsService, errorHandler: ErrorHandler) {
    self.collectionID = collection.id
    self.collection = collection
    self.title = collection.title
    self.collectionsService = collectionsService
    self.errorHandler = errorHandler
  }

  func fetch() async {
    isLoading = allItems.isEmpty
    defer { isLoading = false }
    do {
      let (fetched, items) = try await collectionsService.fetchCollection(id: collectionID)
      collection = fetched
      title = fetched.title
      allItems = items
      applySort()
      loadFailed = false
      loadError = nil
    } catch {
      Logger.app.debug("fetch collection \(self.collectionID) error: \(error)")
      if self.allItems.isEmpty {
        loadFailed = true
        loadError = error
      } else {
        errorHandler.setError(error)
      }
    }
  }

  // MARK: - FilterBarDriver

  /// Honors sort and ignores every other pick. The collection endpoint cannot
  /// filter, and applying the search row on the device was a second filter system.
  func update(_ transform: (inout LibraryFilter) -> Void) {
    var updated = filter
    transform(&updated)
    guard updated.sort != filter.sort else { return }
    filter.sort = updated.sort
    applySort()
  }

  func clearFilters() {
    guard filter.sort != .recentlyAdded else { return }
    filter.sort = .recentlyAdded
    applySort()
  }

  /// A picked sort reorders the fetched list. At rest the curator's order stands.
  private func applySort() {
    items = filter.sort == .recentlyAdded ? allItems : filter.sortingLocally(allItems)
  }
}

extension CollectionDetailModel: FilterBarDriver {
  var genres: [MediaGenre] { [] }
  var countries: [Country] { [] }
}
