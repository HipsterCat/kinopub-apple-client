//
//  AudioRenditionsTests.swift
//
//  The bridge between what `TrackResolver` decides and what the player can select.
//  Covered without an asset on purpose — see `AudioRendition`.
//

import XCTest
@testable import KinoPubBackend

final class AudioRenditionsTests: XCTestCase {

  private struct Rendition: AudioRendition, Equatable {
    var renditionName: String
    var renditionLanguageCode: String = "ru"
    var describesVideoForAccessibility: Bool = false
  }

  private func track(_ lang: String,
                     _ typeId: Int,
                     _ studio: String? = nil,
                     index: Int = 0) -> AudioTrackInfo {
    let titles = [1: "Дубляж", 2: "Многоголосый", 3: "Двухголосый", 6: "Оригинал"]
    return AudioTrackInfo(lang: lang,
                          typeId: typeId,
                          typeTitle: titles[typeId],
                          authorTitle: studio,
                          index: index)
  }

  // MARK: - Finding the rendition for a decided track

  func testAnExactLabelWins() {
    let lostfilm = track("ru", 2, "LostFilm")
    let renditions = [Rendition(renditionName: "Английский ∙ Оригинал", renditionLanguageCode: "en"),
                      Rendition(renditionName: AudioTracks.baseLabel(lostfilm))]
    XCTAssertEqual(AudioRenditions.rendition(for: lostfilm, in: renditions, apiTracks: [lostfilm]),
                   renditions[1])
  }

  /// HLS forbids two identical `NAME=` in one group, so our labeller uniques them. The
  /// suffixed rendition is still the one the track means.
  func testASuffixedDuplicateStillMatches() {
    let lostfilm = track("ru", 2, "LostFilm")
    let label = AudioTracks.baseLabel(lostfilm)
    let renditions = [Rendition(renditionName: "\(label) ∙ 2")]
    XCTAssertEqual(AudioRenditions.rendition(for: lostfilm, in: renditions, apiTracks: [lostfilm]),
                   renditions[0])
  }

  /// The whole point of labelling: two Russian dubs must not be interchangeable.
  func testTwoDubsOfOneLanguageDoNotCollide() {
    let lostfilm = track("ru", 2, "LostFilm", index: 0)
    let kuraj = track("ru", 2, "Кураж-Бамбей", index: 1)
    let apiTracks = [lostfilm, kuraj]
    let renditions = [Rendition(renditionName: AudioTracks.baseLabel(lostfilm)),
                      Rendition(renditionName: AudioTracks.baseLabel(kuraj))]

    XCTAssertEqual(AudioRenditions.rendition(for: kuraj, in: renditions, apiTracks: apiTracks),
                   renditions[1])
  }

  /// A label that is a prefix of another must not swallow it: "Русский ∙ Дубляж" is not
  /// "Русский ∙ Дубляж, LostFilm".
  func testAPrefixOfALongerLabelIsNotAMatch() {
    let anonymous = track("ru", 1)
    let studio = track("ru", 1, "LostFilm")
    let renditions = [Rendition(renditionName: AudioTracks.baseLabel(studio))]
    XCTAssertNil(AudioRenditions.rendition(for: anonymous, in: renditions, apiTracks: [anonymous]))
  }

  func testAMissingRenditionIsNotInvented() {
    let syenduk = track("ru", 3, "Сыендук")
    let renditions = [Rendition(renditionName: "Английский ∙ Оригинал", renditionLanguageCode: "en")]
    XCTAssertNil(AudioRenditions.rendition(for: syenduk, in: renditions, apiTracks: [syenduk]))
  }

  // MARK: - The synthesised menu

  func testWithoutAPITracksTheMenuIsBuiltFromTheRenditions() {
    let renditions = [
      Rendition(renditionName: "Русский ∙ Дубляж, Мосфильм"),
      Rendition(renditionName: "Japanese", renditionLanguageCode: "ja"),
      Rendition(renditionName: "Описание", describesVideoForAccessibility: true)
    ]
    let menu = AudioRenditions.menu(from: renditions)

    XCTAssertEqual(menu.count, 3)
    XCTAssertEqual(menu[0].kindRank, 0, "the dub kind is readable from the name")
    XCTAssertEqual(menu[0].signature.studio, "Мосфильм", "display keeps the source's own case")
    XCTAssertEqual(menu[1].languageKey, "ja")
    XCTAssertTrue(menu[2].isAudioDescription)
    XCTAssertEqual(menu.map(\.index), [0, 1, 2], "index is the rendition's position")
  }

