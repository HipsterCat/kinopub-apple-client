import XCTest
@testable import KinoPubMetadata

final class TMDBIDFormatterTests: XCTestCase {
  func testPadsToSevenDigits() {
    XCTAssertEqual(TMDBIDFormatter.imdbString(from: 42), "tt0000042")
    XCTAssertEqual(TMDBIDFormatter.imdbString(from: 903_747), "tt0903747")
  }

  func testLongIdsUnpadded() {
    XCTAssertEqual(TMDBIDFormatter.imdbString(from: 12_345_678), "tt12345678")
  }
}

final class TMDBDTODecodingTests: XCTestCase {
  private let client = MetadataHTTPClient()

  func testFindMovie() throws {
    let data = try fixture("find_movie")
    let response = try client.decode(TMDBFindResponse.self, from: data)
    let match = response.match(preferSeries: false)
    XCTAssertEqual(match?.id, 550)
    XCTAssertEqual(match?.type, .movie)
  }

  func testFindTV() throws {
    let data = try fixture("find_tv")
    let response = try client.decode(TMDBFindResponse.self, from: data)
    let match = response.match(preferSeries: true)
    XCTAssertEqual(match?.id, 1399)
    XCTAssertEqual(match?.type, .tv)
  }

  func testMovieDetailsCastAndLogoPreference() throws {
    let data = try fixture("movie_details")
    let details = try client.decode(TMDBTitleDetails.self, from: data)
    XCTAssertEqual(details.credits?.cast?.count, 2)
    XCTAssertEqual(details.credits?.cast?.first?.character, "The Narrator")
    // ru preferred over higher-voted en/null
    XCTAssertEqual(details.images?.bestLogoPath(preferring: ["ru", "en", nil]), "/ruLogo.png")
    XCTAssertEqual(details.images?.bestLogoPath(preferring: ["en", nil]), "/enLogo.png")
    XCTAssertEqual(details.tagline, "Mischief. Mayhem. Soap.")
  }

  func testTVAggregateCreditsAndAgeRating() throws {
    let data = try fixture("tv_details")
    let details = try client.decode(TMDBTitleDetails.self, from: data)
    let cast = details.aggregateCredits?.cast?.first
    XCTAssertEqual(cast?.name, "Peter Dinklage")
    XCTAssertEqual(cast?.primaryCharacter, "Tyrion Lannister")
    XCTAssertEqual(details.lastEpisodeToAir?.episodeNumber, 6)
  }

  func testSeasonScheduleAndUpcoming() throws {
    let data = try fixture("season_1")
    let season = try client.decode(TMDBSeasonDetails.self, from: data)
    XCTAssertEqual(season.episodes?.count, 3)
    let future = season.episodes?.last
    let air = TMDBSource.parseDate(future?.airDate)
    XCTAssertNotNil(air)
    let schedule = EpisodeSchedule(
      episodeNumber: future!.episodeNumber!,
      seasonNumber: 1,
      airDate: air
    )
    XCTAssertTrue(schedule.isUpcoming)
  }

  func testPersonDetails() throws {
    let data = try fixture("person_details")
    let details = try client.decode(TMDBPersonDetails.self, from: data)
    XCTAssertEqual(details.id, 5081)
    XCTAssertEqual(details.name, "Emily Blunt")
    XCTAssertEqual(details.placeOfBirth, "London, England, UK")
    XCTAssertNotNil(TMDBSource.parseDate(details.birthday))
  }

  private func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
      ?? Bundle.module.url(forResource: name, withExtension: "json")
    )
    return try Data(contentsOf: url)
  }
}

