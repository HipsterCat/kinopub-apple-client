//
//  Routes.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 31.07.2023.
//

import Foundation
import KinoPubBackend
import KinoPubMetadata

/// Single destination vocabulary for every tab stack. Stacks stay per-tab; the
/// cases and `Equatable`/`Hashable` rules are shared so deep links and Back titles
/// do not need five parallel mappings.
enum Route: Hashable {
  case details(MediaItem)
  /// Watching endpoints / cards often carry only an id and artwork.
  case detailsById(Int)
  /// Same title page as `detailsById`, without `.navigationTransition(.zoom)`.
  /// Home banner taps have no matched source of their own; zooming from a shelf
  /// poster behind the banner produced `CVPixelBufferCreate … -6680` (250×375 RGBA)
  /// on iPhone Duo (Sasha, 2026-11-26).
  case detailsFromBanner(Int)
  case history
  case bookmark(Bookmark)
  case seasons([Season])
  case season(Season)
  case person(MediaPerson)
  /// The token is minted where the route value is created, so one push of an episode
  /// is one request instance: a destination re-evaluated while its route is leaving
  /// carries the same token (and must not re-arm playback), while a fresh tap on the
  /// same episode mints a new one (and must). See `PlaybackSession`.
  case player(any PlayableItem, token: UUID)
  case trailerPlayer(any PlayableItem, token: UUID)
  /// A TV channel's live stream in the same system player — no resume, no Up Next, no
  /// episodes, nothing reported to the watching history (`WatchMode.live`).
  case livePlayer(TVChannel, token: UUID)
  /// The curated-collections browser (`GET /v1/collections`).
  case collections
  /// One collection's full item grid (`GET /v1/collections/view`).
  case collection(Collection)
  /// One Home shelf ("Hot Movies", "Fresh Series", …) opened as its own full,
  /// paginated grid — the shelf's "see all". `title` carries the already-localized
  /// row name so the pushed page and the row header read identically.
  case shortcutItems(MediaShortcut, MediaType, title: String)
  /// A Home filter shelf (`/v1/items`) opened as its own paginated grid.
  case filteredShelf(LibraryFilter, title: String)
  /// Continue Watching past the row's cap, same ranking, its own page.
  case continueWatching
  /// The followed serials in full, pushed from the Library's Watchlist row.
  case watchlist
  /// Every bookmark folder as a tile, pushed from the Library's Collections row.
  case bookmarkFolders([Bookmark])
  /// A detail page's Ratings and Reviews block, opened in full.
  case ratingsAndReviews(RatingsAndReviews)
  /// A detail page's cast rail, opened as the full cast & crew company.
  case castAndCrew(CastAndCrew)

  var isPlayerRoute: Bool {
    switch self {
    case .player, .trailerPlayer, .livePlayer: true
    default: false
    }
  }

  /// The title a details route opens, whichever way it carries it.
  var detailsItemID: Int? {
    switch self {
    case .details(let item): item.id
    case .detailsById(let id), .detailsFromBanner(let id): id
    default: nil
    }
  }

  func hash(into hasher: inout Hasher) {
    switch self {
    case .details(let item):
      hasher.combine(0)
      hasher.combine(item)
    case .detailsById(let id):
      hasher.combine(1)
      hasher.combine(id)
    case .detailsFromBanner(let id):
      // Same destination identity as `detailsById` — zoom is presentation only.
      hasher.combine(1)
      hasher.combine(id)
    case .history:
      hasher.combine(2)
    case .bookmark(let bookmark):
      hasher.combine(3)
      hasher.combine(bookmark)
    case .seasons(let seasons):
      hasher.combine(4)
      hasher.combine(seasons)
    case .season(let season):
      hasher.combine(5)
      hasher.combine(season)
    case .person(let person):
      hasher.combine(6)
      hasher.combine(person)
    case .player(let item, let token):
      hasher.combine(7)
      hasher.combine(item.id)
      hasher.combine(token)
    case .trailerPlayer(let item, let token):
      hasher.combine(8)
      hasher.combine(item.id)
      hasher.combine(token)
    case .livePlayer(let channel, let token):
      hasher.combine(13)
      hasher.combine(channel.id)
      hasher.combine(token)
    case .collections:
      hasher.combine(9)
    case .collection(let collection):
      hasher.combine(10)
      hasher.combine(collection)
    case .shortcutItems(let shortcut, let type, let title):
      hasher.combine(11)
      hasher.combine(shortcut)
      hasher.combine(type)
      hasher.combine(title)
    case .ratingsAndReviews(let payload):
      hasher.combine(12)
      hasher.combine(payload)
    case .castAndCrew(let payload):
      hasher.combine(18)
      hasher.combine(payload)
    case .filteredShelf(let filter, let title):
      hasher.combine(14)
      hasher.combine(filter)
      hasher.combine(title)
    case .continueWatching:
      hasher.combine(15)
    case .watchlist:
      hasher.combine(16)
    case .bookmarkFolders(let folders):
      hasher.combine(17)
      hasher.combine(folders)
    }
  }

