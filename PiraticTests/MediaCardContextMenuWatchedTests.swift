//
//  MediaCardContextMenuWatchedTests.swift
//  PiraticTests
//
//  Watched submenu shape for series CW cards; sneak-peek aspect + metadata.
//

import XCTest
@testable import Piratic
@testable import KinoPubBackend
import PiraticMedia
import PiraticMetadata
import PiraticUI

@MainActor
final class MediaCardContextMenuWatchedTests: XCTestCase {
  private var savedCoverLanguage: Any?

  override func setUp() {
    savedCoverLanguage = UserDefaults.standard.object(forKey: CoverArtworkPreferences.languageKey)
  }

  override func tearDown() {
    if let savedCoverLanguage {
      UserDefaults.standard.set(savedCoverLanguage, forKey: CoverArtworkPreferences.languageKey)
    } else {
      UserDefaults.standard.removeObject(forKey: CoverArtworkPreferences.languageKey)
    }
  }

  private func seriesCard(watched: Bool = false) -> MediaCard {
    MediaCard(
      id: 42,
      posterURL: "https://example.com/poster.jpg",
      title: "Альтруисты",
      landscapeImageURL: "https://example.com/wide.jpg",
      overlayLabel: "S1, E3",
      hoverStillURL: "https://m.staticpop.net/poster/episode/thumb/42.jpg",
      itemID: 42,
      video: 3,
      season: 1,
      seasonCount: 2,
      isWatched: watched,
      isSeries: true,
      year: 2024,
      durationSeconds: 50 * 60,
      genres: [Genre(id: "drama", domain: .video,
                     name: LocalizedName(en: "Drama", ru: "Драма"))]
    )
  }

  private func posterCard() -> MediaCard {
    MediaCard(
      id: 7,
      posterURL: "https://m.staticpop.net/poster/item/big/7.jpg",
      title: "Декстер: Воскрешение",
      isSeries: true,
      year: 2025,
      genres: [Genre(id: "drama", domain: .video,
                     name: LocalizedName(en: "Drama", ru: "Драма"))],
      kinopoiskID: 322
    )
  }

  private func filmCard() -> MediaCard {
    MediaCard(
      id: 9,
      posterURL: "https://example.com/film.jpg",
      title: "Фильм",
      landscapeImageURL: "https://example.com/film-wide.jpg",
      itemID: 9,
      video: 1,
      isSeries: false,
      year: 2023,
      durationSeconds: 7200,
      genres: [Genre(id: "thriller", domain: .video,
                     name: LocalizedName(en: "Thriller", ru: "Триллер"))],
      kinopoiskID: 100
    )
  }

  func testSeriesContinueWatchingUsesWatchedSubmenu() {
    var markedEpisode = false
    let entries = MediaCardContextMenus.entries(
      for: seriesCard(),
      surface: .shelf,
      onToggleWatched: { XCTFail("flat toggle must not appear when submenu is set") },
      watchedSubmenu: .init(
        season: 1,
        episode: 3,
        seasonCount: 2,
        onMarkEpisode: { markedEpisode = true },
        onMarkSeason: {},
        onMarkUnwatchedInSeason: {},
        onMarkAllEpisodes: {}
      )
    )
    let ids = entries.compactMap { entry -> String? in
      if case .submenu(let id, _, _, _, _) = entry { return id }
      if case .action(let action) = entry { return action.id }
      return nil
    }
    XCTAssertTrue(ids.contains(MediaCardContextMenus.watchedMenuID))
    XCTAssertFalse(ids.contains("toggle-watched"))
    guard case .submenu(_, _, _, let children, _) = entries.first(where: {
      if case .submenu(let id, _, _, _, _) = $0 { return id == MediaCardContextMenus.watchedMenuID }
      return false
    }) else {
      return XCTFail("expected watched submenu")
    }
    XCTAssertEqual(children.map(\.id), [
      "mark-episode-watched",
      "mark-season-watched",
      "mark-unwatched-in-season",
      "mark-all-episodes-watched"
    ])
    children.first?.handler()
    XCTAssertTrue(markedEpisode)
  }

  func testAlreadyWatchedStaysFlatMarkAsNew() {
    let entries = MediaCardContextMenus.entries(
      for: seriesCard(watched: true),
      surface: .shelf,
      onToggleWatched: {},
      watchedSubmenu: .init(
        season: 1, episode: 3, seasonCount: 2,
        onMarkEpisode: { XCTFail("submenu must not appear when watched") },
        onMarkSeason: {},
        onMarkUnwatchedInSeason: {},
        onMarkAllEpisodes: {}
      )
    )
    let ids = entries.compactMap { entry -> String? in
      if case .submenu(let id, _, _, _, _) = entry { return id }
      if case .action(let action) = entry { return action.id }
      return nil
    }
    XCTAssertTrue(ids.contains("toggle-watched"))
    XCTAssertFalse(ids.contains(MediaCardContextMenus.watchedMenuID))
  }

