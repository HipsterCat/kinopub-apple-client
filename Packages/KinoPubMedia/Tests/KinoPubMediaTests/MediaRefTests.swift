//
//  MediaRefTests.swift
//
//  One key for one thing, whichever API handed over its parts.
//

import XCTest
@testable import KinoPubMedia

final class MediaRefTests: XCTestCase {

  func testKindsFollowTheParts() {
    XCTAssertEqual(MediaRef.title(7).kind, .title)
    XCTAssertEqual(MediaRef.episode(7, season: 2, number: 5).kind, .episode)
    XCTAssertEqual(MediaRef.version(7, number: 2).kind, .version)
  }

  /// `/v1/watching` hands a season without a number, or a film's video number without a
  /// season. Neither is an episode.
  func testRawPartsNormalise() {
    XCTAssertEqual(MediaRef(itemID: 7, season: 2, number: nil), .title(7))
    XCTAssertEqual(MediaRef(itemID: 7, season: nil, number: 1), .version(7, number: 1))
    XCTAssertEqual(MediaRef(itemID: 7, season: nil, number: nil), .title(7))
    XCTAssertEqual(MediaRef(itemID: 7, season: 1, number: 3), .episode(7, season: 1, number: 3))
  }

  /// A film's versions share one watch state; an episode keeps its own.
  func testWatchStateIsTheFilmsOrTheEpisodes() {
    XCTAssertEqual(MediaRef.version(7, number: 2).watchRef, .title(7))
    XCTAssertEqual(MediaRef.title(7).watchRef, .title(7))
    let episode = MediaRef.episode(7, season: 2, number: 5)
    XCTAssertEqual(episode.watchRef, episode)
    XCTAssertEqual(episode.title, .title(7))
  }

  func testReadingOrder() {
    let refs: [MediaRef] = [.episode(7, season: 2, number: 1), .title(7),
                            .episode(7, season: 1, number: 10), .episode(7, season: 1, number: 2)]
    XCTAssertEqual(refs.sorted(), [.title(7), .episode(7, season: 1, number: 2),
                                   .episode(7, season: 1, number: 10),
                                   .episode(7, season: 2, number: 1)])
  }

  func testCodableAndDescription() throws {
    let ref = MediaRef.episode(7, season: 2, number: 5)
    XCTAssertEqual(try JSONDecoder().decode(MediaRef.self, from: JSONEncoder().encode(ref)), ref)
    XCTAssertEqual(ref.description, "7:s2e5")
    XCTAssertEqual(MediaRef.version(7, number: 2).description, "7:v2")
  }
}
