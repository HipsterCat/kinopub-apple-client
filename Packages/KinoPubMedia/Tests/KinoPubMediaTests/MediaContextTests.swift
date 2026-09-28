//
//  MediaContextTests.swift
//
//  What an episode borrows from its season and show, what it must never borrow, and
//  which picture stands for it.
//

import XCTest
@testable import KinoPubMedia

final class MediaContextTests: XCTestCase {

  private let comedy = GenreVocabulary.genre(id: "comedy")!
  private let sport = GenreVocabulary.genre(id: "sport")!

  private let still = URL(string: "https://e.x/still.jpg")!
  private let seasonPoster = URL(string: "https://e.x/season.jpg")!
  private let showPoster = URL(string: "https://e.x/show.jpg")!
  private let showBackdrop = URL(string: "https://e.x/backdrop.jpg")!

  private var show: MediaEntity {
    MediaEntity(kind: .show, title: "Ted Lasso",
                synopsis: Synopsis(full: "A coach."),
                genres: [comedy, sport],
                release: .year(2020),
                contentRating: ContentRating("16+"),
                scores: [Score(.imdb, value: 8.8)!],
                artwork: ArtworkSet(poster: showPoster, backdrop: showBackdrop))
  }

  private var season: MediaEntity {
    MediaEntity(kind: .season, seasonNumber: 2,
                release: .day(year: 2021, month: 7, day: 23),
                artwork: ArtworkSet(poster: seasonPoster))
  }

  private func episode(synopsis: String? = nil, still: URL? = nil,
                       release: ReleaseDate? = nil) -> MediaEntity {
    MediaEntity(kind: .episode, title: "Goodbye Earl", seasonNumber: 2, episodeNumber: 5,
                synopsis: Synopsis(full: synopsis), release: release,
                artwork: ArtworkSet(still: still))
  }

  // MARK: - Borrowed

  func testAnEpisodeIsKnownByItsShowsName() {
    XCTAssertEqual(MediaContext(item: episode(), parent: show).title, "Ted Lasso")
  }

  /// Nobody files an episode under a genre; its show's genres are its genres, and the
  /// show's first is its primary genre.
  func testAnEpisodeTakesItsShowsGenresAndRating() {
    let context = MediaContext(item: episode(), season: season, parent: show)
    XCTAssertEqual(context.genres, [comedy, sport])
    XCTAssertEqual(context.primaryGenre, comedy)
    XCTAssertEqual(context.contentRating?.value, "16+")
  }

  func testAnEpisodesOwnDescriptionWins() {
    let context = MediaContext(item: episode(synopsis: "Rebecca's secret."), parent: show)
    XCTAssertEqual(context.synopsis, "Rebecca's secret.")
  }

  /// A line about the show beats an empty panel.
  func testTheShowsDescriptionStandsInForAMissingOne() {
    XCTAssertEqual(MediaContext(item: episode(), parent: show).synopsis, "A coach.")
  }

  /// Air date: the episode's, else its season's, else its show's.
  func testTheNearestDateWins() {
    let own = ReleaseDate.day(year: 2021, month: 8, day: 20)
    XCTAssertEqual(MediaContext(item: episode(release: own), season: season, parent: show)
      .release, own)
    XCTAssertEqual(MediaContext(item: episode(), season: season, parent: show).release,
                   .day(year: 2021, month: 7, day: 23))
    XCTAssertEqual(MediaContext(item: episode(), parent: show).release, .year(2020))
  }

  // MARK: - Never borrowed

  /// A show's 8.8 printed on one of its episodes would be a number nobody gave it.
  func testScoresAreNeverInherited() {
    XCTAssertTrue(MediaContext(item: episode(), parent: show).scores.isEmpty)
  }

  // MARK: - Artwork

  /// An episode is its own still — the cover of *this* episode, not of the series.
  func testAnEpisodeIsItsOwnStill() {
    let context = MediaContext(item: episode(still: still), season: season, parent: show)
    XCTAssertEqual(context.artworkCandidates, [still, seasonPoster, showPoster, showBackdrop])
  }

  func testWithoutAStillTheSeasonThenTheShowStandIn() {
    XCTAssertEqual(MediaContext(item: episode(), season: season, parent: show)
      .artworkCandidates.first, seasonPoster)
    XCTAssertEqual(MediaContext(item: episode(), parent: show).artworkCandidates.first,
                   showPoster)
  }

  func testAFilmIsItsPoster() {
    let film = MediaEntity(kind: .movie,
                           artwork: ArtworkSet(poster: showPoster, still: still,
                                               backdrop: showBackdrop))
    XCTAssertEqual(MediaContext(item: film).artworkCandidates, [showPoster, showBackdrop, still])
  }

  /// A trailer is about its film: the film's name, its description, its poster.
  func testATrailerDescribesItsFilm() {
    let film = MediaEntity(kind: .movie, title: "Dune", synopsis: Synopsis(full: "Spice."),
                           genres: [GenreVocabulary.genre(id: "sci-fi")!],
                           artwork: ArtworkSet(poster: showPoster))
    let trailer = MediaEntity(kind: .extra, extraKind: .trailer)
    let context = MediaContext(item: trailer, parent: film)
    XCTAssertEqual(context.title, "Dune")
    XCTAssertEqual(context.synopsis, "Spice.")
    XCTAssertEqual(context.primaryGenre?.id, "sci-fi")
    XCTAssertEqual(context.artworkCandidates, [showPoster])
  }

  func testCandidatesAreNeverRepeated() {
    let film = MediaEntity(kind: .movie, artwork: ArtworkSet(poster: showPoster,
                                                             backdrop: showPoster))
    XCTAssertEqual(MediaContext(item: film).artworkCandidates, [showPoster])
  }
}
