//
//  MediaItemTVSectionsTests.swift
//  KinoPubAppleClientTests
//
//  What the tvOS detail page says under the hero, and in what order — one pure function,
//  `MediaItemTVSections.make`, over the `film` fixture (a film with every part populated).
//  Sasha's order of 2026-10-06:
//
//      Ratings (+ a count of reviews) · Cast & Crew (one row) · Similar (actors | director | genre) ·
//      Stills | Facts ·
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

  /// Similar, the lead's and the director's other work, a collection (which has a page of its
  /// own). The shelves overlap — two titles are both alike and the lead's, one is the lead's and
  /// the director's — as real ones do.
  private var cards: [MediaCard] { DetailFixture.similarItems().map(MediaCard.init) }

  private var rows: [MediaRow] {
    let cards = self.cards
    return [
      MediaRow(id: "similar", title: "Похожие", cards: Array(cards[0..<5])),
      MediaRow(id: "director-1", title: "Ещё от режиссёра", cards: Array(cards[5...])),
      MediaRow(id: "actor-7", title: "Ещё с Томом Холландом", cards: Array(cards[3..<7])),
      MediaRow(id: "collection-178", title: "22 фильма о криминальной России", cards: cards,
               destination: Route.detailsById(1))
    ]
  }

  private let authorGroup = MediaItemModel.RelatedPeopleGroup(title: "От этого режиссёра", isPending: false)
  private let castGroup = MediaItemModel.RelatedPeopleGroup(title: "Эти же актёры", isPending: false)

  private func input(_ configure: (inout MediaItemTVSections.Input) -> Void = { _ in })
  -> MediaItemTVSections.Input {
    var input = MediaItemTVSections.Input(mediaItem: fixture.makeItem(),
                                          metadata: fixture.metadata,
                                          likeCount: 145,
                                          dislikeCount: 19,
                                          relatedRows: rows,
                                          authorGroup: authorGroup,
                                          castGroup: castGroup,
                                          preferredLanguages: ["ru"])
    configure(&input)
    return input
  }

  private func groupIDs(_ section: TVPageSection) -> [String] { section.groups.map(\.id) }

  // MARK: - Order

  func testSectionsComeInTheOrderOfTheDesign() {
    let sections = MediaItemTVSections.make(input())
    XCTAssertEqual(sections.map(\.id),
                   ["ratings", "credits", "similar", "stills-facts",
                    "collection-178", "specs"])
  }

  func testRowsOfTwoAreOneStripOfTitledGroups() {
    let sections = MediaItemTVSections.make(input())
    func strip(_ id: String) -> TVPageSection { sections.first { $0.id == id }! }

    XCTAssertEqual(groupIDs(strip("ratings")), ["scores"], "the reviews are a card in the scores' row, not a group")
    XCTAssertEqual(groupIDs(strip("credits")), ["people"], "one row of people, no sections inside it")
    XCTAssertEqual(groupIDs(strip("similar")), ["cast", "director", "genres"])
    XCTAssertEqual(groupIDs(strip("stills-facts")), ["stills", "facts", "awards"])
    XCTAssertEqual(strip("ratings").kind, .strip)
    // The three columns of the technical table are one untitled group — no title strip.
    XCTAssertEqual(groupIDs(strip("specs")), ["specs"])
    XCTAssertNil(strip("specs").groups[0].title)
  }

  /// One heading over three groups of posters, the way Cast & Crew is one over its professions
  /// (Sasha, 2026-10-11): the same actors, this director, then alike by genre — Home's poster,
  /// six across, with Home's own caption (none) — and the collections stay rows of their own
  /// below the tags.
  func testSimilarIsOneHeadingOverThreeGroupsOfPosters() throws {
    let sections = MediaItemTVSections.make(input())
    let similar = try XCTUnwrap(sections.first { $0.id == "similar" })
    XCTAssertEqual(similar.kind, .strip)
    XCTAssertEqual(similar.title, "Similar".localized)
    XCTAssertEqual(similar.groups.map(\.title), ["Эти же актёры", "От этого режиссёра",
                                                  "Фантастика, боевик, приключения"])
    for group in similar.groups {
      XCTAssertEqual(group.cell, .poster, "\(group.id): Home's poster")
      XCTAssertEqual(group.columns, 6, "\(group.id): six across, like every shelf")
      XCTAssertTrue(group.isSubheading, "\(group.id): under a heading of its own")
      XCTAssertTrue(group.items.allSatisfy { if case .card = $0 { return true } else { return false } },
                    "\(group.id): a group ends in its last cover — no See all tile")
    }
    let ids = sections.map(\.id)
    XCTAssertLessThan(ids.firstIndex(of: "credits")!, ids.firstIndex(of: "similar")!)
    XCTAssertLessThan(ids.firstIndex(of: "similar")!, ids.firstIndex(of: "stills-facts")!)
    XCTAssertLessThan(ids.firstIndex(of: "stills-facts")!, ids.firstIndex(of: "collection-178")!)
    XCTAssertFalse(ids.contains("tags"), "the strip of type, country and genre pills is gone")
    XCTAssertLessThan(ids.firstIndex(of: "collection-178")!, ids.firstIndex(of: "specs")!)
    XCTAssertFalse(ids.contains("director-1") || ids.contains("actor-7"), "the people's shelves are groups now")
  }

  /// A title shows once, under the first group that has it: actors, then the director, then genre.
  func testATitleOnTwoShelvesIsUnderTheFirstGroupThatHasIt() throws {
    let similar = try XCTUnwrap(MediaItemTVSections.make(input()).first { $0.id == "similar" })
    func ids(_ group: String) -> [Int] {
      similar.groups.first { $0.id == group }!.items.compactMap { $0.card?.id }
    }
    let all = cards.map(\.id)
    XCTAssertEqual(ids("cast"), Array(all[3..<7]))
    XCTAssertEqual(ids("director"), [all[7]], "the director's, less what the actors already hold")
    XCTAssertEqual(ids("genres"), Array(all[0..<3]), "alike, less what the actors hold")
    let every = ids("cast") + ids("director") + ids("genres")
    XCTAssertEqual(Set(every).count, every.count, "no title twice in one row")
    // The same title in two groups is still two distinct items, should a page ever ask for it.
    XCTAssertEqual(Set((0..<similar.items.count).map(similar.itemID(at:))).count, similar.items.count)
  }

  /// Ten covers at most in a group (Sasha, 2026-10-11) — and each group takes its ten from what
  /// the groups before it left, so a long shelf never starves the next.
  func testAGroupHoldsTenCoversAtMostAndTakesThemFromWhatIsLeft() throws {
    func shelf(_ id: String, _ range: Range<Int>) -> MediaRow {
      MediaRow(id: id, title: id, cards: range.map {
        MediaCard(DetailFixture.posterItem(id: 7_000 + $0, title: "T\($0)", year: 2020, seed: $0))
      })
    }
    let similar = try XCTUnwrap(MediaItemTVSections.make(input {
      $0.relatedRows = [shelf("actor-1", 0..<14), shelf("director-1", 5..<30), shelf("similar", 0..<40)]
    }).first { $0.id == "similar" })
    func ids(_ group: String) -> [Int] {
      similar.groups.first { $0.id == group }!.items.compactMap { $0.card?.id }.map { $0 - 7_000 }
    }
    XCTAssertEqual(ids("cast"), Array(0..<10))
    XCTAssertEqual(ids("director"), Array(10..<20), "5…9 are the actors', so the director's ten start at 10")
    XCTAssertEqual(ids("genres"), Array(20..<30))
    XCTAssertEqual(MediaItemTVSections.similarLimit, 10)
  }

  /// A group is absent once its shelf has come back empty, and the row with it when none is left.
  func testAnEmptyShelfLeavesItsGroupAndAnEmptyRowLeavesTheSection() {
    let withoutPeople = MediaItemTVSections.make(input {
      $0.relatedRows = $0.relatedRows.filter { $0.id == "similar" || $0.id == "collection-178" }
    })
    XCTAssertEqual(withoutPeople.first { $0.id == "similar" }?.groups.map(\.id), ["genres"])

    let none = MediaItemTVSections.make(input { $0.relatedRows = [] })
    XCTAssertNil(none.first { $0.id == "similar" })
  }

  /// With no Similar the genre floor takes its place — and says which genres it asked for.
  func testTheGenreFloorStandsInForSimilar() throws {
    let sections = MediaItemTVSections.make(input {
      $0.relatedRows = [MediaRow(id: "genre-4-8", title: "Ещё: фантастика · приключения", cards: cards)]
    })
    let similar = try XCTUnwrap(sections.first { $0.id == "similar" })
    XCTAssertEqual(similar.groups.map(\.id), ["genres"])
    XCTAssertEqual(similar.groups[0].title, "Фантастика, приключения")
    XCTAssertNil(sections.first { $0.id == "genre-4-8" }, "it is not a row of its own as well")
  }

  /// Every shelf that is not Similar's is covers and nothing else: no "See all" tile
  /// (Sasha, 2026-10-06 — it named itself on focus, and the footer that allowed gave the covers
  /// beside it a height of their own).
  func testACollectionIsCoversOnlyWithNoSeeAllTile() throws {
    let shelf = try XCTUnwrap(MediaItemTVSections.make(input()).first { $0.id == "collection-178" })
    XCTAssertEqual(shelf.caption, .never, "Home's own caption: none")
    XCTAssertTrue(shelf.items.allSatisfy { if case .card = $0 { return true } else { return false } },
                  "a shelf ends in its last cover")
  }

  // MARK: - Absent parts

  func testEmptyPartsAreSimplyAbsent() {
    let sections = MediaItemTVSections.make(input {
      $0.metadata = TitleMetadata()
      $0.relatedRows = []
    })
    let ids = sections.map(\.id)
    XCTAssertEqual(ids, ["ratings", "credits", "specs"],
                   "no similar, no stills or facts, no other shelves")
    XCTAssertEqual(groupIDs(sections[0]), ["scores"])
    XCTAssertFalse(sections[0].items.contains { if case .info(.reviews) = $0 { return true } else { return false } },
                   "no reviews, so nothing to count")
    XCTAssertEqual(groupIDs(sections[1]), ["people"], "kino.pub's own credits need no metadata")
  }

  /// A person's shelf still in flight holds its group as skeleton posters under its own words,
  /// so the row does not jump when it lands — and two of them at once are two distinct runs.
  func testShelvesStillInFlightHoldTheirPlaceAsSkeletonPosters() throws {
    let sections = MediaItemTVSections.make(input {
      $0.relatedRows = []
      $0.authorGroup = .init(title: "От этого режиссёра", isPending: true)
      $0.castGroup = .init(title: "Эти же актёры", isPending: true)
    })
    let similar = try XCTUnwrap(sections.first { $0.id == "similar" })
    XCTAssertEqual(similar.groups.map(\.id), ["cast", "director"])
    XCTAssertEqual(similar.groups.map(\.title), ["Эти же актёры", "От этого режиссёра"])
    XCTAssertTrue(similar.groups.allSatisfy { $0.cell == .poster && $0.items.count == 6 })
    XCTAssertTrue(similar.items.allSatisfy {
      switch $0 {
      case .placeholder, .groupTitle: return true
      default: return false
      }
    })
    XCTAssertEqual(Set((0..<similar.items.count).map(similar.itemID(at:))).count, similar.items.count,
                   "both groups hold placeholder 0…5: the group tells them apart")
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
  }

  /// Kinopoisk counts voters long before it prints a number: the card has no number — it
  /// draws a dash, which is the cell's — and still says how many voted.
  func testASourceWithVotersButNoScoreHasNoNumberAndSaysHowManyVoted() {
    let score = RatingSources.Score(id: "Кинопоиск", logo: .kinopoisk, value: nil, votes: 44,
                                    display: "—", url: nil)
    let rating = MediaItemTVSections.rating(score, input())
    XCTAssertNil(rating.value)
    XCTAssertTrue(rating.caption?.hasPrefix("44") == true, "the voters are written out: \(rating.caption ?? "nil")")
    XCTAssertNil(rating.thumbs)

    let rated = RatingSources.Score(id: "IMDb", logo: .imdb, value: 6.5, votes: 1567, display: "6.5", url: nil)
    XCTAssertEqual(MediaItemTVSections.rating(rated, input()).value, "6.5")
  }

  /// A score has two lines to say; it is not as tall as a review's card beside it.
  func testAScoreCardIsLowerThanTheCardsBesideIt() {
    let rating = TVPageInfoCard.rating(.init(id: "IMDb", source: .imdb, title: "IMDb", value: "6.5", caption: "1 567"))
    let review = TVPageInfoCard.review(.init(id: "0", headline: "h", body: "b", sentiment: nil, tone: .neutral, date: nil))
    XCTAssertLessThan(rating.height(forWidth: 256), review.height(forWidth: 256))
    XCTAssertEqual(review.height(forWidth: 256), TVPageLayout.infoCardHeight)
  }

  /// The reviews' words are not on the detail page (Sasha, 2026-10-11): the scores' row ends in a
  /// card that counts them and says how they were meant — the source's total, with its three tones.
  func testTheScoresRowEndsInACardThatCountsTheReviews() throws {
    let ratings = try XCTUnwrap(MediaItemTVSections.make(input()).first { $0.id == "ratings" })
    guard case .info(.reviews(let card))? = ratings.items.last else { return XCTFail("no count card at the end") }
    XCTAssertEqual(card.count, "11", "the source's total, from the summary")
    XCTAssertEqual(card.tones, .init(positive: "7", negative: "1", neutral: "3"))
    XCTAssertEqual(card.title, "Reviews".localized)
    XCTAssertTrue(card.accessibilityLabel.contains("11"))
    // No review card — no text of one — anywhere on the page.
    let page = MediaItemTVSections.make(input())
    XCTAssertFalse(page.flatMap(\.items).contains { if case .info(.review) = $0 { return true } else { return false } })
  }

  func testWithNoSummaryTheCountIsWhatWeHold() throws {
    let card = try XCTUnwrap(MediaItemTVSections.reviewsCard(input { $0.metadata.reviewsSummary = nil }))
    XCTAssertEqual(card.count, "3")
    XCTAssertEqual(card.tones, .init(positive: "1", negative: "1", neutral: "1"), "tallied from the reviews' own tones")
    XCTAssertNil(MediaItemTVSections.reviewsCard(input {
      $0.metadata.reviewsSummary = nil
      $0.metadata.reviews = []
    }), "nothing to count, no card")
  }

  /// A review is a card on the page of their own — a headline, or the author when there is none.
  func testAReviewWithNoHeadlineIsTitledByItsAuthor() {
    let reviews = fixture.metadata.reviews.enumerated().map { MediaItemTVSections.review($1, index: $0) }
    XCTAssertEqual(reviews.count, 3)
    XCTAssertEqual(reviews[0].headline, "Крепкое возвращение")
    XCTAssertEqual(reviews[1].headline, "Lintandil", "no headline: the author stands in")
    XCTAssertEqual(reviews.map(\.tone), [.positive, .neutral, .negative])
  }

  // MARK: - People

  private func people(_ section: TVPageSection) -> [TVUIKitPerson] {
    section.groups.flatMap(\.items).compactMap { item in
      if case .person(let person) = item { return person }
      return nil
    }
  }

  /// A film's director opens the row, then the cast: search's person cards, three across, with
  /// what each is to the title under the name (Sasha, 2026-10-11).
  func testADirectorOpensAFilmsRowThenTheCast() {
    let credits = MediaItemTVSections.make(input()).first { $0.id == "credits" }!
    XCTAssertEqual(credits.groups[0].columns, 3, "the wide card search draws, three across")
    let row = people(credits)
    XCTAssertEqual(row.first?.name, "Дестин Дэниел Креттон")
    XCTAssertEqual(row.first?.caption, "Director".localized, "the role is the card's own subtitle")
    XCTAssertEqual(row.dropFirst().first?.name, "Том Холланд")
    XCTAssertEqual(row.dropFirst().first?.caption, "Питер Паркер", "the character, from TMDB")
  }

  /// "Cast & Crew" over one row — no subheadings inside it.
  func testCastAndCrewIsOneHeadingOverOneRowOfPeople() {
    let credits = MediaItemTVSections.make(input()).first { $0.id == "credits" }!
    XCTAssertEqual(credits.title, "MediaItem_CastAndCrew".localized)
    XCTAssertEqual(credits.groups.count, 1)
    XCTAssertNil(credits.groups[0].title, "no section inside the row")
    XCTAssertEqual(credits.kind, .strip)
    // The other rows' groups are the rows' own titles.
    let ratings = MediaItemTVSections.make(input()).first { $0.id == "ratings" }!
    XCTAssertEqual(ratings.groups.map(\.isSubheading), [false, false])
  }

  func testAnActorWithNoCharacterHasNoCaptionAtAll() {
    let credits = MediaItemTVSections.make(input {
      $0.metadata = TitleMetadata()
    }).first { $0.id == "credits" }!
    let actors = people(credits).filter { MediaItemTVSections.person(from: $0)?.role == .actor }
    XCTAssertFalse(actors.isEmpty)
    XCTAssertTrue(actors.allSatisfy { $0.caption == nil }, "no \"Actor\" under an actor: \(actors.map(\.caption))")
  }

  /// Several directors are still one row with the cast — a row of their own would push the cast off.
  func testSeveralDirectorsShareTheOneRowWithTheCast() {
    let crew = DetailFixture.filmCrew
    let sections = MediaItemTVSections.make(.init(mediaItem: crew.makeItem(), metadata: crew.metadata,
                                                  preferredLanguages: ["ru"]))
    XCTAssertEqual(sections.map(\.id).prefix(2), ["ratings", "credits"])
    let row = people(sections.first { $0.id == "credits" }!)
    XCTAssertEqual(row.prefix(2).map(\.caption), ["Director".localized, "Director".localized])
    XCTAssertEqual(row.prefix(2).map(\.name), ["Энтони Руссо", "Джо Руссо"])
  }

  /// A show's creators close the row, behind the actors, however many there are (Sasha,
  /// 2026-10-11) — and what they are to it is their subtitle.
  func testAShowsCreatorsClosTheRowBehindTheActors() throws {
    let json: [String: Any] = [
      "id": 8, "type": "serial", "subtype": "", "title": "Декстер", "year": 2006,
      "cast": "Майкл К. Холл, Дженнифер Карпентер", "director": "Джеймс Манос-мл., Клайд Филлипс",
      "genres": [Any](), "countries": [Any](), "duration": ["average": 3000, "total": 100_000],
      "langs": 1, "quality": 1080, "plot": "", "posters": ["small": "", "medium": "", "big": "", "wide": ""],
      "finished": true
    ]
    let item = try JSONDecoder().decode(MediaItem.self, from: JSONSerialization.data(withJSONObject: json))
    XCTAssertEqual(item.presentation.authorRole, .creator)
    let sections = MediaItemTVSections.make(.init(mediaItem: item))
    XCTAssertEqual(sections.filter { $0.id.hasPrefix("credits") }.map(\.id), ["credits"], "never a row of their own")
    let row = people(try XCTUnwrap(sections.first { $0.id == "credits" }))
    XCTAssertEqual(row.map(\.name), ["Майкл К. Холл", "Дженнифер Карпентер", "Джеймс Манос-мл.", "Клайд Филлипс"])
    XCTAssertEqual(row.suffix(2).map(\.caption), ["MediaItem_CreatorRole".localized, "MediaItem_CreatorRole".localized])
  }

  /// kino.pub listed the same actor twice (126967). The snapshot cannot.
  func testARepeatedNameInTheCreditsIsOneCard() throws {
    let json: [String: Any] = [
      "id": 126967, "type": "movie", "subtype": "", "title": "T", "year": 2020,
      "cast": "Валид Зуэйтер, Валид Зуэйтер, Том Холланд",
      "director": "Режиссёр",
      "genres": [Any](), "countries": [Any](), "duration": ["total": 6000],
      "langs": 1, "quality": 1080, "plot": "", "posters": ["small": "", "medium": "", "big": "", "wide": ""]
    ]
    let item = try JSONDecoder().decode(MediaItem.self, from: JSONSerialization.data(withJSONObject: json))
    let credits = try XCTUnwrap(MediaItemTVSections.make(.init(mediaItem: item)).first { $0.id == "credits" })
    let names = people(credits).compactMap { MediaItemTVSections.person(from: $0) }.filter { $0.role == .actor }.map(\.name)
    XCTAssertEqual(names.filter { $0 == "Валид Зуэйтер" }.count, 1)
    XCTAssertEqual(Set((0..<credits.items.count).map(credits.itemID(at:))).count, credits.items.count)
  }

  func testAPersonCardIdPrefersTMDBWhenItHasOne() {
    let named = MediaPerson(name: "Валид Зуэйтер", role: .actor)
    let numbered = MediaPerson(name: "Валид Зуэйтер", role: .actor, tmdbPersonId: 77)
    XCTAssertEqual(MediaItemTVSections.cardID(for: named), "actor:Валид Зуэйтер")
    XCTAssertEqual(MediaItemTVSections.cardID(for: numbered), "actor.tmdb.77")
    XCTAssertNotEqual(MediaItemTVSections.cardID(for: named), MediaItemTVSections.cardID(for: numbered))
    let card = TVUIKitPerson(id: MediaItemTVSections.cardID(for: numbered),
                             name: numbered.name,
                             nameComponents: TVUIKitPerson.nameComponents(from: numbered.name),
                             caption: nil, photoURL: nil)
    XCTAssertEqual(MediaItemTVSections.person(from: card)?.role, .actor)
    XCTAssertEqual(MediaItemTVSections.person(from: card)?.name, "Валид Зуэйтер")
  }

  func testACardNamesThePersonItStandsFor() {
    let credits = MediaItemTVSections.make(input()).first { $0.id == "credits" }!
    let row = people(credits)
    XCTAssertEqual(MediaItemTVSections.person(from: row[0])?.role, .director)
    XCTAssertEqual(MediaItemTVSections.person(from: row[0])?.name, "Дестин Дэниел Креттон")
    XCTAssertEqual(MediaItemTVSections.person(from: row[1])?.role, .actor)
    XCTAssertEqual(MediaItemTVSections.person(from: row[1])?.name, "Том Холланд")
  }

  /// A card of a section, by its id.
  private func specs(in section: TVPageSection) -> [TVPageInfoCard.Spec] {
    section.groups.flatMap(\.items).compactMap { item in
      if case .info(.spec(let spec)) = item { return spec }
      return nil
    }
  }

  /// Faces are for fiction (`showsCastPortraits`): a concert's, an anime's people are text, **under
  /// the table with the audio and the subtitles, with no heading** (Sasha, 2026-10-11) — three
  /// columns: whoever made it first, the cast second, the third not yet used — and not up where the
  /// portraits are, and not in the table's third column.
  func testAConcertHasNoFacesButItsPeopleAreTextUnderTheTable() throws {
    let item = try concert(cast: "Певец Один, Певица Два", director: "Режиссёр Три")
    let sections = MediaItemTVSections.make(.init(mediaItem: item))
    XCTAssertEqual(sections.map(\.id).suffix(2), ["specs", "credits"], "last, under the table")
    XCTAssertNotEqual(sections.map(\.id).first, "credits", "not up with the portraits")
    let credits = try XCTUnwrap(sections.last)
    XCTAssertNil(credits.title, "no Cast & Crew heading")
    XCTAssertEqual(groupIDs(credits), ["authors", "cast"], "creators first, the cast second")
    XCTAssertTrue(credits.groups.allSatisfy { $0.stacked && $0.columns == 3 }, "three columns; the third is left empty")
    XCTAssertFalse(credits.items.contains { if case .person = $0 { return true } else { return false } }, "no portraits")
    let cards = specs(in: credits)
    XCTAssertEqual(cards.map(\.id), ["authors", "cast", "cast.expand"])
    XCTAssertEqual(cards[0].rows.last?.text, "Режиссёр\u{00A0}Три")
    XCTAssertEqual(cards[1].rows.last?.text, "Певец\u{00A0}Один, Певица\u{00A0}Два", "every name, none of them split")

    // And the table has none of it.
    let table = try XCTUnwrap(sections.first { $0.id == "specs" })
    let rowIDs = specs(in: table).flatMap { $0.rows.map(\.id) }
    XCTAssertFalse(rowIDs.contains("author") || rowIDs.contains("cast"), "the people are not in the information column")
  }

  /// A fiction title has portraits and no text credits at the bottom.
  func testAFilmHasNoTextCreditsUnderItsTable() {
    let sections = MediaItemTVSections.make(input())
    XCTAssertEqual(sections.last?.id, "specs")
    XCTAssertEqual(sections.filter { $0.id == "credits" }.count, 1, "the portraits, near the top")
  }

  /// The cast card shows its first names, every one whole — and **always** has the *Развернуть* link
  /// under it, however short the cast (Sasha, 2026-10-11): the one focus stop of the section, which
  /// opens everyone kino.pub lists, a row to a name.
  func testTheCastCardAlwaysHasAnExpandLinkThatOpensEveryone() throws {
    let names = (1...15).map { "Имя Фамилия\($0)" }
    let item = try concert(cast: names.joined(separator: ", "), director: "")
    let credits = try XCTUnwrap(MediaItemTVSections.make(.init(mediaItem: item)).last)
    XCTAssertEqual(groupIDs(credits), ["cast"], "no creators, no column for them")
    let cards = specs(in: credits)
    XCTAssertEqual(cards.map(\.id), ["cast", "cast.expand"])
    XCTAssertEqual(cards[0].rows.last?.text.components(separatedBy: ", ").count, MediaItemTVSections.creditsPreview)
    XCTAssertEqual(cards[1].rows.map(\.style), [.more])
    XCTAssertEqual(cards[1].rows.map(\.text), ["MediaItem_Expand".localized])
    XCTAssertTrue(cards[1].opensInPopup)
    XCTAssertFalse(cards[0].opensInPopup, "names that are only read take no focus")

    var full = MediaItemTVSections.Input(mediaItem: item)
    full.showsEveryLanguage = true
    let everything = specs(in: try XCTUnwrap(MediaItemTVSections.creditsAsText(full).first)).last
    XCTAssertEqual(everything?.rows.map(\.text), names, "every name, a row each")

    // A short cast has the link too.
    let short = try concert(cast: "Один, Два", director: "")
    let shortCredits = try XCTUnwrap(MediaItemTVSections.make(.init(mediaItem: short)).last)
    XCTAssertEqual(specs(in: shortCredits).map(\.id), ["cast", "cast.expand"])
  }

  private func concert(cast: String, director: String) throws -> MediaItem {
    let json: [String: Any] = [
      "id": 5, "type": "concert", "subtype": "", "title": "Концерт", "year": 2020,
      "cast": cast, "director": director,
      "genres": [Any](), "countries": [Any](), "duration": ["average": 5400, "total": 5400],
      "langs": 1, "quality": 1080, "plot": "", "posters": ["small": "", "medium": "", "big": "", "wide": ""],
      "finished": false
    ]
    return try JSONDecoder().decode(MediaItem.self, from: JSONSerialization.data(withJSONObject: json))
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

  /// The first of kino.pub's own list is the lead and is never dropped (Sasha, 2026-10-11): a name
  /// TMDB could not match has no episode count, and used to be sent away as a guest.
  func testTheFirstOfKinoPubsListIsNeverDropped() {
    let series = MediaItemTVSections.rankedCast(
      [member("lead"), member("a", episodes: 100), member("b", episodes: 80)], isEpisodic: true)
    XCTAssertEqual(series.map(\.name), ["lead", "a", "b"], "unmatched, so below every floor — and still first")

    let nobody = MediaItemTVSections.rankedCast(
      [member("lead", episodes: 1), member("a", episodes: 100)], isEpisodic: true)
    XCTAssertEqual(nobody.first?.name, "a", "one episode of a hundred is a guest, but the lead of kino.pub's list keeps their place")
    XCTAssertTrue(nobody.contains { $0.name == "lead" })

    let film = MediaItemTVSections.rankedCast(
      (0..<30).map { member("p\($0)", order: $0 == 0 ? 99 : $0) }, isEpisodic: false)
    XCTAssertEqual(film.count, MediaItemTVSections.castLimit)
    XCTAssertTrue(film.contains { $0.name == "p0" }, "past the cap by billing, and still in")
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
    let cast = people(sections.first { $0.id == "credits" }!)
      .filter { MediaItemTVSections.person(from: $0)?.role == .actor }.map(\.name)
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
    // The spoiler (third in kino.pub's list) goes to the end: facts without one first.
    XCTAssertEqual(facts([]).map(\.isHidden), [false, false, false, true])
    XCTAssertEqual(facts([]).last?.id, MediaItemTVSections.factID(2), "its id is its place in the list, not the row")
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

  // MARK: - Specifications

  private func table(_ configure: (inout MediaItemTVSections.Input) -> Void = { _ in }) -> TVPageSection {
    MediaItemTVSections.make(input(configure)).first { $0.id == "specs" }!
  }

  private func spec(_ id: String, _ configure: (inout MediaItemTVSections.Input) -> Void = { _ in })
  -> TVPageInfoCard.Spec? {
    specs(in: table(configure)).first { $0.id == id }
  }

  /// The table is three columns at most, always, a gutter apart and sharing the width equally —
  /// each a stack of cards, one to an item, so focus goes from item to item (Sasha, 2026-10-11).
  func testTheTableIsThreeStackedColumnsOfCardsThatShareTheWidthEqually() throws {
    let section = table()
    XCTAssertEqual(groupIDs(section), ["languages", "video", "info"])
    XCTAssertTrue(section.groups.allSatisfy { $0.stacked && $0.columns == 3 && $0.title == nil })
    XCTAssertEqual(specs(in: section).map(\.id),
                   ["audio", "subtitles", "resolution", "runtime", "type", "year", "genres", "countries"],
                   "audio and subtitles each a card; the resolution and the runtime each; every item of the third")

    let plan = TVPageStripPlan(section: section, contentWidth: 1760, sideInset: 80)
    let art = TVPageStripPlan.cardWidth(columns: 3, contentWidth: 1760, share: 3)
    XCTAssertEqual(art, 557)
    XCTAssertEqual(art * 3 + TVHIGGrid.gutter * 2, 1760, accuracy: 3, "edge to edge, less two gutters")
    XCTAssertEqual(Set(plan.frames.map(\.width)).count, 1, "one width for every card")

    // One column: every card of a group at one x, one under the next. Columns a gutter apart.
    let languages = Array(plan.frames[0..<2]), video = Array(plan.frames[2..<4])
    XCTAssertEqual(languages[0].minX, languages[1].minX)
    XCTAssertLessThan(languages[0].maxY, languages[1].maxY)
    XCTAssertEqual(video[0].minX - languages[0].minX, art + TVHIGGrid.gutter, accuracy: 1,
                   "twice the air two cards of a row have")
  }

  /// A column that is missing leaves the others their width — never a fourth, never a stretched one.
  func testAMissingColumnLeavesItsWidthEmpty() {
    XCTAssertEqual(TVPageStripPlan.cardWidth(columns: 3, contentWidth: 1760, share: 3), 557)
    XCTAssertEqual(TVPageStripPlan.cardWidth(columns: 3, contentWidth: 1760, share: 2), 858)
  }

  func testVideoSaysHowBigThenHowLong() throws {
    let video = try XCTUnwrap(table().groups.first { $0.id == "video" })
    let cards = video.items.compactMap { item -> TVPageInfoCard.Spec? in
      if case .info(.spec(let spec)) = item { return spec }
      return nil
    }
    XCTAssertEqual(cards.map(\.id).prefix(2), ["resolution", "runtime"], "the picture first, then how long it runs")
    XCTAssertTrue(cards.allSatisfy { !$0.showsHeader }, "no Video header")
    let resolution = try XCTUnwrap(cards[0].rows.first { $0.id == "resolution" })
    XCTAssertEqual(resolution.text, "3840×1600")
    XCTAssertEqual(resolution.badges, ["4K"])
  }

  func testAudioKeepsTheViewersLanguagesOpenAndFoldsTheRest() throws {
    let audio = try XCTUnwrap(spec("audio")).rows
    let languages = audio.filter { $0.style == .language }
    // The viewer reads Russian; English is the base the table always keeps.
    XCTAssertEqual(languages.map(\.text), [LanguageNames.name(for: "rus"), LanguageNames.name(for: "eng")])
    XCTAssertTrue(languages.allSatisfy { $0.leading == nil }, "no flags on languages")
    XCTAssertEqual(audio.last?.style, .more)
    XCTAssertEqual(audio.last?.text, String(format: "MediaItem_SpecMore".localized, "5"), "+ ещё 5, no glyph")

    // The popup a card opens lists every one.
    let everything = try XCTUnwrap(spec("audio") { $0.showsEveryLanguage = true }).rows
    XCTAssertEqual(everything.filter { $0.style == .language }.count, 7)
    XCTAssertFalse(everything.contains { $0.style == .more })
    XCTAssertTrue(try XCTUnwrap(spec("audio")).opensInPopup)
    XCTAssertTrue(try XCTUnwrap(spec("subtitles")).opensInPopup)
    XCTAssertEqual(try XCTUnwrap(spec("audio")).title, "Audio".localized)
    XCTAssertTrue(try XCTUnwrap(spec("audio")).showsHeader)
  }

  /// A dub is said in words, no glyph (Sasha, 2026-10-11): its kind and every studio, all of them.
  func testADubIsNamedByItsKindAndItsStudiosInWords() throws {
    let details = try XCTUnwrap(spec("audio")).rows.filter { $0.style == .detail }
    XCTAssertEqual(details.count, 4)
    XCTAssertTrue(details.allSatisfy { $0.leading == nil }, "no icon on a category of dub")
    XCTAssertEqual(details[0].text, "\(AudioTracks.localizedKindLabel(rank: 0) ?? ""): Мосфильм")
    XCTAssertEqual(details[1].text, "\(AudioTracks.localizedKindLabel(rank: 1) ?? ""): Кубик\u{00A0}в\u{00A0}Кубе, Пифагор",
                   "every studio, each whole")
    XCTAssertTrue(details.allSatisfy { TVPageSpecRowView.wraps($0) }, "a long list of studios wraps and is never cut")
  }

  /// The languages of the subtitles are one line, two spaces apart (Sasha, 2026-10-11); a note on a
  /// track is in brackets; what is folded away is "+ ещё N".
  func testSubtitlesAreOneLineOfLanguagesTwoSpacesApart() throws {
    let subtitles = try XCTUnwrap(spec("subtitles") { $0.preferredLanguages = ["ru", "en"] }).rows
    let line = try XCTUnwrap(subtitles.first { $0.id == "subtitles.languages" })
    XCTAssertEqual(line.style, .value)
    XCTAssertTrue(line.text.contains("  "), "two spaces between languages: \(line.text)")
    XCTAssertTrue(line.text.contains("(CC)"), "a hard-of-hearing track says so: \(line.text)")
    XCTAssertTrue(line.text.contains("Forced".localized))
    XCTAssertEqual(subtitles.filter { $0.style == .language }.count, 0, "not a row to a language")
    if let more = subtitles.first(where: { $0.style == .more }) {
      XCTAssertTrue(more.text.contains { $0.isNumber }, "a count, and no glyph: \(more.text)")
    }
  }

  /// A title that reports no audio or no subtitles still says so, in a card of its own.
  func testAudioAndSubtitlesSayTheyAreNoneWhenTheTitleReportsNone() throws {
    let item = try concert(cast: "", director: "")
    let table = try XCTUnwrap(MediaItemTVSections.make(.init(mediaItem: item)).first { $0.id == "specs" })
    let cards = specs(in: table)
    XCTAssertEqual(try XCTUnwrap(cards.first { $0.id == "audio" }).rows.map(\.text), ["MediaItem_SpecNoAudio".localized])
    XCTAssertEqual(try XCTUnwrap(cards.first { $0.id == "subtitles" }).rows.map(\.text),
                   ["MediaItem_SpecNoSubtitles".localized])
  }

  /// What the title is, a card to each item: type, year, genres, countries — words that wrap, no
  /// header, and no emoji on a genre.
  func testTheThirdColumnSaysWhatTheTitleIsAnItemToACard() throws {
    let cards = specs(in: table()).filter { ["type", "year", "genres", "countries"].contains($0.id) }
    XCTAssertEqual(cards.map(\.id), ["type", "year", "genres", "countries"])
    XCTAssertTrue(cards.allSatisfy { !$0.showsHeader && !$0.opensInPopup }, "focusable, and Select does nothing")
    func value(_ id: String) -> String? { cards.first { $0.id == id }?.rows.last?.text }
    func caption(_ id: String) -> String? { cards.first { $0.id == id }?.rows.first?.text }
    XCTAssertEqual(value("type"), fixture.makeItem().contentTypeTitleKey.localized)
    XCTAssertEqual(value("year"), "2026")
    XCTAssertTrue(value("genres")?.contains("Фантастика") == true)
    XCTAssertTrue(value("genres")?.unicodeScalars.allSatisfy { !$0.properties.isEmojiPresentation } == true,
                  "genres are words: \(value("genres") ?? "")")
    XCTAssertTrue(value("countries")?.contains("США") == true)
    XCTAssertTrue(value("countries")?.unicodeScalars.allSatisfy { !$0.properties.isEmojiPresentation } == true,
                  "no flags: \(value("countries") ?? "")")
    XCTAssertTrue(cards.flatMap(\.rows).filter { $0.style == .value }.allSatisfy { TVPageSpecRowView.wraps($0) },
                  "words that wrap onto as many lines as they need")
    // Several of each: the plural label.
    XCTAssertEqual(caption("genres"), "MediaItem_TagGenres".localized)
    XCTAssertEqual(caption("countries"), "MediaItem_TagCountries".localized)
  }

  /// The label is singular for one genre or country and plural for several.
  func testGenreAndCountryLabelsFollowTheirNumber() throws {
    let json: [String: Any] = [
      "id": 9, "type": "movie", "subtype": "", "title": "Один", "year": 2020, "cast": "", "director": "",
      "genres": [["id": 4, "title": "Фантастика"]], "countries": [["id": 1, "title": "США"]],
      "duration": ["average": 5400, "total": 5400], "langs": 1, "quality": 1080, "plot": "",
      "posters": ["small": "", "medium": "", "big": "", "wide": ""], "finished": false
    ]
    let item = try JSONDecoder().decode(MediaItem.self, from: JSONSerialization.data(withJSONObject: json))
    let table = try XCTUnwrap(MediaItemTVSections.make(.init(mediaItem: item)).first { $0.id == "specs" })
    let cards = specs(in: table)
    XCTAssertEqual(cards.first { $0.id == "genres" }?.rows.first?.text, "MediaItem_TagGenre".localized)
    XCTAssertEqual(cards.first { $0.id == "countries" }?.rows.first?.text, "MediaItem_TagCountry".localized)
  }

  /// A series has a status, the years it aired in place of a year, and how much of it there is.
  func testASeriesHasAStatusAYearRangeAndHowMuchOfItThereIs() throws {
    func series(finished: Bool) throws -> MediaItem {
      let json: [String: Any] = [
        "id": 6, "type": "serial", "subtype": "", "title": "Сериал", "year": 2019, "cast": "", "director": "",
        "genres": [Any](), "countries": [Any](), "duration": ["average": 2700, "total": 100_000],
        "langs": 1, "quality": 1080, "plot": "", "posters": ["small": "", "medium": "", "big": "", "wide": ""],
        "finished": finished
      ]
      return try JSONDecoder().decode(MediaItem.self, from: JSONSerialization.data(withJSONObject: json))
    }
    func date(_ year: Int) -> Date { Calendar.current.date(from: DateComponents(year: year, month: 6, day: 1))! }
    func cards(_ item: MediaItem, _ configure: (inout TitleMetadata) -> Void) throws -> [TVPageInfoCard.Spec] {
      var metadata = TitleMetadata()
      configure(&metadata)
      let section = try XCTUnwrap(MediaItemTVSections.make(.init(mediaItem: item, metadata: metadata))
        .first { $0.id == "specs" })
      return specs(in: section)
    }

    let running = try cards(series(finished: false)) {
      $0.status = "Returning Series"; $0.firstAirDate = date(2019); $0.numberOfSeasons = 3; $0.numberOfEpisodes = 28
    }
    func value(_ cards: [TVPageInfoCard.Spec], _ id: String) -> String? { cards.first { $0.id == id }?.rows.last?.text }
    XCTAssertEqual(value(running, "year"), String(format: "MediaItem_SinceDate".localized, "2019"), "still airing: since")
    XCTAssertEqual(value(running, "status"), "MediaItem_StatusInProduction".localized)
    XCTAssertEqual(running.first { $0.id == "year" }?.rows.first?.text, "MediaItem_YearsAired".localized,
                   "a series is not given a year")
    XCTAssertEqual(value(running, "volume"), "3 \(SeriesFacts.unit(3, .season)), 28 \(SeriesFacts.unit(28, .episode))")
    // …in the video column, under how long it runs (Sasha, 2026-10-11) — not in the information one.
    var metadata = TitleMetadata()
    metadata.numberOfSeasons = 3; metadata.numberOfEpisodes = 28
    let section = try XCTUnwrap(MediaItemTVSections.make(.init(mediaItem: try series(finished: false), metadata: metadata))
      .first { $0.id == "specs" })
    let video = specs(in: TVPageSection.strip(id: "x", groups: section.groups.filter { $0.id == "video" })).map(\.id)
    XCTAssertEqual(video.suffix(3), ["runtime", "runtime.total", "volume"], "under the duration, in its column")
    let info = specs(in: TVPageSection.strip(id: "x", groups: section.groups.filter { $0.id == "info" })).map(\.id)
    XCTAssertFalse(info.contains("volume"))

    let ended = try cards(series(finished: true)) {
      $0.status = "Ended"; $0.firstAirDate = date(2019); $0.lastAirDate = date(2026)
    }
    XCTAssertEqual(value(ended, "year"), String(format: "MediaItem_YearsRange".localized, "2019", "2026"),
                   "ended: from … to …")
    XCTAssertEqual(value(ended, "status"), "MediaItem_StatusEnded".localized)
  }

  /// A series' runtime is one episode's, with the whole run's in a card beside it.
  func testASeriesSaysHowLongAnEpisodeIsAndHowLongTheWholeRun() throws {
    let json: [String: Any] = [
      "id": 7, "type": "serial", "subtype": "", "title": "Сериал", "year": 2019, "cast": "", "director": "",
      "genres": [Any](), "countries": [Any](), "duration": ["average": 2700, "total": 100_000],
      "langs": 1, "quality": 1080, "plot": "", "posters": ["small": "", "medium": "", "big": "", "wide": ""],
      "finished": false
    ]
    let item = try JSONDecoder().decode(MediaItem.self, from: JSONSerialization.data(withJSONObject: json))
    let table = try XCTUnwrap(MediaItemTVSections.make(.init(mediaItem: item)).first { $0.id == "specs" })
    let cards = specs(in: table)
    XCTAssertEqual(cards.first { $0.id == "runtime" }?.rows.first?.text, "MediaItem_EpisodeRuntime".localized)
    XCTAssertEqual(cards.first { $0.id == "runtime.total" }?.rows.first?.text, "MediaItem_TotalDuration".localized)
  }

  /// A value that is only words is never cut: it takes as many lines as it needs, so a narrow
  /// card is taller than a wide one — and the layout reserves that height before any cell exists.
  func testNamesAreNeverCutACardTakesTheLinesTheyNeed() {
    let names = (1...12).map { "Имя\u{00A0}Фамилия\($0)" }.joined(separator: ", ")
    let row = TVPageInfoCard.Spec.Row(id: "cast", text: names, style: .value)
    let wide = TVPageSpecRowView.height(for: row, width: 900)
    let narrow = TVPageSpecRowView.height(for: row, width: 300)
    XCTAssertGreaterThan(wide, TVPageSpecRowView.height(for: .value), "more than a line of names")
    XCTAssertGreaterThan(narrow, wide, "the narrower the card the more lines")

    let spec = TVPageInfoCard.Spec(id: "info", title: "Информация", showsHeader: false, rows: [row])
    XCTAssertGreaterThan(TVPageSpecContent.height(for: spec, cardWidth: 400),
                         TVPageSpecContent.height(for: spec, cardWidth: 1000))
    // Marks after the words keep the row to one line, which they share.
    let marked = TVPageInfoCard.Spec.Row(id: "r", text: names, badges: ["4K"], style: .value)
    XCTAssertEqual(TVPageSpecRowView.height(for: marked, width: 300), TVPageSpecRowView.height(for: .value))
  }

  /// A card with no header has no room for one: it is its rows and the padding.
  func testACardWithoutAHeaderIsShorterThanOneWith() {
    let rows = [TVPageInfoCard.Spec.Row(id: "a", text: "x", style: .value)]
    let headed = TVPageInfoCard.Spec(id: "a", title: "Audio", rows: rows)
    let bare = TVPageInfoCard.Spec(id: "a", title: "Audio", showsHeader: false, rows: rows)
    XCTAssertLessThan(TVPageSpecContent.height(for: bare, cardWidth: 500), TVPageSpecContent.height(for: headed, cardWidth: 500))
    XCTAssertLessThan(TVPageSpecContent.height(for: bare, cardWidth: 500), TVPageLayout.infoCardHeight,
                      "a card of one line is not as tall as a review's")
  }

  /// Only an item that does something on Select can take focus (Sasha, 2026-10-11): Audio, Subtitles and
  /// the cast's *Expand*; a type, a year, a resolution are text on the page.
  func testOnlyAnItemThatDoesSomethingOnSelectCanTakeFocus() throws {
    let cards = specs(in: table())
    for card in cards {
      let cell = TVPageSpecCell(frame: CGRect(x: 0, y: 0, width: 557, height: 200))
      cell.configure(card)
      XCTAssertEqual(cell.canBecomeFocused, card.opensInPopup, "\(card.id)")
    }
    XCTAssertEqual(cards.filter(\.opensInPopup).map(\.id), ["audio", "subtitles"])
  }

  /// Between two items that are only read the air is half what it is between two blocks — Audio and
  /// Subtitles are blocks and keep theirs (Sasha, 2026-10-11).
  func testTheAirBetweenItemsIsHalfTheAirBetweenBlocks() {
    let block = TVPageSpecContent.blockPadding * 2 + TVPageStripPlan.stackGap
    let item = TVPageSpecContent.itemVerticalPadding * 2 + TVPageStripPlan.stackGap
    XCTAssertEqual(item * 2, block, accuracy: 0.5, "text to text, bottom of one card to the top of the next")
  }
}
#endif
