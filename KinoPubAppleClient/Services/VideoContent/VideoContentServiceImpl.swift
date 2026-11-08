//
//  VideoContentServiceImpl.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 26.07.2023.
//

import Foundation
import KinoPubBackend
import KinoPubUI

final class VideoContentServiceImpl: VideoContentService, @unchecked Sendable {

  private let apiClient: APIClient

  init(apiClient: APIClient) {
    self.apiClient = apiClient
  }

  func fetch(shortcut: MediaShortcut, contentType: MediaType, page: Int?, perPage: Int?) async throws -> PaginatedData<MediaItem> {
    let request = ShortcutItemsRequest(shortcut: shortcut, contentType: contentType, page: page, perPage: perPage)
    let response = try await apiClient.performRequest(with: request,
                                                      decodingType: PaginatedData<MediaItem>.self)
    ListedItemCache.shared.remember(response.items)
    return response
  }

  func search(query: String?, filter: LibraryFilter?, sort: MediaSortOrder?,
              field: SearchItemsRequest.Field?,
              page: Int?, perPage: Int?) async throws -> PaginatedData<MediaItem> {
    let request = SearchItemsRequest(query: query, filter: filter, sort: sort, field: field,
                                     page: page, perPage: perPage)
    var response = try await apiClient.performRequest(with: request,
                                                      decodingType: PaginatedData<MediaItem>.self)
    if let filter, filter.hasClientSideFacets {
      response.items = response.items.filter { filter.clientSideMatches($0) }
    }
    ListedItemCache.shared.remember(response.items)
    return response
  }

  func autocomplete(query: String) async throws -> [SearchAutocompleteEntry] {
    try await SearchAutocomplete.fetch(query)
  }

  func fetchDetails(for id: String, excludeLinks: Bool) async throws -> SingleItemData<MediaItem> {
    if let status = DebugLaunch.failDetails(for: id) {
      throw APIClientError.httpStatus(status, data: nil)
    }
    let request = ItemDetailsRequest(id: id, excludeLinks: excludeLinks)
    let response = try await apiClient.performRequest(with: request,
                                                      decodingType: SingleItemData<MediaItem>.self)
    return response
  }

  func fetchMediaLinks(mediaId: Int) async throws -> MediaLinks {
    let request = MediaLinksRequest(mediaId: mediaId)
    return try await apiClient.performRequest(with: request, decodingType: MediaLinks.self)
  }

  func fetchSimilar(for id: String) async throws -> ArrayData<MediaItem> {
    let request = SimilarItemsRequest(id: id)
    let response = try await apiClient.performRequest(with: request,
                                                      decodingType: ArrayData<MediaItem>.self)
    ListedItemCache.shared.remember(response.items)
    return response
  }

  func fetchBookmarks() async throws -> ArrayData<Bookmark> {
    let request = BookmarksRequest()
    let response = try await apiClient.performRequest(with: request,
                                                      decodingType: ArrayData<Bookmark>.self)
    return response
  }
  
  func fetchBookmarkItems(id: String, page: Int?, perPage: Int?) async throws -> BookmarkFolderItemsData {
    let request = BookmarkItemsRequest(id: id, page: page, perPage: perPage)
    let response = try await apiClient.performRequest(with: request,
                                                      decodingType: BookmarkFolderItemsData.self)
    ListedItemCache.shared.remember(response.items)
    return response
  }

  func fetchWatchingMovies() async throws -> ArrayData<WatchingItem> {
    let request = WatchingMoviesRequest()
    let response = try await apiClient.performRequest(with: request,
                                                      decodingType: ArrayData<WatchingItem>.self)
    return response
  }

  func fetchWatchingSerials(subscribedOnly: Bool) async throws -> ArrayData<WatchingItem> {
    let request = WatchingSerialsRequest(subscribedOnly: subscribedOnly)
    let response = try await apiClient.performRequest(with: request,
                                                      decodingType: ArrayData<WatchingItem>.self)
    return response
  }

  func fetchHistory(page: Int?, perPage: Int = 20) async throws -> HistoryData {
    let request = HistoryRequest(page: page, perPage: perPage)
    return try await apiClient.performRequest(with: request,
                                              decodingType: HistoryData.self)
  }

  func fetchItems(filter: LibraryFilter, page: Int?, perPage: Int?) async throws -> PaginatedData<MediaItem> {
    let request = ItemsRequest(filter: filter, page: page, perPage: perPage)
    var response = try await apiClient.performRequest(
      with: request,
      decodingType: PaginatedData<MediaItem>.self
    )
    // Rating / quality / AC3 query params are silently ignored by /v1/items — filter locally.
    if filter.hasClientSideFacets {
      response.items = response.items.filter { filter.clientSideMatches($0) }
    }
    ListedItemCache.shared.remember(response.items)
    return response
  }

  func fetchGenres(for type: MediaType?) async throws -> ArrayData<MediaGenre> {
    let request = GenresRequest(contentType: type)
    return try await apiClient.performRequest(with: request,
                                              decodingType: ArrayData<MediaGenre>.self)
  }

  func fetchCountries() async throws -> ArrayData<Country> {
    let request = CountriesRequest()
    return try await apiClient.performRequest(with: request,
                                              decodingType: ArrayData<Country>.self)
  }

  func fetchItemFolders(itemId: Int) async throws -> ArrayData<Bookmark> {
    let request = ItemFoldersRequest(itemId: itemId)
    let response = try await apiClient.performRequest(with: request,
                                                      decodingType: ArrayData<Bookmark>.self)
    return response
  }

  func toggleBookmark(itemId: Int, folderId: Int) async throws {
    let request = ToggleBookmarkRequest(itemId: itemId, folderId: folderId)
    _ = try await apiClient.performRequest(with: request, decodingType: EmptyResponseData.self)
  }

  func fetchTVChannels() async throws -> [TVChannel] {
    let request = TVChannelsRequest()
    let response = try await apiClient.performRequest(
      with: request,
      decodingType: TVChannelsData.self
    )
    return response.channels
  }

}

/// The listing copy of every title the app has been handed this session — catalogue
/// shelves, search, Similar, bookmarks — by id, so a title opened from a card that only
/// carries its id (`Route.detailsById`) still paints its page at once from what the card
/// showed (`RouteDestination.detailsView`). In memory, bounded; the oldest half goes when
/// it fills.
final class ListedItemCache: @unchecked Sendable {
  static let shared = ListedItemCache()

  private let lock = NSLock()
  private var items: [Int: MediaItem] = [:]
  private var order: [Int] = []
  private let capacity = 2_000

  func remember(_ listed: [MediaItem]) {
    guard !listed.isEmpty else { return }
    lock.lock(); defer { lock.unlock() }
    for item in listed {
      if items.updateValue(item, forKey: item.id) == nil {
        order.append(item.id)
      }
    }
    if order.count > capacity {
      let dropped = order.prefix(order.count - capacity / 2)
      dropped.forEach { items[$0] = nil }
      order.removeFirst(dropped.count)
    }
  }

  func item(id: Int) -> MediaItem? {
    lock.lock(); defer { lock.unlock() }
    return items[id]
  }
}
