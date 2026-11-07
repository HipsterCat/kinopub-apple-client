//
//  PlayerTrackSelectionTests.swift
//  KinoPubAppleClientTests
//
//  That the player asks the resolver — and gets the same answer — on every platform this
//  bundle runs on. The gap this covers was not a wrong rule but a missing one: the
//  cataloguing and the decision were fenced to tvOS, so on iOS nothing chose anything and
//  no test noticed, because there was no player test at all.
//
//  The bridge to what the system player can actually select (`SubtitleRenditions`) is
//  covered here too rather than only in `KinoPubBackend`: package tests run on macOS alone,
//  and this bundle runs on the iOS and tvOS simulators in CI.
//

import XCTest
import AVFoundation
import KinoPubBackend
import KinoPubKit
import KinoPubMedia
// The app target's module is `KinoPub` — see `PlaybackPreflightTests`.
@testable import KinoPub

@MainActor
final class PlayerTrackSelectionTests: XCTestCase {

  private struct StubItem: PlayableItem {
    let id: Int
    var files: [FileInfo] = []
    var trailer: Trailer?
    var metadata: WatchingMetadata
    var subtitles: [Subtitle] = []
    var audioTracks: [AudioTrackInfo] = []
  }

  private var defaults: UserDefaults!
  private var suiteName: String!
  private var store: TrackPreferenceStore!
  private var preflight: PlaybackPreflight!

  /// The app's language settings live in `UserDefaults.standard`, which the player reads.
  /// Pinned for every test to Sasha's own setup — Russian audio, English subtitles, shown
  /// with foreign audio — so nothing here depends on the simulator's languages.
  private static let settingKeys = [PlaybackLanguagePreferences.audioLanguagesKey,
                                    PlaybackLanguagePreferences.subtitleLanguagesKey,
                                    PlaybackLanguagePreferences.subtitleModeKey]
  private var savedSettings: [String: Any] = [:]

  override func setUpWithError() throws {
    suiteName = "PlayerTrackSelectionTests.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    store = TrackPreferenceStore(defaults: defaults)
    preflight = PlaybackPreflight(preferences: store, contentService: VideoContentServiceMock())
    // Runs the one-time migration first, so it cannot overwrite the list below.
    _ = PlaybackLanguagePreferences.current
    for key in Self.settingKeys {
      savedSettings[key] = UserDefaults.standard.object(forKey: key)
    }
    PlaybackLanguageList.set(.audio, ["ru"])
    PlaybackLanguageList.set(.subtitles, ["en"])
    PlaybackLanguagePreferences.setSubtitleMode(.foreignAudio)
  }

  override func tearDownWithError() throws {
    defaults.removePersistentDomain(forName: suiteName)
    for key in Self.settingKeys {
      UserDefaults.standard.set(savedSettings[key], forKey: key)
    }
  }

  private func subtitles(_ languages: [String]) -> [Subtitle] {
    languages.map { Subtitle(lang: $0, shift: 0, embed: false, url: "https://e.x/\($0).srt") }
  }

  private func manager(for item: StubItem, mode: WatchMode = .media) -> PlayerManager {
    PlayerManager(playItem: item,
                  watchMode: mode,
                  downloadedFilesDatabase: DownloadedFilesDatabase<DownloadMeta>(fileSaver: FileSaver()),
                  actionsService: UserActionsServiceMock(),
                  contentService: VideoContentServiceMock(),
                  trackPreferences: store,
                  preflight: preflight)
  }

  private func item(subtitles languages: [String],
                    audio: [AudioTrackInfo] = []) -> StubItem {
    StubItem(id: 7,
             metadata: WatchingMetadata(id: 7, video: 1, season: nil),
             subtitles: subtitles(languages),
             audioTracks: audio)
  }

  // MARK: - The player asks, on every platform

  /// The catalogue existing at all is the platform-fenced half that was missing: off tvOS
  /// `subtitleTracks` stayed empty, so there was nothing for anything to decide between.
  func testTheItemsSubtitlesAreCataloguedWhereverThePlayerRuns() {
    let player = manager(for: item(subtitles: ["rus", "eng"]))
    XCTAssertEqual(player.subtitleTracks.count, 2)
    XCTAssertEqual(player.subtitleTracks.map(\.lang), ["rus", "eng"])
  }

