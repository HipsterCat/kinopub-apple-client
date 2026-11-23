//
//  CoverArtworkTests.swift
//

import XCTest
@testable import KinoPubUI

final class CoverArtworkTests: XCTestCase {
  private let medium = "https://m.staticpop.net/poster/item/medium/1.jpg"
  private let big = "https://m.staticpop.net/poster/item/big/1.jpg"
  private let small = "https://m.staticpop.net/poster/item/small/1.jpg"
  private let wide = "https://m.staticpop.net/poster/item/wide/1.jpg"
  private let large = "https://kinopoiskapiunofficial.tech/images/posters/kp/322.jpg"
  private let compact = "https://kinopoiskapiunofficial.tech/images/posters/kp_small/322.jpg"

  private var savedCover: Any?
  private var savedLanguage: Any?

  override func setUp() {
    savedCover = UserDefaults.standard.object(forKey: CoverArtworkPreferences.languageKey)
    savedLanguage = UserDefaults.standard.object(forKey: "selectedLanguage")
    UserDefaults.standard.removeObject(forKey: CoverArtworkPreferences.languageKey)
  }

  override func tearDown() {
    restore(CoverArtworkPreferences.languageKey, savedCover)
    restore("selectedLanguage", savedLanguage)
  }

  func testRussianMediumAndBigUseTheLargeKinopoiskPoster() {
    CoverArtworkPreferences.set(.russian)
    XCTAssertEqual(CoverArtwork.resolve(url: medium, kinopoiskID: 322), large)
    XCTAssertEqual(CoverArtwork.resolve(url: big, kinopoiskID: 322), large)
  }

  func testRussianSmallUsesTheSmallKinopoiskPoster() {
    CoverArtworkPreferences.set(.russian)
    XCTAssertEqual(CoverArtwork.resolve(url: small, kinopoiskID: 322), compact)
  }

  func testWideArtAndAMissingIdStayKinoPub() {
    CoverArtworkPreferences.set(.russian)
    XCTAssertEqual(CoverArtwork.resolve(url: wide, kinopoiskID: 322), wide)
    XCTAssertEqual(CoverArtwork.resolve(url: medium, kinopoiskID: nil), medium)
    XCTAssertEqual(CoverArtwork.resolve(url: medium, kinopoiskID: 0), medium)
  }

  func testEnglishKeepsKinoPubCovers() {
    CoverArtworkPreferences.set(.english)
    XCTAssertEqual(CoverArtwork.resolve(url: big, kinopoiskID: 322), big)
  }

  func testAnUnsetChoiceFollowsTheAppLanguage() {
    UserDefaults.standard.set("ru", forKey: "selectedLanguage")
    XCTAssertEqual(CoverArtworkPreferences.language, .russian)
    UserDefaults.standard.set("en", forKey: "selectedLanguage")
    XCTAssertEqual(CoverArtworkPreferences.language, .english)
    UserDefaults.standard.set("de", forKey: "selectedLanguage")
    XCTAssertEqual(CoverArtworkPreferences.language, .english)
  }

  func testAnExplicitChoiceOutlivesTheAppLanguage() {
    CoverArtworkPreferences.set(.english)
    UserDefaults.standard.set("ru", forKey: "selectedLanguage")
    XCTAssertEqual(CoverArtworkPreferences.language, .english)
  }

  private func restore(_ key: String, _ value: Any?) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }
}

final class CardArtworkLadderTests: XCTestCase {
  private let medium = "https://m.staticpop.net/poster/item/medium/1.jpg"
  private let wide = "https://m.staticpop.net/poster/item/wide/1.jpg"
  private let kinopoisk = "https://kinopoiskapiunofficial.tech/images/posters/kp/16497.jpg"
  private var savedCover: Any?

  override func setUp() {
    savedCover = UserDefaults.standard.object(forKey: CoverArtworkPreferences.languageKey)
  }

  override func tearDown() {
    if let savedCover {
      UserDefaults.standard.set(savedCover, forKey: CoverArtworkPreferences.languageKey)
    } else {
      UserDefaults.standard.removeObject(forKey: CoverArtworkPreferences.languageKey)
    }
  }

  /// «Иностранная интрига» on Mac Home: the wide backdrop was cropped into the poster
  /// tile while the Kinopoisk cover loaded. A vertical card tries vertical covers only.
  func testAPosterCardNeverTriesTheBackdrop() {
    CoverArtworkPreferences.set(.russian)
    let card = MediaCard(id: 1, posterURL: medium, title: "Иностранная интрига",
                         backdropURL: wide, kinopoiskID: 16497)
    XCTAssertEqual(card.artworkLadder.map(\.absoluteString), [kinopoisk, medium])
  }

  func testEnglishPosterCardTriesItsKinoPubCoverOnce() {
    CoverArtworkPreferences.set(.english)
    let card = MediaCard(id: 1, posterURL: medium, title: "T", backdropURL: wide, kinopoiskID: 16497)
    XCTAssertEqual(card.artworkLadder.map(\.absoluteString), [medium])
  }

  func testAWideCardKeepsTheBackdropAsTheLastResort() {
    let still = "https://example.com/still.jpg"
    var card = MediaCard(id: 1, posterURL: medium, title: "T", backdropURL: wide,
                         landscapeImageURL: still)
    card.fallbackLandscapeURL = "https://example.com/thumb.jpg"
    XCTAssertEqual(card.artworkLadder.map(\.absoluteString),
                   [still, "https://example.com/thumb.jpg", wide])
  }
}
