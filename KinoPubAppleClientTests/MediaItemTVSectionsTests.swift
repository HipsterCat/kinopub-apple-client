//
//  MediaItemTVSectionsTests.swift
//  KinoPubAppleClientTests
//
//  What the tvOS detail page says under the hero, and in what order — one pure function,
//  `MediaItemTVSections.make`, over the `film` fixture (a film with every part populated).
//  Sasha's order of 2026-10-06:
//
//      Ratings | Reviews · Cast & Crew (Director | Starring) · Similar · Stills | Facts ·
//      Type, Year, Countries, Genres · Collections and other selections ·
//      Video | Audio | Subtitles
//
//  and what Sasha asked for on top of it the same day: professions as subheadings, no
//  profession on a card, several directors in a row of their own, the cast ranked and
//  trimmed, no captions on covers, the type as an SF Symbol.
//

#if os(tvOS)
import KinoPubBackend
import KinoPubMetadata
import UIKit
import XCTest
@testable import KinoPub
@testable import KinoPubUI

@MainActor
final class MediaItemTVSectionsTests: XCTestCase {

  private let fixture = DetailFixture.film

  /// Similar, the director's other work, a collection (which has a page of its own).
  private var rows: [MediaRow] {
    let cards = DetailFixture.similarItems().map(MediaCard.init)
    return [
      MediaRow(id: "similar", title: "Похожие", cards: cards),
      MediaRow(id: "director-1", title: "Ещё от режиссёра", cards: cards),
      MediaRow(id: "collection-178", title: "22 фильма о криминальной России", cards: cards,
               destination: Route.detailsById(1))
    ]
  }

  private func input(_ configure: (inout MediaItemTVSections.Input) -> Void = { _ in })
  -> MediaItemTVSections.Input {
    var input = MediaItemTVSections.Input(mediaItem: fixture.makeItem(),
                                          metadata: fixture.metadata,
                                          likeCount: 145,
                                          dislikeCount: 19,
                                          relatedRows: rows,
                                          preferredLanguages: ["ru"])
    configure(&input)
    return input
  }

  private func groupIDs(_ section: TVPageSection) -> [String] { section.groups.map(\.id) }

  // MARK: - Order

  func testSectionsComeInTheOrderOfTheDesign() {
    let sections = MediaItemTVSections.make(input())
    XCTAssertEqual(sections.map(\.id),
                   ["ratings", "credits", "similar", "stills-facts", "tags",
                    "director-1", "collection-178", "specs"])
  }

  func testRowsOfTwoAreOneStripOfTitledGroups() {
    let sections = MediaItemTVSections.make(input())
    func strip(_ id: String) -> TVPageSection { sections.first { $0.id == id }! }

    XCTAssertEqual(groupIDs(strip("ratings")), ["scores", "reviews"])
    XCTAssertEqual(groupIDs(strip("credits")), ["directors", "cast"])
    XCTAssertEqual(groupIDs(strip("stills-facts")), ["stills", "facts", "awards"])
    XCTAssertEqual(groupIDs(strip("tags")), ["type", "year", "countries", "genres"])
    XCTAssertEqual(strip("ratings").kind, .strip)
    // The three columns of the technical table are one untitled group — no title strip.
    XCTAssertEqual(groupIDs(strip("specs")), ["specs"])
    XCTAssertNil(strip("specs").groups[0].title)
  }

  func testSimilarIsTheOnlyRowInItsPlaceAndTheOthersFollowTheTags() {
    let sections = MediaItemTVSections.make(input())
    let similar = sections.first { $0.id == "similar" }
    XCTAssertEqual(similar?.kind, .poster)
    XCTAssertEqual(similar?.columns, 6, "Home's own poster row")
    XCTAssertEqual(similar?.caption, .never, "Home's own caption: none — no title or year under a cover, not even on focus")
    // Everything else the model recommends is below the tags, in the model's order.
    let ids = sections.map(\.id)
    XCTAssertLessThan(ids.firstIndex(of: "tags")!, ids.firstIndex(of: "director-1")!)
    XCTAssertLessThan(ids.firstIndex(of: "collection-178")!, ids.firstIndex(of: "specs")!)
  }

