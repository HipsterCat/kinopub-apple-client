#if os(tvOS)
//
//  MediaItemTVSections.swift
//  KinoPubAppleClient
//
//  The tvOS detail page under the hero, as data: one list of typed `TVPageSection`s, in
//  the order the page reads, drawn by one `TVEmbeddedPage`. The order is **here and only
//  here** (AGENTS.md › The detail page: "Sections are data, empty ones simply absent,
//  order defined in one place").
//
//  What the page says, top to bottom (Sasha, 2026-10-06; `docs/product/detail-sections.md`):
//
//      Ratings (and how many reviews there are)
//      Cast & Crew   (one row of portraits — fiction only)
//      Similar:      the same actors | this director | by genre   (Sasha, 2026-10-11)
//      Stills          | Facts (| Awards)
//      Collections
//      Audio & Subtitles | Video | Information      (three columns at most, filling the width)
//      Creators | Cast                              (as text, no heading — a kind with no faces)
//
//  A `|` is two titled groups in one row that scrolls as one (`TVPageSection.strip`). The
//  playable rails (episodes, versions) are not here: they stay directly under the hero.
//

import Foundation
import UIKit
import KinoPubBackend
import KinoPubMedia
import KinoPubMetadata
import KinoPubUI

enum MediaItemTVSections {

  /// Everything the sections are drawn from. A value, so what is on the page and in
  /// what order is one pure function a test can call.
  struct Input {
    var mediaItem: MediaItem
    var metadata: TitleMetadata = TitleMetadata()
    var likeCount: Int = 0
    var dislikeCount: Int = 0
    /// `MediaItemModel.relatedRows`: Similar first, then the people's, collections' and
    /// genre shelves.
    var relatedRows: [MediaRow] = []
    /// The author and cast shelves as groups of Similar: the words over them, and whether
    /// their query is still in flight (`MediaItemModel.authorGroup` / `castGroup`).
    var authorGroup: MediaItemModel.RelatedPeopleGroup?
    var castGroup: MediaItemModel.RelatedPeopleGroup?
    /// Facts the viewer asked to see in full — a spoiler stays hidden until it is.
    var revealedFacts: Set<String> = []
    var preferredLanguages: [String] = mediaItemPreferredLanguages()
    /// Off on the page, where the languages the viewer reads stay open and the rest fold
    /// into "N more"; on in the popup a column opens, which lists them all.
    var showsEveryLanguage = false
  }

  /// Ids the page uses to say what a selection was. Strings, because a `TVPageItem` is.
  enum ID {
    static let similar = "similar"
    /// How `MediaItemModel.relatedRows` names the shelves that Similar takes in.
    static let genreShelfPrefix = "genre-"
    static let authorShelfPrefix = "director-"
    static let castShelfPrefix = "actor-"
    static let gallery = "stills"
    static let kinoPubScore = "KinoPub"
  }

  static func make(_ input: Input) -> [TVPageSection] {
    ratings(input)
      + credits(input)
      + similar(input)
      + stillsAndFacts(input)
      + selections(input)
      + specifications(input)
      + creditsAsText(input)
  }

  // MARK: - Ratings

  /// The scores, one card per source — and, as the last card of the same row, how many reviews
  /// there are and how they were meant (Sasha, 2026-10-11). The reviews' own words are not on this
  /// page any more: that card opens a page of their own.
  static func ratings(_ input: Input) -> [TVPageSection] {
    let scores = RatingSources.scores(for: input.mediaItem,
                                      metadata: input.metadata,
                                      likeCount: input.likeCount,
                                      dislikeCount: input.dislikeCount)
    var items: [TVPageItem] = scores.map { .info(.rating(rating($0, input))) }
    if let reviews = reviewsCard(input) { items.append(.info(.reviews(reviews))) }
    guard !items.isEmpty else { return [] }
    return [.strip(id: "ratings", groups: [TVPageGroup(id: "scores",
                                                        title: "MediaItem_ScoresTitle".localized,
                                                        columns: 6,
                                                        items: items)])]
  }

  /// The count card: the source's total (the proxy pages its reviews, so it is more than the page
  /// carries), and the three tones from its summary — or, with no summary, from the reviews we hold.
  /// Nil when there is nothing to count.
  static func reviewsCard(_ input: Input) -> TVPageInfoCard.Reviews? {
    let metadata = input.metadata
    func formatted(_ number: Int) -> String { number.formatted(.number.grouping(.automatic)) }

    let total: Int
    let tones: (positive: Int, negative: Int, neutral: Int)?
    if let summary = metadata.reviewsSummary, !summary.isEmpty {
      total = summary.total > 0 ? summary.total : metadata.reviews.count
      tones = (summary.positive, summary.negative, summary.neutral)
    } else if !metadata.reviews.isEmpty {
      let held = metadata.reviews.map { $0.sentiment?.uppercased() }
      total = held.count
      tones = (held.filter { $0 == "POSITIVE" }.count, held.filter { $0 == "NEGATIVE" }.count,
               held.filter { $0 != "POSITIVE" && $0 != "NEGATIVE" }.count)
    } else {
      return nil
    }
    guard total > 0 else { return nil }

    let title = "Reviews".localized
    var label = "\(title), \(formatted(total))"
    var cardTones: TVPageInfoCard.Reviews.Tones?
    if let tones {
      cardTones = .init(positive: formatted(tones.positive), negative: formatted(tones.negative),
                        neutral: formatted(tones.neutral))
      label += ". \("Positive".localized) \(tones.positive), \("Negative".localized) \(tones.negative), "
        + "\("Neutral".localized) \(tones.neutral)"
    }
    return TVPageInfoCard.Reviews(id: "reviews", title: title, count: formatted(total), tones: cardTones,
                                  accessibilityLabel: label)
  }

