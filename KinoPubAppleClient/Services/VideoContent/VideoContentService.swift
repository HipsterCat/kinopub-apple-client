//
//  VideoContentService.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 26.07.2023.
//

import Foundation
import KinoPubBackend
import KinoPubUI

protocol VideoContentService: Sendable {
  func fetch(shortcut: MediaShortcut, contentType: MediaType, page: Int?, perPage: Int?) async throws -> PaginatedData<MediaItem>
  /// Text search with the catalog's filters. `sort: nil` is the server's relevance;
  /// `field` searches titles, cast or directors only.
  func search(query: String?, filter: LibraryFilter?, sort: MediaSortOrder?,
              field: SearchItemsRequest.Field?,
              page: Int?, perPage: Int?) async throws -> PaginatedData<MediaItem>
  /// kino.pub's type-ahead rows for the suggestion strip.
  func autocomplete(query: String) async throws -> [SearchAutocompleteEntry]
  /// - Parameter excludeLinks: `nolinks=1` — details without video links. Only for
  ///   callers that will resolve links per media with `fetchMediaLinks(mediaId:)`.
  func fetchDetails(for id: String, excludeLinks: Bool) async throws -> SingleItemData<MediaItem>
  /// Files + subtitles of one media (an episode's own id, or a film's video id).
  func fetchMediaLinks(mediaId: Int) async throws -> MediaLinks
  func fetchSimilar(for id: String) async throws -> ArrayData<MediaItem>
  func fetchBookmarks() async throws -> ArrayData<Bookmark>
  func fetchBookmarkItems(id: String, page: Int?) async throws -> BookmarkFolderItemsData
  func fetchWatchingMovies() async throws -> ArrayData<WatchingItem>
  func fetchWatchingSerials(subscribedOnly: Bool) async throws -> ArrayData<WatchingItem>
  /// - Parameter perPage: raw history *entries*, not cards. History is one entry per
  ///   play, so a page of 20 collapses to far fewer titles — see `LibrarySectionCatalog`.
  func fetchHistory(page: Int?, perPage: Int) async throws -> HistoryData
  func fetchItems(filter: LibraryFilter, page: Int?, perPage: Int?) async throws -> PaginatedData<MediaItem>
  func fetchGenres(for type: MediaType?) async throws -> ArrayData<MediaGenre>
  func fetchCountries() async throws -> ArrayData<Country>
  func fetchItemFolders(itemId: Int) async throws -> ArrayData<Bookmark>
  func toggleBookmark(itemId: Int, folderId: Int) async throws
  /// Live sport / event channels — `GET /v1/tv`.
  func fetchTVChannels() async throws -> [TVChannel]
}

extension VideoContentService {
  /// Back-compat overloads for callers that don't tune page size. Home rails, the
  /// background `StreamSurvey`, and the search screen keep the terse call and get the
  /// server's default page; only the full-screen grids in `MediaCatalog` pass an
  /// explicit `perPage` (see `CatalogPageSize`).
  func fetch(shortcut: MediaShortcut, contentType: MediaType, page: Int?) async throws -> PaginatedData<MediaItem> {
    try await fetch(shortcut: shortcut, contentType: contentType, page: page, perPage: nil)
  }

  func fetchItems(filter: LibraryFilter, page: Int?) async throws -> PaginatedData<MediaItem> {
    try await fetchItems(filter: filter, page: page, perPage: nil)
  }

  func search(query: String?, page: Int?) async throws -> PaginatedData<MediaItem> {
    try await search(query: query, filter: nil, sort: nil, field: nil, page: page, perPage: nil)
  }

  func search(query: String?, page: Int?, perPage: Int?) async throws -> PaginatedData<MediaItem> {
    try await search(query: query, filter: nil, sort: nil, field: nil, page: page, perPage: perPage)
  }

  /// Details with links, which is what every caller that plays straight from the payload
  /// wants. The detail page is the exception and asks for `excludeLinks: true`.
  func fetchDetails(for id: String) async throws -> SingleItemData<MediaItem> {
    try await fetchDetails(for: id, excludeLinks: false)
  }
}

protocol VideoContentServiceProvider {
  var contentService: VideoContentService { get set }
}

