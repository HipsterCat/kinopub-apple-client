//
//  PersonFilmographyTests.swift
//  PiraticTests
//
//  Loaded-window matching: no false «Not on Kinopub» for years still behind pagination;
//  future titles keep no Kinopub-absence chip.
//

import XCTest
import KinoPubBackend
import PiraticMetadata
@testable import Piratic

final class PersonFilmographyTests: XCTestCase {

  func testYearWindowWithholdsOlderCreditsUntilLoaded() {
    let kinopub = [
      sampleItem(title: "New Film / New Film", year: 2024),
      sampleItem(title: "Mid Film / Mid Film", year: 2020)
    ]
    let credits = [
      PersonCredit(tmdbId: 1, mediaType: "movie", title: "New Film",
                   character: "Lead", releaseDate: date(2024)),
      PersonCredit(tmdbId: 2, mediaType: "movie", title: "Missing 2022",
                   character: "Lead", releaseDate: date(2022)),
      PersonCredit(tmdbId: 3, mediaType: "movie", title: "Old Missing",
                   character: "Lead", releaseDate: date(2010))
    ]
    let window = PersonFilmography.MatchWindow.yearSorted(items: kinopub, complete: false)
    let cards = PersonFilmography.externalCards(credits: credits, kinopubItems: kinopub,
                                                role: .actor, window: window)
    // 2024 matched; 2022 in window unmatched → unavailable; 2010 outside window → withheld.
    XCTAssertEqual(cards.map(\.title), ["Missing 2022"])
    XCTAssertEqual(cards.first?.unavailableNotice, "MediaItem_NotOnKinoPubChip".localized)
  }

  func testCompleteListingEmitsOutsideWindow() {
    let kinopub = [sampleItem(title: "Only / Only", year: 2024)]
    let credits = [
      PersonCredit(tmdbId: 1, mediaType: "movie", title: "Only",
                   character: "Lead", releaseDate: date(2024)),
      PersonCredit(tmdbId: 2, mediaType: "movie", title: "Ancient",
                   character: "Lead", releaseDate: date(1999))
    ]
    let window = PersonFilmography.MatchWindow.yearSorted(items: kinopub, complete: true)
    let cards = PersonFilmography.externalCards(credits: credits, kinopubItems: kinopub,
                                                role: .actor, window: window)
    XCTAssertEqual(cards.map(\.title), ["Ancient"])
  }

  func testLocalizedTitleMatchAvoidsFalseUnavailable() {
    let kinopub = [sampleItem(title: "Оппенгеймер / Oppenheimer", year: 2023)]
    let credits = [
      PersonCredit(tmdbId: 1, mediaType: "movie", title: "Оппенгеймер",
                   originalTitle: "Oppenheimer", character: "Lead", releaseDate: date(2023))
    ]
    let window = PersonFilmography.MatchWindow.yearSorted(items: kinopub, complete: true)
    let cards = PersonFilmography.externalCards(credits: credits, kinopubItems: kinopub,
                                                role: .actor, window: window)
    XCTAssertTrue(cards.isEmpty)
  }

  func testNonYearSortWaitsUntilComplete() {
    let kinopub = [sampleItem(title: "A / A", year: 2020)]
    let credits = [
      PersonCredit(tmdbId: 1, mediaType: "movie", title: "Missing",
                   character: "Lead", releaseDate: date(2020))
    ]
    let incomplete = PersonFilmography.MatchWindow.completeOnly(false)
    XCTAssertTrue(PersonFilmography.externalCards(credits: credits, kinopubItems: kinopub,
                                                   role: .actor, window: incomplete).isEmpty)
    let complete = PersonFilmography.MatchWindow.completeOnly(true)
    XCTAssertEqual(PersonFilmography.externalCards(credits: credits, kinopubItems: kinopub,
                                                   role: .actor, window: complete).count, 1)
  }