  static func rating(_ score: RatingSources.Score, _ input: Input) -> TVPageInfoCard.Rating {
    let isKinoPub = score.logo == .kinopub
    var caption: String?
    var thumbs: TVPageInfoCard.Rating.Thumbs?
    if isKinoPub, input.likeCount + input.dislikeCount > 0 {
      thumbs = .init(up: input.likeCount.formatted(.number.grouping(.automatic)),
                     down: input.dislikeCount.formatted(.number.grouping(.automatic)))
    } else if let votes = score.votes, votes > 0 {
      caption = "\(votes.formatted(.number.grouping(.automatic))) \(ratingsUnit(votes))"
    }
    // Voters but no score yet ("not enough ratings"): no number, and the card says how many voted.
    return TVPageInfoCard.Rating(id: score.id, source: score.logo, title: score.id,
                                 value: score.value == nil ? nil : score.display,
                                 caption: caption, thumbs: thumbs)
  }

  private static func ratingsUnit(_ count: Int) -> String {
    switch localizedPluralForm(count) {
    case 0: return "MediaItem_UnitRatingOne".localized
    case 1: return "MediaItem_UnitRatingFew".localized
    default: return "MediaItem_UnitRatingMany".localized
    }
  }

  static func review(_ review: Review, index: Int) -> TVPageInfoCard.Review {
    let tone: TVPageInfoCard.Review.Tone
    switch review.sentiment?.uppercased() {
    case "POSITIVE": tone = .positive
    case "NEGATIVE": tone = .negative
    default: tone = .neutral
    }
    return TVPageInfoCard.Review(
      id: "\(index)",
      // Roughly half of a title's reviews carry no headline, so the author stands in.
      headline: review.title.isEmpty ? review.author : review.title,
      body: review.body,
      sentiment: review.sentimentTitle,
      tone: tone,
      date: shortDate(of: review)
    )
  }

  /// Numeric, so it and the sentiment share one line of a 4-column card.
  private static func shortDate(of review: Review) -> String? {
    if let posted = review.postedAt { return posted.formatted(date: .numeric, time: .omitted) }
    return review.displayDate
  }

  // MARK: - Cast & Crew

  /// Faces are for fiction (`MediaPresentationProfile.showsCastPortraits`): a concert, a
  /// stand-up set, a documentary, a show or anything animated lists its people as text, under the
  /// table at the bottom (`creditsAsText`).
  ///
  /// One heading, "Cast & Crew", over **one row of people with no sections inside it** (Sasha,
  /// 2026-10-11): what each is to the title is the card's own subtitle — the character for an
  /// actor, "Режиссёр" or "Создатель" for whoever made it. A film's director opens the row; a
  /// show's creators close it, behind the actors, and never get a row of their own however many
  /// there are.
  static func credits(_ input: Input) -> [TVPageSection] {
    let profile = input.mediaItem.presentation
    guard profile.showsCastPortraits else { return [] }

    let authors = authorCards(input)
    let cast = castCards(input)
    let people = profile.authorRole == .creator ? cast + authors : authors + cast
    var seen = Set<String>()
    let unique = people.filter { seen.insert($0.id).inserted }
    guard !unique.isEmpty else { return [] }
    return [.strip(id: "credits", title: "MediaItem_CastAndCrew".localized,
                   groups: [TVPageGroup(id: "people", title: nil, columns: 3, items: unique.map(TVPageItem.person))])]
  }

  /// Whoever directed or created it, at most three — a face where there is one, the initials
  /// where there is not — each with what they are to the title under the name.
  private static func authorCards(_ input: Input) -> [TVUIKitPerson] {
    let profile = input.mediaItem.presentation
    let names = MediaPerson.each(of: input.mediaItem.directorNames, role: .director, limit: 3).map(\.name)
    return TitleMetadata.enrich(names: names, roleDepartment: "Directing", from: input.metadata).map { member in
      let person = MediaPerson(name: member.name, role: .director,
                               photoURL: member.photo ?? ActorImageProvider.photoURL(for: member.name),
                               tmdbPersonId: member.tmdbPersonId)
      return card(for: person, caption: profile.authorRoleKey.localized)
    }
  }

