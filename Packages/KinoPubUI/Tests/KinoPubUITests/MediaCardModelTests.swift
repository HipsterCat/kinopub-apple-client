//
//  MediaCardModelTests.swift
//
//  A poster card worded from the media model and the viewer's state.
//

import XCTest
import KinoPubBackend
import KinoPubMedia
@testable import KinoPubUI

final class MediaCardModelTests: XCTestCase {

  private var film: MediaEntity {
    var entity = MediaEntity(kind: .movie,
                             ids: [ExternalID(.kinopub, "124447"), ExternalID(.imdb, "tt0903747"),
                                   ExternalID(.kinopoisk, "326")],
                             title: "Побег из Шоушенка",
                             originalTitle: "The Shawshank Redemption",
                             synopsis: Synopsis(full: "Банкир готовит побег."),
                             genres: [GenreVocabulary.genre(id: "drama")!],
                             release: .year(1994),
                             runtime: 142 * 60,
                             scores: [Score(.imdb, value: 9.3, votes: 3_000_000)!,
                                      Score(.kinopoisk, value: 9.1)!],
                             countries: ["США"],
                             formats: [.uhd])
    entity.artwork = ArtworkSet(poster: URL(string: "https://kp/big.jpg"),
                                backdrop: URL(string: "https://kp/wide.jpg"),
                                posterPreview: URL(string: "https://kp/medium.jpg"),
                                backdropFromSpecifiedWide: true)
    return entity
  }

  func testAFilmCard() {
    let card = MediaCard(ref: .title(124447), entity: film, state: .unknown)
    XCTAssertEqual(card.id, 124447)
    XCTAssertEqual(card.title, "Побег из Шоушенка")
    XCTAssertEqual(card.subtitle, "The Shawshank Redemption")
    XCTAssertEqual(card.posterURL, "https://kp/medium.jpg", "the grid's size first")
    XCTAssertEqual(card.backdropURL, "https://kp/wide.jpg")
    XCTAssertTrue(card.hasSpecifiedWideArtwork)
    XCTAssertEqual(card.overview, "Банкир готовит побег.")
    XCTAssertEqual(card.year, 1994)
    XCTAssertEqual(card.durationSeconds, 142 * 60)
    XCTAssertTrue(card.is4K)
    XCTAssertFalse(card.isSeries)
    XCTAssertEqual(card.imdbID, 903747)
    XCTAssertEqual(card.kinopoiskID, 326)
    XCTAssertEqual(card.scores.imdb, 9.3)
    XCTAssertEqual(card.scores.kinopoisk, 9.1)
  }

  /// Follow is a series' alone: a film never reads as followed, whatever a store says.
  func testAFilmIsNeverFollowed() {
    let card = MediaCard(ref: .title(1), entity: film,
                         state: ViewerState(isFollowing: nil, bookmarkFolderIDs: [7]))
    XCTAssertEqual(card.isSeries, false)
    XCTAssertEqual(card.viewerState.bookmarkFolderIDs, [7])
    XCTAssertTrue(card.viewerState.isBookmarked)
    XCTAssertNil(card.viewerState.isFollowing)
  }

  func testASeriesCard() {
    let show = MediaEntity(kind: .show, title: "Тед Лассо", seasonCount: 3, release: .year(2020),
                           runtime: 99_999)
    let card = MediaCard(ref: .title(87940), entity: show, state: ViewerState(isFollowing: true))
    XCTAssertTrue(card.isSeries)
    XCTAssertNil(card.durationSeconds, "a series has no single runtime")
    XCTAssertEqual(card.seasonCount, 3)
    XCTAssertEqual(card.seasonCountText(language: .ru), "3 сезона")
  }

