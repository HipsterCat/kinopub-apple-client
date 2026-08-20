//
//  PlaybackPreflightTests.swift
//  KinoPubAppleClientTests
//
//  That a surface outside the player gets the same answer the player will act on.
//

import XCTest
import KinoPubBackend
// The app target's module is `KinoPub` — `PRODUCT_NAME` is KinoPub and nothing overrides
// `PRODUCT_MODULE_NAME`.
@testable import KinoPub

@MainActor
final class PlaybackPreflightTests: XCTestCase {

  /// A stand-in for whatever was tapped. Building a real `Episode` needs a payload's worth
  /// of fields that say nothing about track selection.
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

  override func setUpWithError() throws {
    suiteName = "PlaybackPreflightTests.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    store = TrackPreferenceStore(defaults: defaults)
  }

  override func tearDownWithError() throws {
    defaults.removePersistentDomain(forName: suiteName)
  }

  private let seriesID = 4242

  private func preflight() -> PlaybackPreflight {
    PlaybackPreflight(preferences: store)
  }

  private func audio(_ lang: String, _ typeId: Int, _ studio: String? = nil) -> AudioTrackInfo {
    let titles = [1: "Дубляж", 2: "Многоголосый", 3: "Двухголосый", 6: "Оригинал"]
    return AudioTrackInfo(lang: lang, typeId: typeId, typeTitle: titles[typeId], authorTitle: studio)
  }

  private func episode(season: Int? = 2, number: Int? = 5) -> StubItem {
    StubItem(id: 99,
             metadata: WatchingMetadata(id: seriesID, video: number, season: season),
             audioTracks: [audio("ru", 1, "Мосфильм"), audio("ru", 3, "Сыендук")])
  }

  // MARK: - Scopes

  func testAnEpisodeReadsTheWholeChain() {
    let scopes = preflight().scopes(for: episode(), profile: TitleTrackProfile())
    XCTAssertEqual(scopes, [.episode(titleID: seriesID, season: 2, episode: 5),
                            .season(titleID: seriesID, season: 2),
                            .title(id: seriesID)])
  }

  func testAnAnimeAlsoReadsItsBucket() {
    let scopes = preflight().scopes(for: episode(),
                                    profile: TitleTrackProfile(isAnime: true))
    XCTAssertEqual(scopes.last, TrackMemoryScope.anime)
  }

  func testAFilmIsJustItsTitle() {
    let film = StubItem(id: 7, metadata: WatchingMetadata(id: seriesID))
    XCTAssertEqual(preflight().scopes(for: film, profile: TitleTrackProfile()),
                   [.title(id: seriesID)])
  }

  /// An unresolved item has no id worth writing under — everything would pool into one
  /// bucket keyed 0.
  func testAnUnresolvedItemHasNoScopes() {
    let orphan = StubItem(id: 7, metadata: WatchingMetadata(id: 0, video: 1, season: 1))
    XCTAssertTrue(preflight().scopes(for: orphan, profile: TitleTrackProfile()).isEmpty)
  }

  // MARK: - The answer, before the player exists

  func testTheDecisionFollowsTheLadderWithNoHistory() {
    let decision = preflight().decision(for: episode(), profile: TitleTrackProfile())
    XCTAssertEqual(decision.audio?.signature, audio("ru", 1, "Мосфильм").signature)
    XCTAssertEqual(decision.audioReason, .ladder)
  }

  /// The point of the whole thing: a card asks and gets what the player will act on.
  func testTheDecisionFollowsWhatTheSeriesLearned() {
    let syenduk = audio("ru", 3, "Сыендук")
    store.recordAudio(syenduk.signature, in: [.title(id: seriesID)])
    store.recordAudio(syenduk.signature, in: [.title(id: seriesID)])
    store.recordAudio(syenduk.signature, in: [.title(id: seriesID)])

    let decision = preflight().decision(for: episode(), profile: TitleTrackProfile())
    XCTAssertEqual(decision.audio?.signature, syenduk.signature)
    XCTAssertEqual(decision.audioReason, .remembered)
    XCTAssertEqual(decision.audioScope, TrackMemoryScope.title(id: seriesID))
  }

  /// The player passes the renditions it can see; everyone else gets the API's list. Both
  /// go through the same call so they cannot disagree.
  func testAnOverriddenMenuIsWhatGetsDecidedOver() {
    let onlyOriginal = [audio("en", 6)]
    let decision = preflight().decision(for: episode(),
                                        profile: TitleTrackProfile(),
                                        audioMenu: onlyOriginal)
    XCTAssertEqual(decision.audio?.languageKey, "en")
  }

  // MARK: - Saying it out loud

  func testTheSummaryNamesTheDubThatWillPlay() {
    let summary = preflight().audioSummary(for: episode(), profile: TitleTrackProfile())
    XCTAssertEqual(summary, AudioTracks.baseLabel(audio("ru", 1, "Мосфильм")))
  }

  /// Naming the only track there is tells the viewer nothing they can act on.
  func testASingleTrackIsNotWorthNaming() {
    let single = StubItem(id: 99,
                          metadata: WatchingMetadata(id: seriesID, video: 5, season: 2),
                          audioTracks: [audio("ru", 1, "Мосфильм")])
    XCTAssertNil(preflight().audioSummary(for: single, profile: TitleTrackProfile()))
  }

  func testNoTracksIsNotWorthNaming() {
    let bare = StubItem(id: 99, metadata: WatchingMetadata(id: seriesID))
    XCTAssertNil(preflight().audioSummary(for: bare, profile: TitleTrackProfile()))
  }

  // MARK: - Warming

  /// Warming is an optimisation for episodes that arrive without links. Anything else must
  /// not cost a request, so it is not even attempted.
  func testWarmingAnythingButAnEpisodeCostsNoRequest() async {
    // `episode()` is a stub, not the `Episode` class, so `warm` must bail before it looks
    // for a content service — no service is injected here, and reaching for one would
    // build the whole app context.
    await preflight().warm(episode())
  }
}