  /// Every shelf is covers and nothing else: no "See all" tile (Sasha, 2026-10-06 — it named
  /// itself on focus, and the footer that allowed gave the covers beside it a height of their own).
  func testAShelfIsCoversOnlyWithNoSeeAllTile() {
    let sections = MediaItemTVSections.make(input())
    for id in ["collection-178", "director-1"] {
      let shelf = sections.first { $0.id == id }!
      XCTAssertEqual(shelf.caption, .never, "Home's own caption: none")
      XCTAssertFalse(shelf.items.contains { if case .tile = $0 { return true } else { return false } },
                     "\(id): a shelf ends in its last cover")
      XCTAssertTrue(shelf.items.allSatisfy { if case .card = $0 { return true } else { return false } })
    }
  }

  // MARK: - Absent parts

  func testEmptyPartsAreSimplyAbsent() {
    let sections = MediaItemTVSections.make(input {
      $0.metadata = TitleMetadata()
      $0.relatedRows = []
    })
    let ids = sections.map(\.id)
    XCTAssertEqual(ids, ["ratings", "credits", "tags", "specs"],
                   "no similar, no stills or facts, no other shelves")
    XCTAssertEqual(groupIDs(sections[0]), ["scores"], "no reviews, so no Reviews group")
    XCTAssertEqual(groupIDs(sections[1]), ["directors", "cast"], "kino.pub's own credits need no metadata")
  }

  func testShelvesStillInFlightHoldTheirPlaceAsSkeletonRows() {
    let sections = MediaItemTVSections.make(input {
      $0.relatedRows = []
      $0.pendingShelfTitles = ["Ещё от режиссёра"]
    })
    let pending = sections.first { $0.id == "pending.Ещё от режиссёра" }
    XCTAssertEqual(pending?.isPlaceholder, true)
  }

  // MARK: - Scores and reviews

  func testScoresAreOrderedByAudienceAndKinoPubCarriesItsThumbs() {
    let ratings = MediaItemTVSections.make(input()).first { $0.id == "ratings" }!
    let scores = ratings.groups[0].items.compactMap { item -> TVPageInfoCard.Rating? in
      if case .info(.rating(let rating)) = item { return rating }
      return nil
    }
    XCTAssertEqual(scores.map(\.id), ["IMDb", "Кинопоиск", "KinoPub", "TMDB"])
    let kinoPub = scores.first { $0.id == "KinoPub" }!
    XCTAssertEqual(kinoPub.thumbs?.up, 145.formatted(.number.grouping(.automatic)))
    XCTAssertEqual(kinoPub.thumbs?.down, 19.formatted(.number.grouping(.automatic)))
    XCTAssertNil(kinoPub.caption, "its thumbs are its caption")
    XCTAssertTrue(kinoPub.showsName, "a glyph with no lettering carries the source's name")
    XCTAssertFalse(scores.first { $0.id == "IMDb" }!.showsName, "the IMDb mark spells its own name")
  }

  func testAReviewWithNoHeadlineIsTitledByItsAuthor() {
    let ratings = MediaItemTVSections.make(input()).first { $0.id == "ratings" }!
    let reviews = ratings.groups[1].items.compactMap { item -> TVPageInfoCard.Review? in
      if case .info(.review(let review)) = item { return review }
      return nil
    }
    XCTAssertEqual(reviews.count, 3)
    XCTAssertEqual(reviews[0].headline, "Крепкое возвращение")
    XCTAssertEqual(reviews[1].headline, "Lintandil", "no headline: the author stands in")
    XCTAssertEqual(reviews.map(\.tone), [.positive, .neutral, .negative])
  }

  // MARK: - People

  func testDirectorAndCastAreSearchStylePersonCards() {
    let credits = MediaItemTVSections.make(input()).first { $0.id == "credits" }!
    let directors = credits.groups[0]
    XCTAssertEqual(directors.title, "Director".localized)
    XCTAssertEqual(directors.columns, 3, "the wide card search draws, three across")
    guard case .person(let director)? = directors.items.first else { return XCTFail("no director card") }
    XCTAssertEqual(director.name, "Дестин Дэниел Креттон")
    XCTAssertNil(director.caption, "the group's subheading says Director; the card does not")

    let cast = credits.groups[1]
    XCTAssertEqual(cast.title, "MediaItem_Starring".localized)
    guard case .person(let lead)? = cast.items.first else { return XCTFail("no cast card") }
    XCTAssertEqual(lead.name, "Том Холланд")
    XCTAssertEqual(lead.caption, "Питер Паркер", "the character, from TMDB")
  }

