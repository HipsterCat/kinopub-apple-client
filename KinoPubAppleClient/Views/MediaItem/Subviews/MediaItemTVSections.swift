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
//      Ratings         | Reviews
//      Cast & Crew:  Director | Starring
//      Similar
//      Stills          | Facts (| Awards)
//      Type · Year · Countries · Genres
//      Collections and other selections
//      Video           | Audio | Subtitles
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
    /// Titles of shelves whose query is still in flight — drawn as skeleton rows.
    var pendingShelfTitles: [String] = []
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
    static let tagType = "tag.type"
    static let tagYear = "tag.year"
    static let tagCountryPrefix = "tag.country."
    static let tagGenrePrefix = "tag.genre."
    static let gallery = "stills"
    static let kinoPubScore = "KinoPub"
  }

  static func make(_ input: Input) -> [TVPageSection] {
    scoresAndReviews(input)
      + credits(input)
      + similar(input)
      + stillsAndFacts(input)
      + tags(input)
      + selections(input)
      + specifications(input)
  }

  // MARK: - Ratings | Reviews

  static func scoresAndReviews(_ input: Input) -> [TVPageSection] {
    var groups: [TVPageGroup] = []

    let scores = RatingSources.scores(for: input.mediaItem,
                                      metadata: input.metadata,
                                      likeCount: input.likeCount,
                                      dislikeCount: input.dislikeCount)
    if !scores.isEmpty {
      groups.append(TVPageGroup(id: "scores",
                                title: "MediaItem_ScoresTitle".localized,
                                columns: 6,
                                items: scores.map { .info(.rating(rating($0, input))) }))
    }

    let reviews = Array(input.metadata.reviews.prefix(reviewLimit))
    if !reviews.isEmpty {
      groups.append(TVPageGroup(id: "reviews",
                                title: "Reviews".localized,
                                columns: 4,
                                items: reviews.enumerated().map { .info(.review(review($1, index: $0))) }))
    }
    return groups.isEmpty ? [] : [.strip(id: "ratings", groups: groups)]
  }

  /// A review is a preview here — the whole text is behind Select.
  static let reviewLimit = 10

  static func rating(_ score: RatingSources.Score, _ input: Input) -> TVPageInfoCard.Rating {
    let isKinoPub = score.logo == .kinopub
    var caption: String?
    var thumbs: TVPageInfoCard.Rating.Thumbs?
    if isKinoPub, input.likeCount + input.dislikeCount > 0 {
      thumbs = .init(up: input.likeCount.formatted(.number.grouping(.automatic)),
                     down: input.dislikeCount.formatted(.number.grouping(.automatic)))
    } else if score.value == nil {
      caption = "MediaItem_NotEnoughRatings".localized
    } else if let votes = score.votes, votes > 0 {
      caption = "\(votes.formatted(.number.grouping(.automatic))) \(ratingsUnit(votes))"
    }
    return TVPageInfoCard.Rating(id: score.id, source: score.logo, title: score.id,
                                 showsName: score.logo == .kinopoisk || score.logo == .kinopub,
                                 value: score.display, caption: caption, thumbs: thumbs)
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
  /// stand-up set, a documentary, a show or anything animated lists its people as a
  /// Credits column of the specifications instead.
  ///
  /// One heading, "Cast & Crew", with the professions as its subheadings — Director,
  /// Starring — and no profession on the cards under them (Sasha, 2026-10-06). One director
  /// stands beside the cast, in one row. Several would push the cast off the screen, so
  /// they are a row of their own with the cast under it.
  static func credits(_ input: Input) -> [TVPageSection] {
    let profile = input.mediaItem.presentation
    guard profile.showsCastPortraits else { return [] }

    let directors = directorCards(input)
    let directorGroup = directors.isEmpty ? nil : TVPageGroup(
      id: "directors", title: profile.authorCaptionKey.localized, columns: 3, subheading: true,
      items: directors.map(TVPageItem.person))
    let cast = castCards(input)
    let castGroup = cast.isEmpty ? nil : TVPageGroup(
      id: "cast", title: "MediaItem_Starring".localized, columns: 3, subheading: true,
      items: cast.map(TVPageItem.person))
    let heading = "MediaItem_CastAndCrew".localized

    if let directorGroup, let castGroup, directors.count > 1 {
      return [.strip(id: "credits-directors", title: heading, groups: [directorGroup]),
              .strip(id: "credits-cast", groups: [castGroup])]
    }
    let groups = [directorGroup, castGroup].compactMap { $0 }
    return groups.isEmpty ? [] : [.strip(id: "credits", title: heading, groups: groups)]
  }

  /// Whoever directed or created it, at most three — a face where there is one, the
  /// initials where there is not. No caption: the group's subheading says what they are.
  private static func directorCards(_ input: Input) -> [TVUIKitPerson] {
    let names = MediaPerson.each(of: input.mediaItem.directorNames, role: .director, limit: 3).map(\.name)
    return TitleMetadata.enrich(names: names, roleDepartment: "Directing", from: input.metadata).map { member in
      let person = MediaPerson(name: member.name, role: .director,
                               photoURL: member.photo ?? ActorImageProvider.photoURL(for: member.name),
                               tmdbPersonId: member.tmdbPersonId)
      return card(for: person, caption: nil)
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
  static func rankedCast(_ members: [CastMember], isEpisodic: Bool) -> [CastMember] {
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

  private static func card(for person: MediaPerson, caption: String?) -> TVUIKitPerson {
    TVUIKitPerson(id: person.id,
                  name: person.name,
                  nameComponents: TVUIKitPerson.nameComponents(from: person.name),
                  caption: caption,
                  photoURL: person.photoURL)
  }

  /// The person a card stands for — the id is built from the same `MediaPerson.id`.
  static func person(from card: TVUIKitPerson) -> MediaPerson? {
    guard let colon = card.id.firstIndex(of: ":"),
          let role = MediaPerson.Role(rawValue: String(card.id[..<colon])) else { return nil }
    return MediaPerson(name: String(card.id[card.id.index(after: colon)...]), role: role,
                       photoURL: card.photoURL)
  }

  // MARK: - Similar

  /// Home's own poster row: the 6-column lockup, with Home's own caption — none, not even
  /// on focus (Sasha, 2026-10-06): the covers are what the row is for.
  static func similar(_ input: Input) -> [TVPageSection] {
    guard let row = input.relatedRows.first(where: { $0.id == ID.similar }), !row.cards.isEmpty else { return [] }
    return [.posters(id: row.id, title: row.title, count: row.count, caption: .never, cards: row.cards)]
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

    let facts = input.metadata.facts
    if !facts.isEmpty {
      groups.append(TVPageGroup(
        id: "facts", title: "MediaItem_FactsTitle".localized, columns: 4,
        items: facts.enumerated().map { index, fact in
          let id = factID(index)
          return .info(.fact(.init(id: id, text: fact.text, isSpoiler: fact.isSpoiler,
                                   isRevealed: input.revealedFacts.contains(id),
                                   warning: "MediaItem_FactSpoilerWarning".localized,
                                   revealTitle: "MediaItem_FactShow".localized)))
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
                            warning: "", revealTitle: "")))
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

  // MARK: - Type · Year · Countries · Genres

  /// What this title *is* and where it comes from — each pill is a way into the catalogue
  /// narrowed to it (`searchTarget(forChip:in:)`). One group per axis, each under its own
  /// small title, in one row.
  static func tags(_ input: Input) -> [TVPageSection] {
    let item = input.mediaItem
    var groups: [TVPageGroup] = []

    var typeChips = [TVPageChip(id: ID.tagType, title: item.contentTypeTitleKey.localized,
                                systemImage: TypeSymbol.name(for: item.type))]
    // `multi` says the film ships in several versions, which the versions rail above
    // already lists. An unknown subtype still surfaces: better an unexplained word than a
    // dropped one.
    if !item.isMultiVersion {
      if let key = item.contentSubtypeTitleKey {
        typeChips.append(TVPageChip(id: "tag.subtype", title: key.localized))
      } else if let raw = item.contentSubtypeRaw {
        typeChips.append(TVPageChip(id: "tag.subtype", title: raw))
      }
    }
    groups.append(chipGroup(id: "type", title: "Type".localized, chips: typeChips))

    if item.year > 0 {
      groups.append(chipGroup(id: "year", title: "Year".localized,
                              chips: [TVPageChip(id: ID.tagYear, title: String(item.year))]))
    }

    let countries = item.countries.filter { !$0.title.isEmpty }
    if !countries.isEmpty {
      groups.append(chipGroup(
        id: "countries", title: "MediaItem_TagCountries".localized,
        chips: countries.map {
          TVPageChip(id: "\(ID.tagCountryPrefix)\($0.id)", title: Emoji.decorated(Emoji.flag(countryID: $0.id), $0.title))
        }
      ))
    }

    let genres = item.genres.compactMap { genre -> TVPageChip? in
      guard let title = genre.title, !title.isEmpty else { return nil }
      return TVPageChip(id: "\(ID.tagGenrePrefix)\(genre.id)", title: Emoji.decorated(Emoji.genre(id: genre.id), title))
    }
    if !genres.isEmpty {
      groups.append(chipGroup(id: "genres", title: "MediaItem_TagGenres".localized, chips: genres))
    }
    return [.strip(id: "tags", groups: groups)]
  }

  private static func chipGroup(id: String, title: String, chips: [TVPageChip]) -> TVPageGroup {
    TVPageGroup(id: id, title: title, columns: 0, items: chips.map(TVPageItem.chip))
  }

  /// The catalogue narrowed to what a pill names, and the words to title that search with.
  /// Nil for a pill that is only a statement (an unknown subtype).
  static func searchTarget(forChip id: String, in item: MediaItem) -> (filter: LibraryFilter, title: String)? {
    switch id {
    case ID.tagType:
      guard let type = item.contentTypeFilter else { return nil }
      return (LibraryFilter(contentType: type), item.contentTypeTitleKey.localized)
    case ID.tagYear:
      guard item.year > 0 else { return nil }
      return (LibraryFilter(years: YearRange(from: item.year, to: item.year)), String(item.year))
    default:
      if id.hasPrefix(ID.tagCountryPrefix), let value = Int(id.dropFirst(ID.tagCountryPrefix.count)),
         let country = item.countries.first(where: { $0.id == value }) {
        return (LibraryFilter(countryID: value), country.title)
      }
      if id.hasPrefix(ID.tagGenrePrefix), let value = Int(id.dropFirst(ID.tagGenrePrefix.count)),
         let title = item.genres.first(where: { $0.id == value })?.title {
        return (LibraryFilter(genreID: value), title)
      }
      return nil
    }
  }

  // MARK: - Collections and other selections

  /// Every shelf that is not Similar — the director's and the lead's other work,
  /// the collections this title is in, the genre floor — each a Home-style poster row, covers
  /// only: no "See all" tile at the end of one (Sasha, 2026-10-06 — it named itself on focus
  /// and its footer made the covers beside it grow).
  static func selections(_ input: Input) -> [TVPageSection] {
    var sections: [TVPageSection] = input.relatedRows.filter { $0.id != ID.similar && !$0.cards.isEmpty }.map { row in
      TVPageSection.posters(id: row.id, title: row.title, count: row.count, caption: .never, cards: row.cards)
    }
    // Shelves still in flight hold their place as skeleton rows, so the page does not jump.
    sections += input.pendingShelfTitles.map {
      .placeholder(id: "pending.\($0)", title: $0, kind: .poster, columns: 6)
    }
    return sections
  }

  // MARK: - Video | Audio | Subtitles

  /// The technical table as columns, 3 across: what it is, what can be heard, what can be
  /// read. A kind with no faces on the page gets its people here, as a first column.
  static func specifications(_ input: Input) -> [TVPageSection] {
    var columns: [TVPageInfoCard.Spec] = []
    if let credits = creditsSpec(input) { columns.append(credits) }
    if let video = videoSpec(input) { columns.append(video) }
    if let audio = audioSpec(input) { columns.append(audio) }
    if let subtitles = subtitlesSpec(input) { columns.append(subtitles) }
    guard !columns.isEmpty else { return [] }
    return [.strip(id: "specs",
                   groups: [TVPageGroup(id: "specs", title: nil, columns: 3,
                                        items: columns.map { .info(.spec($0)) })])]
  }

  /// People as text, for the kinds whose cast is not on the page as faces
  /// (`MediaPresentationProfile.showsCastPortraits` is false).
  private static func creditsSpec(_ input: Input) -> TVPageInfoCard.Spec? {
    let item = input.mediaItem
    let profile = item.presentation
    guard !profile.showsCastPortraits else { return nil }
    var rows: [TVPageInfoCard.Spec.Row] = []
    let authors = item.directorNames
    if !authors.isEmpty {
      rows.append(.init(id: "author.caption", text: profile.authorCaptionKey.localized, style: .caption))
      rows.append(.init(id: "author", text: authors.joined(separator: ", "), style: .value))
    }
    let people = item.castMembers
    if !people.isEmpty {
      rows.append(.init(id: "cast.caption", text: "MediaItem_CreditsParticipants".localized, style: .caption))
      rows.append(.init(id: "cast", text: people.prefix(6).joined(separator: ", "), style: .value))
    }
    guard !rows.isEmpty else { return nil }
    return TVPageInfoCard.Spec(id: "credits", symbol: "person.2.fill",
                               title: "MediaItem_Credits".localized, rows: rows)
  }

  private static func videoSpec(_ input: Input) -> TVPageInfoCard.Spec? {
    let item = input.mediaItem
    var rows: [TVPageInfoCard.Spec.Row] = []

    // A film's runtime is the film's; a series' is one episode's. A multi-version film
    // sums every version in `total`, which is the payload's runtime and not the film's.
    let seconds: Int
    if item.isEpisodicType {
      seconds = Int(item.duration.average)
    } else {
      seconds = Int(item.playbackVariants.isEmpty ? item.duration.total : item.duration.average)
    }
    if let runtime = RuntimeText(seconds: seconds).formatted(.long) {
      rows.append(.init(id: "runtime.caption",
                        text: (item.isEpisodicType ? "MediaItem_EpisodeRuntime" : "MediaItem_Runtime").localized,
                        style: .caption))
      rows.append(.init(id: "runtime", text: runtime, style: .value))
    }

    // The best file the title has: its size and what class that is. A payload without
    // files (a listing, `nolinks`) still says what quality it advertises.
    if let best = item.detailFiles.max(by: { ($0.h, $0.w) < ($1.h, $1.w) }), best.w > 0, best.h > 0 {
      rows.append(.init(id: "resolution.caption", text: "MediaItem_SpecResolution".localized, style: .caption))
      rows.append(.init(id: "resolution", text: "\(best.w)×\(best.h)",
                        badges: qualityBadge(for: item).map { [$0] } ?? [], style: .value))
    } else if let quality = item.qualityDisplay {
      rows.append(.init(id: "resolution.caption", text: "MediaItem_SpecQuality".localized, style: .caption))
      rows.append(.init(id: "resolution", text: quality, badges: qualityBadge(for: item).map { [$0] } ?? [], style: .value))
    }

    // The two flags kino.pub raises about a release, said where the video is.
    for (index, advisory) in mediaItemAdvisories(item).enumerated() {
      rows.append(.init(id: "advisory.\(index)", text: advisory,
                        leading: .symbol("exclamationmark.triangle"), style: .detail))
    }
    guard !rows.isEmpty else { return nil }
    return TVPageInfoCard.Spec(id: "video", symbol: "play.fill", title: "MediaItem_SpecVideo".localized, rows: rows)
  }

  private static func qualityBadge(for item: MediaItem) -> String? {
    let caps = MediaCapabilityBadges.from(item: item)
    if caps.is4K { return "4K" }
    if caps.isHD { return "HD" }
    return item.qualityDisplay == nil ? nil : "SD"
  }

  /// Languages in the viewer's order. The ones they read stay open with what dubs them;
  /// the rest fold into "N more languages" (`LanguageListVisibility`, the one rule).
  private static func audioSpec(_ input: Input) -> TVPageInfoCard.Spec? {
    let item = input.mediaItem
    let groups = item.audioLanguageGroups(preferredLanguages: input.preferredLanguages)
    guard !groups.isEmpty else { return nil }
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
                        leading: Emoji.languageFlag(group.key).map { .emoji($0) }, style: .language))
      rows.append(contentsOf: dubs)
    }
    if partition.hiddenCount > 0 {
      rows.append(moreLanguagesRow(partition.hiddenCount, id: "audio.more"))
    }
    return TVPageInfoCard.Spec(id: "audio", symbol: "waveform", title: "Audio".localized, rows: rows)
  }

  /// One line per kind of dub within a language, under it: the kind says itself by its
  /// glyph — ✓ a studio dub, three heads a multi-voice, two a two-voice, one a single voice.
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
      // A studio dub names itself ("Dubbed: Mosfilm"); the voice kinds are the glyph.
      let text: String
      switch (rank, studios.isEmpty) {
      case (0, false): text = "\(kind): \(studios.joined(separator: ", "))"
      case (_, false): text = studios.joined(separator: ", ")
      default: text = kind
      }
      return .init(id: "audio.\(language).\(rank)", text: text, leading: .symbol(dubSymbol(rank)), style: .detail)
    }
  }

  private static func dubSymbol(_ rank: Int) -> String {
    switch rank {
    case 0: return "checkmark"
    case 1: return "person.3.fill"
    case 2: return "person.2.fill"
    default: return "person.fill"
    }
  }

  private static func subtitlesSpec(_ input: Input) -> TVPageInfoCard.Spec? {
    let item = input.mediaItem
    let groups = item.subtitleLanguageGroups(preferredLanguages: input.preferredLanguages)
    guard !groups.isEmpty else { return nil }
    let tracks = SubtitleTracks.sort(item.detailSubtitleTracks, preferredLanguages: input.preferredLanguages)
    let tracksByLanguage = Dictionary(grouping: tracks) { SubtitleTracks.languageKey($0.lang) }

    let partition = visibleLanguages(groups, input)
    var rows: [TVPageInfoCard.Spec.Row] = []
    for group in partition.visible {
      let own = tracksByLanguage[group.key] ?? []
      // kino.pub does not tell a hard-of-hearing track from a translated one, so a track
      // is "CC" when its own name says so and nothing more is claimed (see `LanguagesCard`).
      rows.append(.init(id: "subtitles.\(group.key)", text: group.name,
                        secondary: own.contains(where: \.isForced) ? "Forced".localized : nil,
                        badges: own.contains(where: \.isCC) ? ["CC"] : [],
                        leading: Emoji.languageFlag(group.key).map { .emoji($0) }, style: .language))
    }
    if partition.hiddenCount > 0 {
      rows.append(moreLanguagesRow(partition.hiddenCount, id: "subtitles.more"))
    }
    return TVPageInfoCard.Spec(id: "subtitles", symbol: "captions.bubble", title: "Subtitles".localized, rows: rows)
  }

  private static func visibleLanguages(_ groups: [MediaLanguageGroup], _ input: Input)
  -> (visible: [MediaLanguageGroup], hiddenCount: Int) {
    input.showsEveryLanguage
      ? (groups, 0)
      : LanguageListVisibility.partition(groups, preferredLanguages: input.preferredLanguages)
  }

  private static func moreLanguagesRow(_ count: Int, id: String) -> TVPageInfoCard.Spec.Row {
    let unit: String
    switch localizedPluralForm(count) {
    case 0: unit = "MediaItem_UnitLanguageOne".localized
    case 1: unit = "MediaItem_UnitLanguageFew".localized
    default: unit = "MediaItem_UnitLanguageMany".localized
    }
    return .init(id: id, text: String(format: "MediaItem_SpecMoreLanguages".localized, "\(count)", unit),
                 style: .more)
  }
}
#endif
