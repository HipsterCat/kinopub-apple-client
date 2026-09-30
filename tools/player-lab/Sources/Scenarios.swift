import UIKit

/// Which player surfaces a row turns on. Applied to `LabConfig` when the row is played.
struct Recipe {
  let name: String
  let set: [String: Int]
}

/// One row: a real catalogue title (real poster, real Russian text) played the way one approach
/// would play it. `tags` name the AVKit API in play, so the list is its own legend.
struct Scenario {
  enum Kind { case film, episode, trailer }
  let id: String
  let group: String
  let name: String
  var subtitle: String
  var subtitle2: String?
  let tags: [String]
  let context: MediaContext
  let kind: Kind
  let thumbURL: URL?
  let artURL: URL?
  let posterURL: URL?
  let recipe: [String: Int]
  var nextID: String?
  var hidden = false
  var followingIDs: [String] = []
  var isEpisode: Bool { kind == .episode }
  var info: PlayerInfo { PlayerInfo(context: context, labels: Scenarios.ru) }
}

/// The catalogue is Plozz's `KinoPubDemoCatalog.json` (copied in by build.sh as catalog.json).
enum Scenarios {

  static let ru = PlayerInfo.Labels(
    languageCode: "ru",
    episode: { s, e in s.map { "Сезон \($0), серия \(e)" } ?? "Серия \(e)" },
    extra: { $0 == .trailer ? "Трейлер" : nil })

  private struct Item: Decodable {
    let id: String, kind: String, title: String
    let year: Int?, overview: String?, genres: [String], officialRating: String?
    let posterURL: URL?, posterWideURL: URL?
  }
  private struct Catalog: Decodable { let items: [Item] }

  private static let items: [String: Item] = {
    let url = Bundle.main.url(forResource: "catalog", withExtension: "json")!
    let c = try! JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    return Dictionary(uniqueKeysWithValues: c.items.map { ($0.id, $0) })
  }()

  private static func entity(_ i: Item, kind: MediaKind = .movie, genres: [String]? = nil, title: String? = nil,
                             extra: ExtraKind? = nil, edition: String? = nil, overview: String? = nil) -> MediaEntity {
    MediaEntity(kind: kind, extraKind: extra, title: title ?? i.title, edition: edition,
                synopsis: Synopsis(full: overview ?? i.overview),
                genres: (genres ?? i.genres).compactMap { GenreVocabulary.named($0, domain: .video) },
                release: i.year.flatMap(ReleaseDate.init(year:)),
                contentRating: ContentRating(i.officialRating.map { $0.hasPrefix("age") ? String($0.dropFirst(3)) + "+" : $0 }))
  }

  // Recipes ------------------------------------------------------------------------------
  static let plain: [String: Int] = ["infoActions": 1]
  static let ours: [String: Int] = [:]
  static func apple(_ tab: Int) -> [String: Int] { ["infoActions": 3, "infoTab": tab, "proposal": 0] }
  static let kinopub: [String: Int] = ["infoActions": 1, "contextual": 1, "proposal": 2, "start": 1]
  static let nativeCard: [String: Int] = ["infoActions": 1, "proposal": 0, "start": 1]
  static let chapters: [String: Int] = ["infoActions": 1, "chapters": 1]

  /// Three episodes of one real series; the last has no next.
  private static func show(_ itemID: String, group: String, recipe: [String: Int], tags: [String], lastTags: [String],
                           names: [String?], notes: [String]) -> [Scenario] {
    let i = items[itemID]!
    let parent = entity(i, kind: .show)
    var out: [Scenario] = []
    for n in 1...3 {
      let ep = MediaEntity(kind: .episode, title: names[n - 1], seasonNumber: 1, episodeNumber: n,
                           release: i.year.flatMap(ReleaseDate.init(year:)))
      out.append(Scenario(id: "\(itemID)-e\(n)", group: group, name: "\(i.title) — S1E\(n)",
                          subtitle: notes[n - 1], tags: n < 3 ? tags : lastTags,
                          context: MediaContext(item: ep, season: MediaEntity(kind: .season, seasonNumber: 1), parent: parent),
                          kind: .episode, thumbURL: i.posterWideURL, artURL: i.posterWideURL, posterURL: i.posterURL, recipe: recipe))
    }
    for k in 0..<3 {
      out[k].nextID = k < 2 ? out[k + 1].id : nil
      out[k].followingIDs = Array(out[(k + 1)...].map(\.id))
    }
    return out
  }

  private static func film(_ itemID: String, group: String, name: String? = nil, subtitle: String, tags: [String],
                           recipe: [String: Int], genres: [String]? = nil, edition: String? = nil,
                           overview: String? = nil, blank: Bool = false) -> Scenario {
    let i = items[itemID]!
    var e = entity(i, genres: genres, edition: edition, overview: overview)
    if blank { e = MediaEntity(kind: .movie, title: i.title) }
    return Scenario(id: "\(itemID)-\(group)-\(name ?? "film")", group: group, name: name ?? i.title, subtitle: subtitle, tags: tags,
                    context: MediaContext(item: e), kind: .film, thumbURL: i.posterWideURL, artURL: i.posterURL, posterURL: i.posterURL, recipe: recipe)
  }