  func testPreviewSpecUsesLandscapeForWideCardWithoutEpisodeLine() {
    let spec = MediaCardContextPreviewSpec.from(card: seriesCard(), surface: .shelf)
    XCTAssertEqual(spec.aspect, .landscape)
    // Series CW peek uses the episode still (`hoverStillURL` / pointerArtwork), same
    // as macOS hover — not the tile's wide cover (#165).
    XCTAssertEqual(spec.url?.absoluteString,
                   "https://m.staticpop.net/poster/episode/thumb/42.jpg")
    XCTAssertEqual(spec.title, "Альтруисты")
    // Title-level CW peek: genre / year · genre — never «S1, E3» / «Ep. 1».
    XCTAssertTrue(
      spec.subtitle == "2024 · Драма" || spec.subtitle == "2024 · Drama",
      "unexpected subtitle \(spec.subtitle ?? "nil")"
    )
  }

  func testFilmContinueWatchingPeekHasNoEpisodeLine() {
    let spec = MediaCardContextPreviewSpec.from(card: filmCard(), surface: .shelf)
    XCTAssertEqual(spec.aspect, .landscape)
    let subtitle = spec.subtitle ?? ""
    XCTAssertFalse(subtitle.contains("Ep"), "film peek must not say Ep: \(subtitle)")
    XCTAssertFalse(subtitle.contains("серия"), "film peek must not say серия: \(subtitle)")
    XCTAssertTrue(
      subtitle == "2023 · Триллер" || subtitle == "2023 · Thriller",
      "unexpected subtitle \(subtitle)"
    )
  }

  func testContinuePeekHintBeatsGenre() {
    var card = seriesCard()
    card.continuePeekHint = "В закладках"
    let spec = MediaCardContextPreviewSpec.from(card: card, surface: .shelf)
    XCTAssertEqual(spec.subtitle, "В закладках")
  }

  func testPreviewSpecUsesCoverURLForPortraitWhenRussian() {
    CoverArtworkPreferences.set(.russian)
    defer { CoverArtworkPreferences.set(.english) }
    let card = posterCard()
    let spec = MediaCardContextPreviewSpec.from(card: card, surface: .shelf)
    XCTAssertEqual(spec.aspect, .poster)
    // The peek draws what the card draws: the worker poster in Russian (#176),
    // the Kinopoisk file as the direct rung.
    XCTAssertEqual(spec.url?.absoluteString, card.coverURL)
    XCTAssertEqual(card.directCoverURL, CoverArtwork.kinopoiskURL(id: 322, tier: .regular))
    if card.coverURL.contains("/img/poster/") {
      XCTAssertTrue(card.coverURL.contains("lang=ru"), card.coverURL)
    }
  }

  func testSeriesPeekPrefersWorkerEpisodeStill() {
    let worker = URL(string: "https://proxy.example/img")!
    let images = TitleImageRoute(baseURL: worker, language: nil)
    let card = seriesCard()
    let spec = MediaCardContextPreviewSpec.from(card: card, surface: .shelf, images: images)
    let expected = images.episodeStill(
      kinopubID: 42, imdb: nil, season: 1, episode: 3,
      pixelWidth: TitleImageRoute.episodeStillPixelWidth(points: 340, scale: 2),
      kinopubThumb: card.hoverStillURL
    )
    XCTAssertEqual(spec.url, expected)
  }

  func testPreviewSpecUsesPosterAspectAndYearGenre() {
    CoverArtworkPreferences.set(.english)
    let spec = MediaCardContextPreviewSpec.from(card: posterCard(), surface: .shelf)
    XCTAssertEqual(spec.aspect, .poster)
    XCTAssertEqual(spec.url?.absoluteString, posterCard().coverURL)
    XCTAssertEqual(posterCard().directCoverURL, "https://m.staticpop.net/poster/item/big/7.jpg")
    XCTAssertEqual(spec.title, "Декстер: Воскрешение")
    // Language follows the process locale; accept either localisation of Drama.
    XCTAssertTrue(
      spec.subtitle == "2025 · Драма" || spec.subtitle == "2025 · Drama",
      "unexpected subtitle \(spec.subtitle ?? "nil")"
    )
    XCTAssertGreaterThan(spec.preferredSize.height, spec.artSize.height)
  }

  func testArtDisplaySizeHugsBitmapWithoutLetterbox() {
    let spec = MediaCardContextPreviewSpec(
      url: nil, aspect: .poster, title: "T", subtitle: "2024 · Drama"
    )
    // Narrower than 2:3 → width shrinks inside the max box (no side gutters).
    let hugged = spec.artDisplaySize(forImageSize: CGSize(width: 400, height: 700))
    XCTAssertEqual(hugged.height, 420, accuracy: 0.5)
    XCTAssertLessThan(hugged.width, 280)
    XCTAssertEqual(hugged.width / hugged.height, 400.0 / 700.0, accuracy: 0.01)
    // Wider than 2:3 → height shrinks.
    let wide = spec.artDisplaySize(forImageSize: CGSize(width: 600, height: 700))
    XCTAssertEqual(wide.width, 280, accuracy: 0.5)
    XCTAssertLessThan(wide.height, 420)
  }

  func testContinuePeekHintForReasons() {
    XCTAssertEqual(
      HomeCatalog.continuePeekHint(for: .bookmarked(Date())),
      String(localized: "Bookmarked")
    )
    XCTAssertEqual(
      HomeCatalog.continuePeekHint(for: .unfinished),
      String(localized: "Left Unfinished")
    )
    XCTAssertNil(HomeCatalog.continuePeekHint(for: .watched(Date())))
    XCTAssertNil(HomeCatalog.continuePeekHint(for: .released(Date())))
  }
}