  /// "Cast & Crew", and under it the professions as subheadings — Director, Starring.
  func testCastAndCrewIsOneHeadingOverTheProfessions() {
    let credits = MediaItemTVSections.make(input()).first { $0.id == "credits" }!
    XCTAssertEqual(credits.title, "MediaItem_CastAndCrew".localized)
    XCTAssertEqual(credits.groups.map(\.title), ["Director".localized, "MediaItem_Starring".localized])
    XCTAssertEqual(credits.groups.map(\.isSubheading), [true, true])
    XCTAssertEqual(credits.kind, .strip)
    // The other rows' groups are the rows' own titles.
    let ratings = MediaItemTVSections.make(input()).first { $0.id == "ratings" }!
    XCTAssertEqual(ratings.groups.map(\.isSubheading), [false, false])
  }

  func testAPersonWithNoCharacterHasNoCaptionAtAll() {
    let credits = MediaItemTVSections.make(input {
      $0.metadata = TitleMetadata()
    }).first { $0.id == "credits" }!
    let captions = credits.groups.flatMap(\.items).compactMap { item -> String?? in
      if case .person(let person) = item { return .some(person.caption) }
      return nil
    }
    XCTAssertFalse(captions.isEmpty)
    XCTAssertTrue(captions.allSatisfy { $0 == nil }, "no \"Actor\" under an actor: \(captions)")
  }

  /// One director stands beside the cast; several would push it off the screen, so they
  /// are a row, and the cast is the row under it. The heading is over the first.
  func testSeveralDirectorsAreARowOfTheirOwnWithTheCastUnderIt() {
    let crew = DetailFixture.filmCrew
    let sections = MediaItemTVSections.make(.init(mediaItem: crew.makeItem(), metadata: crew.metadata,
                                                  preferredLanguages: ["ru"]))
    XCTAssertEqual(sections.map(\.id).prefix(3), ["ratings", "credits-directors", "credits-cast"])
    let directors = sections.first { $0.id == "credits-directors" }!
    let cast = sections.first { $0.id == "credits-cast" }!
    XCTAssertEqual(directors.title, "MediaItem_CastAndCrew".localized)
    XCTAssertNil(cast.title, "one heading for the block")
    XCTAssertEqual(directors.groups.map(\.id), ["directors"])
    XCTAssertEqual(cast.groups.map(\.id), ["cast"])
    XCTAssertEqual(directors.groups.map(\.isSubheading) + cast.groups.map(\.isSubheading), [true, true],
                   "the cast's title is as small as the directors'")
    XCTAssertEqual(directors.groups[0].items.count, 2)
  }

  func testACardNamesThePersonItStandsFor() {
    let credits = MediaItemTVSections.make(input()).first { $0.id == "credits" }!
    guard case .person(let director)? = credits.groups[0].items.first,
          case .person(let lead)? = credits.groups[1].items.first else { return XCTFail("no cards") }
    XCTAssertEqual(MediaItemTVSections.person(from: director)?.role, .director)
    XCTAssertEqual(MediaItemTVSections.person(from: director)?.name, "Дестин Дэниел Креттон")
    XCTAssertEqual(MediaItemTVSections.person(from: lead)?.role, .actor)
    XCTAssertEqual(MediaItemTVSections.person(from: lead)?.name, "Том Холланд")
  }

  /// Faces are for fiction (`showsCastPortraits`): a concert's people are text, in a
  /// Credits column of the table — not dropped, and not a rail of portraits.
  func testAConcertHasNoFacesButItsPeopleAreStillSaid() throws {
    let json: [String: Any] = [
      "id": 5, "type": "concert", "subtype": "", "title": "Концерт", "year": 2020,
      "cast": "Певец Один, Певица Два", "director": "Режиссёр Три",
      "genres": [Any](), "countries": [Any](), "duration": ["average": 5400, "total": 5400],
      "langs": 1, "quality": 1080, "plot": "", "posters": ["small": "", "medium": "", "big": "", "wide": ""],
      "finished": false
    ]
    let item = try JSONDecoder().decode(MediaItem.self, from: JSONSerialization.data(withJSONObject: json))
    let sections = MediaItemTVSections.make(.init(mediaItem: item))
    XCTAssertFalse(sections.contains { $0.id == "credits" })
    let specs = try XCTUnwrap(sections.first { $0.id == "specs" })
    let columns = specs.groups[0].items.compactMap { item -> TVPageInfoCard.Spec? in
      if case .info(.spec(let spec)) = item { return spec }
      return nil
    }
    XCTAssertEqual(columns.first?.id, "credits")
    XCTAssertTrue(columns.first?.rows.contains { $0.text.contains("Певец Один") } == true)
  }

