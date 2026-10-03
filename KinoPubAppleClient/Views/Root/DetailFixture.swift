#if DEBUG && os(tvOS)
//
//  DetailFixture.swift
//  KinoPubAppleClient
//
//  DEBUG, tvOS. `-KINOPUBDetailFixture <name>` makes the app root a stack of fixture
//  titles, opened at the one named, with local stand-ins for the API, TMDB and the
//  player. The detail page itself is the real one — this only replaces what it talks
//  to — so `TVDetailPageUITests` can walk it with the remote on a simulator with no
//  session: focus on coming back from the player, episodes kino.pub does not have,
//  films in several versions.
//
//  The stand-in player writes "watched to the end" for what it was handed and does
//  nothing else; Menu leaves it, the way it leaves the real one.
//

import Foundation
import SwiftUI
import KinoPubBackend
import KinoPubMetadata
import KinoPubUI

enum DetailFixture: String, CaseIterable, Identifiable {
  /// One episode short of caught up (S2E4 unwatched); TMDB has S2E5 nine days out.
  /// Play, watch, come back: Follow is the main button and has focus.
  case awaiting
  /// Caught up on everything kino.pub has; TMDB lists eight more episodes of the same
  /// season in every state one can be in — aired long ago, 3 / 2 / 1 / 0 days ago,
  /// ahead, far ahead, undated. Follow leads: the next one has a date (in the past).
  case missing
  /// A film in two named versions, the first one half-watched.
  case versions
  /// A film in three unnamed versions.
  case versionsUnnamed
  /// A finished series watched to the end: Replay leads, and keeps the focus.
  case rewatch

  var id: String { rawValue }

  static var isActive: Bool { DebugLaunch.detailFixture != nil }

  static var launched: DetailFixture? {
    DebugLaunch.detailFixture.flatMap(DetailFixture.init(rawValue:))
  }

  var itemID: Int {
    switch self {
    case .awaiting: 9_900_001
    case .missing: 9_900_002
    case .versions: 9_900_003
    case .versionsUnnamed: 9_900_004
    case .rewatch: 9_900_005
    }
  }

  var title: String {
    switch self {
    case .awaiting: "Ожидание новой серии / Awaiting the Next Episode"
    case .missing: "Нет на KinoPub / Missing Episodes"
    case .versions: "Две версии / Two Versions"
    case .versionsUnnamed: "Версии без названий / Unnamed Versions"
    case .rewatch: "Пересмотр / Rewatch"
    }
  }

  private var isSeries: Bool {
    switch self {
    case .awaiting, .missing, .rewatch: true
    case .versions, .versionsUnnamed: false
    }
  }

  // MARK: - kino.pub payload

  /// Decoded fresh on every call, from the same JSON shape `/v1/items/{id}` answers
  /// with: episodes are classes the page writes progress into, and a second fetch must
  /// not hand back the first one's.
  func makeItem() -> MediaItem {
    var json: [String: Any] = [
      "id": itemID,
      "type": isSeries ? "serial" : "movie",
      "subtype": isSeries ? "" : "multi",
      "title": title,
      "year": 2024,
      "cast": "Анна Петрова, Иван Смирнов",
      "director": "Мария Иванова",
      "genres": [Any](),
      "countries": [Any](),
      "duration": ["average": 2400, "total": 2400],
      "langs": 2,
      "quality": 1080,
      "plot": "Тестовый тайтл для UI-тестов страницы деталей: главная кнопка и фокус, серии, которых нет на KinoPub, версии фильма.",
      "imdb": itemID,
      "imdb_rating": 7.9,
      "kinopoisk_rating": 7.4,
      "posters": ["small": "", "medium": "", "big": "", "wide": ""],
      "finished": false,
      "in_watchlist": false,
      "subscribed": false
    ]
    switch self {
    case .awaiting:
      json["seasons"] = [
        season(1, episodes: (1...3).map { episode(season: 1, number: $0, watched: true) }),
        season(2, episodes: (1...4).map { episode(season: 2, number: $0, watched: $0 < 4) })
      ]
    case .missing:
      json["seasons"] = [
        season(1, episodes: (1...2).map { episode(season: 1, number: $0, watched: true) })
      ]
    case .versions:
      json["videos"] = [
        video(number: 1, title: "24 fps", position: 1800),
        video(number: 2, title: "48 fps", position: 0)
      ]
    case .versionsUnnamed:
      json["videos"] = (1...3).map { video(number: $0, title: "", position: 0) }
    case .rewatch:
      json["finished"] = true
      json["seasons"] = [
        season(1, episodes: (1...3).map { episode(season: 1, number: $0, watched: true) })
      ]
    }
    do {
      let data = try JSONSerialization.data(withJSONObject: json)
      return try JSONDecoder().decode(MediaItem.self, from: data)
    } catch {
      fatalError("DetailFixture.\(rawValue) does not decode: \(error)")
    }
  }

  private func season(_ number: Int, episodes: [[String: Any]]) -> [String: Any] {
    ["id": itemID * 10 + number, "title": "", "number": number,
     "watching": ["status": 0], "episodes": episodes]
  }

  private func episode(season: Int, number: Int, watched: Bool) -> [String: Any] {
    ["id": itemID * 1000 + season * 100 + number,
     "title": "Серия \(number)",
     "thumbnail": "",
     "duration": 2400,
     "tracks": 1,
     "number": number,
     "ac3": 0,
     "audios": [Any](),
     "watched": watched ? 1 : 0,
     "watching": ["status": watched ? 1 : -1, "time": watched ? 2400 : 0],
     "subtitles": [Any](),
     "files": [Any]()]
  }

