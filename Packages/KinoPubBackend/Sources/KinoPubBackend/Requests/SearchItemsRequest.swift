//
//  SearchItemsRequest.swift
//
//
//  Created by Kirill Kunst on 26.07.2023.
//

import Foundation

/// Text search — `/v1/items/search`, over `title`, `director` and `cast` (or one of them
/// with `field`). It takes the catalog's filters and sort too: `type`, `genre`,
/// `country`, `year`, `sort` all apply to the matches (verified live 2026-09-25 — see
/// docs/providers/kinopub/video.md). No `sort` is the server's relevance order.
public struct SearchItemsRequest: Endpoint {

  /// `field=` — search one credit field instead of all three.
  public enum Field: String, Sendable {
    case title, director, cast
  }

  private var query: String?
  private var filter: LibraryFilter?
  private var sort: MediaSortOrder?
  private var field: Field?
  private var page: Int?
  private var perPage: Int?

  public init(query: String?,
              filter: LibraryFilter? = nil,
              sort: MediaSortOrder? = nil,
              field: Field? = nil,
              page: Int? = nil,
              perPage: Int? = nil) {
    self.query = query
    self.filter = filter
    self.sort = sort
    self.field = field
    self.page = page
    self.perPage = perPage
  }

  public init(contentType: MediaType?, page: Int? = nil, query: String? = nil, perPage: Int? = nil) {
    self.init(query: query, filter: LibraryFilter(contentType: contentType), page: page, perPage: perPage)
  }

  public var path: String {
    "/v1/items/search"
  }

  public var method: String {
    "GET"
  }

  public var parameters: [String: Any]? {
    var params = filter?.serverParameters ?? [:]
    if let sort {
      params["sort"] = sort.apiValue
    }
    if let field {
      params["field"] = field.rawValue
    }
    if let page {
      params["page"] = "\(page)"
    }
    if let query {
      params["q"] = query
    }
    if let perPage {
      params["perpage"] = "\(perPage)"
    }
    return params
  }

  public var headers: [String: String]? {
    nil
  }

  public var forceSendAsGetParams: Bool { false }
}
