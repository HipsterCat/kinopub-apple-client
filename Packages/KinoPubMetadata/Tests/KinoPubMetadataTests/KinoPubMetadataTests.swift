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

  /// kino.pub and the worker transliterate Korean names differently; the match must hold,
  /// and one worker person answers one kino.pub name only.
  func testEnrichMatchesAnotherTransliterationOfTheSameName() {
    var meta = TitleMetadata()
    meta.cast = [
      CastMember(name: "До Кён Су", tmdbPersonId: 2, episodeCount: 12),
      CastMember(name: "Ли Кван Су", tmdbPersonId: 3, episodeCount: 12),
      CastMember(name: "Майкл С. Холл", tmdbPersonId: 4)
    ]
    let enriched = TitleMetadata.enrich(names: ["То Гён-су", "Ли Гван-су", "До Кён-су", "Иван Петров"],
                                        roleDepartment: "Acting", from: meta)
    XCTAssertEqual(enriched.map(\.name), ["То Гён-су", "Ли Гван-су", "До Кён-су", "Иван Петров"])
    XCTAssertEqual(enriched.map(\.tmdbPersonId), [2, 3, nil, nil])
    XCTAssertEqual(TitleMetadata.soundKey("Чжан Цзыи"), TitleMetadata.soundKey("Чжан Цзы-и"))
    XCTAssertNotEqual(TitleMetadata.soundKey("Майкл С. Холл"), TitleMetadata.soundKey("Майкл К. Холл"))
  }

  /// Closed-pool fuzzy: diminutives, EN↔RU, hyphen glue — not an alias dictionary.
  func testEnrichFuzzyMatchesDiminutiveAndTranslitInClosedPool() {
    var meta = TitleMetadata()
    meta.cast = [
      CastMember(name: "Raymond Nicholson", localizedName: "Реймонд Николсон", tmdbPersonId: 10),
      CastMember(name: "Lola Bond", localizedName: "Лола Бонд", tmdbPersonId: 11),
      CastMember(name: "Owen Wilson", localizedName: "Оуэн Уилсон", tmdbPersonId: 12),
      CastMember(name: "Luke Wilson", localizedName: "Люк Уилсон", tmdbPersonId: 13),
      CastMember(name: "Michael C. Hall", localizedName: "Майкл С. Холл", tmdbPersonId: 14),
      CastMember(name: "Michael K. Hall", localizedName: "Майкл К. Холл", tmdbPersonId: 15),
      CastMember(name: "Ку Гё-Хван", tmdbPersonId: 16),
      CastMember(name: "Brad Pitt", localizedName: "Брэд Питт", tmdbPersonId: 17),
    ]
    let enriched = TitleMetadata.enrich(
      names: [
        "Рей Николсон",
        "Лола Бонд",
        "Ку ГёХван",
        "Оуэн Уилсон",
        "Майкл С. Холл",
        "Уилсон",
      ],
      roleDepartment: "Acting",
      from: meta
    )
    XCTAssertEqual(enriched.map(\.tmdbPersonId), [10, 11, 16, 12, 14, nil])
  }

  func testPersonNameMatchRayRaymondAndRejectsAmbiguousSurname() {
    let pool = [
      "Brad Pitt", "Edward Norton", "Raymond Nicholson", "Owen Wilson", "Luke Wilson",
      "Lola Bond", "Michael C. Hall", "Michael K. Hall", "Gu Gyo-hwan", "Tom Holland",
    ]
    let ray = PersonNameMatch.bestIndex(query: "Ray Nicholson", in: pool)
    XCTAssertEqual(ray?.index, 2)
    XCTAssertGreaterThanOrEqual(ray?.score ?? 0, PersonNameMatch.acceptScore)

    let lola = PersonNameMatch.bestIndex(query: "Лола Бонд", in: pool)
    XCTAssertEqual(lola?.index, 5)

    // Surname-only against two Wilsons — margin fails.
    XCTAssertNil(PersonNameMatch.bestIndex(query: "Уилсон", in: pool))
    // After one Wilson is claimed, the leftover sibling must still look ambiguous.
    XCTAssertNil(PersonNameMatch.bestIndex(query: "Уилсон", in: pool, excluding: [3]))

    // Middle initial: same-script discrimination (stage-1; cross-script Hall needs aliases).
    let hallRU = ["Майкл К. Холл", "Майкл С. Холл"]
    XCTAssertEqual(PersonNameMatch.bestIndex(query: "Майкл С. Холл", in: hallRU)?.index, 1)
    let hallEN = ["Michael K. Hall", "Michael C. Hall"]
    XCTAssertEqual(PersonNameMatch.bestIndex(query: "Michael C. Hall", in: hallEN)?.index, 1)
    // Cyrillic С. initial maps to Latin C (glyph), not phonetic /s/.
    XCTAssertEqual(PersonNameMatch.bestIndex(query: "Майкл С. Холл", in: hallEN)?.index, 1)
  }

  func testPersonPhotoMarksTinyKinopoiskAsUpgrade() {
    let tiny = URL(string: "https://st.kp.yandex.net/images/actor_iphone/iphone120_123.jpg")
    let ok = URL(string: "https://st.kp.yandex.net/images/actor_iphone/iphone360_123.jpg")
    let tmdb = URL(string: "https://image.tmdb.org/t/p/w185/abc.jpg")
    let smallFolder = URL(string: "https://kinopoiskapiunofficial.tech/images/actor_posters/kp_small/9.jpg")
    XCTAssertTrue(PersonPhoto.needsUpgrade(nil))
    XCTAssertTrue(PersonPhoto.needsUpgrade(tiny))
    XCTAssertTrue(PersonPhoto.needsUpgrade(smallFolder))
    XCTAssertFalse(PersonPhoto.needsUpgrade(ok))
    XCTAssertFalse(PersonPhoto.needsUpgrade(tmdb))
    XCTAssertEqual(PersonPhoto.inferredWidth(in: tiny!.absoluteString), 120)
    XCTAssertEqual(PersonPhoto.inferredWidth(in: ok!.absoluteString), 360)
  }

  func testPersonPhotoPrefersStrongKinopoiskThenTMDBOverTiny() {
    let tinyKP = URL(string: "https://st.kp.yandex.net/images/actor_iphone/iphone120_1.jpg")
    let strongKP = URL(string: "https://st.kp.yandex.net/images/actor_iphone/iphone360_1.jpg")
    let tmdb = URL(string: "https://image.tmdb.org/t/p/w185/a.jpg")
    XCTAssertEqual(PersonPhoto.picking(existing: tinyKP, candidate: tmdb), tmdb)
    XCTAssertEqual(PersonPhoto.picking(existing: tmdb, candidate: tinyKP), tmdb)
    XCTAssertEqual(PersonPhoto.picking(existing: tmdb, candidate: strongKP), strongKP)
    XCTAssertEqual(PersonPhoto.picking(existing: strongKP, candidate: tmdb), strongKP)
    XCTAssertEqual(PersonPhoto.picking(existing: nil, candidate: tmdb), tmdb)
  }

  /// TMDB-first merge: a tiny Kinopoisk headshot on the RU spelling upgrades to TMDB.
  func testMergeCastUpgradesTinyKinopoiskPhotoFromFuzzyTMDBMatch() {
    let tinyKP = URL(string: "https://st.kp.yandex.net/images/actor_iphone/iphone120_99.jpg")!
    let tmdb = URL(string: "https://image.tmdb.org/t/p/w185/ni.jpg")!
    let base = [
      CastMember(name: "Ni Dahong", photo: tmdb, tmdbPersonId: 42),
      CastMember(name: "Selena Li", photo: tmdb, tmdbPersonId: 7),
    ]
    let overlay = [
      CastMember(name: "Ни Дахун", photo: tinyKP),
      CastMember(name: "Селена Ли"),
    ]
    let merged = TitleMetadata.mergeCast(base: overlay, overlay: base)
    XCTAssertEqual(merged.map(\.name), ["Ни Дахун", "Селена Ли"])
    XCTAssertEqual(merged[0].photo, tmdb)
    XCTAssertEqual(merged[0].tmdbPersonId, 42)
    XCTAssertEqual(merged[1].photo, tmdb)
    XCTAssertEqual(merged[1].tmdbPersonId, 7)
  }

  /// A large Kinopoisk face must not be replaced by TMDB when merging the other way.
  func testMergeCastKeepsStrongKinopoiskPhoto() {
    let strongKP = URL(string: "https://st.kp.yandex.net/images/actor_iphone/iphone360_1.jpg")!
    let tmdb = URL(string: "https://image.tmdb.org/t/p/w185/a.jpg")!
    let merged = TitleMetadata.mergeCast(
      base: [CastMember(name: "Морган Фриман", photo: strongKP)],
      overlay: [CastMember(name: "Morgan Freeman", photo: tmdb, tmdbPersonId: 6750)]
    )
    XCTAssertEqual(merged[0].photo, strongKP)
    XCTAssertEqual(merged[0].tmdbPersonId, 6750)
  }

  func testEnrichUpgradesTinyPhotoFromPoolTwin() {
    let tinyKP = URL(string: "https://st.kp.yandex.net/images/actor_iphone/iphone120_5.jpg")!
    let tmdb = URL(string: "https://image.tmdb.org/t/p/w185/selena.jpg")!
    var meta = TitleMetadata()
    meta.cast = [
      CastMember(name: "Селена Ли", photo: tinyKP, tmdbPersonId: 7),
      CastMember(name: "Selena Li", localizedName: "Селена Ли", photo: tmdb, tmdbPersonId: 7),
    ]
    let enriched = TitleMetadata.enrich(names: ["Селена Ли"], roleDepartment: "Acting", from: meta)
    XCTAssertEqual(enriched[0].photo, tmdb)
    XCTAssertEqual(enriched[0].tmdbPersonId, 7)
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
      "https://kinopub-tmdb-proxy.example.workers.dev/img/logo/by/kinopub/128209?w=1280&imdb=tt0903747"
    )
  }

  func testBackdropCarriesWidthAndLanguage() {
    let route = TitleImageRoute(baseURL: worker, language: "en")
    XCTAssertEqual(
      route.backdrop(kinopubID: 7, imdb: nil, width: 3840)?.absoluteString,
      "https://kinopub-tmdb-proxy.example.workers.dev/img/backdrop/by/kinopub/7?w=2400&lang=en"
    )
  }

  func testCoverUsesBackdropLadderAndLanguage() {
    let route = TitleImageRoute(baseURL: worker, language: "en")
    XCTAssertEqual(
      route.cover(kinopubID: 7, imdb: 903_747, width: 1920)?.absoluteString,
      "https://kinopub-tmdb-proxy.example.workers.dev/img/cover/by/kinopub/7?w=1920&imdb=tt0903747&lang=en"
    )
    XCTAssertEqual(TitleImageRoute.bucketedWidth(.cover, pixels: 2400), 2400)
  }

  func testBucketedWidthNeverOriginal() {
    XCTAssertEqual(TitleImageRoute.bucketedWidth(.logo, pixels: 680), 780)
    XCTAssertEqual(TitleImageRoute.bucketedWidth(.logo, pixels: 1080), 1280)
    XCTAssertEqual(TitleImageRoute.bucketedWidth(.logo, pixels: 1360), 1280)
    XCTAssertEqual(TitleImageRoute.bucketedWidth(.logo, pixels: 2560), 1280)
    XCTAssertEqual(TitleImageRoute.bucketedWidth(.backdrop, pixels: 1920), 1920)
    XCTAssertEqual(TitleImageRoute.bucketedWidth(.backdrop, pixels: 2400), 2400)
    XCTAssertEqual(TitleImageRoute.bucketedWidth(.backdrop, pixels: 3840), 2400)
    XCTAssertEqual(TitleImageRoute.bucketedWidth(.backdrop, pixels: 5120), 2400)
    XCTAssertEqual(TitleImageRoute.bucketedWidth(.poster, pixels: 400), 454)
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
    let thumb = "https://m.staticpop.net/thumb/item/abc/1280.jpg"
    let withSrc = route.url(.thumbnail, kinopubID: 128431, imdb: 39_980_704, width: 584,
                            season: 1, episode: 6, kinopubThumb: thumb)?.absoluteString
    XCTAssertEqual(
      withSrc,
      "https://kinopub-tmdb-proxy.example.workers.dev/img/thumbnail/by/kinopub/128431?w=584&s=1&e=6&imdb=tt39980704&src=https://m.staticpop.net/thumb/item/abc/1280.jpg"
    )
    XCTAssertFalse(TitleImageRoute.isStaticpopThumb("https://image.tmdb.org/t/p/original/x.jpg"))
    XCTAssertTrue(TitleImageRoute.isStaticpopThumb(thumb))
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
    XCTAssertEqual(
      meta.cast.first?.photo?.absoluteString,
      "https://kinopub-tmdb-proxy.example.workers.dev/t/p/original/face.jpg"
    )
    // Billing had no profile_url; images[] supplies the TMDB face.
    XCTAssertEqual(
      meta.cast[1].photo?.absoluteString,
      "https://kinopub-tmdb-proxy.example.workers.dev/t/p/original/sugiyama.jpg"
    )
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

  func testByKinopubURLCarriesIdentityHints() throws {
    let source = TitleCardSource(configuration: MetadataConfiguration(
      proxyBaseURL: URL(string: "https://proxy.test")
    ))
    let identity = MediaIdentity(
      kinopubId: 99,
      imdb: "tt0418279",
      kinopoisk: 81288,
      title: "Трансформеры",
      originalTitle: "Transformers",
      year: 2007,
      isSeries: false,
      runtimeMinutes: 144
    )
    let url = try XCTUnwrap(source.makeURL(for: identity))
    let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
    XCTAssertEqual(url.path, "/v2/title/by/kinopub/99")
    XCTAssertEqual(value("imdb"), "tt0418279")
    XCTAssertEqual(value("kinopoisk"), "81288")
    XCTAssertEqual(value("year"), "2007")
    XCTAssertEqual(value("name_ru"), "Трансформеры")
    XCTAssertEqual(value("name_original"), "Transformers")
    XCTAssertEqual(value("runtime"), "144")
    XCTAssertEqual(value("type"), "movie")
  }

  func testSeriesURLHintsShowAndOmitsEmptyIds() throws {
    let source = TitleCardSource(configuration: MetadataConfiguration(
      proxyBaseURL: URL(string: "https://proxy.test/")
    ))
    let identity = MediaIdentity(
      kinopubId: 7,
      imdb: nil,
      kinopoisk: nil,
      title: "Шоу",
      originalTitle: "",
      year: 0,
      isSeries: true
    )
    let url = try XCTUnwrap(source.makeURL(for: identity))
    let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    XCTAssertEqual(Set(items.map(\.name)), ["name_ru", "type"])
    XCTAssertEqual(items.first { $0.name == "type" }?.value, "show")
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
    // Card / seasons stills are relative `/img/thumbnail…` — join to the proxy host.
    XCTAssertEqual(
      TMDBImageURL.proxied("/img/thumbnail/by/kinopub/7?s=1&e=2", proxyBase: proxy)?.absoluteString,
      "https://proxy.example/img/thumbnail/by/kinopub/7?s=1&e=2"
    )
  }

  private func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
    )
    return try Data(contentsOf: url)
  }

  func testLinkedTMDBIDIsReadByTypeAndNumber() {
    let show = TMDBSource.linkedID("tv/343022")
    XCTAssertEqual(show?.tmdbId, 343022)
    XCTAssertEqual(show?.type, .tv)
    XCTAssertEqual(TMDBSource.linkedID("movie/550")?.type, .movie)
    for bad in [nil, "", "343022", "tv/", "tv/0", "person/5", "tv/5/6"] {
      XCTAssertNil(TMDBSource.linkedID(bad))
    }
  }

  func testLinkedIdsFillWhatKinopubLacksAndKeepItsIMDb() {
    let bare = MediaIdentity(kinopubId: 129247, imdb: nil, kinopoisk: 5236833, title: "Шанхай",
                             originalTitle: "Шанхай", year: 2021, isSeries: true)
    let linked = bare.withLinked(imdb: "tt40658685", tmdb: "tv/343022")
    XCTAssertEqual(linked.imdb, "tt40658685")
    XCTAssertEqual(linked.linkedTMDB, "tv/343022")
    XCTAssertEqual(linked.withKinopoisk(7).linkedTMDB, "tv/343022")
    XCTAssertEqual(linked.withLinked(imdb: "tt1", tmdb: nil), linked)
  }

  /// The live card of kino.pub 129247: `season_finale` arrives as 0, not a Bool.
  func testLinkedIdsSurviveACardTheFullDecoderRejects() throws {
    let json = """
    {"kinopub_id":129247,"type":null,"year":null,
     "ids":{"imdb":"tt40658685","tmdb":"tv/343022","kinopoisk":"5236833","myshows":null},
     "seasons":[{"number":1,"episodes":[{"number":1,"season_finale":0}]}]}
    """
    let ids = try TitleCardSource.linkedIDs(from: Data(json.utf8), client: MetadataHTTPClient())
    XCTAssertEqual(ids.imdb, "tt40658685")
    XCTAssertEqual(ids.tmdb, "tv/343022")
  }
}