  /// The player must not answer this question its own way. Whatever a card or a Play button
  /// would have been told is what the player opens with.
  func testTheOpeningSubtitleIsWhateverThePreflightDecided() {
    let stub = item(subtitles: ["rus", "eng"])
    let expected = preflight.plan(for: stub,
                                  profile: TitleTrackProfile(),
                                  subtitles: SubtitleSelector.tracks(in: stub.subtitles))
    XCTAssertEqual(manager(for: stub).primaryTrack, expected.decision.subtitle)
  }

  /// A remembered choice is the strongest input there is, and it has to reach the player on
  /// the platform the choice was made on *and* the ones it was not.
  func testARememberedChoiceIsWhatThePlayerOpensWith() throws {
    let stub = item(subtitles: ["rus", "eng"])
    let english = try XCTUnwrap(SubtitleSelector.tracks(in: stub.subtitles).last)
    store.recordSubtitle(SubtitleChoiceSignature(english),
                         in: preflight.scopes(for: stub, profile: TitleTrackProfile()),
                         picked: true)
    XCTAssertEqual(manager(for: stub).primaryTrack?.lang, "eng")
  }

  /// "Off" is a choice like any other — the next episode has to honour it.
  func testARememberedOffOpensWithoutSubtitles() {
    let stub = item(subtitles: ["rus", "eng"])
    PlaybackLanguagePreferences.setSubtitleMode(.always)
    store.recordSubtitle(.off, in: preflight.scopes(for: stub, profile: TitleTrackProfile()),
                         picked: true)
    XCTAssertNil(manager(for: stub).primaryTrack)
  }

  // MARK: - The everyday case: a pick carries to the next episode

  /// Five episodes of one season watched the way they opened — LostFilm, no subtitles —
  /// then, in episode 6, the viewer switches to the original and turns English subtitles
  /// on, and the next episode starts (Up Next, *Episodes*, or on its own) without leaving
  /// the player. Episode 7 has to open the way 6 was left.
  ///
  /// It did not: a pick counted as one play, the season had "LostFilm × 6, off × 6" against
  /// "original × 1, English × 1", and the count won — subtitles off, dub back, every time.
  private let lostFilm = AudioTrackInfo(lang: "rus", typeId: 2, typeTitle: "Многоголосый",
                                        authorTitle: "LostFilm", index: 1)
  private let kuraj = AudioTrackInfo(lang: "rus", typeId: 3, typeTitle: "Двухголосый",
                                     authorTitle: "Кураж-Бамбей", index: 2)
  private let original = AudioTrackInfo(lang: "eng", typeId: 6, typeTitle: "Оригинал", index: 3)
  /// A full dub that only arrives with a later episode — the "new better dub" rule's case.
  private let studioDub = AudioTrackInfo(lang: "rus", typeId: 4, typeTitle: "Дубляж",
                                         authorTitle: "Пифагор", index: 4)

  private func episode(_ number: Int, audio: [AudioTrackInfo]? = nil) -> StubItem {
    StubItem(id: 1000 + number,
             metadata: WatchingMetadata(id: 42, video: number, season: 1),
             subtitles: subtitles(["rus", "eng"]),
             audioTracks: audio ?? [lostFilm, kuraj, original])
  }

  /// What the tick writes for an episode watched past the Continue Watching floor the way
  /// it opened: one play of its dub. Subtitles are not counted.
  private func watchedAsOpened(_ item: StubItem) {
    let player = manager(for: item)
    let scopes = preflight.scopes(for: item, profile: TitleTrackProfile())
    if let audio = player.plan.decision.audio {
      store.recordAudio(AudioTrackSignature(audio), in: scopes)
    }
  }

  /// Written as the tick would have, rather than left to the ladder. The "off" plays are
  /// what builds used to count; they are here to show they no longer vote.
  private func seasonWatchedWithLostFilmAndNoSubtitles() throws {
    for number in 1...5 {
      let scopes = preflight.scopes(for: episode(number), profile: TitleTrackProfile())
      store.recordAudio(AudioTrackSignature(lostFilm), in: scopes)
      store.recordSubtitle(.off, in: scopes)
    }
    let sixth = manager(for: episode(6))
    XCTAssertEqual(sixth.plan.decision.audio, lostFilm, "the habit this test starts from")
    XCTAssertNil(sixth.primaryTrack, "the habit this test starts from")
  }