final class TitleMetadataMergeTests: XCTestCase {
  func testEnrichFillsPhotoAndCharacterKeepingKinoPubOrder() {
    var meta = TitleMetadata()
    meta.cast = [
      CastMember(name: "Brad Pitt", character: "Tyler Durden",
                 photo: URL(string: "https://image.tmdb.org/t/p/w185/a.jpg")),
      CastMember(name: "Edward Norton", character: "The Narrator",
                 photo: URL(string: "https://image.tmdb.org/t/p/w185/b.jpg")),
    ]
    let enriched = TitleMetadata.enrich(
      names: ["Edward Norton", "Someone Else", "Brad Pitt"],
      roleDepartment: "Acting",
      from: meta
    )
    XCTAssertEqual(enriched.map(\.name), ["Edward Norton", "Someone Else", "Brad Pitt"])
    XCTAssertEqual(enriched[0].character, "The Narrator")
    XCTAssertNotNil(enriched[0].photo)
    XCTAssertNil(enriched[1].photo)
    XCTAssertEqual(enriched[2].character, "Tyler Durden")
  }

  func testMergePrefersExistingLogo() {
    var base = TitleMetadata()
    base.artwork.titleLogo = URL(string: "https://example.com/a.png")
    var other = TitleMetadata()
    other.artwork.titleLogo = URL(string: "https://example.com/b.png")
    other.cast = [CastMember(name: "A")]
    base.merge(other)
    XCTAssertEqual(base.artwork.titleLogo?.absoluteString, "https://example.com/a.png")
    XCTAssertEqual(base.cast.count, 1)
  }
}

final class TMDBImageURLTests: XCTestCase {
  func testBuildsCDNURL() {
    let url = TMDBImageURL.url(path: "/abc.png", size: .logoW500)
    XCTAssertEqual(url?.absoluteString, "https://image.tmdb.org/t/p/w500/abc.png")
  }

  func testBuildsProxiedURL() {
    let proxy = URL(string: "https://kinopub-tmdb-proxy.example.workers.dev")!
    let url = TMDBImageURL.url(path: "/abc.png", size: .profileW185, proxyBase: proxy)
    XCTAssertEqual(
      url?.absoluteString,
      "https://kinopub-tmdb-proxy.example.workers.dev/t/p/w185/abc.png"
    )
  }

  func testNilPath() {
    XCTAssertNil(TMDBImageURL.url(path: nil, size: .profileW185))
    XCTAssertNil(TMDBImageURL.url(path: "", size: .profileW185))
  }
}

final class TitleImageRouteTests: XCTestCase {
  private let worker = URL(string: "https://kinopub-tmdb-proxy.example.workers.dev")!

  func testLogoByKinopubIDWithWidthAndImdbHint() {
    let route = TitleImageRoute(baseURL: worker, language: nil)
    XCTAssertEqual(
      route.logo(kinopubID: 128209, imdb: 903_747, width: 960)?.absoluteString,
      "https://kinopub-tmdb-proxy.example.workers.dev/img/logo/by/kinopub/128209?w=960&imdb=tt0903747"
    )
  }

  func testBackdropCarriesWidthAndLanguage() {
    let route = TitleImageRoute(baseURL: worker, language: "en")
    XCTAssertEqual(
      route.backdrop(kinopubID: 7, imdb: nil, width: 3840)?.absoluteString,
      "https://kinopub-tmdb-proxy.example.workers.dev/img/backdrop/by/kinopub/7?w=3840&lang=en"
    )
  }

  func testNoWidthAsksForOriginal() {
    let route = TitleImageRoute(baseURL: worker, language: nil)
    XCTAssertEqual(
      route.logo(kinopubID: 7, imdb: nil, width: nil)?.absoluteString,
      "https://kinopub-tmdb-proxy.example.workers.dev/img/logo/by/kinopub/7"
    )
  }

  func testSeasonPosterAndEpisodeThumbnail() {
    let route = TitleImageRoute(baseURL: worker, language: nil)
    XCTAssertEqual(
      route.url(.poster, kinopubID: 7, imdb: nil, width: 342, season: 2)?.absoluteString,
      "https://kinopub-tmdb-proxy.example.workers.dev/img/poster/by/kinopub/7?w=342&s=2"
    )
    XCTAssertEqual(
      route.url(.thumbnail, kinopubID: 7, imdb: nil, width: 300, season: 1, episode: 5)?.absoluteString,
      "https://kinopub-tmdb-proxy.example.workers.dev/img/thumbnail/by/kinopub/7?w=300&s=1&e=5"
    )
  }

