//
//  ItemsRequest.swift
//
//

import Foundation

/// The full catalog listing with sorting and filters — `/v1/items`.
public struct ItemsRequest: Endpoint {

  private let filter: LibraryFilter
  private let page: Int?

  public init(filter: LibraryFilter, page: Int? = nil) {
    self.filter = filter
    self.page = page
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
    return params
  }

  public var headers: [String: String]? {
    nil
  }

  public var forceSendAsGetParams: Bool { false }
}