  func testSubtitlesAndDubPickedInOneEpisodeAreWhatTheNextOneOpensWith() throws {
    try seasonWatchedWithLostFilmAndNoSubtitles()

    // Episode 6: past the floor the tick has already counted what it opened with…
    watchedAsOpened(episode(6))
    // …then the viewer picks in the system menus.
    let sixth = manager(for: episode(6))
    let english = try XCTUnwrap(sixth.subtitleTracks.first { $0.lang == "eng" })
    sixth.viewerPicked(audio: AudioTrackSignature(original))
    sixth.viewerPicked(subtitle: SubtitleChoiceSignature(english))

    let seventh = manager(for: episode(7))
    XCTAssertEqual(seventh.plan.decision.audio, original, "the dub went back to the season's habit")
    XCTAssertEqual(seventh.primaryTrack?.lang, "eng", "subtitles went off on the next episode")
  }

  /// And it keeps holding: watching on with the pick does not let the old count take over
  /// again on episode 8.
  func testThePickHoldsForTheRestOfTheSeason() throws {
    try seasonWatchedWithLostFilmAndNoSubtitles()
    let sixth = manager(for: episode(6))
    let english = try XCTUnwrap(sixth.subtitleTracks.first { $0.lang == "eng" })
    sixth.viewerPicked(audio: AudioTrackSignature(original))
    sixth.viewerPicked(subtitle: SubtitleChoiceSignature(english))

    for number in 7...9 { watchedAsOpened(episode(number)) }
    let tenth = manager(for: episode(10))
    XCTAssertEqual(tenth.plan.decision.audio, original)
    XCTAssertEqual(tenth.primaryTrack?.lang, "eng")
  }

  /// A dub the viewer chose is not a stopgap: a studio dub showing up on the next episode
  /// does not take over a pick made one episode ago, however few plays it has.
  func testAPickIsNotDisplacedByANewDubOnTheNextEpisode() throws {
    try seasonWatchedWithLostFilmAndNoSubtitles()
    manager(for: episode(6)).viewerPicked(audio: AudioTrackSignature(original))

    let seventh = manager(for: episode(7, audio: [studioDub, lostFilm, kuraj, original]))
    XCTAssertEqual(seventh.plan.decision.audio, original)
  }

  /// Turning subtitles back off is a pick too, and the newest pick is the one that holds.
  func testTurningSubtitlesBackOffIsAlsoCarried() throws {
    try seasonWatchedWithLostFilmAndNoSubtitles()
    let sixth = manager(for: episode(6))
    let english = try XCTUnwrap(sixth.subtitleTracks.first { $0.lang == "eng" })
    sixth.viewerPicked(subtitle: SubtitleChoiceSignature(english))
    manager(for: episode(7)).viewerPicked(subtitle: .off)

    XCTAssertNil(manager(for: episode(8)).primaryTrack)
  }

  // MARK: - Subtitle mode, with no pick

  func testShownWithForeignAudioFollowsTheDub() {
    XCTAssertNil(manager(for: episode(1)).primaryTrack, "Russian audio is not foreign")
    XCTAssertEqual(manager(for: episode(1, audio: [original])).primaryTrack?.lang, "eng")
  }

  func testAlwaysEnabledPutsThemOnARussianDub() {
    PlaybackLanguagePreferences.setSubtitleMode(.always)
    XCTAssertEqual(manager(for: episode(1)).primaryTrack?.lang, "eng")
  }

  func testManuallySelectedOpensBareEvenInTheOriginal() {
    PlaybackLanguagePreferences.setSubtitleMode(.manual)
    XCTAssertNil(manager(for: episode(1, audio: [original])).primaryTrack)
  }

  /// "Ukrainian first" is a list edit, not a new setting.
  func testTheFirstListedSubtitleLanguageAnEpisodeHasWins() {
    PlaybackLanguagePreferences.setSubtitleMode(.always)
    PlaybackLanguageList.set(.subtitles, ["uk", "en"])
    let item = StubItem(id: 1, metadata: WatchingMetadata(id: 42, video: 1, season: 1),
                        subtitles: subtitles(["rus", "eng", "ukr"]), audioTracks: [lostFilm])
    XCTAssertEqual(manager(for: item).primaryTrack?.lang, "ukr")
  }