  static func == (lhs: Route, rhs: Route) -> Bool {
    switch (lhs, rhs) {
    case (.details(let a), .details(let b)):
      return a == b
    case (.detailsById(let a), .detailsById(let b)),
         (.detailsFromBanner(let a), .detailsFromBanner(let b)),
         (.detailsById(let a), .detailsFromBanner(let b)),
         (.detailsFromBanner(let a), .detailsById(let b)):
      return a == b
    case (.history, .history):
      return true
    case (.bookmark(let a), .bookmark(let b)):
      return a == b
    // By id: a watched mark changed since the push is not another destination.
    case (.seasons(let a), .seasons(let b)):
      return a.map(\.id) == b.map(\.id)
    case (.season(let a), .season(let b)):
      return a.id == b.id
    case (.person(let a), .person(let b)):
      return a == b
    case (.player(let a, let at), .player(let b, let bt)):
      return a.id == b.id && at == bt
    case (.trailerPlayer(let a, let at), .trailerPlayer(let b, let bt)):
      return a.id == b.id && at == bt
    case (.livePlayer(let a, let at), .livePlayer(let b, let bt)):
      return a.id == b.id && at == bt
    case (.collections, .collections):
      return true
    case (.collection(let a), .collection(let b)):
      return a == b
    case (.shortcutItems(let a, let at, let atitle), .shortcutItems(let b, let bt, let btitle)):
      return a == b && at == bt && atitle == btitle
    case (.ratingsAndReviews(let a), .ratingsAndReviews(let b)):
      return a == b
    case (.castAndCrew(let a), .castAndCrew(let b)):
      return a == b
    case (.filteredShelf(let a, let atitle), .filteredShelf(let b, let btitle)):
      return a == b && atitle == btitle
    case (.watchlist, .watchlist):
      return true
    case (.bookmarkFolders(let a), .bookmarkFolders(let b)):
      return a == b
    case (.continueWatching, .continueWatching):
      return true
    default:
      return false
    }
  }
}

/// Everything the Ratings and Reviews page needs, already loaded.
///
/// A payload struct rather than seven associated values, and **not** `TitleMetadata`
/// itself: the route has to be `Hashable`, and making the whole merged-metadata type
/// conform would drag a dozen models into it that have no reason to be comparable.
/// Only the fields the page renders travel.
struct RatingsAndReviews: Hashable {
  let item: MediaItem
  let reviews: [Review]
  let summary: ReviewsSummary?
  let tmdbRating: Double?
  let tmdbVotes: Int?
  /// Trakt, Rotten Tomatoes, Metacritic, Letterboxd, MyAnimeList.
  let externalRatings: [ExternalRating]
  let tmdbID: Int?
  let linkedIMDb: String?
  /// Trakt: how its votes fall, what its users do, what its reviews praise and fault.
  let traktDistribution: [Int: Int]
  let audienceStats: AudienceStats?
  let reviewInsights: ReviewInsights?
  let doubanStats: DoubanStats?
  let myShowsStats: MyShowsStats?
  let relayedIMDbRating: Double?
  let relayedIMDbVotes: Int?
  let hasAfterCreditsScene: Bool?
  let hasDuringCreditsScene: Bool?
  let likeCount: Int
  let dislikeCount: Int
  /// Which side the page opens on: the section's title opens all of it, the viewers' and
  /// critics' cards their own (Sasha, 2026-11-09).
  var tab: RatingsTab = .all