  func testFutureTitleHasNoNotOnKinopubBadge() {
    let kinopub = [sampleItem(title: "Past / Past", year: 2022)]
    let credits = [
      PersonCredit(tmdbId: 1, mediaType: "movie", title: "Avatar 5",
                   character: "Lead", releaseDate: date(2031)),
      PersonCredit(tmdbId: 2, mediaType: "movie", title: "Missing Now",
                   character: "Lead", releaseDate: date(2022))
    ]
    let window = PersonFilmography.MatchWindow.yearSorted(items: kinopub, complete: true)
    let cards = PersonFilmography.externalCards(credits: credits, kinopubItems: kinopub,
                                                role: .actor, window: window)
    let avatar = cards.first { $0.title == "Avatar 5" }
    let missing = cards.first { $0.title == "Missing Now" }
    XCTAssertNotNil(avatar)
    XCTAssertNil(avatar?.unavailableNotice)
    XCTAssertEqual(missing?.unavailableNotice, "MediaItem_NotOnKinoPubChip".localized)
  }

  func testMergedTimelineInterleavesByYear() {
    let kinopub = [
      sampleItem(title: "New / New", year: 2024),
      sampleItem(title: "Old / Old", year: 2018)
    ]
    let credits = [
      PersonCredit(tmdbId: 1, mediaType: "movie", title: "Missing Mid",
                   character: "Lead", releaseDate: date(2021)),
      PersonCredit(tmdbId: 2, mediaType: "movie", title: "Missing New",
                   character: "Lead", releaseDate: date(2023))
    ]
    let window = PersonFilmography.MatchWindow.yearSorted(items: kinopub, complete: true)
    let external = PersonFilmography.externalCards(credits: credits, kinopubItems: kinopub,
                                                   role: .actor, window: window)
    let timeline = PersonFilmography.mergedTimeline(kinopubItems: kinopub,
                                                    externalCards: external,
                                                    descending: true)
    XCTAssertEqual(timeline.map(\.title), ["New", "Missing New", "Missing Mid", "Old"])
  }

  func testMatchedKinopubPosterUsesWorkerViaWeserv() {
    let worker = URL(string: "https://kinopub-tmdb-proxy.example.workers.dev")!
    let images = TitleImageRoute(baseURL: worker, language: "en")
    let item = sampleItem(title: "Film / Film", year: 2024, id: 7, imdb: 42)
    let card = PersonFilmography.kinopubCard(item, images: images)
    let url = URL(string: card.posterURL)
    XCTAssertEqual(url?.host, "images.weserv.nl")
    let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let source = items.first(where: { $0.name == "url" })?.value
    XCTAssertEqual(
      source,
      "https://kinopub-tmdb-proxy.example.workers.dev/img/poster/by/kinopub/7?imdb=tt0000042&lang=en"
    )
    XCTAssertEqual(items.first(where: { $0.name == "w" })?.value, "454")
    XCTAssertEqual(items.first(where: { $0.name == "output" })?.value, "webp")
  }

  private func date(_ year: Int) -> Date {
    var c = DateComponents()
    c.year = year
    c.month = 6
    c.day = 1
    return Calendar(identifier: .gregorian).date(from: c)!
  }

  private func sampleItem(title: String, year: Int, id: Int? = nil, imdb: Int? = nil) -> MediaItem {
    MediaItem(
      id: id ?? abs(title.hashValue) % 1_000_000 + 1,
      type: "movie",
      subtype: "",
      title: title,
      year: year,
      cast: "",
      director: "",
      genres: [],
      countries: [],
      voice: nil,
      duration: Duration(average: 0, total: 0),
      langs: 0,
      quality: 0,
      plot: "",
      imdb: imdb,
      imdbRating: nil,
      imdbVotes: nil,
      kinopoisk: nil,
      kinopoiskRating: nil,
      kinopoiskVotes: nil,
      rating: 0,
      ratingVotes: 0,
      ratingPercentage: 0,
      views: 0,
      comments: 0,
      posters: Posters(small: "", medium: "", big: "", wide: ""),
      trailer: nil,
      finished: false,
      advert: false,
      poorQuality: false,
      createdAt: 0,
      updatedAt: 0,
      inWatchlist: false,
      subscribed: false,
      ac3: nil,
      bookmarks: nil,
      seasons: nil,
      videos: nil
    )
  }
}
