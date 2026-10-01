//
//  MediaAggregatorTests.swift
//
//  Which source wins which field — declared once, and independent of which network call
//  happened to answer first.
//

import XCTest
@testable import KinoPubMedia

final class MediaAggregatorTests: XCTestCase {

  private let drama = GenreVocabulary.genre(id: "drama")!
  private let comedy = GenreVocabulary.genre(id: "comedy")!
  private let sport = GenreVocabulary.genre(id: "sport")!

  private var kinopubShow: MediaFragment {
    MediaFragment(.kinopub, .show) { entity in
      entity.ids = [ExternalID(.kinopub, "87940")]
      entity.title = "Тед Лассо"
      entity.synopsis = Synopsis(full: "Американский тренер…")
      entity.genres = [comedy, sport]
      entity.release = ReleaseDate(year: 2020)
      entity.scores = [Score(.imdb, value: 8.8, votes: 300_000)!]
      entity.artwork = ArtworkSet(poster: URL(string: "https://kinopub/poster.jpg"))
    }
  }

  private var tmdbShow: MediaFragment {
    MediaFragment(.tmdb, .show) { entity in
      entity.ids = [ExternalID(.tmdb, "97546")]
      entity.title = "Ted Lasso"
      entity.originalTitle = "Ted Lasso"
      entity.synopsis = Synopsis(full: "An American coach…", tagline: "Believe.")
      entity.genres = [comedy, drama]
      entity.release = .day(year: 2020, month: 8, day: 14)
      entity.contentRating = ContentRating("16+")
      entity.scores = [Score(.tmdb, value: 8.4, votes: 3_000)!]
      entity.artwork = ArtworkSet(poster: URL(string: "https://tmdb/poster.jpg"),
                                  backdrop: URL(string: "https://tmdb/backdrop.jpg"),
                                  logo: URL(string: "https://tmdb/logo.png"))
    }
  }

  func testNothingMergesToNothing() {
    XCTAssertNil(MediaAggregator.merge([MediaFragment]()))
  }

  /// The standard order, field by field: kino.pub's Russian title and plot, TMDB's day-
  /// precise premiere and artwork, the age rating only TMDB had.
  func testEachFieldComesFromItsDeclaredSource() throws {
    let show = try XCTUnwrap(MediaAggregator.merge([kinopubShow, tmdbShow]))
    XCTAssertEqual(show.title, "Тед Лассо")
    XCTAssertEqual(show.originalTitle, "Ted Lasso")
    XCTAssertEqual(show.synopsis.full, "Американский тренер…")
    XCTAssertEqual(show.release, .day(year: 2020, month: 8, day: 14))
    XCTAssertEqual(show.contentRating?.value, "16+")
    XCTAssertEqual(show.artwork.poster?.absoluteString, "https://tmdb/poster.jpg")
    XCTAssertEqual(show.artwork.logo?.absoluteString, "https://tmdb/logo.png")

    XCTAssertEqual(show.provenance[.title], .kinopub)
    XCTAssertEqual(show.provenance[.release], .tmdb)
    XCTAssertEqual(show.provenance[.poster], .tmdb)
    XCTAssertEqual(show.provenance[.synopsis], .kinopub)
  }

  /// Parts of a synopsis do not compete: kino.pub's plot and TMDB's tagline both stay.
  func testTheTaglineFillsInBesideAnotherSourcesPlot() throws {
    let show = try XCTUnwrap(MediaAggregator.merge([kinopubShow, tmdbShow]))
    XCTAssertEqual(show.synopsis.tagline, "Believe.")
  }

  /// **Genres are one source's list, never a splice** — the list's first is the primary
  /// genre, and interleaving two orders invents a primary nobody gave.
  func testGenresAreOneSourcesListAndItsFirstIsPrimary() throws {
    let show = try XCTUnwrap(MediaAggregator.merge([tmdbShow, kinopubShow]))
    XCTAssertEqual(show.genres, [comedy, sport])
    XCTAssertEqual(show.primaryGenre, comedy)
    XCTAssertEqual(show.provenance[.genres], .kinopub)
  }