  init(item: MediaItem,
       metadata: TitleMetadata,
       likeCount: Int,
       dislikeCount: Int,
       tab: RatingsTab = .all) {
    self.tab = tab
    self.item = item
    self.reviews = metadata.reviews
    self.summary = metadata.reviewsSummary
    self.tmdbRating = metadata.tmdbRating
    self.tmdbVotes = metadata.tmdbVotes
    self.externalRatings = metadata.externalRatings
    self.tmdbID = metadata.tmdbId
    self.linkedIMDb = metadata.linkedIMDb
    self.traktDistribution = metadata.traktDistribution
    self.audienceStats = metadata.audienceStats
    self.reviewInsights = metadata.reviewInsights
    self.doubanStats = metadata.doubanStats
    self.myShowsStats = metadata.myShowsStats
    self.relayedIMDbRating = metadata.relayedIMDbRating
    self.relayedIMDbVotes = metadata.relayedIMDbVotes
    self.hasAfterCreditsScene = metadata.hasAfterCreditsScene
    self.hasDuringCreditsScene = metadata.hasDuringCreditsScene
    self.likeCount = likeCount
    self.dislikeCount = dislikeCount
  }

  /// The zoom source a summary card marks and its tab's page grows out of (iPhone, iPad).
  static func zoomSourceID(item: Int, tab: RatingsTab) -> String {
    "ratings-\(item)-\(tab.rawValue)"
  }

  /// The slice of `TitleMetadata` the ratings card and review cards read, rebuilt on
  /// the far side of the route.
  var metadata: TitleMetadata {
    var meta = TitleMetadata()
    meta.reviews = reviews
    meta.reviewsSummary = summary
    meta.tmdbRating = tmdbRating
    meta.tmdbVotes = tmdbVotes
    meta.externalRatings = externalRatings
    meta.tmdbId = tmdbID
    meta.linkedIMDb = linkedIMDb
    meta.traktDistribution = traktDistribution
    meta.audienceStats = audienceStats
    meta.reviewInsights = reviewInsights
    meta.doubanStats = doubanStats
    meta.myShowsStats = myShowsStats
    meta.relayedIMDbRating = relayedIMDbRating
    meta.relayedIMDbVotes = relayedIMDbVotes
    meta.hasAfterCreditsScene = hasAfterCreditsScene
    meta.hasDuringCreditsScene = hasDuringCreditsScene
    return meta
  }
}

/// The Ratings and Reviews page's tabs.
enum RatingsTab: String, CaseIterable, Hashable, Identifiable {
  case all, viewers, critics

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all: "All".localized
    case .viewers: "MediaItem_SummaryViewers".localized
    case .critics: "MediaItem_SummaryCritics".localized
    }
  }
}


/// Everything the Cast & Crew page needs, already loaded from the title's metadata.
struct CastAndCrew: Hashable {
  let item: MediaItem
  let cast: [CastMember]
  let crew: [CastMember]
  var tab: CastAndCrewTab = .all

  /// One row on the page — person identity for navigation plus the lines under the name.
  struct Entry: Hashable, Identifiable {
    let id: String
    let person: MediaPerson
    let roleLine: String?
    let episodeLine: String?

    func matches(_ needle: String) -> Bool {
      let q = needle.lowercased()
      if person.name.lowercased().contains(q) { return true }
      if let roleLine, roleLine.lowercased().contains(q) { return true }
      return false
    }
  }

  /// A titled block on the page — starring / other cast, or one TMDB crew department.
  struct Section: Hashable, Identifiable {
    let id: String
    let title: String
    let rows: [Entry]

    var titleWithCount: String {
      guard !rows.isEmpty else { return title }
      return "\(title) (\(rows.count.formatted(.number.grouping(.automatic))))"
    }
  }

  /// kino.pub's billed names plus everyone TMDB listed, then the crew.
  static func make(item: MediaItem, metadata: TitleMetadata,
                   tab: CastAndCrewTab = .all) -> CastAndCrew {
    let listed = TitleMetadata.enrich(names: item.castMembers, roleDepartment: "Acting",
                                      from: metadata)
    let cast = listed + CastRanking.unlisted(metadata.cast, besides: listed)
    return CastAndCrew(item: item, cast: cast, crew: metadata.crew, tab: tab)
  }

