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
/// The endpoint takes no parameters, so the search catalog's filters apply **on the
/// device**: `LibraryFilter.locallyMatches` narrows the fetched list and
/// `sortingLocally` reorders it. On tvOS those filters are `TVSearchFilters` — the
/// same pull-down chips as search — over the same poster grid. The picker contents
/// are the collection's own genres and countries — a fixed list can only offer what
/// it holds. The curator's order is the rest state: it survives until a sort is
/// picked, because `recentlyAdded` applied blindly would scramble a ranked list.
@MainActor
class CollectionDetailModel: ObservableObject {

  @Published public private(set) var title: String
  /// The collection's items as fetched — the curator's order.
  @Published public private(set) var allItems: [MediaItem] = []
  /// What the grid shows: `allItems` after the filter bar's picks.
  @Published public var items: [MediaItem] = []
  @Published public private(set) var isLoading: Bool = true
  @Published public private(set) var loadFailed: Bool = false
  @Published public private(set) var loadError: Error?

  /// The filter bar's state. `filter` is read-only to the bar; picks land through
  /// `update` / `clearFilters` so the grid reapplies.
  @Published public private(set) var filter = LibraryFilter()
  /// The pickers' contents — the genres and countries the collection itself holds.
  @Published public private(set) var genres: [MediaGenre] = []
  @Published public private(set) var countries: [Country] = []

  private let collectionID: Int
  private let collectionsService: CollectionsService
  private let errorHandler: ErrorHandler

  init(collection: Collection, collectionsService: CollectionsService, errorHandler: ErrorHandler) {
    self.collectionID = collection.id
    self.title = collection.title
    self.collectionsService = collectionsService
    self.errorHandler = errorHandler
  }

  func fetch() async {
    isLoading = allItems.isEmpty
    defer { isLoading = false }
    do {
      let (collection, items) = try await collectionsService.fetchCollection(id: collectionID)
      title = collection.title
      allItems = items
      rebuildPickers()
      applyFilter()
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

  func update(_ transform: (inout LibraryFilter) -> Void) {
    var updated = filter
    transform(&updated)
    guard updated != filter else { return }
    filter = updated
    applyFilter()
  }

  func clearFilters() {
    guard filter.hasActiveFilters else { return }
    filter = LibraryFilter(sort: filter.sort)
    applyFilter()
  }

  /// Filter, then sort — but only a sort the user picked: at the rest state
  /// (`recentlyAdded`) the list keeps the curator's order.
  private func applyFilter() {
    let matched = allItems.filter(filter.locallyMatches)
    items = filter.sort == .recentlyAdded ? matched : filter.sortingLocally(matched)
  }

  /// A fixed list can only offer to narrow by what it holds — the pickers are the
  /// collection's own genres and countries, not the catalogue's.
  private func rebuildPickers() {
    var genreSeen = Set<Int>()
    var genreList: [MediaGenre] = []
    var countrySeen = Set<Int>()
    var countryList: [Country] = []
    for item in allItems {
      // Item payloads carry a genre id and a title, not which set it belongs to.
      // The title's type files it — the same sets the search genre menu sections by.
      let kind = MediaType(rawValue: item.type)?.genreKind
      for genre in item.genres {
        if let title = genre.title, genreSeen.insert(genre.id).inserted {
          genreList.append(MediaGenre(id: genre.id, title: title, kind: kind))
        }
      }
      for country in item.countries where countrySeen.insert(country.id).inserted {
        countryList.append(Country(id: country.id, title: country.title))
      }
    }
    genres = genreList.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    countries = countryList.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
  }
}

extension CollectionDetailModel: FilterBarDriver {}
