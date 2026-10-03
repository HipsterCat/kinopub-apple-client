//
//  PlayerInfoTests.swift
//
//  What the system player is told. The panel itself cannot be asserted without a
//  device, but what we hand it can — field by field, through the identifiers Apple
//  documents for it.
//

import AVFoundation
import XCTest
@testable import KinoPubMedia

final class PlayerInfoTests: XCTestCase {

  private let comedy = GenreVocabulary.genre(id: "comedy")!
  private let sport = GenreVocabulary.genre(id: "sport")!

  private var show: MediaEntity {
    MediaEntity(kind: .show, title: "Ted Lasso", synopsis: Synopsis(full: "A coach."),
                genres: [comedy, sport], release: .day(year: 2020, month: 8, day: 14),
                contentRating: ContentRating("16+"))
  }

  private func episode(title: String? = "Goodbye Earl") -> MediaEntity {
    MediaEntity(kind: .episode, title: title, seasonNumber: 2, episodeNumber: 5)
  }

  // MARK: - The fields

  func testAnEpisodeReadsAsItsShowWithItsNumberAndName() {
    let info = PlayerInfo(context: MediaContext(item: episode(), parent: show), language: .en)
    XCTAssertEqual(info.title, "Ted Lasso")
    XCTAssertEqual(info.subtitle, "S2, E5: Goodbye Earl")
    XCTAssertEqual(info.description, "A coach.")
    XCTAssertEqual(info.contentRating, "16+")
  }

  /// The name is dropped when it only repeats the title line, and absent when there is none.
  func testTheEpisodeLineCarriesTheNameOnlyWhenItSaysSomething() {
    XCTAssertEqual(PlayerInfo(context: MediaContext(item: episode(title: "Ted Lasso"),
                                                    parent: show), language: .en).subtitle,
                   "Season 2, Episode 5")
    XCTAssertEqual(PlayerInfo(context: MediaContext(item: episode(title: nil),
                                                    parent: show), language: .en).subtitle,
                   "Season 2, Episode 5")
  }

  /// **One genre.** Apple's card and panel say "Comedy" for a show filed under Comedy and
  /// Sport; a comma list there is what got truncated.
  func testOnlyThePrimaryGenreIsSent() {
    let info = PlayerInfo(context: MediaContext(item: episode(), parent: show), language: .en)
    XCTAssertEqual(info.genre, "Comedy")
  }

  func testTheGenreSpeaksTheViewersLanguage() {
    let info = PlayerInfo(context: MediaContext(item: episode(), parent: show), language: .ru)
    XCTAssertEqual(info.genre, "Комедия")
    XCTAssertEqual(info.subtitle, "2 сезон, 5 серия: Goodbye Earl")
  }

  /// Only one season known, and it is the first: the season goes without saying
  /// (user's spec, 2026-10-03).
  func testAShowWithOnlyItsFirstSeasonSaysTheEpisodeAlone() {
    var single = show
    single.seasonCount = 1
    let first = MediaEntity(kind: .episode, title: "Pilot", seasonNumber: 1, episodeNumber: 1)
    let unnamed = MediaEntity(kind: .episode, title: "Эпизод 1", seasonNumber: 1, episodeNumber: 1)
    XCTAssertEqual(PlayerInfo(context: MediaContext(item: first, parent: single),
                              language: .en).subtitle, "Episode 1: Pilot")
    XCTAssertEqual(PlayerInfo(context: MediaContext(item: unnamed, parent: single),
                              language: .en).subtitle, "Episode 1")
    XCTAssertEqual(PlayerInfo(context: MediaContext(item: first, parent: single),
                              language: .ru).subtitle, "1 серия: Pilot")
    XCTAssertEqual(PlayerInfo(context: MediaContext(item: unnamed, parent: single),
                              language: .ru).subtitle, "1 серия")
  }

  /// A concert leads with its music genre.
  func testAConcertLeadsWithItsMusicGenre() {
    let concert = MediaEntity(kind: .movie, title: "Schiller / Nature One",
                              genres: [GenreVocabulary.genre(id: "music.electronic")!,
                                       GenreVocabulary.genre(id: "concert")!])
    XCTAssertEqual(PlayerInfo(context: MediaContext(item: concert)).genre, "Electronic")
  }

  func testTheDateIsISOAtThePrecisionWeHave() {
    XCTAssertEqual(PlayerInfo(context: MediaContext(item: show)).creationDate, "2020-08-14")
    let film = MediaEntity(kind: .movie, release: .year(1999))
    XCTAssertEqual(PlayerInfo(context: MediaContext(item: film)).creationDate, "1999")
  }

