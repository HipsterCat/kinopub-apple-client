//
//  GenreVocabularyTests.swift
//
//  Our genre table and how each source's genres land in it.
//

import XCTest
@testable import KinoPubMedia

final class GenreVocabularyTests: XCTestCase {

  /// Ids from captured item payloads, next to the name each payload printed: the id table
  /// (from kino.pub's reference list) and the name must land on the same genre. The whole
  /// reference list is checked in `KinoPubMediaMappingTests`.
  func testEveryConfirmedKinoPubIDAgreesWithTheNameItWasCapturedWith() {
    let captured: [(id: Int, title: String, domain: GenreDomain, expected: String)] = [
      (2, "Боевик", .video, "action"),
      (4, "Фантастика", .video, "sci-fi"),
      (5, "Фэнтези", .video, "fantasy"),
      (6, "Семейный", .video, "family"),
      (8, "Приключения", .video, "adventure"),
      (9, "Драма", .video, "drama"),
      (10, "Мелодрама", .video, "romance"),
      (36, "Electronic", .music, "music.electronic"),
      (42, "New Age", .music, "music.new-age"),
      (100, "Trance", .music, "music.trance"),
      (102, "Chillout", .music, "music.chillout"),
    ]
    for row in captured {
      let byID = GenreVocabulary.kinopub(id: row.id, title: nil, domain: row.domain)
      let byName = GenreVocabulary.kinopub(id: -1, title: row.title, domain: row.domain)
      XCTAssertEqual(byID?.id, row.expected, "id \(row.id)")
      XCTAssertEqual(byName?.id, row.expected, "name \(row.title)")
    }
  }

  /// The ids `CatalogKind` already builds shelves on.
  func testTheCatalogKindGenreIDsAreKnown() {
    XCTAssertEqual(GenreVocabulary.kinopub(id: 23, title: nil, domain: .video)?.id, "animation")
    XCTAssertEqual(GenreVocabulary.kinopub(id: 25, title: nil, domain: .video)?.id, "anime")
    XCTAssertEqual(GenreVocabulary.kinopub(id: 26, title: nil, domain: .video)?.id, "short")
    XCTAssertEqual(GenreVocabulary.kinopub(id: 101, title: nil, domain: .video)?.id, "stand-up")
  }

  /// The API answers in either language; one idea is one genre.
  func testBothLanguagesLandOnOneGenre() {
    XCTAssertEqual(GenreVocabulary.named("Комедия", domain: .video),
                   GenreVocabulary.named("Comedy", domain: .video))
    XCTAssertEqual(GenreVocabulary.named("  КОМЕДИЯ ", domain: .video)?.id, "comedy")
    // kino.pub's English name for Фантастика.
    XCTAssertEqual(GenreVocabulary.named("Fantastic", domain: .video)?.id, "sci-fi")
  }

  /// TMDB's TV list folds pairs into one id; both halves are real genres of the title.
  func testATMDBPairIsTwoGenres() {
    XCTAssertEqual(GenreVocabulary.tmdb(id: 10759, name: "Action & Adventure").map(\.id),
                   ["action", "adventure"])
    XCTAssertEqual(GenreVocabulary.tmdb(id: 10765, name: "Sci-Fi & Fantasy").map(\.id),
                   ["sci-fi", "fantasy"])
    XCTAssertEqual(GenreVocabulary.tmdb(id: 10768, name: "War & Politics").map(\.id),
                   ["war", "politics"])
    XCTAssertEqual(GenreVocabulary.tmdb(id: 18, name: "Drama").map(\.id), ["drama"])
  }

  /// kino.pub's genre id and TMDB's are different numbers for one idea.
  func testSourcesAgreeThroughTheTable() {
    XCTAssertEqual(GenreVocabulary.kinopub(id: 9, title: nil, domain: .video),
                   GenreVocabulary.tmdb(id: 18, name: nil).first)
  }

  /// A concert's genres are looked up among music genres first, and a name only the
  /// other vocabulary knows is still found there.
  func testTheDomainIsAHintNotAWall() {
    XCTAssertEqual(GenreVocabulary.named("Electronic", domain: .video)?.id, "music.electronic")
    XCTAssertEqual(GenreVocabulary.named("Документальный", domain: .music)?.id, "documentary")
  }