  /// What `noteViewerPicks` treats as a pick (`PickWatch`).
  func testWhatCountsAsAPick() {
    typealias Pick = SubtitleChoiceSignature
    let eng = Pick(languageKey: "eng", isCC: false)
    let rus = Pick(languageKey: "rus", isCC: false)
    var watch = PickWatch<Pick>()
    watch.request(eng)
    // The Mac's blip while English was being applied (2026-11-07): not the viewer.
    XCTAssertNil(watch.observe(Pick.off))
    XCTAssertNil(watch.observe(eng), "what was asked for, now on screen: settled, not a pick")
    XCTAssertEqual(watch.observe(Pick.off), Pick.off, "after that, Off is the viewer's")
    XCTAssertNil(watch.observe(Pick.off), "the same pick seen again is written once")
    XCTAssertEqual(watch.observe(rus), rus)
    XCTAssertEqual(watch.observe(eng), eng, "back to what it opened with is a pick too")
  }

  /// A selection the system never shows as asked settles on the first tick, as the baseline.
  func testATickSettlesWhateverIsShowing() {
    typealias Pick = SubtitleChoiceSignature
    let eng = Pick(languageKey: "eng", isCC: false)
    var watch = PickWatch<Pick>()
    watch.request(eng)
    XCTAssertNil(watch.observe(Pick.off, settling: true))
    XCTAssertNil(watch.observe(Pick.off))
    XCTAssertEqual(watch.observe(eng), eng)
  }

  func testATrailerChoosesNothingAndTeachesNothing() {
    let player = manager(for: item(subtitles: ["rus"]), mode: .trailer)
    XCTAssertTrue(player.subtitleTracks.isEmpty)
    XCTAssertNil(player.primaryTrack)
  }

  // MARK: - The bridge to what the system player can select

  /// Same assertions as the package's own, run here because these are the platforms the
  /// selection actually happens on.
  func testTheDecidedTrackFindsItsRenditionOnThisPlatform() throws {
    let catalog = SubtitleSelector.tracks(in: subtitles(["rus", "eng", "ai"]))
    let renditions = [StubRendition(renditionLanguageCode: "ru"),
                      StubRendition(renditionLanguageCode: "en"),
                      StubRendition(renditionLanguageCode: "ai")]
    for (index, track) in catalog.enumerated() {
      XCTAssertEqual(SubtitleRenditions.renditionIndex(for: track, among: catalog, in: renditions),
                     index,
                     "\(track.lang) did not find its rendition")
    }
  }

  func testMachineTranslatedRussianIsItsOwnLanguageOnThisPlatform() {
    XCTAssertNotEqual(SubtitleTracks.languageKey("ai"), SubtitleTracks.languageKey("rus"))
    XCTAssertEqual(SubtitleTracks.languageKey("uzb"), "uz")
    XCTAssertEqual(SubtitleTracks.languageKey("phi"), "fil")
  }

  /// Every language id kino.pub's own reference list ships, resolved through one table.
  /// A code that normalises to nothing matches nothing, and the viewer silently loses that
  /// language — which is what `uzb` and `phi` did.
  func testEveryKinoPubSubtitleLanguageResolvesToSomething() {
    let ids = ["rus", "eng", "ukr", "fre", "ger", "spa", "ita", "por", "fin", "pol", "chi",
               "jpn", "kor", "hin", "heb", "swe", "nor", "dan", "ron", "kaz", "uzb", "phi",
               "tur", "ai"]
    var keys: Set<String> = []
    for id in ids {
      let key = SubtitleTracks.languageKey(id)
      XCTAssertFalse(key.isEmpty, "\(id) normalised to nothing")
      XCTAssertTrue(keys.insert(key).inserted, "\(id) collided with another language on \(key)")
      XCTAssertFalse(LanguageNames.name(for: id).isEmpty, "\(id) has no name to show")
    }
  }

  // MARK: - What the system player is told

