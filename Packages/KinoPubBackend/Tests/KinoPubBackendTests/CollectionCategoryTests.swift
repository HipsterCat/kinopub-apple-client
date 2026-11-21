//
//  CollectionCategoryTests.swift
//

import XCTest
@testable import KinoPubBackend

final class CollectionCategoryTests: XCTestCase {

  func testCatalogLoadsEveryCategoryInKpappOrder() {
    let catalog = CollectionCategory.catalog
    XCTAssertEqual(catalog.count, 38)
    XCTAssertEqual(catalog.first?.title, "Антологии")
    XCTAssertEqual(catalog.last?.title, "Другие")
    XCTAssertEqual(catalog.reduce(0) { $0 + $1.collections.count }, 531)
  }

  func testLooksUpACollectionsCategory() {
    XCTAssertEqual(CollectionCategory.containing(collectionID: 33)?.title, "Комиксы")
    // Its anchor is malformed in kpapp's page; the title was recovered by hand.
    XCTAssertEqual(CollectionCategory.containing(collectionID: 231)?.title, "Суб-жанры")
    XCTAssertNil(CollectionCategory.containing(collectionID: 999_999))
  }
}