  /// A name nobody mapped yet still shows, under the source's own words, and says so.
  func testAnUnknownGenreIsKeptAndMarked() throws {
    let genre = try XCTUnwrap(GenreVocabulary.kinopub(id: 777, title: "Киберпанк",
                                                      domain: .video))
    XCTAssertFalse(genre.isMapped)
    XCTAssertEqual(genre.id, "kinopub:777")
    XCTAssertEqual(genre.name.value(languageCode: "ru"), "Киберпанк")
    XCTAssertEqual(genre.name.value(languageCode: "en"), "Киберпанк")
  }

  func testNamesFollowTheLanguage() {
    let drama = GenreVocabulary.genre(id: "drama")
    XCTAssertEqual(drama?.name.value(languageCode: "ru"), "Драма")
    XCTAssertEqual(drama?.name.value(languageCode: "ru-RU"), "Драма")
    XCTAssertEqual(drama?.name.value(languageCode: "en"), "Drama")
    XCTAssertEqual(drama?.name.value(languageCode: nil), "Drama")
  }

  // MARK: - The table itself

  func testIDsAreUnique() {
    let ids = GenreVocabulary.definitions.map(\.genre.id)
    XCTAssertEqual(ids.count, Set(ids).count)
  }

  /// One name must never mean two genres in one vocabulary — the lookup would silently
  /// keep whichever came first.
  func testNoNameMeansTwoGenres() {
    var owner: [String: String] = [:]
    for definition in GenreVocabulary.definitions {
      let genre = definition.genre
      let names = [genre.name.en, genre.name.ru] + definition.aliases
      for name in Set(names.map(GenreVocabulary.normalize)) {
        let key = "\(genre.domain.rawValue)/\(name)"
        if let previous = owner[key] {
          XCTFail("\"\(name)\" is both \(previous) and \(genre.id)")
        }
        owner[key] = genre.id
      }
    }
  }

  /// Each kino.pub set numbers its own genres, so one idea holds several ids.
  func testOneIdeaAcrossKinoPubSets() {
    XCTAssertEqual(GenreVocabulary.kinopub(id: 3, title: nil, domain: .video)?.id, "biography")
    XCTAssertEqual(GenreVocabulary.kinopub(id: 78, title: nil, domain: .video)?.id, "biography")
    XCTAssertNil(GenreVocabulary.kinopub(id: 128, title: "Эксклюзив", domain: .video))
  }

  /// "Эксклюзив" is not a genre, but it is kept: a label, with kino.pub's own key.
  func testExclusiveIsALabel() {
    XCTAssertEqual(GenreVocabulary.kinopubLabel(id: 128)?.id, "exclusive")
    XCTAssertEqual(GenreVocabulary.kinopubLabel(id: 133)?.sourceKey, "genre:133")
    XCTAssertNil(GenreVocabulary.kinopubLabel(id: 9))
    XCTAssertEqual(GenreVocabulary.kinopubNonGenres, [128, 133])
  }

  /// The table is a file; it has to have loaded, and every row has to be usable.
  func testTheFileLoaded() {
    XCTAssertGreaterThan(GenreVocabulary.definitions.count, 100)
    XCTAssertNotNil(GenreVocabulary.genre(id: "tv-show"))
  }

  /// kino.pub's lists stay told apart: a documentary's subject is not a film genre.
  func testGroupsKeepKinoPubsSpecificity() {
    XCTAssertEqual(GenreVocabulary.genre(id: "drama").flatMap(GenreVocabulary.group), .film)
    XCTAssertEqual(GenreVocabulary.genre(id: "aviation").flatMap(GenreVocabulary.group),
                   .documentarySubject)
    XCTAssertEqual(GenreVocabulary.genre(id: "reality").flatMap(GenreVocabulary.group),
                   .tvFormat)
    XCTAssertEqual(GenreVocabulary.genre(id: "music.trance").flatMap(GenreVocabulary.group),
                   .music)
  }

  func testNoKinoPubIDIsClaimedTwice() {
    let ids = GenreVocabulary.definitions.flatMap(\.kinopub)
    XCTAssertEqual(ids.count, Set(ids).count)
  }

  func testMusicGenresLiveInTheMusicDomain() {
    for definition in GenreVocabulary.definitions {
      XCTAssertEqual(definition.genre.id.hasPrefix("music."), definition.genre.domain == .music,
                     definition.genre.id)
    }
  }
}
