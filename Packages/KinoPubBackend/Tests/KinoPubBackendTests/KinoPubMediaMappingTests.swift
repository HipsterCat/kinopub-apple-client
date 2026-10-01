//
//  KinoPubMediaMappingTests.swift
//
//  kino.pub's side of the media model: its seven content types, its genre ids, its
//  seasons and episodes, landing in our shapes. Against the captured concert (126187)
//  and multi-version film (124447) payloads where one exists.
//

import XCTest
import KinoPubMedia
@testable import KinoPubBackend

final class KinoPubMediaMappingTests: XCTestCase {

  private func fixture(_ name: String) throws -> MediaItem {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json",
                                              subdirectory: "Fixtures"))
    return try JSONDecoder().decode(SingleItemData<MediaItem>.self,
                                    from: Data(contentsOf: url)).item
  }

  private func item(type: String, genres: [TypeClass], seasons: [Season]? = nil) -> MediaItem {
    let base = MediaItem.mock()
    return MediaItem(id: 87940, type: type, subtype: "", title: "Тед Лассо / Ted Lasso",
                     year: 2020, cast: base.cast, director: base.director, genres: genres,
                     countries: base.countries, voice: nil, duration: base.duration, langs: 0,
                     quality: 0, plot: "Американский тренер…", imdb: 10_986_410,
                     imdbRating: 8.8, imdbVotes: 300_000, kinopoisk: 1_355_139,
                     kinopoiskRating: 8.2, kinopoiskVotes: 90_000, rating: 36,
                     ratingVotes: 328, ratingPercentage: 55, views: 0, comments: 0,
                     posters: Posters(small: "https://k/s.jpg", medium: "", big: "https://k/b.jpg",
                                      wide: nil),
                     trailer: nil, finished: false, advert: false, poorQuality: false,
                     createdAt: 0, updatedAt: 0, inWatchlist: nil, subscribed: nil, ac3: nil,
                     bookmarks: nil, seasons: seasons, videos: nil)
  }

  private func episode(number: Int, title: String = "", thumbnail: String = "") -> Episode {
    Episode(id: 900 + number, title: title, thumbnail: thumbnail, duration: 1_800, tracks: 1,
            number: number, ac3: 0, audios: [], watched: 0,
            watching: EpisodeWatching(status: 0, time: 0), subtitles: [], files: [])
  }

  private func season(number: Int, title: String, episodes: [Episode]) -> Season {
    Season(id: 70 + number, title: title, number: number,
           watching: SeasonWatching(status: 0), episodes: episodes)
  }

  private let comedy = TypeClass(id: 1, title: "Комедия", shortTitle: nil)
  private let sport = TypeClass(id: 20, title: "Спорт", shortTitle: nil)

  // MARK: - Seven types, five shapes

  /// Documentary, concert and 3D are not shapes: they are a genre, a genre, and a format
  /// of this copy.
  func testEveryKinoPubTypeLandsOnAShape() {
    let expected: [(String, MediaKind, GenreDomain, String?)] = [
      ("movie", .movie, .video, nil),
      ("3D", .movie, .video, nil),
      ("serial", .show, .video, nil),
      ("tvshow", .show, .video, "tv-show"),
      ("documovie", .movie, .video, "documentary"),
      ("docuserial", .show, .video, "documentary"),
      ("concert", .movie, .music, "concert"),
    ]
    for (type, kind, domain, implied) in expected {
      let mapping = KinoPubMediaMapping.typeMapping(type)
      XCTAssertEqual(mapping.kind, kind, type)
      XCTAssertEqual(mapping.genreDomain, domain, type)
      XCTAssertEqual(mapping.impliedGenre?.id, implied, type)
    }
    // Every `MediaType` the app knows is covered.
    for type in MediaType.allCases {
      XCTAssertNotNil(expected.first { $0.0.lowercased() == type.rawValue.lowercased() },
                      type.rawValue)
    }
  }

  /// An unknown type reads its shape off the payload.
  func testAnUnknownTypeWithSeasonsIsAShow() {
    XCTAssertEqual(KinoPubMediaMapping.typeMapping("anime", hasSeasons: true).kind, .show)
    XCTAssertEqual(KinoPubMediaMapping.typeMapping("anime").kind, .movie)
  }

  // MARK: - Genres

  /// kino.pub's order is kept — its first is the primary genre.
  func testGenresKeepKinoPubsOrder() {
    let genres = KinoPubMediaMapping.genres([comedy, sport], type: "serial")
    XCTAssertEqual(genres.map(\.id), ["comedy", "sport"])
  }

  /// The captured concert: four music genres, in kino.pub's order, and Concert after them.
  /// The music genre leads.
  func testAConcertIsFiledUnderItsMusic() throws {
    let concert = try fixture("item_126187_concert")
    let entity = concert.mediaFragment.entity
    XCTAssertEqual(entity.kind, .movie)
    XCTAssertEqual(entity.genres.map(\.id),
                   ["music.electronic", "music.new-age", "music.trance", "music.chillout",
                    "concert"])
    XCTAssertEqual(entity.primaryGenre?.id, "music.electronic")
    XCTAssertTrue(entity.genres.allSatisfy(\.isMapped))
  }

  /// Documentary leads a documentary, as Apple files it, and its subject follows.
  func testADocumentaryLeadsWithDocumentary() {
    let history = TypeClass(id: 51, title: "История", shortTitle: nil)
    XCTAssertEqual(KinoPubMediaMapping.genres([history], type: "documovie").map(\.id),
                   ["documentary", "history"])
    // Filed under Documentary explicitly, and not first: it still leads, once.
    let documentary = TypeClass(id: 24, title: "Документальный", shortTitle: nil)
    XCTAssertEqual(KinoPubMediaMapping.genres([history, documentary], type: "docuserial")
      .map(\.id), ["documentary", "history"])
  }

  /// "Эксклюзив" says who carries the copy, not what the work is.
  func testExclusiveIsNotAGenre() {
    let exclusive = TypeClass(id: 133, title: "Эксклюзив", shortTitle: nil)
    let nature = TypeClass(id: 73, title: "Природа", shortTitle: nil)
    XCTAssertEqual(KinoPubMediaMapping.genres([exclusive, nature], type: "documovie")
      .map(\.id), ["documentary", "nature"])
    XCTAssertTrue(KinoPubMediaMapping.genres([TypeClass(id: 128, title: "Эксклюзив",
                                                        shortTitle: nil)], type: "movie")
      .isEmpty)
  }

  /// …but it is not lost: it is a label, with the key kino.pub itself filters by.
  func testExclusiveIsKeptAsALabel() {
    let exclusive = TypeClass(id: 128, title: "Эксклюзив", shortTitle: nil)
    let film = item(type: "movie", genres: [comedy, exclusive])
    let entity = film.mediaFragment.entity
    XCTAssertEqual(entity.genres.map(\.id), ["comedy"])
    XCTAssertEqual(entity.labels.map(\.id), ["exclusive"])
    XCTAssertEqual(entity.labels.first?.sourceKey, "genre:128")
    XCTAssertEqual(entity.labels.first?.source, .kinopub)
    XCTAssertEqual(entity.labels.first?.name.value(languageCode: "ru"), "Эксклюзив")
  }

  /// A TV show says so in its genres, after its formats.
  func testATVShowIsFiledUnderTVShowAfterItsFormat() {
    let reality = TypeClass(id: 114, title: "Реалити-шоу", shortTitle: nil)
    XCTAssertEqual(KinoPubMediaMapping.genres([reality], type: "tvshow").map(\.id),
                   ["reality", "tv-show"])
  }

  // MARK: - kino.pub's own reference list

  private struct Config: Decodable {
    struct Filter: Decodable {
      struct TypeRow: Decodable { let id: String; let genres: String }
      struct GenreRow: Decodable { let id: Int; let title: String }
      let types: [TypeRow]
      let genres: [String: [GenreRow]]
    }
    let filter: Filter
  }

  private func config() throws -> Config {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "kinopub_config",
                                              withExtension: "json",
                                              subdirectory: "Fixtures"))
    return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
  }

  /// `kpapp.link/config.json` v2.12.7, verbatim: **every** genre id kino.pub has lands on a
  /// genre of ours, in the right vocabulary, and no two ids of one set collapse into one
  /// genre — each set keeps its own distinctions.
  func testEveryKinoPubGenreIsMapped() throws {
    let sets = try config().filter.genres
    XCTAssertEqual(Set(sets.keys), ["movie", "docu", "tvshow", "music"])
    for (set, rows) in sets {
      let domain: GenreDomain = set == "music" ? .music : .video
      var seen: [String: String] = [:]
      for row in rows {
        if GenreVocabulary.kinopubNonGenres.contains(row.id) {
          XCTAssertNil(GenreVocabulary.kinopub(id: row.id, title: row.title, domain: domain))
          continue
        }
        guard let genre = GenreVocabulary.kinopub(id: row.id, title: nil, domain: domain) else {
          XCTFail("\(set) \(row.id) \(row.title) has no genre")
          continue
        }
        XCTAssertTrue(genre.isMapped, "\(set) \(row.id) \(row.title)")
        XCTAssertEqual(genre.domain, domain, "\(set) \(row.id) \(row.title)")
        if let other = seen[genre.id] {
          XCTFail("\(set): \(other) and \(row.title) are both \(genre.id)")
        }
        seen[genre.id] = row.title
      }
    }
  }

  /// The type → genre-set table in the same file is the one `typeMapping` follows.
  func testEachTypeLooksUpItsOwnGenreSet() throws {
    for row in try config().filter.types {
      let domain = KinoPubMediaMapping.typeMapping(row.id).genreDomain
      XCTAssertEqual(domain, row.genres == "music" ? .music : .video, row.id)
    }
  }

  // MARK: - The title

  func testATitleCarriesWhatKinoPubKnows() {
    let show = item(type: "serial", genres: [comedy, sport],
                    seasons: [season(number: 1, title: "Сезон 1", episodes: [])])
    let entity = show.mediaFragment.entity
    XCTAssertEqual(entity.kind, .show)
    XCTAssertEqual(entity.title, "Тед Лассо")
    XCTAssertEqual(entity.originalTitle, "Ted Lasso")
    XCTAssertEqual(entity.synopsis.full, "Американский тренер…")
    XCTAssertEqual(entity.release, .year(2020))
    XCTAssertEqual(entity.id(.kinopub), "87940")
    XCTAssertEqual(entity.id(.imdb), "tt10986410")
    XCTAssertEqual(entity.id(.kinopoisk), "1355139")
    XCTAssertEqual(entity.artwork.poster?.absoluteString, "https://k/b.jpg")
    XCTAssertNil(entity.runtime, "a series' total is every episode summed, not a runtime")
  }

  /// IMDb's and Kinopoisk's numbers as kino.pub reports them, and kino.pub's own thumbs
  /// tally as a percentage — side by side.
  func testScoresKeepTheirOwnScales() {
    let scores = item(type: "movie", genres: []).mediaFragment.entity.scores
    XCTAssertEqual(scores.first { $0.provider == .imdb }?.value, 8.8)
    XCTAssertEqual(scores.first { $0.provider == .kinopoisk }?.value, 8.2)
    let own = scores.first { $0.provider == .kinopub }
    XCTAssertEqual(own?.value, 55)
    XCTAssertEqual(own?.scale, 100)
    XCTAssertEqual(own?.votes, 328)
  }

  /// A title without a slash has no separate original title.
  func testNoSlashNoOriginalTitle() {
    XCTAssertNil(MediaItem.mock().replacingTitle("Брат").mediaFragment.entity.originalTitle)
  }

  /// `total` sums both versions of the captured 24/48 fps film; `average` is the film.
  func testAMultiVersionFilmRunsForOneVersion() throws {
    let film = try fixture("item_124447_multi")
    XCTAssertEqual(film.mediaFragment.entity.runtime, 8634)
  }

  // MARK: - Seasons and episodes

  /// kino.pub numbers some shows' blocks from 1 while naming them "Сезон 14"; our model
  /// only carries the real number.
  func testASeasonCarriesItsRealNumber() {
    let block = season(number: 1, title: "Сезон 14", episodes: [])
    XCTAssertEqual(block.mediaFragment.entity.seasonNumber, 14)
    let plain = season(number: 3, title: "Спецвыпуски", episodes: [])
    XCTAssertEqual(plain.mediaFragment.entity.seasonNumber, 3)
  }

  func testAnEpisodeCarriesItsNumbersAndItsOwnStill() {
    let block = season(number: 1, title: "Сезон 14", episodes: [])
    let entity = episode(number: 5, title: "Goodbye Earl", thumbnail: "https://k/still.jpg")
      .mediaFragment(in: block).entity
    XCTAssertEqual(entity.kind, .episode)
    XCTAssertEqual(entity.seasonNumber, 14)
    XCTAssertEqual(entity.episodeNumber, 5)
    XCTAssertEqual(entity.title, "Goodbye Earl")
    XCTAssertEqual(entity.runtime, 1_800)
    XCTAssertEqual(entity.artwork.still?.absoluteString, "https://k/still.jpg")
  }

  // MARK: - A whole playback

  /// An episode played from its series page: the episode, the season it is in, the show.
  func testAnEpisodeIsPlayedInsideItsSeasonAndShow() throws {
    let played = episode(number: 5, thumbnail: "https://k/still.jpg")
    let show = item(type: "serial", genres: [comedy, sport],
                    seasons: [season(number: 2, title: "Сезон 2",
                                     episodes: [episode(number: 1), played])])
    let draft = KinoPubMediaMapping.draft(playing: played, title: show)
    let context = try XCTUnwrap(MediaAggregator.merge(draft))
    XCTAssertEqual(context.item.kind, .episode)
    XCTAssertEqual(context.item.seasonNumber, 2)
    XCTAssertEqual(context.season?.seasonNumber, 2)
    XCTAssertEqual(context.parent?.kind, .show)
    XCTAssertEqual(context.title, "Тед Лассо")
    XCTAssertEqual(context.primaryGenre?.id, "comedy")
    XCTAssertEqual(context.artworkCandidates.first?.absoluteString, "https://k/still.jpg",
                   "an episode is its own cover, not its series'")
  }

  /// Without the series payload (a cold start into a download, say), the name the page
  /// stamped on the episode is still the show's name.
  func testWithoutTheSeriesTheStampedNameStillNamesTheShow() throws {
    let played = episode(number: 3)
    played.seriesTitle = "Ted Lasso"
    played.seasonNumber = 1
    let context = try XCTUnwrap(MediaAggregator.merge(
      KinoPubMediaMapping.draft(playing: played, title: nil)))
    XCTAssertEqual(context.title, "Ted Lasso")
    XCTAssertEqual(context.item.seasonNumber, 1)
    XCTAssertNil(context.season)
  }

  /// A trailer is an extra of its title and reads as that title.
  func testATrailerIsAnExtraOfItsTitle() throws {
    let film = item(type: "movie", genres: [comedy])
    let context = try XCTUnwrap(MediaAggregator.merge(
      KinoPubMediaMapping.draft(playing: film, title: film, isTrailer: true)))
    XCTAssertEqual(context.item.kind, .extra)
    XCTAssertEqual(context.item.extraKind, .trailer)
    XCTAssertEqual(context.title, "Тед Лассо")
    XCTAssertEqual(context.synopsis, "Американский тренер…")
  }

  /// One version of the captured multi-version film: the film's facts, the version's name.
  func testAVersionIsTheFilmWithItsEditionName() throws {
    let film = try fixture("item_124447_multi")
    let variant = try XCTUnwrap(film.playbackVariants.last)
    let context = try XCTUnwrap(MediaAggregator.merge(
      KinoPubMediaMapping.draft(playing: variant, title: film)))
    XCTAssertEqual(context.item.kind, .movie)
    XCTAssertEqual(context.item.edition, "48 fps")
    XCTAssertEqual(context.title, film.localizedTitle)
    XCTAssertEqual(context.primaryGenre?.id, "action")
  }
}

private extension MediaItem {
  func replacingTitle(_ title: String) -> MediaItem {
    MediaItem(id: id, type: type, subtype: subtype, title: title, year: year, cast: cast,
              director: director, genres: genres, countries: countries, voice: voice,
              duration: duration, langs: langs, quality: quality, plot: plot, imdb: imdb,
              imdbRating: imdbRating, imdbVotes: imdbVotes, kinopoisk: kinopoisk,
              kinopoiskRating: kinopoiskRating, kinopoiskVotes: kinopoiskVotes, rating: rating,
              ratingVotes: ratingVotes, ratingPercentage: ratingPercentage, views: views,
              comments: comments, posters: posters, trailer: trailer, finished: finished,
              advert: advert, poorQuality: poorQuality, createdAt: createdAt,
              updatedAt: updatedAt, inWatchlist: inWatchlist, subscribed: subscribed, ac3: ac3,
              bookmarks: bookmarks, seasons: seasons, videos: videos)
  }
}