struct VideoContentServiceMock: VideoContentService {
  /// The item `fetchDetails` answers with, by id; `MediaItem.mock()` when nil or when it
  /// has nothing for that id. The DEBUG detail fixture (`DetailFixture`) serves its
  /// titles through this.
  var details: (@Sendable (Int) -> MediaItem?)? = nil
  /// What `fetchSimilar` answers with, by item id; the short placeholder rail when nil or
  /// when it has nothing for that id.
  var similar: (@Sendable (Int) -> [MediaItem]?)? = nil
  /// What a person's shelf (`fetchItems` with a person filter) answers with.
  var personItems: (@Sendable (LibraryFilter) -> [MediaItem])? = nil
  /// What `fetchWatchingSerials` answers with — the Library's Subscriptions. The DEBUG
  /// library fixture (`LibraryFixture`) serves its followed series through this.
  var watchingSerials: (@Sendable () -> [WatchingItem])? = nil

  func fetch(shortcut: MediaShortcut, contentType: MediaType, page: Int?, perPage: Int?) async throws -> PaginatedData<MediaItem> {
    return PaginatedData.mock(data: [])
  }

  func search(query: String?, filter: LibraryFilter?, sort: MediaSortOrder?,
              field: SearchItemsRequest.Field?,
              page: Int?, perPage: Int?) async throws -> PaginatedData<MediaItem> {
    return PaginatedData.mock(data: [])
  }

  func autocomplete(query: String) async throws -> [SearchAutocompleteEntry] {
    []
  }

  func fetchDetails(for id: String, excludeLinks: Bool) async throws -> SingleItemData<MediaItem> {
    if let itemID = Int(id), let item = details?(itemID) {
      return SingleItemData.mock(data: item)
    }
    return SingleItemData.mock(data: MediaItem.mock())
  }

  func fetchMediaLinks(mediaId: Int) async throws -> MediaLinks {
    return MediaLinks(files: [])
  }

  func fetchSimilar(for id: String) async throws -> ArrayData<MediaItem> {
    if let itemID = Int(id), let items = similar?(itemID) {
      return ArrayData.mock(data: items)
    }
    // A short rail so MediaItem previews exercise the section instead of hiding it.
    return ArrayData.mock(data: [
      MediaItem.mock(id: 101),
      MediaItem.mock(id: 102),
      MediaItem.mock(id: 103),
    ])
  }

  func fetchBookmarks() async throws -> ArrayData<Bookmark> {
    return ArrayData.mock(data: [])
  }
  
  func fetchBookmarkItems(id: String, page: Int?) async throws -> BookmarkFolderItemsData {
    return BookmarkFolderItemsData(items: [])
  }

  func fetchWatchingMovies() async throws -> ArrayData<WatchingItem> {
    return ArrayData.mock(data: [])
  }

  func fetchWatchingSerials(subscribedOnly: Bool) async throws -> ArrayData<WatchingItem> {
    return ArrayData.mock(data: watchingSerials?() ?? [])
  }

  func fetchHistory(page: Int?, perPage: Int = 20) async throws -> HistoryData {
    return HistoryData.mock(data: [])
  }

  func fetchItems(filter: LibraryFilter, page: Int?, perPage: Int?) async throws -> PaginatedData<MediaItem> {
    // Person shelves on the detail page need something non-empty so previews
    // exercise the rail instead of hiding it.
    if filter.person != nil {
      // A real connection takes a while; `-KINOPUBSlowShelves` says how long.
      if let delay = DebugLaunch.slowShelves {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }
      if let items = personItems?(filter) {
        return PaginatedData.mock(data: items)
      }
      return PaginatedData.mock(data: [
        MediaItem.mock(id: 201),
        MediaItem.mock(id: 202),
        MediaItem.mock(id: 203),
      ])
    }
    return PaginatedData.mock(data: [])
  }

  func fetchGenres(for type: MediaType?) async throws -> ArrayData<MediaGenre> {
    return ArrayData.mock(data: [])
  }

  func fetchCountries() async throws -> ArrayData<Country> {
    return ArrayData.mock(data: [])
  }

  func fetchItemFolders(itemId: Int) async throws -> ArrayData<Bookmark> {
    return ArrayData.mock(data: [])
  }

  func toggleBookmark(itemId: Int, folderId: Int) async throws { }

  func fetchTVChannels() async throws -> [TVChannel] {
    []
  }

}
