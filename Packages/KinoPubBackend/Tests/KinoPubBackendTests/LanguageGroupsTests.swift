//
//  LanguageGroupsTests.swift
//

import XCTest
@testable import KinoPubBackend

final class LanguageGroupsTests: XCTestCase {

  private let preferredRUThenEN = ["ru-RU", "en-US"]

  private func track(lang: String,
                     typeId: Int,
                     typeTitle: String,
                     author: String? = nil,
                     index: Int) -> AudioTrackInfo {
    AudioTrackInfo(lang: lang,
                   typeId: typeId,
                   typeTitle: typeTitle,
                   authorTitle: author,
                   index: index)
  }

  // MARK: - Audio summaries

  func testAudioGroupsByLanguageWithKindCountsAndStudios() {
    let tracks = [
      track(lang: "rus", typeId: 1, typeTitle: "Дубляж", author: "Кубик в Кубе", index: 1),
      track(lang: "rus", typeId: 1, typeTitle: "Дубляж", author: "Мосфильм", index: 2),
      track(lang: "rus", typeId: 2, typeTitle: "Многоголосый", author: "Jask", index: 3),
      track(lang: "rus", typeId: 2, typeTitle: "Многоголосый", author: nil, index: 4),
      track(lang: "eng", typeId: 6, typeTitle: "Оригинал", author: nil, index: 5),
      track(lang: "ukr", typeId: 2, typeTitle: "Многоголосый", author: "DniproFilm", index: 6)
    ]

    let groups = AudioTracks.languageGroups(for: tracks, preferredLanguages: preferredRUThenEN)
    XCTAssertEqual(groups.map(\.key), ["ru", "en", "uk"])

    let russian = groups[0]
    XCTAssertEqual(russian.detailLines[0],
                   expectedKindLine(typeId: 1, authors: ["Кубик в Кубе", "Мосфильм"]))
    XCTAssertTrue(russian.detailLines[1].contains("2"))
    XCTAssertTrue(russian.detailLines[1].contains("Jask"))

    let english = groups[1]
    XCTAssertEqual(english.detailLines, [
      AudioTracks.localizedKindLabel(typeId: 6, typeTitle: "Оригинал", typeShortTitle: nil)!
    ])
  }

  func testSingleAnonymousKindOmitsUnknownStudio() {
    let tracks = [track(lang: "eng", typeId: 6, typeTitle: "Оригинал", author: nil, index: 1)]
    let lines = AudioTracks.kindSummaryLines(for: tracks)
    XCTAssertEqual(lines.count, 1)
    XCTAssertFalse(lines[0].contains(","))
  }

  // MARK: - The original sound with no language (Midnight Girls, TMDB 1473592)

  private var midnightGirls: [AudioTrackInfo] {
    [track(lang: "rus", typeId: 2, typeTitle: "Многоголосый", index: 1),
     track(lang: "und", typeId: 6, typeTitle: "Оригинал", index: 2)]
  }

  func testUnnamedTrackBesideOneDubLanguageIsTheOriginal() {
    XCTAssertTrue(AudioTracks.unnamedIsOriginal(midnightGirls))
    // A concert's one track, kind unknown.
    XCTAssertTrue(AudioTracks.unnamedIsOriginal([track(lang: "und", typeId: -1, typeTitle: "", index: 1)]))
    // Dubs in two languages and a track of unknown kind: nothing says it is the original.
    XCTAssertFalse(AudioTracks.unnamedIsOriginal([
      track(lang: "rus", typeId: 2, typeTitle: "Многоголосый", index: 1),
      track(lang: "ukr", typeId: 2, typeTitle: "Многоголосый", index: 2),
      track(lang: "und", typeId: -1, typeTitle: "", index: 3)
    ]))
    // A named original is already there.
    XCTAssertFalse(AudioTracks.unnamedIsOriginal([
      track(lang: "eng", typeId: 6, typeTitle: "Оригинал", index: 1),
      track(lang: "und", typeId: -1, typeTitle: "", index: 2)
    ]))
  }

  func testUnnamedOriginalReadsOriginalLanguageNotUnknown() {
    let groups = AudioTracks.languageGroups(for: midnightGirls, preferredLanguages: preferredRUThenEN)
    XCTAssertEqual(groups.map(\.key), ["ru", "und"])
    XCTAssertEqual(groups[1].name, AudioTracks.originalLanguageName)
    XCTAssertEqual(groups[1].detailLines, [AudioTracks.languageNotSpecified])
  }