  // MARK: - Ranking the cast

  private func member(_ name: String, order: Int? = nil, episodes: Int? = nil) -> CastMember {
    CastMember(name: name, department: "Acting", episodeCount: episodes, order: order)
  }

  /// A film: TMDB's billing order, kino.pub's own order for a tie and for a title TMDB
  /// knows nothing about.
  func testAFilmsCastIsRankedByBillingAndTheRestFallsToKinoPubsOrder() {
    let ranked = MediaItemTVSections.rankedCast(
      [member("bit", order: 40), member("lead", order: 0), member("second", order: 1), member("unknown")],
      isEpisodic: false)
    XCTAssertEqual(ranked.map(\.name), ["lead", "second", "bit", "unknown"])

    let unbilled = MediaItemTVSections.rankedCast([member("a"), member("b"), member("c")], isEpisodic: false)
    XCTAssertEqual(unbilled.map(\.name), ["a", "b", "c"], "no TMDB: kino.pub's order")
  }

  /// A series: by how many episodes a person is in; guests — under a fifth of the
  /// most-seen person's, and never fewer than two — are dropped.
  func testASeriesCastIsRankedByEpisodesAndGuestsAreDropped() {
    let ranked = MediaItemTVSections.rankedCast(
      [member("guest", episodes: 3), member("recurring", episodes: 30), member("lead", episodes: 100),
       member("nobody"), member("edge", episodes: 20), member("under", episodes: 19)],
      isEpisodic: true)
    XCTAssertEqual(ranked.map(\.name), ["lead", "recurring", "edge"],
                   "100 episodes make 20 the floor; unmatched and one-offs are out")

    let miniseries = MediaItemTVSections.rankedCast(
      [member("a", episodes: 6), member("b", episodes: 1), member("c", episodes: 2)], isEpisodic: true)
    XCTAssertEqual(miniseries.map(\.name), ["a", "c"], "never fewer than two episodes once anyone has more")

    let oneEpisodes = MediaItemTVSections.rankedCast(
      [member("a", episodes: 1), member("b", episodes: 1)], isEpisodic: true)
    XCTAssertEqual(oneEpisodes.count, 2, "everyone in one episode: nobody is a guest")
  }

  func testTheCastRowStopsAtAnArbitraryDozen() {
    let many = (0..<30).map { member("p\($0)", order: $0) }
    XCTAssertEqual(MediaItemTVSections.rankedCast(many, isEpisodic: false).count, MediaItemTVSections.castLimit)
    XCTAssertEqual(MediaItemTVSections.castLimit, 12)
  }

  /// The fixture's billing lists two bit parts first (kino.pub's order) and a third last.
  func testTheCrewFixtureShowsTheStarsFirstAndDropsTheBitParts() {
    let crew = DetailFixture.filmCrew
    let sections = MediaItemTVSections.make(.init(mediaItem: crew.makeItem(), metadata: crew.metadata,
                                                  preferredLanguages: ["ru"]))
    let cast = sections.first { $0.id == "credits-cast" }!.groups[0].items.compactMap { item -> String? in
      if case .person(let person) = item { return person.name }
      return nil
    }
    XCTAssertEqual(cast.count, 12)
    XCTAssertEqual(cast.first, "Крис Эванс")
    XCTAssertEqual(cast.prefix(3), ["Крис Эванс", "Роберт Дауни-мл.", "Скарлетт Йоханссон"])
    XCTAssertFalse(cast.contains { $0.hasPrefix("Эпизод") }, "bit parts are dropped, not just moved: \(cast)")
  }

  // MARK: - Facts