  func entry(for member: CastMember, role: MediaPerson.Role, index: Int) -> Entry {
    let photo = member.photo ?? ActorImageProvider.photoURL(for: member.name)
    let person = MediaPerson.from(member, role: role, photoURL: photo,
                                  sourceItemID: item.id)
    let roleLine = member.character?.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleaned = (roleLine?.isEmpty == false) ? roleLine : nil
    let episodes: String?
    if let count = member.episodeCount, count > 0 {
      episodes = localizedEpisodeCount(count)
    } else {
      episodes = nil
    }
    // Never `MediaPerson.id` (`director:name`) alone — one person can hold several
    // credits; index makes every row unique for `ForEach`.
    let personKey = member.tmdbPersonId.map(String.init) ?? member.name
    let id = [
      role.rawValue,
      personKey,
      member.department ?? "",
      cleaned ?? "",
      String(index)
    ].joined(separator: "|")
    return Entry(id: id, person: person, roleLine: cleaned, episodeLine: episodes)
  }

  /// The same people the title page's rail shows (`CastRanking.ranked`): `make` puts
  /// kino.pub's names first.
  private var starringCast: [CastMember] {
    let listedCount = min(item.castMembers.count, cast.count)
    return CastRanking.ranked(listed: Array(cast.prefix(listedCount)),
                              others: Array(cast.dropFirst(listedCount)),
                              isEpisodic: item.isEpisodicType)
  }

  private var starringIDs: Set<String> {
    var ids = Set(starringCast.compactMap(\.tmdbPersonId).map(String.init))
    ids.formUnion(starringCast.map { TitleMetadata.normalize($0.name) })
    return ids
  }

  private func isStarring(_ member: CastMember) -> Bool {
    if let id = member.tmdbPersonId, starringIDs.contains(String(id)) { return true }
    return starringIDs.contains(TitleMetadata.normalize(member.name))
  }

  var starringPeople: [Entry] {
    starringCast.enumerated().map { entry(for: $0.element, role: .actor, index: $0.offset) }
  }

  var otherCastPeople: [Entry] {
    cast.enumerated().compactMap { index, member in
      guard !isStarring(member) else { return nil }
      return entry(for: member, role: .actor, index: index)
    }
  }

  var castPeople: [Entry] { starringPeople + otherCastPeople }

  var crewPeople: [Entry] {
    crew.enumerated().map { entry(for: $0.element, role: .director, index: $0.offset) }
  }

  var allPeople: [Entry] { castPeople + crewPeople }

  /// Cast blocks: «В главных ролях» then «Другие участники». Empty ones omitted.
  func castSections(matching query: String = "") -> [Section] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    func filtered(_ rows: [Entry]) -> [Entry] {
      guard !needle.isEmpty else { return rows }
      return rows.filter { $0.matches(needle) }
    }
    var sections: [Section] = []
    let starring = filtered(starringPeople)
    if !starring.isEmpty {
      sections.append(Section(id: "cast.starring",
                              title: "MediaItem_CastSectionStarring".localized,
                              rows: starring))
    }
    let others = filtered(otherCastPeople)
    if !others.isEmpty {
      sections.append(Section(id: "cast.other",
                              title: "MediaItem_CastSectionOther".localized,
                              rows: others))
    }
    return sections
  }

  /// Crew blocks by TMDB department — Sasha's labels (Art → Writing order); «Ещё» catches
  /// Crew / Lighting / Visual Effects / blank / anything else.
  func crewSections(matching query: String = "") -> [Section] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    var buckets: [CrewDepartment: [Entry]] = [:]
    for (index, member) in crew.enumerated() {
      let row = entry(for: member, role: .director, index: index)
      if !needle.isEmpty, !row.matches(needle) { continue }
      buckets[CrewDepartment.classify(member), default: []].append(row)
    }
    return CrewDepartment.allCases.compactMap { department in
      guard let rows = buckets[department], !rows.isEmpty else { return nil }
      return Section(id: "crew.\(department.rawValue)",
                     title: department.title,
                     rows: rows)
    }
  }

  func sections(for tab: CastAndCrewTab, matching query: String = "") -> [Section] {
    switch tab {
    case .all: castSections(matching: query) + crewSections(matching: query)
    case .cast: castSections(matching: query)
    case .crew: crewSections(matching: query)
    }
  }
}