  /// The most people the cast row holds. A billing runs to dozens; past a dozen it is a
  /// list of names nobody is looking for.
  static let castLimit = 12

  /// Who is worth a card, the most important first — "sort the stars by episodes or
  /// popularity and drop the insignificant" (Sasha, 2026-10-06).
  ///
  /// A series ranks by how many of its episodes a person is in (TMDB's aggregate credits); a
  /// film by TMDB's billing order, the one measure of prominence its credits carry. kino.pub's
  /// own order breaks a tie, and stands in for a title TMDB has nothing on. In a series,
  /// someone in fewer than a fifth of the episodes the most-seen person is in — and never
  /// fewer than two, once anyone has more than one — is a guest and is dropped; so is
  /// everything past `castLimit`.
  ///
  /// **Except the first of kino.pub's own list, when TMDB could not match them** (Sasha,
  /// 2026-10-11): no episode count, dropped as a guest — Dexter's own Dexter. If ranking
  /// would have left them out they open the row. A name TMDB *did* match — a guest by
  /// episode count, a bit part by billing — is dropped like anyone else, even when
  /// kino.pub listed them first. Restoring every first name put extras at the front of
  /// the row (`filmCrew`: «Эпизод Первый» ahead of the stars).
  static func rankedCast(_ members: [CastMember], isEpisodic: Bool) -> [CastMember] {
    let ranked = ranking(members, isEpisodic: isEpisodic)
    guard isEpisodic,
          let lead = members.first,
          lead.episodeCount == nil,
          !ranked.contains(where: { $0.name == lead.name }) else { return ranked }
    return [lead] + ranked.prefix(castLimit - 1)
  }

  private static func ranking(_ members: [CastMember], isEpisodic: Bool) -> [CastMember] {
    var ranked = Array(members.enumerated())
    let most = members.compactMap(\.episodeCount).max() ?? 0
    if isEpisodic, most > 0 {
      let floor = most > 1 ? max(2, Int((Double(most) * 0.2).rounded(.up))) : 1
      ranked = ranked.filter { ($0.element.episodeCount ?? 0) >= floor }
      ranked.sort { lhs, rhs in
        let (left, right) = (lhs.element, rhs.element)
        if (left.episodeCount ?? 0) != (right.episodeCount ?? 0) { return (left.episodeCount ?? 0) > (right.episodeCount ?? 0) }
        if (left.order ?? .max) != (right.order ?? .max) { return (left.order ?? .max) < (right.order ?? .max) }
        return lhs.offset < rhs.offset
      }
    } else if members.contains(where: { $0.order != nil }) {
      ranked.sort { lhs, rhs in
        if (lhs.element.order ?? .max) != (rhs.element.order ?? .max) { return (lhs.element.order ?? .max) < (rhs.element.order ?? .max) }
        return lhs.offset < rhs.offset
      }
    }
    return ranked.prefix(castLimit).map(\.element)
  }

  /// Actors as `MediaItemCastSection` has always chosen them — kino.pub's names, with
  /// TMDB's photo and character where it has them — ranked and trimmed (`rankedCast`). The
  /// caption is the character, then how many episodes for a series; a person with neither
  /// has none, because "Actor" under an actor says nothing.
  private static func castCards(_ input: Input) -> [TVUIKitPerson] {
    let members = TitleMetadata.enrich(names: input.mediaItem.castMembers, roleDepartment: "Acting",
                                       from: input.metadata)
    return rankedCast(members, isEpisodic: input.mediaItem.isEpisodicType).map { member in
      let person = MediaPerson(name: member.name, role: .actor,
                               photoURL: member.photo ?? ActorImageProvider.photoURL(for: member.name),
                               tmdbPersonId: member.tmdbPersonId)
      var parts: [String] = []
      if let character = member.character?.trimmingCharacters(in: .whitespacesAndNewlines), !character.isEmpty {
        parts.append(character)
      }
      if let episodes = member.episodeCount, episodes > 0 {
        parts.append("\(episodes) \("MediaItem_EpisodesShort".localized)")
      }
      return card(for: person, caption: parts.isEmpty ? nil : parts.joined(separator: " · "))
    }
  }

  /// TMDB's person id when we have it, else `role:name`. Two billed credits can share a
  /// name (`person.actor:Валид Зуэйтер` twice on 126967); the page's snapshot cannot.
  static func cardID(for person: MediaPerson) -> String {
    if let tmdb = person.tmdbPersonId {
      return "\(person.role.rawValue).tmdb.\(tmdb)"
    }
    return person.id
  }

  private static func card(for person: MediaPerson, caption: String?) -> TVUIKitPerson {
    TVUIKitPerson(id: cardID(for: person),
                  name: person.name,
                  nameComponents: TVUIKitPerson.nameComponents(from: person.name),
                  caption: caption,
                  photoURL: person.photoURL)
  }