  /// The panel cannot be asserted without a device, but what the player hands it can —
  /// on the platforms whose panel we are talking about: an episode carries its series'
  /// name, description and **one** genre, through the identifiers Apple documents.
  func testAnEpisodeCarriesItsSeriesIntoTheInfoPanel() async throws {
    let series = MediaItem.mock()
    let episode = Episode(id: 900, title: "Pilot", thumbnail: "", duration: 1500, tracks: 1,
                          number: 2, ac3: 0, audios: [], watched: 0,
                          watching: EpisodeWatching(status: 0, time: 0), subtitles: [],
                          files: [])
    episode.seasonNumber = 1
    let draft = PlaybackMediaContext.draft(playing: episode, title: series, isTrailer: false)
    let context = try XCTUnwrap(MediaAggregator.merge(draft))
    let items = PlayerInfo(context: context, language: .en).metadataItems()
    func value(_ identifier: AVMetadataIdentifier) async -> String? {
      try? await items.first { $0.identifier == identifier }?.load(.stringValue)
    }
    let title = await value(.commonIdentifierTitle)
    let subtitle = await value(.iTunesMetadataTrackSubTitle)
    let description = await value(.commonIdentifierDescription)
    let genre = await value(.quickTimeMetadataGenre)
    let type = await value(.commonIdentifierType)
    XCTAssertEqual(title, series.localizedTitle)
    // The player's length (`MediaSurface.playerSubtitle`): a name makes room by shortening
    // the reference (docs/product/media-text.md).
    XCTAssertEqual(subtitle, "S1, E2: Pilot")
    XCTAssertEqual(description, series.plot)
    XCTAssertEqual(genre, "Comedy")
    XCTAssertNil(type, "genres went here once, and never showed")
  }

  /// A download's "S4E4" marker is the only numbering it keeps.
  func testADownloadMarkerReadsAsSeasonAndEpisode() {
    let numbers = PlaybackMediaContext.episodeNumbers("S4E12")
    XCTAssertEqual(numbers?.season, 4)
    XCTAssertEqual(numbers?.episode, 12)
    XCTAssertNil(PlaybackMediaContext.episodeNumbers("Film"))
  }

  private struct StubRendition: SubtitleRendition, Equatable {
    var renditionLanguageCode: String
    var isForcedRendition: Bool = false
    var isCaptioningRendition: Bool = false
  }
}

/// The master-playlist rewrite — what the system pickers (Audio / Subtitles) actually
/// list. Lives in this file because the test target's membership is spelled out file
/// by file in the project, and these cases belong to the same "what the player is
/// told" story as the selection tests above.
final class HLSAudioLabelerTests: XCTestCase {

  private let base = URL(string: "https://cdn.example.com/hls/master.m3u8")!

  /// Item 126352's shape: four real tracks repeated under three per-quality groups, and
  /// its four subtitle renditions — two Russian, one Russian forced, one English.
  private func master(audioGroups: [String] = ["audio1080", "audio720", "audio480"],
                      subtitleGroups: [String] = ["sub"],
                      names: [(name: String, lang: String)] = [("01. Многоголосый. Rezka (RUS)", "rus"),
                                                               ("02. Многоголосый. Rezka 18+ (RUS)", "rus"),
                                                               ("03. Двухголосый. AlphaProject (RUS)", "rus"),
                                                               ("04. Оригинал (ENG)", "eng")]) -> String {
    let subs: [(name: String, lang: String, forced: Bool)] = [("RUS #01", "rus", false),
                                                              ("RUS #02", "rus", false),
                                                              ("RUS #03 Forced", "rus", true),
                                                              ("ENG #04", "eng", false)]
    var lines = ["#EXTM3U", "#EXT-X-VERSION:4"]
    for (groupIndex, group) in subtitleGroups.enumerated() {
      for sub in subs {
        var line = "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"\(group)\",NAME=\"\(sub.name)\",LANGUAGE=\"\(sub.lang)\""
        if sub.forced { line += ",FORCED=YES" }
        line += ",URI=\"sub/\(sub.name)-\(groupIndex).m3u8\""
        lines.append(line)
      }
    }
    for (groupIndex, group) in audioGroups.enumerated() {
      for (nameIndex, rendition) in names.enumerated() {
        lines.append("#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"\(group)\",NAME=\"\(rendition.name)\",LANGUAGE=\"\(rendition.lang)\",DEFAULT=\(nameIndex == 0 ? "YES" : "NO"),AUTOSELECT=YES,URI=\"a\(nameIndex)-\(groupIndex)/index.m3u8\"")
      }
    }
    for (groupIndex, group) in audioGroups.enumerated() {
      // As on the CDN, each variant stream points at its own quality's subtitle group.
      let subs = subtitleGroups[min(groupIndex, subtitleGroups.count - 1)]
      lines.append("#EXT-X-STREAM-INF:BANDWIDTH=1000,AUDIO=\"\(group)\",SUBTITLES=\"\(subs)\"")
      lines.append("vod/\(group).m3u8")
    }
    return lines.joined(separator: "\n")
  }