  private func video(number: Int, title: String, position: Int) -> [String: Any] {
    ["id": itemID * 10 + number,
     "title": title,
     "thumbnail": "",
     "duration": 6000,
     "tracks": 1,
     "number": number,
     "ac3": 0,
     "audios": [Any](),
     "watched": 0,
     "watching": ["status": position > 0 ? 0 : -1, "time": position],
     "subtitles": [Any](),
     "files": [Any]()]
  }

  // MARK: - TMDB

  /// What TMDB says about the title, dated from today.
  var metadata: TitleMetadata {
    var meta = TitleMetadata()
    meta.attribution = [.tmdb]
    switch self {
    case .awaiting:
      meta.status = "Returning Series"
      meta.seasonSummaries = [SeasonSummary(seasonNumber: 1, episodeCount: 3),
                              SeasonSummary(seasonNumber: 2, episodeCount: 6)]
      meta.nextEpisode = EpisodeRef(seasonNumber: 2, episodeNumber: 5, airDate: Self.day(9))
    case .missing:
      meta.status = "Returning Series"
      meta.seasonSummaries = [SeasonSummary(seasonNumber: 1, episodeCount: 10)]
      meta.nextEpisode = EpisodeRef(seasonNumber: 1, episodeNumber: 8, airDate: Self.day(2))
    case .rewatch:
      meta.status = "Ended"
      meta.seasonSummaries = [SeasonSummary(seasonNumber: 1, episodeCount: 3)]
    case .versions, .versionsUnnamed:
      break
    }
    return meta
  }

  func schedule(season: Int) -> [EpisodeSchedule] {
    let days: [Int?]
    switch (self, season) {
    case (.awaiting, 1): days = [-120, -113, -106]
    case (.awaiting, 2): days = [-30, -23, -16, -9, 9, nil]
    // E1–E2 on kino.pub; E3 aired long ago; E4…E7 three days ago to today; E8 in two
    // days, E9 in twenty; E10 undated.
    case (.missing, 1): days = [-514, -507, -500, -3, -2, -1, 0, 2, 20, nil]
    case (.rewatch, 1): days = [-400, -393, -386]
    default: return []
    }
    return days.enumerated().map { index, day in
      EpisodeSchedule(episodeNumber: index + 1,
                      seasonNumber: season,
                      name: "Серия \(index + 1)",
                      airDate: day.map(Self.day))
    }
  }

  private static func day(_ offset: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
  }

  // MARK: - Services

  /// The app's context with the API, TMDB and the account actions swapped for local
  /// ones. Everything else — stores, player session, downloads — is the real thing.
  static func context(replacingServicesOf base: AppContext) -> AppContext {
    var context = base
    context.contentService = VideoContentServiceMock(details: { id in
      DetailFixture.allCases.first { $0.itemID == id }?.makeItem()
    })
    context.actionsService = UserActionsServiceMock()
    context.collectionsService = CollectionsServiceMock()
    context.metadataService = MetadataService(sources: [DetailFixtureMetadataSource()])
    return context
  }
}

/// TMDB, as far as the fixtures need it.
struct DetailFixtureMetadataSource: MetadataSource {
  var id: MetadataSourceID { .tmdb }
  var isConfigured: Bool { true }

  func titleMetadata(for identity: MediaIdentity) async throws -> TitleMetadata? {
    DetailFixture.allCases.first { $0.itemID == identity.kinopubId }?.metadata
  }

  func schedule(for identity: MediaIdentity, season: Int) async throws -> [EpisodeSchedule] {
    DetailFixture.allCases.first { $0.itemID == identity.kinopubId }?.schedule(season: season) ?? []
  }
}

// MARK: - Root

/// The fixture titles as a list, on a stack of its own, opened at the launched one.
struct DetailFixtureRoot: View {
  @State private var path: [Route] = []

  var body: some View {
    NavigationStack(path: $path) {
      VStack(alignment: .leading, spacing: 24) {
        ForEach(DetailFixture.allCases) { fixture in
          Button(fixture.title) {
            path.append(.details(fixture.makeItem()))
          }
          .accessibilityIdentifier("kinopub.fixture.\(fixture.rawValue)")
        }
      }
      .padding(80)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .appRouteDestinations()
    }
    // What the real tabs hand down (`TabsNavigationView`): the same rails, and the hook
    // the TVUIKit ones push through rather than a `NavigationLink`.
    .environment(\.usesTVUIKitPosters, FeatureFlags.tvUIKitPosters)
    .environment(\.mediaNavigation) { value in
      if let route = value as? Route {
        path.append(route)
      }
    }
    .task {
      guard path.isEmpty, let start = DetailFixture.launched else { return }
      path = [.details(start.makeItem())]
    }
  }
}

// MARK: - Player

/// Stands in for the player: records what it was handed as watched to the end, the way
/// the real one does at the credits, and waits for Menu.
struct DetailFixturePlayer: View {
  let item: any PlayableItem
  let mode: WatchMode

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      // Something focusable, so Menu has a responder to travel up from.
      Button(caption) {}
        .accessibilityIdentifier("kinopub.fixture.player")
    }
    .onAppear(perform: finish)
  }

  private var caption: String {
    let meta = item.metadata
    return "Fixture player · item \(meta.id) · season \(meta.season ?? 0) · video \(meta.video ?? 0)"
  }

  private func finish() {
    guard mode == .media else { return }
    let duration = (item as? Episode)?.duration ?? (item as? PlaybackVariant)?.duration ?? 3600
    AppContext.shared.localProgressStore.recordFinished(
      mediaId: item.metadata.id,
      duration: Double(duration),
      season: item.metadata.season,
      episode: item.metadata.video
    )
  }
}
#endif