  func testASynthesisedTrackIsMatchedBackByPosition() {
    let renditions = [Rendition(renditionName: "One"),
                      Rendition(renditionName: "Two"),
                      Rendition(renditionName: "Three")]
    let menu = AudioRenditions.menu(from: renditions)
    XCTAssertEqual(AudioRenditions.rendition(for: menu[2], in: renditions, apiTracks: []),
                   renditions[2])
  }

  func testASynthesisedIndexPastTheEndFindsNothing() {
    let renditions = [Rendition(renditionName: "One")]
    let stale = track("ru", 2, "LostFilm", index: 7)
    XCTAssertNil(AudioRenditions.rendition(for: stale, in: renditions, apiTracks: []))
  }


  // MARK: - Writing down what played

  private func signature(_ rendition: Rendition, apiTracks: [AudioTrackInfo]) -> AudioTrackSignature? {
    AudioRenditions.signature(forRenditionAt: 0, in: [rendition], apiTracks: apiTracks)
  }

  func testTheAPIRowIsPreferredWhenTheRenditionMapsBack() {
    let syenduk = track("ru", 3, "Сыендук")
    let rendition = Rendition(renditionName: AudioTracks.baseLabel(syenduk))
    XCTAssertEqual(signature(rendition, apiTracks: [syenduk]), syenduk.signature)
  }

  func testASuffixedRenditionStillResolvesToItsAPIRow() {
    let syenduk = track("ru", 3, "Сыендук")
    let rendition = Rendition(renditionName: "\(AudioTracks.baseLabel(syenduk)) ∙ 2")
    XCTAssertEqual(signature(rendition, apiTracks: [syenduk]), syenduk.signature)
  }

  /// No API metadata at all — kind and studio are read out of the rendition's own name so
  /// the choice is still remembered as something more specific than "Russian".
  func testWithoutAnAPIRowTheNameIsRead() {
    let rendition = Rendition(renditionName: "Русский ∙ Двухголосый, Jaskier")
    let signature = signature(rendition, apiTracks: [])

    XCTAssertEqual(signature?.languageKey, "ru")
    XCTAssertEqual(signature?.kindRank, 2)
    XCTAssertEqual(signature?.studio, "Jaskier", "display keeps the source's own case")
  }

  func testAnUnlabelledRenditionStillCarriesItsLanguage() {
    let rendition = Rendition(renditionName: "Audio", renditionLanguageCode: "en")
    let signature = signature(rendition, apiTracks: [])
    XCTAssertEqual(signature?.languageKey, "en")
    XCTAssertEqual(signature?.kindRank, AudioTracks.kindRankUnknown)
    XCTAssertNil(signature?.studio)
  }

  /// A rendition whose name matches nothing must not borrow another dub's identity.
  func testAnUnrelatedRenditionDoesNotBorrowAnAPIRow() {
    let syenduk = track("ru", 3, "Сыендук")
    let rendition = Rendition(renditionName: "Русский ∙ Дубляж, Мосфильм")
    XCTAssertNotEqual(signature(rendition, apiTracks: [syenduk]), syenduk.signature)
  }

  // MARK: - The CDN's own names (`FeatureFlags.rewritesStreamTrackMenus` off)

  /// Item 126352's shape as the CDN names it: `NN. Kind. Studio (LANG)`, `NN` the API row.
  private var rezka: AudioTrackInfo { track("rus", 2, "Rezka", index: 1) }
  private var rezka18: AudioTrackInfo { track("rus", 2, "Rezka 18+", index: 2) }
  private var alpha: AudioTrackInfo { track("rus", 3, "AlphaProject", index: 3) }
  private var original: AudioTrackInfo { track("eng", 6, index: 4) }
  private var apiTracks: [AudioTrackInfo] { [rezka, rezka18, alpha, original] }

  private func sourceRenditions(copies: Int = 1) -> [Rendition] {
    let one = [Rendition(renditionName: "01. Многоголосый. Rezka (RUS)"),
               Rendition(renditionName: "02. Многоголосый. Rezka 18+ (RUS)"),
               Rendition(renditionName: "03. Двухголосый. AlphaProject (RUS)"),
               Rendition(renditionName: "04. Оригинал (ENG)", renditionLanguageCode: "en")]
    return Array(repeating: one, count: copies).flatMap { $0 }
  }