  /// The API's type ids, as item 126352 carries them — 6 is "Оригинал", not an index
  /// into the three named ones (an offset subscript there crashed the whole suite).
  private static let typeTitles = [1: "VO", 2: "Многоголосый", 3: "Двухголосый", 6: "Оригинал"]

  private func track(lang: String, typeId: Int, author: String? = nil, index: Int) -> AudioTrackInfo {
    AudioTrackInfo(lang: lang,
                   typeId: typeId,
                   typeTitle: Self.typeTitles[typeId],
                   typeShortTitle: nil,
                   authorTitle: author,
                   channels: 2,
                   codec: "aac",
                   index: index,
                   isAudioDescription: false)
  }

  private var apiTracks: [AudioTrackInfo] {
    [track(lang: "rus", typeId: 2, author: "Rezka", index: 1),
     track(lang: "rus", typeId: 2, author: "Rezka 18+", index: 2),
     track(lang: "rus", typeId: 3, author: "AlphaProject", index: 3),
     track(lang: "eng", typeId: 6, index: 4)]
  }

  private func audioLines(in playlist: String) -> [String] {
    playlist.split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
      .filter { $0.contains("#EXT-X-MEDIA:") && $0.contains("TYPE=AUDIO") }
  }

  private func attribute(_ key: String, in line: String) -> String? {
    guard let range = line.range(of: "\(key)=\"[^\"]*\"", options: .regularExpression) else { return nil }
    return String(line[range]).split(separator: "\"").dropFirst().first.map(String.init)
  }

  // MARK: - The per-quality collapse

  /// The bug behind "восемь русских озвучек": every track listed once per video
  /// quality, all rows identical. Four real tracks stay four rows.
  func testPerQualityCopiesCollapseIntoOneAudioGroup() {
    let rewritten = HLSAudioLabeler.rewrite(master(), baseURL: base, tracks: apiTracks)
    let audio = audioLines(in: rewritten)
    XCTAssertEqual(audio.count, 4)
    XCTAssertEqual(Set(audio.map { attribute("GROUP-ID", in: $0) }), ["audio1080"])

    let streamAudioGroups = rewritten.split(separator: "\n")
      .filter { $0.hasPrefix("#EXT-X-STREAM-INF:") }
      .map { attribute("AUDIO", in: String($0)) }
    XCTAssertEqual(streamAudioGroups, ["audio1080", "audio1080", "audio1080"])

    XCTAssertTrue(rewritten.contains("GROUP-ID=\"sub\""), "a single subtitle group keeps its id")
  }

  // MARK: - Subtitle labels

  private func subtitleLines(in playlist: String) -> [String] {
    playlist.split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
      .filter { $0.contains("#EXT-X-MEDIA:") && $0.contains("TYPE=SUBTITLES") }
  }

  /// The bug behind "ENG #04 - English, Russian, Russian, Russian Forced" in the system
  /// menu: the CDN's language-prefixed names confuse AVKit's display-name derivation into
  /// stripping some rows and keeping others. Every rendition gets the clean language
  /// label, duplicates numbered, the forced kind spelled out.
  func testSubtitleNamesBecomeCleanLanguageLabels() {
    let rewritten = HLSAudioLabeler.rewrite(master(), baseURL: base, tracks: apiTracks)
    let subs = subtitleLines(in: rewritten)
    XCTAssertEqual(subs.count, 4)
    let rus = LanguageNames.name(for: "rus")
    let eng = LanguageNames.name(for: "eng")
    XCTAssertEqual(subs.map { attribute("NAME", in: $0) },
                   [rus, "\(rus) ∙ 2", "\(rus) (\("Forced".localized))", eng])
    XCTAssertTrue(subs[2].contains("FORCED=YES"), "the forced kind survives the rename")
  }

  /// Subtitles repeated under per-quality groups collapse exactly like audio does.
  func testPerQualitySubtitleCopiesCollapseIntoOneGroup() {
    let rewritten = HLSAudioLabeler.rewrite(master(subtitleGroups: ["sub1080", "sub720"]),
                                            baseURL: base, tracks: apiTracks)
    let subs = subtitleLines(in: rewritten)
    XCTAssertEqual(subs.count, 4)
    XCTAssertEqual(Set(subs.map { attribute("GROUP-ID", in: $0) }), ["sub1080"])
    let streamSubGroups = rewritten.split(separator: "\n")
      .filter { $0.hasPrefix("#EXT-X-STREAM-INF:") }
      .map { attribute("SUBTITLES", in: String($0)) }
    XCTAssertEqual(streamSubGroups, ["sub1080", "sub1080", "sub1080"])
  }

