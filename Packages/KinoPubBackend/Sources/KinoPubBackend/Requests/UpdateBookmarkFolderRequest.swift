//
//  UpdateBookmarkFolderRequest.swift
//

import Foundation

/// Renames a bookmark folder. Public docs only list create / remove; the create
/// call is a body POST with `title`, and remove is a body POST with `folder`.
/// Passing both (`title` + `folder`) is the same family. Unverified live — the
/// public sheet has no rename.
public struct UpdateBookmarkFolderRequest: Endpoint {

  public var id: Int
  public var title: String

  public init(id: Int, title: String) {
    self.id = id
    self.title = title
  }

  public var path: String { "/v1/bookmarks/create" }
  public var method: String { "POST" }
  public var parameters: [String: Any]? { ["folder": id, "title": title] }
  public var headers: [String: String]? { nil }
  public var forceSendAsGetParams: Bool { false }
}