  func testTMDBNamesTheUnnamedOriginalAndListsTheOtherSpokenLanguages() {
    let languages = TitleLanguages(original: "tl", spoken: ["tl", "ja", "en"])
    let groups = AudioTracks.languageGroups(for: midnightGirls, preferredLanguages: preferredRUThenEN,
                                            languages: languages)
    XCTAssertEqual(groups.map(\.key), ["ru", "tl"])
    XCTAssertEqual(groups[1].name, LanguageNames.name(for: "tl"))
    XCTAssertEqual(groups[1].detailLines.count, 2)
    XCTAssertEqual(groups[1].detailLines[1],
                   AudioTracks.alsoSpokenLine(languages, besides: "tl"))
  }

  func testTMDBOriginalAlreadyOnTheMenuLeavesTheUnnamedTrackAlone() {
    let tracks = [track(lang: "rus", typeId: 6, typeTitle: "Оригинал", index: 1),
                  track(lang: "und", typeId: -1, typeTitle: "", index: 2)]
    let resolved = AudioTracks.resolvingUnnamedLanguage(tracks, languages: TitleLanguages(original: "ru"))
    XCTAssertEqual(resolved.map(\.lang), ["rus", "und"])
  }

  // MARK: - Visibility

  func testPreferredAndEnglishStayVisibleOthersCollapse() {
    let groups = [
      MediaLanguageGroup(key: "ru", name: "Russian", detailLines: ["dub"]),
      MediaLanguageGroup(key: "en", name: "English", detailLines: ["original"]),
      MediaLanguageGroup(key: "uk", name: "Ukrainian", detailLines: ["mvo"]),
      MediaLanguageGroup(key: "de", name: "German", detailLines: ["dub"])
    ]
    let result = LanguageListVisibility.partition(groups, preferredLanguages: ["ru"])
    XCTAssertEqual(result.visible.map(\.key), ["ru", "en"])
    XCTAssertEqual(result.hiddenCount, 2)
  }

  func testSingleLeftoverLanguageIsPromoted() {
    let groups = [
      MediaLanguageGroup(key: "ru", name: "Russian", detailLines: []),
      MediaLanguageGroup(key: "uk", name: "Ukrainian", detailLines: [])
    ]
    // English missing from the item; preferred is Russian — Ukrainian is the only leftover.
    let result = LanguageListVisibility.partition(groups, preferredLanguages: ["ru"])
    XCTAssertEqual(result.visible.map(\.key), ["ru", "uk"])
    XCTAssertEqual(result.hiddenCount, 0)
  }

  func testEmptyPreferredStillShowsFirstLanguage() {
    let groups = [
      MediaLanguageGroup(key: "ja", name: "Japanese", detailLines: []),
      MediaLanguageGroup(key: "ko", name: "Korean", detailLines: []),
      MediaLanguageGroup(key: "zh", name: "Chinese", detailLines: [])
    ]
    let result = LanguageListVisibility.partition(groups, preferredLanguages: ["fr"])
    XCTAssertEqual(result.visible.map(\.key), ["ja"])
    XCTAssertEqual(result.hiddenCount, 2)
  }

  // MARK: - Subtitles

  func testSubtitleGroupsSortPreferredFirstAndSummarizeBadges() {
    let tracks = SubtitleTracks.catalog([
      Subtitle(lang: "ukr", shift: 0, embed: false, url: "https://x/uk.srt"),
      Subtitle(lang: "eng", shift: 0, embed: false, url: "https://x/en.sdh.srt"),
      Subtitle(lang: "rus", shift: 0, embed: false, url: "https://x/ru.srt"),
      Subtitle(lang: "rus", shift: 0, embed: false, url: "https://x/ru.forced.srt")
    ])
    let groups = SubtitleTracks.languageGroups(for: tracks, preferredLanguages: preferredRUThenEN)
    XCTAssertEqual(groups.map(\.key), ["ru", "en", "uk"])
    XCTAssertEqual(groups[0].detailLines, ["2 ∙ Forced"])
    XCTAssertEqual(groups[1].detailLines, ["CC"])
    XCTAssertEqual(groups[2].detailLines, [])
  }

  private func expectedKindLine(typeId: Int, authors: [String]) -> String {
    let kind = AudioTracks.localizedKindLabel(typeId: typeId, typeTitle: "", typeShortTitle: nil)!
    return "\(kind) (\(authors.count)), \(authors.joined(separator: ", "))"
  }
}