  func testASpoilerStaysHiddenUntilItIsAskedFor() {
    func facts(_ revealed: Set<String>) -> [TVPageInfoCard.Fact] {
      let strip = MediaItemTVSections.make(input { $0.revealedFacts = revealed })
        .first { $0.id == "stills-facts" }!
      return strip.groups.first { $0.id == "facts" }!.items.compactMap { item in
        if case .info(.fact(let fact)) = item { return fact }
        return nil
      }
    }
    XCTAssertEqual(facts([]).map(\.isHidden), [false, false, true, false])
    XCTAssertEqual(facts([MediaItemTVSections.factID(2)]).map(\.isHidden), [false, false, false, false])
  }

  func testAnAwardIsAFactCardAndNeverAWarning() {
    let strip = MediaItemTVSections.make(input()).first { $0.id == "stills-facts" }!
    let awards = strip.groups.first { $0.id == "awards" }!.items.compactMap { item -> TVPageInfoCard.Fact? in
      if case .info(.fact(let fact)) = item { return fact }
      return nil
    }
    XCTAssertEqual(awards.count, 2)
    XCTAssertTrue(awards.allSatisfy { !$0.isHidden })
    XCTAssertTrue(awards[1].text.hasPrefix("🏆"), "a won award is marked")
  }

  // MARK: - Tags

  func testEveryPillIsAWayIntoTheCatalogueNarrowedToIt() {
    let item = fixture.makeItem()
    let type = MediaItemTVSections.searchTarget(forChip: MediaItemTVSections.ID.tagType, in: item)
    XCTAssertEqual(type?.filter.contentType, .movie)
    let year = MediaItemTVSections.searchTarget(forChip: MediaItemTVSections.ID.tagYear, in: item)
    XCTAssertEqual(year?.filter.years, YearRange(from: 2026, to: 2026))
    XCTAssertEqual(year?.title, "2026")
    let country = MediaItemTVSections.searchTarget(forChip: "tag.country.1", in: item)
    XCTAssertEqual(country?.filter.countryID, 1)
    XCTAssertEqual(country?.title, "США", "the plain name — the pill's own title carries a flag")
    let genre = MediaItemTVSections.searchTarget(forChip: "tag.genre.4", in: item)
    XCTAssertEqual(genre?.filter.genreID, 4)
    XCTAssertEqual(genre?.title, "Фантастика")
    XCTAssertNil(MediaItemTVSections.searchTarget(forChip: "tag.subtype", in: item))
    XCTAssertNil(MediaItemTVSections.searchTarget(forChip: "tag.country.999", in: item))
  }

  /// A type wears an SF Symbol, not an emoji (Sasha, 2026-10-06); countries keep their flags.
  func testTheTypePillWearsASymbolAndNoEmoji() throws {
    let tags = try XCTUnwrap(MediaItemTVSections.make(input()).first { $0.id == "tags" })
    let type = try XCTUnwrap(tags.groups.first { $0.id == "type" })
    guard case .chip(let pill)? = type.items.first else { return XCTFail("no type pill") }
    XCTAssertEqual(pill.title, fixture.makeItem().contentTypeTitleKey.localized, "just the word")
    XCTAssertTrue(pill.title.unicodeScalars.allSatisfy { !$0.properties.isEmojiPresentation }, pill.title)
    XCTAssertEqual(pill.systemImage, "film")
    let countries = try XCTUnwrap(tags.groups.first { $0.id == "countries" })
    guard case .chip(let flagged)? = countries.items.first else { return XCTFail("no country pill") }
    XCTAssertTrue(flagged.title.hasPrefix("🇺🇸"))
    XCTAssertNil(flagged.systemImage)
  }

  /// Every kind of title has a mark, and every mark is a symbol the system has.
  func testEveryTypeHasASymbolTheSystemKnows() {
    for raw in TypeSymbol.known + ["something-new"] {
      let name = TypeSymbol.name(for: raw)
      XCTAssertNotNil(UIImage(systemName: name), "\(raw) → \(name) is not an SF Symbol")
    }
  }