  /// A lower-ranked source fills a field the higher one left empty.
  func testALowerSourceFillsWhatTheHigherLacks() throws {
    var bare = kinopubShow
    bare.entity.genres = []
    let show = try XCTUnwrap(MediaAggregator.merge([bare, tmdbShow]))
    XCTAssertEqual(show.genres, [comedy, drama])
    XCTAssertEqual(show.provenance[.genres], .tmdb)
  }

  /// kino.pub ships `""` for every episode it never named; that is not a title.
  func testABlankTitleLosesToARealOne() throws {
    let kinopub = MediaFragment(.kinopub, .episode) { entity in
      entity.title = ""
      entity.episodeNumber = 1
    }
    let tmdb = MediaFragment(.tmdb, .episode) { entity in
      entity.title = "Pilot"
      entity.episodeNumber = 1
    }
    let episode = try XCTUnwrap(MediaAggregator.merge([kinopub, tmdb]))
    XCTAssertEqual(episode.title, "Pilot")
    XCTAssertEqual(episode.provenance[.title], .tmdb)
  }

  /// Scores stand side by side, one per provider — never averaged, never dropped.
  func testScoresAreKeptSideBySide() throws {
    let show = try XCTUnwrap(MediaAggregator.merge([kinopubShow, tmdbShow]))
    XCTAssertEqual(Set(show.scores.map(\.provider)), [.imdb, .tmdb])
  }

  /// IMDb's own number beats kino.pub's copy of it.
  func testAScoreIsBestReportedByWhoeverGaveIt() throws {
    let imdb = MediaFragment(.imdb, .show) { entity in
      entity.scores = [Score(.imdb, value: 8.9, votes: 310_000)!]
    }
    let show = try XCTUnwrap(MediaAggregator.merge([kinopubShow, imdb]))
    XCTAssertEqual(show.scores.first { $0.provider == .imdb }?.value, 8.9)
  }

  /// The answer never depends on which call finished first.
  func testArrivalOrderChangesNothing() throws {
    let imdb = MediaFragment(.imdb, .show) { entity in
      entity.scores = [Score(.imdb, value: 8.9, votes: 310_000)!]
    }
    let one = try XCTUnwrap(MediaAggregator.merge([kinopubShow, tmdbShow, imdb]))
    let two = try XCTUnwrap(MediaAggregator.merge([imdb, tmdbShow, kinopubShow]))
    XCTAssertEqual(one, two)
  }

  /// Labels are a platform's statements, not a field to win: every source's are kept.
  func testLabelsFromEverySourceAreKept() throws {
    let exclusive = MediaLabel(id: "exclusive", name: LocalizedName(en: "Exclusive", ru: "Эксклюзив"),
                               source: .kinopub, sourceKey: "genre:128")
    var kinopub = kinopubShow
    kinopub.entity.labels = [exclusive]
    let show = try XCTUnwrap(MediaAggregator.merge([tmdbShow, kinopub]))
    XCTAssertEqual(show.labels, [exclusive])
    XCTAssertEqual(show.genres.map(\.id), ["comedy", "sport"])
  }

  func testIDsFromEverySourceAreKept() throws {
    let show = try XCTUnwrap(MediaAggregator.merge([kinopubShow, tmdbShow]))
    XCTAssertEqual(show.id(.kinopub), "87940")
    XCTAssertEqual(show.id(.tmdb), "97546")
  }

  /// A different declared order is a different answer — the table is the decision.
  func testPrecedenceIsTheDecision() throws {
    var order = MediaPrecedence.standard.order
    order[.title] = [.tmdb, .kinopub]
    let show = try XCTUnwrap(MediaAggregator.merge([kinopubShow, tmdbShow],
                                                   precedence: MediaPrecedence(order: order)))
    XCTAssertEqual(show.title, "Ted Lasso")
  }

  /// A context merges level by level, and needs the thing itself.
  func testAContextNeedsItsItem() {
    XCTAssertNil(MediaAggregator.merge(MediaContextDraft(parent: [kinopubShow])))
    let context = MediaAggregator.merge(MediaContextDraft(
      item: [MediaFragment(.kinopub, .episode) { $0.episodeNumber = 1 }],
      parent: [kinopubShow, tmdbShow]))
    XCTAssertEqual(context?.parent?.title, "Тед Лассо")
    XCTAssertNil(context?.season)
  }
}