/// Top-level Cast & Crew tabs — All / Cast / Crew. Subsections live inside the page.
enum CastAndCrewTab: String, CaseIterable, Hashable, Identifiable {
  case all, cast, crew

  var id: String { rawValue }

  func title(count: Int) -> String {
    let label: String
    switch self {
    case .all: label = "All".localized
    case .cast: label = "MediaItem_CastTabCast".localized
    case .crew: label = "MediaItem_CastTabCrew".localized
    }
    guard count > 0 else { return label }
    return "\(label) (\(count.formatted(.number.grouping(.automatic))))"
  }

  func people(in payload: CastAndCrew) -> [CastAndCrew.Entry] {
    switch self {
    case .all: payload.allPeople
    case .cast: payload.castPeople
    case .crew: payload.crewPeople
    }
  }
}

/// TMDB crew departments as section headers under «Съёмочный состав».
/// Order matches Sasha's list (Art → … → Writing); unknown departments fold into `.other`.
enum CrewDepartment: String, CaseIterable, Hashable {
  case art
  case camera
  case costume
  case other
  case directing
  case editing
  case production
  case sound
  case writing

  var title: String {
    switch self {
    case .art: "MediaItem_CrewDeptArt".localized
    case .camera: "MediaItem_CrewDeptCamera".localized
    case .costume: "MediaItem_CrewDeptCostume".localized
    case .other: "MediaItem_CrewDeptOther".localized
    case .directing: "MediaItem_CrewDeptDirecting".localized
    case .editing: "MediaItem_CrewDeptEditing".localized
    case .production: "MediaItem_CrewDeptProduction".localized
    case .sound: "MediaItem_CrewDeptSound".localized
    case .writing: "MediaItem_CrewDeptWriting".localized
    }
  }

  static func classify(_ member: CastMember) -> CrewDepartment {
    let raw = (member.department ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    switch raw.lowercased() {
    case "art": return .art
    case "camera": return .camera
    case "costume & make-up", "costume and make-up", "costume": return .costume
    case "directing": return .directing
    case "editing": return .editing
    case "production": return .production
    case "sound": return .sound
    case "writing": return .writing
    case "crew": return .other
    default: return .other
    }
  }
}

/// Legacy names kept as aliases so call sites migrate without five duplicate enums.
typealias MainRoutes = Route
typealias CatalogRoutes = Route
typealias SearchRoutes = Route
typealias BookmarksRoutes = Route
typealias DownloadsRoutes = Route

// MARK: - Backdrop (tvOS)

/// What a route puts in the app's one backdrop (`PageBackdropStage`). The stage follows
/// the selected tab's path, so this is the whole rule for which picture is behind which page.
enum RouteBackdrop: Equatable {
  /// This title's picture, under this key — the same key the title's page publishes under.
  case picture(String)
  /// No picture: the backdrop fades out while this page is in front.
  case none
  /// Over the page beneath it, which keeps its picture (the player).
  case passThrough
}

extension Route {
  static func backdropKey(itemID: Int) -> String { "media-item-\(itemID)" }

  var backdrop: RouteBackdrop {
    switch self {
    case .details(let item): .picture(Self.backdropKey(itemID: item.id))
    case .detailsById(let id), .detailsFromBanner(let id):
      .picture(Self.backdropKey(itemID: id))
    // A title's own sub-page stays on the title's picture.
    case .ratingsAndReviews(let block): .picture(Self.backdropKey(itemID: block.item.id))
    case .castAndCrew(let block): .picture(Self.backdropKey(itemID: block.item.id))
    case .player, .trailerPlayer, .livePlayer: .passThrough
    default: .none
    }
  }

  /// The key in front for a path: its topmost route that is not see-through.
  static func backdropFront(of path: [Route]) -> String? {
    for route in path.reversed() {
      switch route.backdrop {
      case .picture(let key): return key
      case .none: return nil
      case .passThrough: continue
      }
    }
    return nil
  }

  static func backdropKeys(in path: [Route]) -> Set<String> {
    Set(path.compactMap { route in
      if case .picture(let key) = route.backdrop { return key }
      return nil
    })
  }
}

