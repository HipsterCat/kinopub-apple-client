//
//  UpdateBookmarkFolderRequestTests.swift
//

import XCTest
@testable import KinoPubBackend

final class UpdateBookmarkFolderRequestTests: XCTestCase {

  func testRenamePostsFolderAndTitleToCreate() {
    let request = UpdateBookmarkFolderRequest(id: 12, title: "Семейные")
    XCTAssertEqual(request.path, "/v1/bookmarks/create")
    XCTAssertEqual(request.method, "POST")
    XCTAssertEqual(request.parameters?["folder"] as? Int, 12)
    XCTAssertEqual(request.parameters?["title"] as? String, "Семейные")
    XCTAssertFalse(request.forceSendAsGetParams)
  }
}