  /// Catalog grids: `Год Жанр` for a film, `2019–2024 Жанр` for an ended show.
  func testCatalogCaptionIsYearThenGenre() {
    let filmCard = MediaCard(ref: .title(1), entity: film, state: .unknown)
    XCTAssertEqual(filmCard.catalogCaption(language: .ru), "1994 Драма")
    XCTAssertEqual(filmCard.catalogCaption(language: .en), "1994 Drama", "worded when painted")
    XCTAssertNil(filmCard.yearEnd)

    var show = MediaEntity(kind: .show, title: "Игра престолов",
                           genres: [GenreVocabulary.genre(id: "fantasy")!],
                           release: .year(2011), ended: .year(2019))
    let ended = MediaCard(ref: .title(2), entity: show, state: .unknown)
    XCTAssertEqual(ended.yearLabel, "2011–2019")
    XCTAssertEqual(ended.catalogCaption(language: .ru), "2011–2019 Фэнтези")

    show.ended = nil
    let ongoing = MediaCard(ref: .title(3), entity: show, state: .unknown)
    XCTAssertEqual(ongoing.yearLabel, "2011")
    XCTAssertEqual(ongoing.catalogCaption(language: .ru), "2011 Фэнтези")
  }

  /// A concert's caption is the tour — the half of the title after "/" — not the genre.
  /// A film keeps the genre: its half after "/" is a translation.
  func testAConcertCaptionIsTheTour() {
    let concert = MediaEntity(kind: .movie, title: "Taylor Swift",
                              originalTitle: "The Eras Tour: Taylor's Version",
                              genres: [GenreVocabulary.genre(id: "music.country")!,
                                       GenreVocabulary.genre(id: "concert")!],
                              release: .year(2023))
    let card = MediaCard(ref: .title(1), entity: concert, state: .unknown)
    XCTAssertEqual(card.catalogCaption(language: .ru), "2023 The Eras Tour: Taylor's Version")
    XCTAssertNotEqual(card.catalogCaption(language: .ru), "2023 Кантри")

    let bare = MediaEntity(kind: .movie, title: "Queen",
                           genres: [GenreVocabulary.genre(id: "music.rock")!],
                           release: .year(1986))
    XCTAssertEqual(MediaCard(ref: .title(2), entity: bare, state: .unknown).catalogCaption(language: .ru),
                   "1986 Рок", "no slash, so the genre stays")
  }

  /// Inside Documentaries, Anime or Cartoons the caption names the next genre.
  /// Outside that section the leading word stays — it is what the cover is.
  func testASectionSkipsItsOwnGenre() {
    let documentary = MediaEntity(kind: .movie, title: "Космос",
                                  genres: [GenreVocabulary.genre(id: "documentary")!,
                                           GenreVocabulary.genre(id: "history")!],
                                  release: .year(2014))
    let card = MediaCard(ref: .title(1), entity: documentary, state: .unknown)
    XCTAssertEqual(card.catalogCaption(language: .ru), "2014 Документальный")
    XCTAssertEqual(card.catalogCaption(language: .ru, omittingGenreIDs: ["documentary"]), "2014 Исторический")

    let anime = MediaEntity(kind: .show, title: "Атака титанов",
                            genres: [GenreVocabulary.genre(id: "anime")!,
                                     GenreVocabulary.genre(id: "action")!],
                            release: .year(2013))
    let animeCard = MediaCard(ref: .title(2), entity: anime, state: .unknown)
    XCTAssertEqual(animeCard.catalogCaption(language: .ru, omittingGenreIDs: ["anime"]), "2013 Боевик")

    let cartoon = MediaEntity(kind: .movie, title: "Душа",
                              genres: [GenreVocabulary.genre(id: "animation")!,
                                       GenreVocabulary.genre(id: "comedy")!],
                              release: .year(2020))
    let cartoonCard = MediaCard(ref: .title(3), entity: cartoon, state: .unknown)
    XCTAssertEqual(cartoonCard.catalogCaption(language: .ru, omittingGenreIDs: ["animation"]), "2020 Комедия")

    let only = MediaEntity(kind: .movie, title: "Хроника",
                           genres: [GenreVocabulary.genre(id: "documentary")!],
                           release: .year(2011))
    XCTAssertEqual(MediaCard(ref: .title(4), entity: only, state: .unknown)
      .catalogCaption(language: .ru, omittingGenreIDs: ["documentary"]),
                   "2011", "nothing else to say")
  }
}