  /// "01. …" in the CDN name is the API index — Rezka 18+ has to land on row 2 even
  /// when the API lists its tracks in another order.
  func testLabelsMatchTracksByTheLeadingNumber() {
    let rewritten = HLSAudioLabeler.rewrite(master(), baseURL: base, tracks: apiTracks.reversed())
    let names = audioLines(in: rewritten).map { attribute("NAME", in: $0) }
    XCTAssertEqual(names, [AudioTracks.baseLabel(track(lang: "rus", typeId: 2, author: "Rezka", index: 1)),
                           AudioTracks.baseLabel(track(lang: "rus", typeId: 2, author: "Rezka 18+", index: 2)),
                           AudioTracks.baseLabel(track(lang: "rus", typeId: 3, author: "AlphaProject", index: 3)),
                           AudioTracks.baseLabel(track(lang: "eng", typeId: 6, index: 4))])
  }

  /// Masters without numbered names still match by language, in master order.
  func testLanguageOrderIsTheFallbackWhenNamesHaveNoNumber() {
    let flat = master(audioGroups: ["audio"],
                      names: [("Russian", "rus"), ("Russian", "rus"), ("English", "eng")])
    let tracks = [track(lang: "rus", typeId: 1, author: "Red Head Sound", index: 1),
                  track(lang: "rus", typeId: 2, author: "LostFilm", index: 2),
                  track(lang: "eng", typeId: 6, index: 3)]
    let names = audioLines(in: HLSAudioLabeler.rewrite(flat, baseURL: base, tracks: tracks))
      .map { attribute("NAME", in: $0) }
    XCTAssertEqual(names, [AudioTracks.baseLabel(tracks[0]),
                           AudioTracks.baseLabel(tracks[1]),
                           AudioTracks.baseLabel(tracks[2])])
  }

  /// A rendition the API doesn't know keeps its CDN name — it says more than "Russian".
  func testUnmatchedSurvivorKeepsItsCDNName() {
    let rewritten = HLSAudioLabeler.rewrite(master(), baseURL: base,
                                            tracks: apiTracks.filter { $0.index != 3 })
    let names = audioLines(in: rewritten).map { attribute("NAME", in: $0) }
    XCTAssertEqual(names[2], "03. Двухголосый. AlphaProject (RUS)")
  }

  func testDuplicateLabelsAreUniqued() {
    let flat = master(audioGroups: ["audio"],
                      names: [("Russian", "rus"), ("Russian", "rus")])
    let colliding = [track(lang: "rus", typeId: 2, author: "NewStudio", index: 1),
                     track(lang: "rus", typeId: 2, author: "NewStudio", index: 2)]
    let names = audioLines(in: HLSAudioLabeler.rewrite(flat, baseURL: base, tracks: colliding))
      .map { attribute("NAME", in: $0) }
    XCTAssertEqual(names[0], AudioTracks.baseLabel(colliding[0]))
    XCTAssertEqual(names[1], "\(AudioTracks.baseLabel(colliding[0])) ∙ 2")
  }

  // MARK: - DEFAULT

  /// The signed default comes from the sort ladder: with English preferred, the
  /// original is the one AVFoundation opens with.
  func testDefaultMovesToTheBestTrack() {
    let rewritten = HLSAudioLabeler.rewrite(master(), baseURL: base, tracks: apiTracks,
                                            preferredLanguages: ["en-US"])
    let audio = audioLines(in: rewritten)
    XCTAssertEqual(audio.map { $0.contains("DEFAULT=YES") }, [false, false, false, true])
  }

  /// With no API tracks the collapse still happens, and the CDN's own DEFAULT pick
  /// survives untouched.
  func testWithoutAPITracksTheCDNDefaultSurvives() {
    let rewritten = HLSAudioLabeler.rewrite(master(), baseURL: base, tracks: [])
    let audio = audioLines(in: rewritten)
    XCTAssertEqual(audio.count, 4)
    XCTAssertEqual(audio.map { $0.contains("DEFAULT=YES") }, [true, false, false, false])
    XCTAssertEqual(audio.map { attribute("NAME", in: $0) }[0], "01. Многоголосый. Rezka (RUS)")
  }
}