  /// The person a card stands for. The id is unique (TMDB when known); the name is
  /// on the card itself. Role is the prefix of `role:name` or `role.tmdb.<id>`.
  static func person(from card: TVUIKitPerson) -> MediaPerson? {
    let separator = card.id.firstIndex(where: { $0 == ":" || $0 == "." })
    guard let separator,
          let role = MediaPerson.Role(rawValue: String(card.id[..<separator])) else { return nil }
    return MediaPerson(name: card.name, role: role, photoURL: card.photoURL)
  }

  // MARK: - Similar

  /// One heading over up to three groups of posters, the way Cast & Crew is one heading over
  /// its professions: **the same actors**, **this director's** other work, then what is alike
  /// **by genre** (Sasha, 2026-10-11) — in that order, ten covers at most in each. The three
  /// shelves used to be rows of their own, two of them far below the page. Home's poster, with
  /// Home's own caption — none, not even on focus (Sasha, 2026-10-06) — in one strip that scrolls
  /// as one piece.
  ///
  /// A title shows once, under the first group that has it — the order above. Each group takes
  /// its ten from what the groups before it left, so a thin one never starves the next.
  static func similar(_ input: Input) -> [TVPageSection] {
    func row(prefix: String) -> MediaRow? { input.relatedRows.first { $0.id.hasPrefix(prefix) } }
    var placed = Set<Int>()

    let cast = peopleGroup(id: "cast", input.castGroup, row: row(prefix: ID.castShelfPrefix), placed: &placed)
    let director = peopleGroup(id: "director", input.authorGroup, row: row(prefix: ID.authorShelfPrefix),
                               placed: &placed)

    // The genre floor only exists when nothing else did, so it takes Similar's place.
    var genres: TVPageGroup?
    if let shelf = input.relatedRows.first(where: { $0.id == ID.similar })
        ?? row(prefix: ID.genreShelfPrefix) {
      genres = posterGroup(id: "genres", title: genreTitle(of: input.mediaItem, shelf: shelf),
                           cards: freshCards(shelf, placed: &placed))
    }

    let groups = [cast, director, genres].compactMap { $0 }
    return groups.isEmpty ? [] : [.strip(id: ID.similar, title: "Similar".localized, groups: groups)]
  }

  /// A person's group: the shelf's covers, or skeleton posters while its query is still in
  /// flight. Nothing when the query came back empty.
  private static func peopleGroup(id: String, _ group: MediaItemModel.RelatedPeopleGroup?, row: MediaRow?,
                                  placed: inout Set<Int>) -> TVPageGroup? {
    guard let group else { return nil }
    let cards = row.map { freshCards($0, placed: &placed) } ?? []
    if cards.isEmpty, group.isPending {
      return TVPageGroup(id: id, title: group.title, columns: similarColumns, subheading: true, cell: .poster,
                         items: (0..<similarColumns).map(TVPageItem.placeholder))
    }
    return posterGroup(id: id, title: group.title, cards: cards)
  }

  private static func posterGroup(id: String, title: String, cards: [MediaCard]) -> TVPageGroup? {
    guard !cards.isEmpty else { return nil }
    return TVPageGroup(id: id, title: title, columns: similarColumns, subheading: true, cell: .poster,
                       items: cards.map(TVPageItem.card))
  }

  /// The first `similarLimit` covers of the shelf that no group above has taken, which it now takes.
  private static func freshCards(_ row: MediaRow, placed: inout Set<Int>) -> [MediaCard] {
    var fresh: [MediaCard] = []
    for card in row.cards where fresh.count < similarLimit && placed.insert(card.id).inserted {
      fresh.append(card)
    }
    return fresh
  }

  /// Six across, like every other shelf (HIG 260 at 1920).
  static let similarColumns = 6

  /// How many covers a group holds (Sasha, 2026-10-11): the row is for finding the next watch, not
  /// for walking a filmography — the three groups have to be within a few presses of each other.
  static let similarLimit = 10

  /// "Фантастика, боевики, приключения" — the genres the shelf is alike by, in a sentence.
  /// Similar's own are the title's; the genre floor says which of them it asked for.
  private static func genreTitle(of item: MediaItem, shelf: MediaRow) -> String {
    var genres = item.genres
    if shelf.id.hasPrefix(ID.genreShelfPrefix) {
      let asked = Set(shelf.id.dropFirst(ID.genreShelfPrefix.count).split(separator: "-").compactMap { Int($0) })
      let narrowed = genres.filter { asked.contains($0.id) }
      if !narrowed.isEmpty { genres = narrowed }
    }
    let names = genres.compactMap(\.title).filter { !$0.isEmpty }.map { $0.lowercased() }.joined(separator: ", ")
    guard let first = names.first else { return shelf.title }
    return first.uppercased() + names.dropFirst()
  }

  // MARK: - Stills | Facts | Awards

