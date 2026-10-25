//
//  BookmarkItemsRequest.swift
//

import Foundation

public struct BookmarkItemsRequest: Endpoint {

  private var id: String
  private var page: Int?
  private var perPage: Int?

  public init(id: String, page: Int? = nil, perPage: Int? = nil) {
    self.id = id
    self.page = page
    self.perPage = perPage
  }

  public var path: String {
    "/v1/bookmarks/\(id)"
  }

  public var method: String {
    "GET"
  }

  public var parameters: [String: Any]? {
    var params: [String: Any] = [:]
    if let page { params["page"] = "\(page)" }
    if let perPage { params["perpage"] = "\(perPage)" }
    return params.isEmpty ? nil : params
  }

  public var headers: [String: String]? {
    nil
  }

  public var forceSendAsGetParams: Bool { false }
}