  func testSameInputsSameURL() {
    let route = TitleImageRoute(baseURL: worker, language: nil)
    XCTAssertEqual(route.logo(kinopubID: 5, imdb: 42, width: 960),
                   route.logo(kinopubID: 5, imdb: 42, width: 960))
  }

  func testUnconfiguredOrBadIDGivesNoURL() {
    XCTAssertNil(TitleImageRoute(baseURL: nil).logo(kinopubID: 5, imdb: 42, width: 960))
    XCTAssertNil(TitleImageRoute(baseURL: worker).logo(kinopubID: 0, imdb: 42, width: 960))
  }

  func testWorkerStampedURLParsesLanguageSegment() {
    let ru = URL(string: "https://worker.example/img/logo/by/kinopub/100564/ru/logo.png")!
    XCTAssertEqual(WorkerArtworkLanguageTag.parseStampedURL(ru), .ru)
    let en = URL(string: "https://worker.example/img/backdrop/by/kinopub/7/und/backdrop.jpg")!
    XCTAssertEqual(WorkerArtworkLanguageTag.parseStampedURL(en), .und)
    XCTAssertEqual(WorkerArtworkLanguageTag.normalize("en-US"), .en)
    XCTAssertNil(WorkerArtworkLanguageTag.normalize("de"))
  }

  func testDeliveredLanguageDrivesCaptionKind() {
    XCTAssertEqual(
      TitleLogoRequestKind(deliveredLanguage: .en).supplementaryUnderLogo(
        localized: "Йеллоустоун", original: "Yellowstone"),
      "Йеллоустоун"
    )
    XCTAssertEqual(
      TitleLogoRequestKind(deliveredLanguage: .ru).supplementaryUnderLogo(
        localized: "Фоллаут", original: "Fallout"),
      "Fallout"
    )
    XCTAssertEqual(
      TitleLogoRequestKind(deliveredLanguage: .ru).supplementaryUnderLogo(
        localized: "Уэнсдэй", original: "Wednesday"),
      "Wednesday"
    )
  }

  func testSupplementaryUnderLogoFollowsRequestLanguage() {
    let ru = TitleLogoRequestKind(routeLanguage: nil)
    XCTAssertEqual(ru.supplementaryUnderLogo(localized: "Йеллоустоун", original: "Yellowstone"),
                   "Yellowstone")
    XCTAssertNil(ru.supplementaryUnderLogo(localized: "Фоллаут", original: "Фоллаут"))
    XCTAssertNil(ru.supplementaryUnderLogo(localized: "Solo", original: "Solo"))
    XCTAssertNil(
      ru.supplementaryUnderLogo(localized: "Следствие вели…", original: "Следствие вели…")
    )

    let en = TitleLogoRequestKind(routeLanguage: "en")
    XCTAssertEqual(en.supplementaryUnderLogo(localized: "Йеллоустоун", original: "Yellowstone"),
                   "Йеллоустоун")
    XCTAssertNil(en.supplementaryUnderLogo(localized: "Dino Ranch", original: "Dino Ranch"))
  }
}

final class WorkerImageAdminCatalogDecodingTests: XCTestCase {
  func testDecodesWhenOnlyEnglishBucketPresent() throws {
    let json = """
    {"ok":true,"id":"128455","kind":"logo","tmdb":"movie/1","en":[{"url":"https://example.test/a.png"}]}
    """
    let catalog = try JSONDecoder().decode(WorkerImageAdminCatalog.self, from: Data(json.utf8))
    XCTAssertTrue(catalog.ru.isEmpty)
    XCTAssertEqual(catalog.en.count, 1)
    XCTAssertTrue(catalog.und.isEmpty)
  }