  static func stillsAndFacts(_ input: Input) -> [TVPageSection] {
    var groups: [TVPageGroup] = []

    let stills = input.metadata.stills
    if !stills.isEmpty {
      let title = "MediaItem_StillsTitle".localized
      let gallery = TVPageInfoCard.Gallery(id: ID.gallery,
                                           images: stills.prefix(TVPageInfoCard.Gallery.stillCount)
                                             .map { $0.previewURL ?? $0.url },
                                           accessibilityLabel: title)
      groups.append(TVPageGroup(id: "stills", title: title, columns: 3, items: [.info(.gallery(gallery))]))
    }

    // Facts without a spoiler first, the spoilers after them (Sasha, 2026-10-11) — each keeps its
    // id from its place in the list, so a revealed one stays revealed wherever it stands.
    let facts = input.metadata.facts
    if !facts.isEmpty {
      let ordered = facts.enumerated().sorted { lhs, rhs in
        lhs.element.isSpoiler == rhs.element.isSpoiler ? lhs.offset < rhs.offset : !lhs.element.isSpoiler
      }
      groups.append(TVPageGroup(
        id: "facts", title: "MediaItem_FactsTitle".localized, columns: 4,
        items: ordered.map { index, fact in
          let id = factID(index)
          return .info(.fact(.init(id: id, text: fact.text, isSpoiler: fact.isSpoiler,
                                   isRevealed: input.revealedFacts.contains(id),
                                   warning: "MediaItem_FactSpoilerWarning".localized)))
        }
      ))
    }

    // Awards are facts about the title too, and only exist for a viewer with their own
    // Kinopoisk key — so they follow the facts rather than the page growing a row for them.
    let awards = input.metadata.awards
    if !awards.isEmpty {
      groups.append(TVPageGroup(
        id: "awards", title: "Awards".localized, columns: 4,
        items: awards.enumerated().map { index, award in
          .info(.fact(.init(id: "award.\(index)", text: awardLine(award), isSpoiler: false, isRevealed: true,
                            warning: "")))
        }
      ))
    }
    return groups.isEmpty ? [] : [.strip(id: "stills-facts", groups: groups)]
  }

  static func factID(_ index: Int) -> String { "fact.\(index)" }

  private static func awardLine(_ award: Award) -> String {
    let mark = award.won ? "🏆" : "🎖"
    var parts = [award.nominationName.map { "\(award.name) — \($0)" } ?? award.name]
    if let year = award.year { parts.append(String(year)) }
    return "\(mark) \(parts.joined(separator: ", "))"
  }

  // MARK: - Collections

  /// Every shelf Similar did not take in — the collections this title is in — each a
  /// Home-style poster row, covers only: no "See all" tile at the end of one (Sasha,
  /// 2026-10-06 — it named itself on focus and its footer made the covers beside it grow).
  static func selections(_ input: Input) -> [TVPageSection] {
    input.relatedRows.filter { !isSimilarShelf($0.id) && !$0.cards.isEmpty }.map { row in
      TVPageSection.posters(id: row.id, title: row.title, count: row.count, caption: .never, cards: row.cards)
    }
  }

  /// The shelves `similar` takes in, by the ids `MediaItemModel.relatedRows` gives them.
  private static func isSimilarShelf(_ id: String) -> Bool {
    id == ID.similar || id.hasPrefix(ID.genreShelfPrefix)
      || id.hasPrefix(ID.authorShelfPrefix) || id.hasPrefix(ID.castShelfPrefix)
  }

  // MARK: - Credits as text

  /// How many names the cast card shows before the link that opens the rest.
  static let creditsPreview = 6

  /// The people of a kind with no faces on the page — anime, cartoons, a concert, a show — as text,
  /// **under the table with the audio and the subtitles and with no heading** (Sasha, 2026-10-11):
  /// three columns, each a stack of cards — whoever made it first, the cast second, the third not
  /// yet used. The cast card shows the first few names, every one whole and none cut, and **always**
  /// has the link under it — *Развернуть* — that opens everyone kino.pub lists, a row to a name. That
  /// link is the one focus stop in the section: the words themselves are only read. Faces take the
  /// place of Cast & Crew near the top of the page for fiction (`credits`).
  static func creditsAsText(_ input: Input) -> [TVPageSection] {
    let item = input.mediaItem
    let profile = item.presentation
    guard !profile.showsCastPortraits else { return [] }
    var columns: [TVPageGroup] = []

    let authors = item.directorNames
    if !authors.isEmpty {
      let spec = TVPageInfoCard.Spec(
        id: "authors", title: profile.authorCaptionKey.localized, showsHeader: false,
        rows: pair("author", profile.authorCaptionKey.localized, unbreakable(authors)))
      columns.append(TVPageGroup(id: "authors", title: nil, columns: maxSpecColumns, stacked: true,
                                 items: [.info(.spec(spec))]))
    }

    let cast = item.castMembers
    if !cast.isEmpty {
      let preview = TVPageInfoCard.Spec(
        id: "cast", title: "MediaItem_CreditsParticipants".localized, showsHeader: false,
        rows: pair("cast", "MediaItem_CreditsParticipants".localized,
                   unbreakable(Array(cast.prefix(creditsPreview)))))
      columns.append(TVPageGroup(id: "cast", title: nil, columns: maxSpecColumns, stacked: true,
                                 items: [preview, expandCastSpec(cast, showsEverything: input.showsEveryLanguage)]
                                  .map { .info(.spec($0)) }))
    }
    guard !columns.isEmpty else { return [] }
    return [.strip(id: "credits", groups: columns)]
  }

