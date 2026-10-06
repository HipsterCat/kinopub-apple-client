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
//  The stand-in player writes "watched to the end" for what it was handed — locally, and
//  to the stand-in server, so the details call the page makes on coming back answers with
//  it the way kino.pub does after `marktime` — and does nothing else; Menu leaves it, the
//  way it leaves the real one.
//

import Foundation
import SwiftUI
import UIKit
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
  /// A film with every section under the hero populated — scores from every source,
  /// reviews, a director and a cast with faces, similar titles, stills, facts (one of
  /// them a spoiler), awards, collections, and audio and subtitles in several languages.
  /// All artwork is drawn locally (`DetailFixtureArt`), so the page needs no network.
  case film
  /// The same film with two directors and a long billing, kino.pub's order not TMDB's:
  /// some of the cast are the stars, some bit parts — the page ranks them and drops the rest.
  case filmCrew

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
    case .film: 9_900_006
    case .filmCrew: 9_900_007
    }
  }

  var title: String {
    switch self {
    case .awaiting: "Ожидание новой серии / Awaiting the Next Episode"
    case .missing: "Нет на KinoPub / Missing Episodes"
    case .versions: "Две версии / Two Versions"
    case .versionsUnnamed: "Версии без названий / Unnamed Versions"
    case .rewatch: "Пересмотр / Rewatch"
    case .film: "Фильм со всеми секциями / Every Section"
    case .filmCrew: "Фильм: два режиссёра / Two Directors"
    }
  }

  private var isSeries: Bool {
    switch self {
    case .awaiting, .missing, .rewatch: true
    case .versions, .versionsUnnamed, .film, .filmCrew: false
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
    case .film, .filmCrew:
      json["subtype"] = ""
      json["year"] = 2026
      json["cast"] = (self == .filmCrew ? Self.crewCast.map(\.name) : Self.filmCast.map(\.name)).joined(separator: ", ")
      json["director"] = self == .filmCrew ? "Энтони Руссо, Джо Руссо" : "Дестин Дэниел Креттон"
      json["genres"] = [["id": 4, "title": "Фантастика"], ["id": 2, "title": "Боевик"],
                        ["id": 8, "title": "Приключения"]]
      json["countries"] = [["id": 1, "title": "США"], ["id": 5, "title": "Великобритания"]]
      json["duration"] = ["average": 8400, "total": 8400]
      json["quality"] = 2160
      json["ac3"] = 1
      json["plot"] = "Питер Паркер возвращается в город, который забыл его имя. Чтобы вернуть себе жизнь, друзей и маску, ему придётся договориться с теми, кто давно перестал верить в героев, — и с тем, кто верит в них слишком сильно. Тестовое описание для проверки раскладки страницы деталей под героем: оценки, рецензии, люди, похожие, кадры, факты, теги и технические колонки."
      json["imdb_rating"] = 6.5
      json["kinopoisk_rating"] = 6.5
      json["imdb_votes"] = 1567
      json["kinopoisk_votes"] = 1034
      json["rating"] = 126
      json["rating_votes"] = 164
      json["views"] = 730_000
      json["posters"] = DetailFixtureArt.posters(seed: 0, label: "Новый день")
      json["videos"] = [filmVideo]
    }
    do {
      let data = try JSONSerialization.data(withJSONObject: json)
      return try JSONDecoder().decode(MediaItem.self, from: data)
    } catch {
      fatalError("DetailFixture.\(rawValue) does not decode: \(error)")
    }
  }

  /// The film's one video: a 4K file, original and dubbed audio in several languages,
  /// and subtitles — enough languages that both the audio and the subtitle columns have
  /// something to fold into "N more".
  private var filmVideo: [String: Any] {
    func audio(_ index: Int, _ lang: String, kind: Int, short: String, title: String,
               author: String? = nil) -> [String: Any] {
      var entry: [String: Any] = ["id": itemID * 100 + index, "index": index, "codec": "eac3",
                                  "channels": 6, "lang": lang,
                                  "type": ["id": kind, "title": title, "short_title": short]]
      if let author { entry["author"] = ["id": index + 10, "title": author] }
      return entry
    }
    func subtitle(_ lang: String, _ url: String = "") -> [String: Any] {
      ["lang": lang, "shift": 0, "embed": url.isEmpty, "url": url]
    }
    func file(_ quality: String, _ qualityID: Int, w: Int, h: Int, codec: String) -> [String: Any] {
      ["codec": codec, "w": w, "h": h, "quality": quality, "quality_id": qualityID,
       "url": ["http": "", "hls": "", "hls4": "", "hls2": ""]]
    }
    return ["id": itemID * 10 + 1,
            "title": "",
            "thumbnail": "",
            "duration": 8400,
            "tracks": 9,
            "number": 1,
            "ac3": 1,
            "audios": [
              audio(1, "eng", kind: 6, short: "Orig", title: "Оригинал"),
              audio(2, "rus", kind: 1, short: "DUB", title: "Дубляж", author: "Мосфильм"),
              audio(3, "rus", kind: 2, short: "MVO", title: "Многоголосый", author: "Кубик в Кубе"),
              audio(4, "rus", kind: 2, short: "MVO", title: "Многоголосый", author: "Пифагор"),
              audio(5, "rus", kind: 3, short: "DVO", title: "Двухголосый", author: "Кураж-Бамбей"),
              audio(6, "rus", kind: 4, short: "VO", title: "Одноголосый", author: "Гоблин"),
              audio(7, "rus", kind: 4, short: "VO", title: "Одноголосый", author: "А. Романов"),
              audio(8, "ukr", kind: 2, short: "MVO", title: "Многоголосый", author: "Так Треба"),
              audio(9, "deu", kind: 1, short: "DUB", title: "Дубляж"),
              audio(10, "fra", kind: 1, short: "DUB", title: "Дубляж"),
              audio(11, "spa", kind: 1, short: "DUB", title: "Дубляж"),
              audio(12, "ita", kind: 1, short: "DUB", title: "Дубляж")
            ],
            "watched": 0,
            "watching": ["status": -1, "time": 0],
            "subtitles": [
              subtitle("eng", "https://subs.example/film.eng.cc.srt"),
              subtitle("eng"),
              subtitle("rus", "https://subs.example/film.rus.forced.srt"),
              subtitle("ukr"), subtitle("deu"), subtitle("fra"), subtitle("spa"), subtitle("ita")
            ],
            "files": [
              file("2160p", 4, w: 3840, h: 1600, codec: "h265"),
              file("1080p", 3, w: 1920, h: 800, codec: "h264"),
              file("720p", 2, w: 1280, h: 534, codec: "h264")
            ]]
  }

  /// Billed cast for the `film` fixture; TMDB's side of the same list is `metadata`.
  fileprivate static let filmCast: [(name: String, character: String, episodes: Int?)] = [
    ("Том Холланд", "Питер Паркер", nil),
    ("Зендея", "Эм-Джей", nil),
    ("Джейкоб Баталон", "Нед Лидс", nil),
    ("Мариса Томей", "Тётя Мэй", nil),
    ("Джон Фавро", "Хэппи Хоган", nil),
    ("Бенедикт Камбербэтч", "Доктор Стрэндж", nil)
  ]

  /// Billed cast for the `filmCrew` fixture, in *kino.pub's* order. `order` is TMDB's: the
  /// stars have the low numbers, and the first two names kino.pub lists are bit parts.
  fileprivate static let crewCast: [(name: String, character: String, order: Int)] = [
    ("Эпизод Первый", "Прохожий", 41),
    ("Эпизод Второй", "Продавец", 37),
    ("Крис Эванс", "Стив Роджерс", 0),
    ("Роберт Дауни-мл.", "Тони Старк", 1),
    ("Скарлетт Йоханссон", "Наташа Романофф", 2),
    ("Марк Руффало", "Брюс Баннер", 3),
    ("Крис Хемсворт", "Тор", 4),
    ("Джереми Реннер", "Клинт Бартон", 5),
    ("Пол Радд", "Скотт Лэнг", 6),
    ("Дон Чидл", "Джеймс Роудс", 7),
    ("Эмили ВанКэмп", "Пеппер Поттс", 12),
    ("Джош Бролин", "Танос", 8),
    ("Карен Гиллан", "Небула", 9),
    ("Бенедикт Камбербэтч", "Доктор Стрэндж", 10),
    ("Том Холланд", "Питер Паркер", 11),
    ("Эпизод Третий", "Охранник", 55)
  ]

  /// The titles `fetchSimilar` answers with — drawn posters, each a different colour.
  static func similarItems() -> [MediaItem] {
    ["Возвращение домой", "Вспышка", "Человек-паук 2", "Лига справедливости", "Новый человек-паук 2",
     "Локи", "Дальше от дома", "Нет пути домой"].enumerated().map { index, name in
      posterItem(id: 9_901_000 + index, title: name, year: 2017 + index, seed: index + 1)
    }
  }

  /// A title on a shelf: enough of a payload to draw as a poster card.
  static func posterItem(id: Int, title: String, year: Int, seed: Int) -> MediaItem {
    let json: [String: Any] = [
      "id": id, "type": "movie", "subtype": "", "title": title, "year": year,
      "cast": "", "director": "", "genres": [Any](), "countries": [Any](),
      "duration": ["average": 7200, "total": 7200], "langs": 1, "quality": 1080, "plot": "",
      "kinopoisk_rating": 6.0 + Double(seed % 5) * 0.5, "kinopoisk_votes": 1200,
      "posters": DebugLaunch.fixtureRealArt
        ? ["small", "medium", "big", "wide"].reduce(into: [String: String]()) {
            $0[$1] = "https://m.staticpop.net/poster/item/big/\(10681 + seed).jpg"
          }
        : DetailFixtureArt.posters(seed: seed, label: title),
      "finished": false, "in_watchlist": false, "subscribed": false
    ]
    do {
      return try JSONDecoder().decode(MediaItem.self, from: JSONSerialization.data(withJSONObject: json))
    } catch {
      fatalError("DetailFixture poster item does not decode: \(error)")
    }
  }

  private func season(_ number: Int, episodes: [[String: Any]]) -> [String: Any] {
    ["id": itemID * 10 + number, "title": "", "number": number,
     "watching": ["status": 0], "episodes": episodes]
  }

  private func episode(season: Int, number: Int, watched seeded: Bool) -> [String: Any] {
    let watched = seeded || DetailFixtureServer.shared.isWatched(item: itemID, season: season, video: number)
    return ["id": itemID * 1000 + season * 100 + number,
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
    let watched = DetailFixtureServer.shared.isWatched(item: itemID, season: nil, video: number)
    return ["id": itemID * 10 + number,
            "title": title,
            "thumbnail": "",
            "duration": 6000,
            "tracks": 1,
            "number": number,
            "ac3": 0,
            "audios": [Any](),
            "watched": watched ? 1 : 0,
            "watching": ["status": watched ? 1 : (position > 0 ? 0 : -1), "time": watched ? 6000 : position],
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
    case .film, .filmCrew:
      meta.tmdbId = 9_906
      meta.tmdbRating = 6.5
      meta.tmdbVotes = 25
      meta.ageRating = "12+"
      if self == .filmCrew {
        meta.cast = Self.crewCast.enumerated().map { index, member in
          CastMember(name: member.name, character: member.character,
                     photo: DetailFixtureArt.avatar(seed: index + 1, label: member.name),
                     department: "Acting", tmdbPersonId: 200 + index, order: member.order)
        }
      } else {
        meta.cast = Self.filmCast.enumerated().map { index, member in
          CastMember(name: member.name, character: member.character,
                     photo: DetailFixtureArt.avatar(seed: index + 1, label: member.name),
                     department: "Acting", tmdbPersonId: 100 + index, episodeCount: member.episodes, order: index)
        }
      }
      meta.stills = (1...6).map { index in
        let still = DetailFixtureArt.still(seed: index, label: "Кадр \(index)")
        return StillImage(url: still, previewURL: still)
      }
      meta.facts = [
        Fact(text: "Во время съёмок Том Холланд получил сотрясение мозга, из-за чего вынужден был провести несколько дней в больнице. Съёмочный процесс приостановили на несколько дней."),
        Fact(text: "Для сцены на крыше построили декорацию в натуральную величину: она весила больше шести тонн и собиралась три недели."),
        Fact(text: "Режиссёр рассказал, что финал переснимали дважды, и это один из вариантов, которого зрители не увидят.", isSpoiler: true),
        Fact(text: "В фильме больше сотни отсылок к прежним частям — съёмочная группа вела их список прямо на площадке.")
      ]
      meta.reviews = [
        Review(author: "Арсений П.", title: "Крепкое возвращение",
               body: "Фильм держит темп с первых минут и не разменивается на лишние объяснения. Хорошая работа оператора, неплохой саундтрек и главное — живой герой, за которым интересно следить.",
               sentiment: "POSITIVE", date: "2026-07-18T21:51:09",
               postedAt: Date(timeIntervalSince1970: 1_784_400_000), helpfulVotes: 12, unhelpfulVotes: 2),
        Review(author: "Lintandil", title: "",
               body: "Красиво, шумно и местами бессмысленно. Первая половина работает, вторая тянется. Отдельное спасибо за второй план — актёры вытягивают сцену там, где сценарий сдаётся.",
               sentiment: "NEUTRAL", date: "2026-07-20T12:57:52",
               postedAt: Date(timeIntervalSince1970: 1_784_600_000), helpfulVotes: 7, unhelpfulVotes: 2),
        Review(author: "Мария К.", title: "Ожидала большего",
               body: "После трейлеров ждала другого. Эмоциональные сцены не складываются, шутки повторяются, а злодей остаётся набором реплик без мотивации.",
               sentiment: "NEGATIVE", date: "2026-07-22T09:12:40",
               postedAt: Date(timeIntervalSince1970: 1_784_800_000), helpfulVotes: 3, unhelpfulVotes: 9)
      ]
      meta.reviewsSummary = ReviewsSummary(total: 11, positive: 7, negative: 1, neutral: 3)
      meta.awards = [Award(name: "Золотая малина", nominationName: "Худший сиквел", year: 2027, won: false),
                     Award(name: "Сатурн", nominationName: "Лучший фильм о супергероях", year: 2027, won: true)]
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
    context.contentService = VideoContentServiceMock(
      details: { id in DetailFixture.allCases.first { $0.itemID == id }?.makeItem() },
      similar: { id in
        [.film, .filmCrew].contains(DetailFixture.allCases.first { $0.itemID == id }) ? DetailFixture.similarItems() : nil
      },
      personItems: { _ in
        DetailFixture.similarItems().prefix(5).enumerated().map { index, item in
          DetailFixture.posterItem(id: 9_902_000 + index, title: item.title, year: item.year, seed: index + 9)
        }
      }
    )
    context.actionsService = UserActionsServiceMock()
    context.collectionsService = CollectionsServiceMock()
    context.metadataService = MetadataService(sources: [DetailFixtureMetadataSource()])
    return context
  }
}

/// kino.pub's memory of what was watched, as far as the fixtures need it: the stand-in
/// player marks, the next details payload carries it.
final class DetailFixtureServer: @unchecked Sendable {
  static let shared = DetailFixtureServer()

  private let lock = NSLock()
  private var watched: Set<String> = []

  func markWatched(item: Int, season: Int?, video: Int?) {
    lock.withLock { _ = watched.insert(Self.key(item, season, video)) }
  }

  func isWatched(item: Int, season: Int?, video: Int?) -> Bool {
    lock.withLock { watched.contains(Self.key(item, season, video)) }
  }

  private static func key(_ item: Int, _ season: Int?, _ video: Int?) -> String {
    "\(item)/\(season ?? 0)/\(video ?? 0)"
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
  @State private var tab = 0

  var body: some View {
    if DebugLaunch.fixtureInTabs {
      // Under the real tab bar, as in the shipped app.
      TabView(selection: $tab) {
        Tab(value: 0) { stack } label: { Text("Watch Now") }
        Tab(value: 1) { Color.clear } label: { Text("Movies") }
      }
      .tabViewStyle(.tabBarOnly)
    } else {
      stack
    }
  }

  private var stack: some View {
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

// MARK: - Library

/// `-KINOPUBLibraryFixture YES`: the Library as a signed-in account has it — sidebar, the
/// page, the grid of Subscriptions — on a stand-in API. The Library itself is the real one;
/// only what it talks to, and the account's state, is replaced, so a shot of it is what the
/// shipped app draws for these titles: a title, and under it how many episodes are left.
enum LibraryFixture {
  static var isActive: Bool { DebugLaunch.libraryFixture }

  /// The app's context with the API swapped for one that lists `subscriptions`.
  static func context(replacingServicesOf base: AppContext) -> AppContext {
    var context = base
    context.contentService = VideoContentServiceMock(watchingSerials: { subscriptions })
    context.actionsService = UserActionsServiceMock()
    return context
  }

  /// Followed series: how far through, how many waiting. Two are caught up, one is a single
  /// episode behind, one has a long title.
  static var subscriptions: [WatchingItem] {
    let rows: [(title: String, total: Int, watched: Int)] = [
      ("Дом Дракона / House of the Dragon", 18, 16), ("Медведь / The Bear", 28, 28),
      ("Андор / Andor", 24, 12), ("Мистер и миссис Смит / Mr. & Mrs. Smith", 8, 7),
      ("Пингвин / The Penguin", 8, 8), ("Фоллаут / Fallout", 16, 4),
      ("Неблагодарные с острова очень длинное название / Ungrateful", 10, 0), ("Разделение / Severance", 19, 10),
      ("Тед Лассо / Ted Lasso", 34, 31), ("Ривердейл / Riverdale", 137, 100),
      ("Звёздный путь: Странные новые миры / Strange New Worlds", 30, 20), ("Чернобыль / Chernobyl", 5, 5)
    ]
    return rows.enumerated().map { index, row in
      WatchingItem(id: 9_903_000 + index, type: "serial", title: row.title,
                   posters: posters(seed: index + 60, label: row.title),
                   total: row.total, watched: row.watched, new: row.total - row.watched)
    }
  }

  /// What kino.pub sends as `posters`: drawn locally, or from the CDN with `-KINOPUBFixtureRealArt`.
  private static func posters(seed: Int, label: String) -> Posters {
    let json: [String: Any] = DebugLaunch.fixtureRealArt
      ? ["small", "medium", "big", "wide"].reduce(into: [String: Any]()) {
          $0[$1] = "https://m.staticpop.net/poster/item/big/\(10681 + seed).jpg"
        }
      : DetailFixtureArt.posters(seed: seed, label: label)
    do {
      return try JSONDecoder().decode(Posters.self, from: JSONSerialization.data(withJSONObject: json))
    } catch {
      fatalError("LibraryFixture posters do not decode: \(error)")
    }
  }
}

/// The real Library, signed in, on the stand-in API, with a store of its own that is never
/// written to the app's disk cache.
struct LibraryFixtureRoot: View {
  @Environment(ErrorHandler.self) private var errorHandler
  @Environment(\.appContext) private var appContext
  @StateObject private var authState: AuthState = {
    let state = AuthState(authService: AuthorizationServiceMock(), accessTokenService: AccessTokenServiceMock())
    state.userState = .authorized
    return state
  }()
  @State private var store = ContentStore(
    disk: RowSnapshotStore(directory: FileManager.default.temporaryDirectory
      .appendingPathComponent("KinoPubLibraryFixture", isDirectory: true)))

  var body: some View {
    LibraryShellView(
      model: LibraryModel(contentService: appContext.contentService,
                          actionsService: appContext.actionsService,
                          authState: authState,
                          errorHandler: errorHandler,
                          store: store,
                          defaults: UserDefaults(suiteName: "KinoPubLibraryFixture") ?? .standard),
      catalog: LibrarySectionCatalog(contentService: appContext.contentService,
                                     authState: authState,
                                     errorHandler: errorHandler,
                                     store: store)
    )
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
    DetailFixtureServer.shared.markWatched(item: item.metadata.id,
                                           season: item.metadata.season,
                                           video: item.metadata.video)
    AppContext.shared.localProgressStore.recordFinished(
      mediaId: item.metadata.id,
      duration: Double(duration),
      season: item.metadata.season,
      episode: item.metadata.video
    )
  }
}
// MARK: - Art

/// Artwork for the fixtures, drawn on first use into the temporary directory: a colour
/// wash per seed with the title across it. Local files, so a fixture page paints
/// every poster, still and portrait without a network — and the colours differ per
/// seed, so a screenshot shows which cell is which.
enum DetailFixtureArt {
  private enum Shape {
    case poster, wide, still, avatar

    var size: CGSize {
      switch self {
      case .poster: CGSize(width: 520, height: 780)
      case .wide: CGSize(width: 1280, height: 720)
      case .still: CGSize(width: 640, height: 360)
      case .avatar: CGSize(width: 400, height: 400)
      }
    }
  }

  /// A kino.pub `posters` object.
  static func posters(seed: Int, label: String) -> [String: Any] {
    let poster = url(.poster, seed: seed, label: label).absoluteString
    return ["small": poster, "medium": poster, "big": poster,
            "wide": url(.wide, seed: seed, label: label).absoluteString]
  }

  static func still(seed: Int, label: String) -> URL { url(.still, seed: seed + 20, label: label) }
  static func avatar(seed: Int, label: String) -> URL { url(.avatar, seed: seed + 40, label: label) }

  private static func url(_ shape: Shape, seed: Int, label: String) -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kinopub-fixture-art", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("\(shape)-\(seed).png")
    if !FileManager.default.fileExists(atPath: file.path) {
      try? draw(shape, seed: seed, label: label).write(to: file)
    }
    return file
  }

  private static func draw(_ shape: Shape, seed: Int, label: String) -> Data {
    let size = shape.size
    let hue = CGFloat((seed * 47) % 360) / 360
    let top = UIColor(hue: hue, saturation: 0.62, brightness: 0.78, alpha: 1)
    let bottom = UIColor(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 0.32, alpha: 1)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
      let cg = context.cgContext
      let colors = [top.cgColor, bottom.cgColor] as CFArray
      if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width * 0.4, y: size.height), options: [])
      }
      if shape == .avatar {
        // A head and shoulders, so a face-shaped crop has something to crop.
        UIColor.white.withAlphaComponent(0.55).setFill()
        cg.fillEllipse(in: CGRect(x: size.width * 0.3, y: size.height * 0.16, width: size.width * 0.4, height: size.height * 0.4))
        cg.fillEllipse(in: CGRect(x: size.width * 0.12, y: size.height * 0.62, width: size.width * 0.76, height: size.height * 0.8))
        return
      }
      let font = UIFont.systemFont(ofSize: size.height * (shape == .poster ? 0.075 : 0.11), weight: .heavy)
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center
      let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph
      ]
      let box = CGRect(x: size.width * 0.08, y: size.height * (shape == .poster ? 0.62 : 0.3),
                       width: size.width * 0.84, height: size.height * 0.34)
      (label as NSString).draw(with: box, options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
    }
  }
}
#endif