  static let all: [Scenario] = {
    var s: [Scenario] = []
    let g1 = "Native player features — no custom UI"
    s += show("8739", group: g1, recipe: nativeCard, tags: ["nextContentProposal", "next ✓"], lastTags: ["no next"],
              names: ["Пилот", "Эпизод 2", "Мясо"],
              notes: ["Starts 25 s before the end: the system Up Next card appears at the credits (10 s countdown)",
                      "Same card; «Эпизод 2» is a placeholder name and must not print twice",
                      "Last episode: no card"])
    s.append(film("4349", group: g1, subtitle: "System chapter markers: scrub the bar, or look for the chapter list under Info",
                  tags: ["navigationMarkerGroups"], recipe: chapters))
    let g2 = "Apple TV app style — an “Up Next” tab next to Info (our own TVUIKit view)"
    let variants: [(String, String, Int, String)] = [
      ("12407", "Wide cards — the Continue Watching cell", 1, "TVMediaItemContentConfiguration.wideCell()"),
      ("10741", "Poster cards", 2, "TVPosterView"),
      ("8933", "Wide cards + “Next” badge and progress", 3, "wideCell() + badgeText + playbackProgress"),
    ]
    for (id, label, tab, api) in variants {
      var eps = show(id, group: g2, recipe: apple(tab), tags: ["infoViewActions: From Beginning + Go to Show", "customInfoViewControllers: \(api)", "next ✓"],
                     lastTags: ["infoViewActions: From Beginning + Go to Show", "no next"],
                     names: ["Пилот", "Эпизод 2", "Спасение"],
                     notes: ["\(label). Info → right to the «Up Next» tab", "", ""])
      eps[0].subtitle2 = nil
      eps[1].hidden = true; eps[2].hidden = true
      s += eps
    }
    let g3 = "kino.pub style"
    s += show("8837", group: g3, recipe: kinopub, tags: ["contextualActions: Next Episode", "infoViewActions: From Beginning", "next ✓"],
              lastTags: ["infoViewActions: From Beginning", "no next"],
              names: ["Пилот", "Эпизод 2", "Кошка Шрёдингера"],
              notes: ["Next Episode is a button over the picture in the last minute; From Beginning in Info (starts near the end)",
                      "Same, placeholder name", "Last episode: no button"])
    let g4 = "Ours today"
    s += show("10959", group: g4, recipe: ours, tags: ["infoViewActions: Next Episode + Go to Show", "nextContentProposal", "next ✓"],
              lastTags: ["infoViewActions: From Beginning + Go to Show", "no next"],
              names: ["Пилот", "Эпизод 2", "Свадьба"],
              notes: ["Info tab: Next Episode + Go to Show (two-button cap drops From Beginning)",
                      "Placeholder name «Эпизод 2»: subtitle is just «Сезон 1, серия 2»",
                      "Last episode: From Beginning + Go to Show"])
    let g5 = "Metadata cases (no next episode)"
    s.append(film("4349", group: g5, name: "Film", subtitle: "Plot, first genre, year, age rating, poster", tags: ["externalMetadata"], recipe: plain))
    s.append(film("4349", group: g5, name: "Film, 48 fps edition", subtitle: "Multi-version film: the subtitle names the version",
                  tags: ["externalMetadata", "subtitle = edition"], recipe: plain, edition: "48 fps"))
    let trailer = items["8739"]!
    s.append(Scenario(id: "trailer", group: g5, name: "Trailer — \(trailer.title)", subtitle: "Subtitle «Трейлер»; the show's plot and poster",
                      tags: ["externalMetadata", "subtitle = Трейлер"],
                      context: MediaContext(item: MediaEntity(kind: .extra, extraKind: .trailer), parent: entity(trailer, kind: .show)),
                      kind: .trailer, thumbURL: trailer.posterWideURL, artURL: trailer.posterURL, posterURL: trailer.posterURL, recipe: plain))
    s.append(film("4349", group: g5, name: "Concert (stand-in poster)", subtitle: "Genre must be a music genre, not «Концерт»",
                  tags: ["externalMetadata", "genre = music"], recipe: plain, genres: ["электронная музыка", "концерт"]))
    s.append(film("4349", group: g5, name: "Documentary (stand-in poster)", subtitle: "Genre «Документальный»",
                  tags: ["externalMetadata", "genre = documentary"], recipe: plain, genres: ["документальный", "история"]))
    s.append(film("4349", group: g5, name: "Bare title", subtitle: "Only a title: nothing empty is sent",
                  tags: ["externalMetadata"], recipe: plain, blank: true))
    s.append(film("4349", group: g5, name: "Long plot", subtitle: "How the Info tab clips a long description", tags: ["externalMetadata"],
                  recipe: plain, overview: String(repeating: "Очень длинное описание, которое всё не заканчивается. ", count: 14)))
    return s
  }()

  static func scenario(_ id: String) -> Scenario? { all.first { $0.id == id } }
  static func next(after s: Scenario) -> Scenario? { s.nextID.flatMap(scenario) }
  static func following(_ s: Scenario) -> [Scenario] { s.followingIDs.compactMap(scenario) }

  // Artwork ------------------------------------------------------------------------------
  private static var cache: [URL: Data] = [:]
  static func data(_ url: URL?) async -> Data? {
    guard let url else { return nil }
    if let d = cache[url] { return d }
    guard let (d, _) = try? await URLSession.shared.data(from: url) else { return nil }
    cache[url] = d
    return d
  }
  static func cachedData(_ url: URL?) -> Data? { url.flatMap { cache[$0] } }
}