  /// The link under the cast that opens it all — read in the popup, a row to a name.
  private static func expandCastSpec(_ cast: [String], showsEverything: Bool) -> TVPageInfoCard.Spec {
    let title = "MediaItem_CreditsParticipants".localized
    let rows: [TVPageInfoCard.Spec.Row] = showsEverything
      ? cast.enumerated().map { .init(id: "cast.\($0.offset)", text: $0.element, style: .value) }
      : [.init(id: "cast.expand", text: "MediaItem_Expand".localized, style: .more)]
    return TVPageInfoCard.Spec(id: "cast.expand", symbol: "person.2", title: title, showsHeader: false,
                               opensInPopup: true, rows: rows)
  }

  /// A caption over the value that follows it: the rows of one item of the table.
  private static func pair(_ id: String, _ caption: String, _ value: String) -> [TVPageInfoCard.Spec.Row] {
    [.init(id: "\(id).caption", text: caption, style: .caption), .init(id: id, text: value, style: .value)]
  }

  // MARK: - Audio & Subtitles | Video | Information

  /// The table under the page: **three columns at most, always, a gutter apart** (twice what two
  /// cards of a row stand apart) **and sharing the width equally** — and each is a stack of cards,
  /// one to an item, so focus goes from item to item and not over a whole column, which would be
  /// taller than the screen (Sasha, 2026-10-11). First the languages, audio and subtitles each its
  /// own card; then the video, the resolution, the runtime; then what the title is — type, year,
  /// genres, countries, and for a series its status, the years it aired and how much of it there is.
  /// **Select reads a card in full only where there is more to read** — every language. The people of
  /// a kind with no faces have a section of their own (`creditsAsText`).
  ///
  /// The strip of type / country / genre pills that was above it is gone: it said what the third
  /// column says now.
  static func specifications(_ input: Input) -> [TVPageSection] {
    func column(_ id: String, _ specs: [TVPageInfoCard.Spec]) -> TVPageGroup? {
      specs.isEmpty ? nil : TVPageGroup(id: id, title: nil, columns: maxSpecColumns, stacked: true,
                                        items: specs.map { .info(.spec($0)) })
    }
    let columns = [column("languages", [audioSpec(input), subtitlesSpec(input)]),
                   column("video", videoSpecs(input)),
                   column("info", informationSpecs(input))].compactMap { $0 }
    return columns.isEmpty ? [] : [.strip(id: "specs", groups: columns)]
  }

  /// No more than this many columns, ever.
  static let maxSpecColumns = 3

