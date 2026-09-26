//
//  ItemsRequest.swift
//
//

import Foundation

/// The full catalog listing with sorting and filters — `/v1/items`.
public struct ItemsRequest: Endpoint {

  private let filter: LibraryFilter
  private let page: Int?
  /// `perpage` — the server's default is 50.
  private let perPage: Int?

  public init(filter: LibraryFilter, page: Int? = nil, perPage: Int? = nil) {
    self.filter = filter
    self.page = page
    self.perPage = perPage
  }

  public var path: String {
    "/v1/items"
  }

  public var method: String {
    "GET"
  }

  public var parameters: [String: Any]? {
    var params = filter.serverParameters
    params["sort"] = filter.sort.apiValue
    if let page {
      params["page"] = "\(page)"
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
