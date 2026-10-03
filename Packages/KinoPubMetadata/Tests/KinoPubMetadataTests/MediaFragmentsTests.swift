//
//  MediaFragmentsTests.swift
//
//  TMDB's side of the media model: what it knows about a title, a season and a single
//  episode, landing in our shapes — and the season-number match that decides which TMDB
//  season a kino.pub block is.
//

import XCTest
import KinoPubMedia
@testable import KinoPubMetadata

final class MediaFragmentsTests: XCTestCase {

  private func day(_ raw: String) -> Date {
    TMDBSource.parseDate(raw)!
  }

  private func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
      ?? Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
  }

  // MARK: - Episode

  /// Everything kino.pub never had about an episode: its description, its air date, its
  /// own score.
  func testAnEpisodeCarriesItsOwnDescriptionDateAndScore() {
    let schedule = EpisodeSchedule(episodeNumber: 5, seasonNumber: 2, name: "Rainbow",
                                   overview: "Nate's night.", airDate: day("2021-08-20"),
                                   runtime: 32, still: URL(string: "https://tmdb/still.jpg"),
                                   voteAverage: 8.6, voteCount: 120)
    let entity = schedule.mediaFragment.entity
    XCTAssertEqual(entity.kind, .episode)
    XCTAssertEqual(entity.seasonNumber, 2)
    XCTAssertEqual(entity.episodeNumber, 5)
    XCTAssertEqual(entity.title, "Rainbow")
    XCTAssertEqual(entity.synopsis.full, "Nate's night.")
    XCTAssertEqual(entity.release, .day(year: 2021, month: 8, day: 20))
    XCTAssertEqual(entity.runtime, 32 * 60)
    XCTAssertEqual(entity.artwork.still?.absoluteString, "https://tmdb/still.jpg")
    XCTAssertEqual(entity.scores.first?.provider, .tmdb)
    XCTAssertEqual(entity.scores.first?.value, 8.6)
    XCTAssertEqual(entity.scores.first?.votes, 120)
  }

  /// A date parsed at UTC midnight reads back as the same day, whatever zone runs this.
  func testAirDatesKeepTheirDay() {
    XCTAssertEqual(ReleaseDate(date: day("2011-04-17")).iso8601, "2011-04-17")
    XCTAssertEqual(ReleaseDate(date: day("2020-01-01")).iso8601, "2020-01-01")
  }

  /// Zero means nobody voted, not a score of zero.
  func testAnUnratedEpisodeHasNoScore() {
    let schedule = EpisodeSchedule(episodeNumber: 1, seasonNumber: 1, voteAverage: 0,
                                   voteCount: 0)
    XCTAssertTrue(schedule.mediaFragment.entity.scores.isEmpty)
  }

  // MARK: - Season

  func testASeasonCarriesItsPosterDateAndDescription() {
    let summary = SeasonSummary(seasonNumber: 2, name: "Season 2", overview: "Year two.",
                                episodeCount: 12, airDate: day("2021-07-23"),
                                poster: URL(string: "https://tmdb/s2.jpg"), voteAverage: 7.9)
    let entity = summary.mediaFragment.entity
    XCTAssertEqual(entity.kind, .season)
    XCTAssertEqual(entity.seasonNumber, 2)
    XCTAssertEqual(entity.synopsis.full, "Year two.")
    XCTAssertEqual(entity.release, .day(year: 2021, month: 7, day: 23))
    XCTAssertEqual(entity.artwork.poster?.absoluteString, "https://tmdb/s2.jpg")
    XCTAssertEqual(entity.scores.first?.value, 7.9)
  }

  // MARK: - Title

  func testAShowCarriesItsRunAndItsGenresInOurVocabulary() {
    var meta = TitleMetadata()
    meta.attribution = [.tmdb]
    meta.tmdbId = 97546
    meta.overview = "A coach."
    meta.tagline = "Believe."
    meta.genres = GenreVocabulary.tmdb(id: 35, name: "Comedy")
      + GenreVocabulary.tmdb(id: 18, name: "Drama")
    meta.firstAirDate = day("2020-08-14")
    meta.lastAirDate = day("2023-05-31")
    meta.releaseDate = day("1999-01-01")
    meta.ageRating = "16+"
    meta.tmdbRating = 8.4
    meta.seasonSummaries = [SeasonSummary(seasonNumber: 1), SeasonSummary(seasonNumber: 2)]

    let fragment = meta.mediaFragment(kind: .show)
    XCTAssertEqual(fragment.source, .tmdb)
    let entity = fragment.entity
    XCTAssertEqual(entity.id(.tmdb), "97546")
    XCTAssertEqual(entity.synopsis.full, "A coach.")
    XCTAssertEqual(entity.synopsis.tagline, "Believe.")
    XCTAssertEqual(entity.primaryGenre?.id, "comedy")
    XCTAssertEqual(entity.release, .day(year: 2020, month: 8, day: 14),
                   "a show premieres on its first air date, not on a movie's release date")
    XCTAssertEqual(entity.ended, .day(year: 2023, month: 5, day: 31))
    XCTAssertEqual(entity.contentRating?.value, "16+")
    XCTAssertEqual(meta.seasonFragment(number: 2)?.entity.seasonNumber, 2)
    XCTAssertNil(meta.seasonFragment(number: 3))
  }

  func testAFilmPremieresOnItsReleaseDate() {
    var meta = TitleMetadata()
    meta.attribution = [.tmdb]
    meta.releaseDate = day("1999-10-15")
    meta.firstAirDate = day("2020-01-01")
    let entity = meta.mediaFragment(kind: .movie).entity
    XCTAssertEqual(entity.release, .day(year: 1999, month: 10, day: 15))
    XCTAssertNil(entity.ended)
  }

  /// The merged overlay keeps no per-field provenance; the fragment is labelled by its
  /// main contributor.
  func testAnOverlayWithoutTMDBIsKinopoisks() {
    var meta = TitleMetadata()
    meta.attribution = [.kinopoiskProxy]
    XCTAssertEqual(meta.mediaFragment(kind: .movie).source, .kinopoisk)
  }

  // MARK: - Kinopoisk's own statement

  /// Everything the details payload says about the title lands in the model under
  /// Kinopoisk's name — the slogan, the short description and the Russian plot included,
  /// which the gap-filling overlay used to drop.
  func testKinopoiskDetailsAreKinopoisksOwnFragment() throws {
    let data = try fixture("kinopoisk_details")
    let details = try MetadataHTTPClient().decode(KinopoiskFilmDetails.self, from: data)
    let fragment = KinopoiskSource.mediaFragment(details)
    XCTAssertEqual(fragment.source, .kinopoisk)
    XCTAssertEqual(fragment.language, "ru")
    let entity = fragment.entity
    XCTAssertEqual(entity.kind, .movie)
    XCTAssertEqual(entity.id(.kinopoisk), "326")
    XCTAssertEqual(entity.title, "Побег из Шоушенка")
    XCTAssertEqual(entity.originalTitle, "The Shawshank Redemption")
    XCTAssertEqual(entity.synopsis.tagline, "Страх - это кандалы. Надежда - это свобода")
    XCTAssertNotNil(entity.synopsis.short)
    XCTAssertNotNil(entity.synopsis.full)
    XCTAssertEqual(entity.contentRating, ContentRating("18+", region: "RU"))
    XCTAssertEqual(entity.primaryGenre?.id, "drama")
    XCTAssertEqual(entity.release, .year(1994))
    XCTAssertEqual(entity.runtime, 142 * 60)
    XCTAssertEqual(Set(entity.scores.map(\.provider)), [.kinopoisk, .imdb])
    XCTAssertEqual(entity.countries, ["США"])
  }

  func testKinopoiskAgeLimitsReadAsAgeRatings() {
    XCTAssertEqual(KinopoiskSource.ageLimit("age18"), "18+")
    XCTAssertEqual(KinopoiskSource.ageLimit("age0"), "0+")
    XCTAssertNil(KinopoiskSource.ageLimit("r"))
    XCTAssertNil(KinopoiskSource.ageLimit(nil))
  }

  /// The model gets TMDB's facts as TMDB's — from TMDB's own part, not from the overlay
  /// Kinopoisk gap-filled — and Kinopoisk's beside them, filed under the caller's kind.
  func testEachSourceReachesTheModelUnderItsOwnName() {
    var tmdb = TitleMetadata()
    tmdb.attribution = [.tmdb]
    tmdb.language = "ru-RU"
    tmdb.tagline = "Fear can hold you prisoner."

    var kinopoisk = TitleMetadata()
    kinopoisk.attribution = [.kinopoisk]
    kinopoisk.artwork.poster = URL(string: "https://kinopoisk/poster.jpg")
    kinopoisk.fragments = [MediaFragment(.kinopoisk, .movie, language: "ru") {
      $0.synopsis = Synopsis(tagline: "Страх — это кандалы.")
    }]

    var overlay = TitleMetadata()
    overlay.merge(tmdb)
    overlay.merge(kinopoisk)
    overlay.parts = [.tmdb: tmdb, .kinopoisk: kinopoisk]

    let fragments = overlay.mediaFragments(kind: .show)
    XCTAssertEqual(fragments.map(\.source), [.tmdb, .kinopoisk])
    XCTAssertEqual(fragments.map(\.entity.kind), [.show, .show])
    XCTAssertEqual(fragments[0].language, "ru-RU")
    XCTAssertNil(fragments[0].entity.artwork.poster,
                 "Kinopoisk's poster must not travel under TMDB's name")
    XCTAssertEqual(fragments[1].entity.synopsis.tagline, "Страх — это кандалы.")
  }

  /// The overlay's merge concatenates statements and never lets one source's replace
  /// another's.
  func testMergeKeepsEverySourcesFragments() {
    var one = TitleMetadata()
    one.fragments = [MediaFragment(.kinopoisk, .movie) { $0.title = "А" }]
    var two = TitleMetadata()
    two.fragments = [MediaFragment(.tmdb, .movie) { $0.title = "B" }]
    one.merge(two)
    XCTAssertEqual(one.fragments.map(\.source), [.kinopoisk, .tmdb])
  }

  // MARK: - Decoding what TMDB already sent

  func testSeasonEpisodesDecodeTheirScores() throws {
    let json = Data("""
    {"season_number": 1, "episodes": [
      {"episode_number": 1, "name": "Pilot", "vote_average": 7.8, "vote_count": 51}
    ]}
    """.utf8)
    let season = try MetadataHTTPClient().decode(TMDBSeasonDetails.self, from: json)
    XCTAssertEqual(season.episodes?.first?.voteAverage, 7.8)
    XCTAssertEqual(season.episodes?.first?.voteCount, 51)
  }

  func testSeasonSummariesDecodeTheirOverview() throws {
    let json = Data("""
    {"season_number": 2, "name": "Season 2", "overview": "Year two.", "vote_average": 7.9}
    """.utf8)
    let ref = try MetadataHTTPClient().decode(TMDBSeasonRef.self, from: json)
    XCTAssertEqual(ref.overview, "Year two.")
    XCTAssertEqual(ref.voteAverage, 7.9)
  }

  // MARK: - Which TMDB season a kino.pub block is

  /// A block kino.pub numbered 1 but named "Сезон 14" is TMDB's season 14.
  func testTheNumberInTheBlocksNameWins() {
    XCTAssertEqual(TMDBSeasonMatch.tmdbSeason(kinoNumber: 1, titleNumber: 14,
                                              tmdbSeasons: [1, 13, 14]), 14)
  }

  func testTheBlocksOwnNumberIsTheFallback() {
    XCTAssertEqual(TMDBSeasonMatch.tmdbSeason(kinoNumber: 2, titleNumber: nil,
                                              tmdbSeasons: [1, 2]), 2)
    XCTAssertEqual(TMDBSeasonMatch.tmdbSeason(kinoNumber: 2, titleNumber: 9,
                                              tmdbSeasons: []), 2,
                   "no season list to check against yet")
  }

  /// Asking TMDB for "season 1" of a block that is really season 14 is how decade-old
  /// "missing episodes" appeared on a current show.
  func testNoCounterpartIsNoAnswer() {
    XCTAssertNil(TMDBSeasonMatch.tmdbSeason(kinoNumber: 3, titleNumber: 20,
                                            tmdbSeasons: [1, 2]))
  }
}