  func testTheLeadingNumberIsTheAPIRow() {
    let renditions = sourceRenditions()
    XCTAssertEqual(AudioRenditions.pairing(renditions, apiTracks: apiTracks.reversed(), naming: .asDelivered),
                   [rezka, rezka18, alpha, original])
    XCTAssertEqual(AudioRenditions.rendition(for: alpha, in: renditions, apiTracks: apiTracks,
                                             naming: .asDelivered),
                   renditions[2])
  }

  /// Without the rewrite, a master may list every dub once per video quality. Each copy is
  /// the same row — a pick made on any of them is remembered as that dub.
  func testEveryPerQualityCopyPairsWithItsRow() {
    let renditions = sourceRenditions(copies: 3)
    let paired = AudioRenditions.pairing(renditions, apiTracks: apiTracks, naming: .asDelivered)
    XCTAssertEqual(paired, Array(repeating: [rezka, rezka18, alpha, original], count: 3).flatMap { $0 })
    XCTAssertEqual(AudioRenditions.signature(forRenditionAt: 9, in: renditions, apiTracks: apiTracks,
                                             naming: .asDelivered),
                   rezka18.signature)
  }

  /// Item 127393 as captured: rows without a type are named `Track N (LANG)`, an AC-3 row
  /// gets " AC3" on the end, and every group repeats all three.
  func testUntypedRowsAreNamedTrackN() {
    let aac = AudioTrackInfo(lang: "rus", channels: 6, codec: "aac", index: 1)
    let original = AudioTrackInfo(lang: "rus", typeId: 6, typeTitle: "Оригинал", channels: 6, codec: "aac", index: 2)
    let ac3 = AudioTrackInfo(lang: "rus", channels: 6, codec: "ac3", index: 3)
    let group = [Rendition(renditionName: "Track 1 (RUS)"),
                 Rendition(renditionName: "02. Оригинал (RUS)"),
                 Rendition(renditionName: "Track 3 (RUS) AC3")]
    let renditions = group + group + group
    let paired = AudioRenditions.pairing(renditions, apiTracks: [aac, original, ac3], naming: .asDelivered)
    XCTAssertEqual(paired, [aac, original, ac3, aac, original, ac3, aac, original, ac3])

    let menu = AudioRenditions.menu(from: group)
    XCTAssertEqual(menu.map(\.kindRank), [AudioTracks.kindRankUnknown, 5, AudioTracks.kindRankUnknown])
    XCTAssertEqual(menu.map(\.authorTitle), [nil, nil, nil], "(RUS) is a language, not a studio")
  }

  /// No numbers to go by: same-language dubs are listed in the same order on both sides,
  /// so the API's `index` order is the pairing — each row taken once.
  func testUnnumberedNamesPairByLanguageInListingOrder() {
    let renditions = [Rendition(renditionName: "Russian"),
                      Rendition(renditionName: "Russian"),
                      Rendition(renditionName: "English", renditionLanguageCode: "en")]
    let paired = AudioRenditions.pairing(renditions, apiTracks: [original, rezka18, rezka],
                                         naming: .asDelivered)
    XCTAssertEqual(paired, [rezka, rezka18, original])
  }

  /// Our labels are never read as a CDN name, and the CDN's names are never read as ours.
  func testTheNamingDecidesHowNamesAreRead() {
    let relabelled = [Rendition(renditionName: AudioTracks.baseLabel(rezka))]
    XCTAssertEqual(AudioRenditions.pairing(relabelled, apiTracks: apiTracks, naming: .apiLabels), [rezka])
    XCTAssertEqual(AudioRenditions.pairing(sourceRenditions(), apiTracks: apiTracks, naming: .apiLabels),
                   [nil, nil, nil, nil])
  }

  /// A row the API does not list is still remembered as that dub, and "(RUS)" is the
  /// rendition's language — not a studio called RUS.
  func testAnUnpairedSourceNameIsReadAsKindAndStudio() {
    let renditions = [Rendition(renditionName: "07. Двухголосый. Кубик в Кубе (RUS)")]
    let signature = AudioRenditions.signature(forRenditionAt: 0, in: renditions, apiTracks: [original],
                                              naming: .asDelivered)
    XCTAssertEqual(signature?.languageKey, "ru")
    XCTAssertEqual(signature?.kindRank, 2)
    XCTAssertEqual(signature?.studio, "Кубик в Кубе")

    let menu = AudioRenditions.menu(from: [Rendition(renditionName: "04. Оригинал (ENG)",
                                                     renditionLanguageCode: "en")])
    XCTAssertEqual(menu[0].kindRank, 5)
    XCTAssertNil(menu[0].authorTitle)
  }
}