  /// A trailer's Info is the title's: its name as the heading (no «Trailer» subtitle, which
  /// the Info tab would put there instead), its description, genre and rating.
  func testATrailerIsItsTitle() {
    let trailer = MediaEntity(kind: .extra, extraKind: .trailer)
    let info = PlayerInfo(context: MediaContext(item: trailer, parent: show))
    XCTAssertEqual(info.title, "Ted Lasso")
    XCTAssertNil(info.subtitle)
    XCTAssertEqual(info.description, "A coach.")
    XCTAssertEqual(info.genre, "Comedy")
    XCTAssertEqual(info.contentRating, "16+")
  }

  /// A multi-version film names the version playing: "48 fps".
  func testAnEditionIsTheSubtitle() {
    let film = MediaEntity(kind: .movie, title: "Masters of the Universe", edition: "48 fps")
    XCTAssertEqual(PlayerInfo(context: MediaContext(item: film)).subtitle, "48 fps")
  }

  // MARK: - What reaches AVFoundation

  private func value(_ identifier: AVMetadataIdentifier, in items: [AVMetadataItem]) -> String? {
    items.first { $0.identifier == identifier }?.stringValue
  }

  private func utcNoon(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
  }

  /// A date-shaped *string* renders as a stray number in tvOS's title view ("2025" → 2026,
  /// "2025-01-01" → 12169); an `NSDate` renders the year. Noon UTC survives every viewer
  /// time zone — midnight showed the previous year west of Greenwich.
  func testTheDateReachesAVKitAsADateAtNoonUTC() {
    func sent(_ film: MediaEntity) -> AVMetadataItem? {
      PlayerInfo(context: MediaContext(item: film)).metadataItems()
        .first { $0.identifier == .commonIdentifierCreationDate }
    }
    let yearOnly = sent(MediaEntity(kind: .movie, title: "F", release: .year(2025)))
    XCTAssertEqual(yearOnly?.dateValue, utcNoon(2025, 1, 1))
    XCTAssertNil(yearOnly?.stringValue.flatMap { Int($0) })
    XCTAssertEqual(PlayerInfo.panelDate("2025-03-14"), utcNoon(2025, 3, 14))
    XCTAssertNil(PlayerInfo.panelDate("soon"))
    XCTAssertNil(PlayerInfo.panelDate(""))
  }

  /// Apple's documented identifiers, and only those plus the creation date.
  func testEachFieldGoesThroughItsDocumentedIdentifier() {
    let items = PlayerInfo(context: MediaContext(item: episode(), parent: show), language: .en)
      .metadataItems()
    XCTAssertEqual(value(.commonIdentifierTitle, in: items), "Ted Lasso")
    XCTAssertEqual(value(.iTunesMetadataTrackSubTitle, in: items), "S2, E5: Goodbye Earl")
    XCTAssertEqual(value(.commonIdentifierDescription, in: items), "A coach.")
    XCTAssertEqual(value(.quickTimeMetadataGenre, in: items), "Comedy")
    XCTAssertEqual(value(.iTunesMetadataContentRating, in: items), "16+")
    XCTAssertEqual(items.first { $0.identifier == .commonIdentifierCreationDate }?.dateValue,
                   utcNoon(2020, 8, 14))
    // Where genres went before — no Apple surface reads it as a genre.
    XCTAssertNil(value(.commonIdentifierType, in: items))
  }

  /// An empty line in the panel is worse than an absent one: it reserves the space.
  func testNothingEmptyIsSent() {
    let bare = MediaEntity(kind: .movie, title: "  ")
    XCTAssertTrue(PlayerInfo(context: MediaContext(item: bare)).metadataItems().isEmpty)
  }

  /// Tagging these with a language makes AVFoundation filter them against the viewer's
  /// own locale, and the panel then shows nothing.
  func testEverythingIsLanguageNeutral() {
    let items = PlayerInfo(context: MediaContext(item: episode(), parent: show)).metadataItems()
    XCTAssertFalse(items.isEmpty)
    for item in items {
      XCTAssertEqual(item.extendedLanguageTag, "und")
    }
    XCTAssertEqual(PlayerInfo.artworkItem(Data([0xFF, 0xD8])).extendedLanguageTag, "und")
  }

  func testArtworkDeclaresWhatItIs() {
    let png = PlayerInfo.artworkItem(Data([0x89, 0x50, 0x4E, 0x47, 0x0D]))
    XCTAssertEqual(png.dataType, kCMMetadataBaseDataType_PNG as String)
    let jpeg = PlayerInfo.artworkItem(Data([0xFF, 0xD8, 0xFF]))
    XCTAssertEqual(jpeg.dataType, kCMMetadataBaseDataType_JPEG as String)
    XCTAssertEqual(jpeg.identifier, .commonIdentifierArtwork)
  }
}