  /// Words in a list break between its items and never inside one — "Том Холланд" stays on a
  /// line — so a name is never split, and (with the row's own wrapping) never cut.
  private static func unbreakable(_ items: [String], separator: String = ", ") -> String {
    items.map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }.joined(separator: separator)
  }

  // MARK: Audio & Subtitles

  /// Audio and subtitles, each a card of its own with a quiet header, in the languages of the
  /// viewer's order. A title that reports none says so, instead of a header over nothing; Select
  /// reads every language, the folded ones too.
  private static func audioSpec(_ input: Input) -> TVPageInfoCard.Spec {
    TVPageInfoCard.Spec(id: "audio", symbol: "waveform", title: "Audio".localized,
                        opensInPopup: true, rows: audioRows(input))
  }

  private static func subtitlesSpec(_ input: Input) -> TVPageInfoCard.Spec {
    TVPageInfoCard.Spec(id: "subtitles", symbol: "captions.bubble", title: "Subtitles".localized,
                        opensInPopup: true, rows: subtitleRows(input))
  }

  /// Languages in the viewer's order. The ones they read stay open with what dubs them;
  /// the rest fold into "N more languages" (`LanguageListVisibility`, the one rule).
  private static func audioRows(_ input: Input) -> [TVPageInfoCard.Spec.Row] {
    let item = input.mediaItem
    let groups = item.audioLanguageGroups(preferredLanguages: input.preferredLanguages)
    guard !groups.isEmpty else {
      return [.init(id: "audio.none", text: "MediaItem_SpecNoAudio".localized, style: .value)]
    }
    let tracks = AudioTracks.sort(item.detailAudioTracks, preferredLanguages: input.preferredLanguages)
    let tracksByLanguage = Dictionary(grouping: tracks) { SubtitleTracks.languageKey($0.lang) }

    let partition = visibleLanguages(groups, input)
    var rows: [TVPageInfoCard.Spec.Row] = []
    for group in partition.visible {
      let dubs = dubRows(for: tracksByLanguage[group.key] ?? [], language: group.key)
      // A language with nothing but the original track says so beside its name.
      let isOriginalOnly = dubs.isEmpty
      rows.append(.init(id: "audio.\(group.key)", text: group.name,
                        secondary: isOriginalOnly ? AudioTracks.localizedKindLabel(rank: 5) : nil,
                        style: .language))
      rows.append(contentsOf: dubs)
    }
    if partition.hiddenCount > 0 {
      rows.append(moreLanguagesRow(partition.hiddenCount, id: "audio.more"))
    }
    return rows
  }

  /// One line per kind of dub within a language, under it, in words and no glyph (Sasha,
  /// 2026-10-11): the kind and every studio that voiced it — all of them, the line wraps and is
  /// never cut.
  private static func dubRows(for tracks: [AudioTrackInfo], language: String) -> [TVPageInfoCard.Spec.Row] {
    var order: [Int] = []
    var byRank: [Int: [AudioTrackInfo]] = [:]
    for track in tracks {
      let rank = AudioTracks.kindRank(typeId: track.typeId, typeTitle: track.typeTitle,
                                      typeShortTitle: track.typeShortTitle)
      guard rank != 5 else { continue } // the original is the language row's own note
      if byRank[rank] == nil { order.append(rank) }
      byRank[rank, default: []].append(track)
    }
    return order.compactMap { rank -> TVPageInfoCard.Spec.Row? in
      guard let group = byRank[rank] else { return nil }
      var seen = Set<String>()
      let studios = group.compactMap { track -> String? in
        let studio = track.authorTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return studio.isEmpty || !seen.insert(studio.lowercased()).inserted ? nil : studio
      }
      let kind = AudioTracks.localizedKindLabel(rank: rank) ?? ""
      let text = studios.isEmpty ? kind : "\(kind): \(unbreakable(studios))"
      return .init(id: "audio.\(language).\(rank)", text: text, style: .detail)
    }
  }

  /// The languages on one line, two spaces apart (Sasha, 2026-10-11) — the line wraps when it
  /// has to and is never cut. A track marked hard-of-hearing or forced says so in brackets.
  private static func subtitleRows(_ input: Input) -> [TVPageInfoCard.Spec.Row] {
    let item = input.mediaItem
    let groups = item.subtitleLanguageGroups(preferredLanguages: input.preferredLanguages)
    guard !groups.isEmpty else {
      return [.init(id: "subtitles.none", text: "MediaItem_SpecNoSubtitles".localized, style: .value)]
    }
    let tracks = SubtitleTracks.sort(item.detailSubtitleTracks, preferredLanguages: input.preferredLanguages)
    let tracksByLanguage = Dictionary(grouping: tracks) { SubtitleTracks.languageKey($0.lang) }

    let partition = visibleLanguages(groups, input)
    let languages = partition.visible.map { group -> String in
      let own = tracksByLanguage[group.key] ?? []
      // kino.pub does not tell a hard-of-hearing track from a translated one, so a track
      // is "CC" when its own name says so and nothing more is claimed (see `LanguagesCard`).
      var notes: [String] = []
      if own.contains(where: \.isCC) { notes.append("CC") }
      if own.contains(where: \.isForced) { notes.append("Forced".localized) }
      return notes.isEmpty ? group.name : "\(group.name) (\(notes.joined(separator: ", ")))"
    }
    var rows: [TVPageInfoCard.Spec.Row] = [
      .init(id: "subtitles.languages", text: unbreakable(languages, separator: "  "), style: .value)
    ]
    if partition.hiddenCount > 0 {
      rows.append(moreLanguagesRow(partition.hiddenCount, id: "subtitles.more"))
    }
    return rows
  }

  private static func visibleLanguages(_ groups: [MediaLanguageGroup], _ input: Input)
  -> (visible: [MediaLanguageGroup], hiddenCount: Int) {
    input.showsEveryLanguage
      ? (groups, 0)
      : LanguageListVisibility.partition(groups, preferredLanguages: input.preferredLanguages)
  }

  /// What the card has more of, in two words and no glyph: "+ ещё 7", "+ 7 more".
  private static func moreLanguagesRow(_ count: Int, id: String) -> TVPageInfoCard.Spec.Row {
    .init(id: id, text: String(format: "MediaItem_SpecMore".localized, "\(count)"), style: .more)
  }

  // MARK: Video

  /// What the picture is, then how long it runs, then — for a series — how many seasons and episodes:
  /// each its own card, without a header. A film's runtime is the film's; a series' is one episode's,
  /// with the whole run's under it.
  private static func videoSpecs(_ input: Input) -> [TVPageInfoCard.Spec] {
    let item = input.mediaItem
    var specs: [TVPageInfoCard.Spec] = []
    func card(_ id: String, _ rows: [TVPageInfoCard.Spec.Row]) {
      specs.append(TVPageInfoCard.Spec(id: id, title: "MediaItem_SpecVideo".localized, showsHeader: false, rows: rows))
    }

    // The best file the title has: its size and what class that is. A payload without
    // files (a listing, `nolinks`) still says what quality it advertises.
    if let best = item.detailFiles.max(by: { ($0.h, $0.w) < ($1.h, $1.w) }), best.w > 0, best.h > 0 {
      card("resolution", [
        .init(id: "resolution.caption", text: "MediaItem_SpecResolution".localized, style: .caption),
        .init(id: "resolution", text: "\(best.w)×\(best.h)",
              badges: qualityBadge(for: item).map { [$0] } ?? [], style: .value)])
    } else if let quality = item.qualityDisplay {
      card("resolution", [
        .init(id: "resolution.caption", text: "MediaItem_SpecQuality".localized, style: .caption),
        .init(id: "resolution", text: quality, badges: qualityBadge(for: item).map { [$0] } ?? [], style: .value)])
    }

    // A multi-version film sums every version in `total`, which is the payload's runtime and
    // not the film's.
    let seconds: Int
    if item.isEpisodicType {
      seconds = Int(item.duration.average)
    } else {
      seconds = Int(item.playbackVariants.isEmpty ? item.duration.total : item.duration.average)
    }
    if let runtime = RuntimeText(seconds: seconds).formatted(.long) {
      card("runtime", pair("runtime", (item.isEpisodicType ? "MediaItem_EpisodeRuntime" : "MediaItem_Runtime").localized,
                           runtime))
    }
    if item.isEpisodicType, item.duration.total > item.duration.average,
       let total = RuntimeText(seconds: Int(item.duration.total)).formatted(.long) {
      card("runtime.total", pair("runtime.total", "MediaItem_TotalDuration".localized, total))
    }
    // How much of a series there is stands under how long it runs, in the same column (Sasha,
    // 2026-10-11).
    if item.isEpisodicType, let volume = SeriesFacts.volume(item, input.metadata) {
      card("volume", pair("volume", "MediaItem_SeasonsAndEpisodes".localized, volume))
    }

    // The two flags kino.pub raises about a release, said where the video is.
    let advisories = mediaItemAdvisories(item)
    if !advisories.isEmpty {
      card("advisories", advisories.enumerated().map { index, advisory in
        .init(id: "advisory.\(index)", text: advisory, leading: .symbol("exclamationmark.triangle"), style: .detail)
      })
    }
    return specs
  }

  private static func qualityBadge(for item: MediaItem) -> String? {
    let caps = MediaCapabilityBadges.from(item: item)
    if caps.is4K { return "4K" }
    if caps.isHD { return "HD" }
    return item.qualityDisplay == nil ? nil : "SD"
  }

  // MARK: Information

  /// What the title is, a card to each item: type, year, genres, countries, and for a series the
  /// status and the years it aired. No header. Every value is words that
  /// wrap onto as many lines as they need and are never cut; a label is singular for one genre or
  /// country and plural for several. Genres and countries are words — no emoji, no flags.
  private static func informationSpecs(_ input: Input) -> [TVPageInfoCard.Spec] {
    let item = input.mediaItem
    var specs: [TVPageInfoCard.Spec] = []
    func card(_ id: String, _ caption: String, _ value: String) {
      specs.append(TVPageInfoCard.Spec(id: id, title: caption, showsHeader: false, rows: pair(id, caption, value)))
    }

    // Type — and its subtype, when there is one. `multi` says the film ships in several
    // versions, which the versions rail above already lists. An unknown subtype still surfaces:
    // better an unexplained word than a dropped one.
    var type = [item.contentTypeTitleKey.localized]
    if !item.isMultiVersion {
      if let key = item.contentSubtypeTitleKey {
        type.append(key.localized)
      } else if let raw = item.contentSubtypeRaw {
        type.append(raw)
      }
    }
    card("type", "Type".localized, type.joined(separator: " · "))

    // A series has a status and aired over some years; a film has a year.
    if item.isEpisodicType {
      if let status = SeriesFacts.statusKey(item, input.metadata) {
        card("status", "MediaItem_Status".localized, status.localized)
      }
      if let years = SeriesFacts.years(item, input.metadata) {
        card("year", "MediaItem_YearsAired".localized, years)
      }
    } else if item.year > 0 {
      card("year", "Year".localized, String(item.year))
    }

    let genres = item.genres.compactMap { $0.title }.filter { !$0.isEmpty }
    if !genres.isEmpty {
      card("genres", (genres.count == 1 ? "MediaItem_TagGenre" : "MediaItem_TagGenres").localized, unbreakable(genres))
    }

    let countries = item.countries.map(\.title).filter { !$0.isEmpty }
    if !countries.isEmpty {
      card("countries", (countries.count == 1 ? "MediaItem_TagCountry" : "MediaItem_TagCountries").localized,
           unbreakable(countries))
    }

    return specs
  }
}
#endif