  func testFlagsAndMarksComeFromTablesNotGuesses() {
    XCTAssertEqual(Emoji.flag(countryID: 1), "🇺🇸")
    XCTAssertEqual(Emoji.flag(countryID: 5), "🇬🇧")
    XCTAssertNil(Emoji.flag(countryID: 3), "the USSR has no flag emoji")
    XCTAssertEqual(Emoji.languageFlag("ru"), "🇷🇺")
    XCTAssertNil(Emoji.languageFlag("zz"))
    XCTAssertEqual(Emoji.decorated("🇺🇸", "США"), "🇺🇸 США")
    XCTAssertEqual(Emoji.decorated(nil, "США"), "США")
  }

  // MARK: - Specifications

  private func spec(_ id: String, _ configure: (inout MediaItemTVSections.Input) -> Void = { _ in })
  -> TVPageInfoCard.Spec? {
    let specs = MediaItemTVSections.make(input(configure)).first { $0.id == "specs" }!
    return specs.groups[0].items.compactMap { item -> TVPageInfoCard.Spec? in
      if case .info(.spec(let spec)) = item, spec.id == id { return spec }
      return nil
    }.first
  }

  func testVideoSaysHowLongAndHowBig() throws {
    let video = try XCTUnwrap(spec("video"))
    XCTAssertEqual(video.title, "MediaItem_SpecVideo".localized)
    let resolution = try XCTUnwrap(video.rows.first { $0.id == "resolution" })
    XCTAssertEqual(resolution.text, "3840×1600")
    XCTAssertEqual(resolution.badges, ["4K"])
    XCTAssertNotNil(video.rows.first { $0.id == "runtime" })
  }

  func testAudioKeepsTheViewersLanguagesOpenAndFoldsTheRest() throws {
    let audio = try XCTUnwrap(spec("audio"))
    let languages = audio.rows.filter { $0.style == .language }
    // The viewer reads Russian; English is the base the table always keeps.
    XCTAssertEqual(languages.map(\.text), [LanguageNames.name(for: "rus"), LanguageNames.name(for: "eng")])
    XCTAssertEqual(audio.rows.last?.style, .more)
    XCTAssertTrue(audio.rows.last?.text.contains("5") == true, audio.rows.last?.text ?? "")

    // The popup a column opens lists every one.
    let everything = try XCTUnwrap(spec("audio") { $0.showsEveryLanguage = true })
    XCTAssertEqual(everything.rows.filter { $0.style == .language }.count, 7)
    XCTAssertFalse(everything.rows.contains { $0.style == .more })
  }

  /// The dub's kind is its glyph: a checkmark for a studio dub, three heads for a
  /// multi-voice, two for a two-voice, one for a single voice.
  func testADubIsNamedByItsStudioAndShownByItsKind() throws {
    let audio = try XCTUnwrap(spec("audio"))
    let details = audio.rows.filter { $0.style == .detail }
    XCTAssertEqual(details.count, 4)
    XCTAssertEqual(details[0].text, "\(AudioTracks.localizedKindLabel(rank: 0) ?? ""): Мосфильм")
    XCTAssertEqual(details[0].leading, .symbol("checkmark"))
    XCTAssertEqual(details[1].text, "Кубик в Кубе, Пифагор")
    XCTAssertEqual(details[1].leading, .symbol("person.3.fill"))
    XCTAssertEqual(details[2].leading, .symbol("person.2.fill"))
    XCTAssertEqual(details[3].leading, .symbol("person.fill"))
  }

  func testSubtitlesMarkClosedCaptionsAndForcedTracks() throws {
    let subtitles = try XCTUnwrap(spec("subtitles") { $0.preferredLanguages = ["ru", "en"] })
    let russian = try XCTUnwrap(subtitles.rows.first { $0.id == "subtitles.ru" })
    XCTAssertEqual(russian.secondary, "Forced".localized)
    let english = try XCTUnwrap(subtitles.rows.first { $0.id == "subtitles.en" })
    XCTAssertEqual(english.badges, ["CC"])
  }

  func testEveryColumnOfTheTableIsAsTallAsTheTallest() throws {
    let section = try XCTUnwrap(MediaItemTVSections.make(input()).first { $0.id == "specs" })
    let plan = TVPageStripPlan(section: section, contentWidth: 1760, sideInset: 80)
    let heights = Set(plan.frames.map(\.height))
    XCTAssertEqual(heights.count, 1, "three columns of one table: one platter height — \(heights)")
  }
}
#endif