  func testDecodesExtraLanguageBuckets() throws {
    let json = """
    {"ok":true,"id":"7","kind":"logo","tmdb":"movie/550","ru":[],"en":[],"und":[],"de":[{"url":"https://example.test/de.png","lang":"de"}]}
    """
    let catalog = try JSONDecoder().decode(WorkerImageAdminCatalog.self, from: Data(json.utf8))
    XCTAssertEqual(catalog.extra["de"]?.count, 1)
  }
}

final class TitleCardMappingTests: XCTestCase {
  func testMapsCardOntoThePage() throws {
    let data = try fixture("v2_title")
    let card = try MetadataHTTPClient().decode(TitleCardDTO.self, from: data)
    let proxy = URL(string: "https://kinopub-tmdb-proxy.example.workers.dev")
    let meta = TitleCardSource.map(card, proxyBase: proxy)

    XCTAssertEqual(meta.tmdbId, 30984)
    XCTAssertEqual(meta.kinopoiskID, 4_789_626)
    XCTAssertEqual(meta.status, "Returning Series")
    XCTAssertEqual(meta.inProduction, true)
    XCTAssertEqual(meta.overview, "Про войну.")
    XCTAssertEqual(meta.tmdbRating ?? 0, 8.356, accuracy: 0.001)
    XCTAssertEqual(meta.tmdbVotes, 2323)
    XCTAssertEqual(meta.cast.map(\.name), ["Масакадзу Морита", "Нориаки Сугияма"])
    XCTAssertEqual(meta.cast.first?.character, "Ichigo Kurosaki (voice)")
    XCTAssertEqual(meta.cast.first?.episodeCount, 416)
    XCTAssertEqual(meta.crew.map(\.name), ["Нориюки Абэ"])
    XCTAssertEqual(meta.crew.first?.character, "Director")
    XCTAssertEqual(meta.titleLogoLanguage, "ru")
    XCTAssertEqual(
      meta.titleLogoURL?.absoluteString,
      "https://kinopub-tmdb-proxy.example.workers.dev/t/p/original/logo-ru.png"
    )
    XCTAssertEqual(
      meta.artwork.poster?.absoluteString,
      "https://kinopoiskapiunofficial.tech/images/posters/kp/4789626.jpg"
    )
    XCTAssertEqual(
      meta.backdropURL?.absoluteString,
      "https://kinopub-tmdb-proxy.example.workers.dev/t/p/original/back-plain.jpg"
    )
    XCTAssertEqual(meta.stills.count, 1)
    XCTAssertEqual(meta.productionCompanies.map(\.name), ["TV Tokyo"])
    XCTAssertEqual(meta.seasonSummaries.first?.poster?.absoluteString,
                   "https://kinopub-tmdb-proxy.example.workers.dev/t/p/original/season-1.jpg")
    let season = try XCTUnwrap(meta.schedule[1])
    XCTAssertEqual(season.map(\.name), ["Кровь", "Blood", "Дальше"])
    XCTAssertEqual(meta.nextEpisode?.episodeNumber, 2)
    XCTAssertEqual(meta.nextEpisode?.name, "Дальше")
    XCTAssertEqual(meta.lastEpisode?.episodeNumber, 1)
    XCTAssertEqual(meta.numberOfSeasons, 1)
    XCTAssertEqual(meta.numberOfEpisodes, 2)
  }

  func testProxiesOnlyTMDBImageHosts() {
    let proxy = URL(string: "https://proxy.example")
    XCTAssertEqual(
      TMDBImageURL.proxied("https://image.tmdb.org/t/p/original/a.jpg", proxyBase: proxy)?.absoluteString,
      "https://proxy.example/t/p/original/a.jpg"
    )
    XCTAssertEqual(
      TMDBImageURL.proxied("https://kinopoiskapiunofficial.tech/images/posters/kp/1.jpg", proxyBase: proxy)?.host,
      "kinopoiskapiunofficial.tech"
    )
  }

  private func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
    )
    return try Data(contentsOf: url)
  }
}
