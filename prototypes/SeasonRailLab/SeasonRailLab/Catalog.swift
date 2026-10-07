import Foundation

/// Breaking Bad, fetched once from TMDB. Season 1 is a fixed gallery of the
/// states the product rail has to show side by side; the other seasons stay
/// as the service sent them.
enum Catalog {
  static let showID = 1396
  static let apiKey = "cf87d219c024109a487198735353bb36"

  static let backdrop = URL(string: "https://avatars.mds.yandex.net/get-ott/1531675/2a0000017c07954f2e92e530a0947de62952/orig")!
  static let logo = URL(string: "https://avatars.mds.yandex.net/get-ott/200035/2a0000017802c0dff697971233b0e9def244/orig")!

  static func still(_ path: String) -> URL {
    URL(string: "https://image.tmdb.org/t/p/w780\(path)")!
  }

  static func fetch() async throws -> Show {
    var parts = URLComponents(string: "https://api.themoviedb.org/3/tv/\(showID)")!
    let seasons = (1...5).map { "season/\($0)" }.joined(separator: ",")
    parts.queryItems = [
      URLQueryItem(name: "api_key", value: apiKey),
      URLQueryItem(name: "language", value: "ru-RU"),
      URLQueryItem(name: "append_to_response", value: seasons),
    ]
    let (data, response) = try await URLSession.shared.data(from: parts.url!)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
    let decoded = try JSONDecoder().decode(APIShow.self, from: data)
    let runtime = decoded.episodeRunTime.first
    let seasonsOut = decoded.seasons.sorted { $0.seasonNumber < $1.seasonNumber }.map { season in
      Season(
        number: season.seasonNumber,
        episodes: season.episodes.map { present($0, season: season.seasonNumber, showRuntime: runtime) }
      )
    }
    return Show(name: decoded.name, seasons: seasonsOut)
  }

  /// Season 1 carries every state. Later seasons are the catalog, so the
  /// chip row is a real switch and not a second copy of the gallery.
  private static func present(_ episode: APIEpisode, season: Int, showRuntime: Int?) -> Episode {
    var overview = nonempty(episode.overview)
    var still = episode.stillPath
    let availability: Availability
    if season == 1 {
      switch episode.episodeNumber {
      case 1:
        availability = .watched
      case 2:
        availability = .inProgress(0.42)
      case 3:
        availability = .missing
      case 4:
        availability = .playable
        overview = nil
      case 5:
        availability = .upcoming(Date().addingTimeInterval(18 * 24 * 60 * 60))
      case 6:
        availability = .upcoming(nil)
        still = nil
      case 7:
        availability = .playable
      default:
        availability = .playable
      }
    } else {
      availability = .playable
    }
    return Episode(
      id: "\(season)-\(episode.episodeNumber)",
      season: season,
      number: episode.episodeNumber,
      overview: overview,
      stillURL: still.map(Catalog.still),
      runtimeMinutes: episode.runtime ?? showRuntime,
      availability: availability
    )
  }

  private static func nonempty(_ text: String?) -> String? {
    guard let text else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

struct Show {
  let name: String
  let seasons: [Season]
}

struct Season {
  let number: Int
  let episodes: [Episode]
}

struct Episode: Hashable {
  let id: String
  let season: Int
  let number: Int
  let overview: String?
  let stillURL: URL?
  let runtimeMinutes: Int?
  let availability: Availability

  var onService: Bool {
    switch availability {
    case .playable, .inProgress, .watched: true
    case .missing, .upcoming: false
    }
  }

  var title: String { "\(number) серия" }

  var summary: String {
    switch availability {
    case .watched: return "Просмотрено"
    case .inProgress: return "В процессе"
    case .playable: return ""
    case .missing: return "Нет на Кинопабе"
    case .upcoming(let date):
      if let date { return Self.when(date) }
      return "Запланировано"
    }
  }

  static func when(_ date: Date) -> String {
    if date.timeIntervalSinceNow < 30 * 24 * 60 * 60 {
      let formatter = RelativeDateTimeFormatter()
      formatter.locale = Locale(identifier: "ru_RU")
      formatter.unitsStyle = .full
      return formatter.localizedString(for: date, relativeTo: Date())
    }
    return date.formatted(
      Date.FormatStyle().day().month(.abbreviated).locale(Locale(identifier: "ru_RU"))
    )
  }
}

enum Availability: Hashable {
  case playable
  case inProgress(Float)
  case watched
  case missing
  case upcoming(Date?)
}

enum RailItem: Hashable {
  case skeleton(Int)
  case episode(Episode)
}

private struct APIShow: Decodable {
  let name: String
  let episodeRunTime: [Int]
  let seasons: [APISeason]

  private struct Key: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: Key.self)
    name = try container.decode(String.self, forKey: Key(stringValue: "name")!)
    episodeRunTime = try container.decodeIfPresent([Int].self, forKey: Key(stringValue: "episode_run_time")!) ?? []
    var seasons: [APISeason] = []
    for number in 1...5 {
      let key = Key(stringValue: "season/\(number)")!
      if let season = try container.decodeIfPresent(APISeason.self, forKey: key) {
        seasons.append(season)
      }
    }
    self.seasons = seasons
  }
}

private struct APISeason: Decodable {
  let seasonNumber: Int
  let episodes: [APIEpisode]

  enum CodingKeys: String, CodingKey {
    case seasonNumber = "season_number"
    case episodes
  }
}

private struct APIEpisode: Decodable {
  let episodeNumber: Int
  let name: String
  let overview: String?
  let stillPath: String?
  let airDate: String?
  let runtime: Int?

  enum CodingKeys: String, CodingKey {
    case episodeNumber = "episode_number"
    case name
    case overview
    case stillPath = "still_path"
    case airDate = "air_date"
    case runtime
  }
}

enum RailCopy {
  static func summary(season: Int, episodes: [Episode]) -> String {
    let count = episodes.count
    let watched = episodes.reduce(0.0) { partial, episode in
      switch episode.availability {
      case .watched: return partial + 1
      case .inProgress(let fraction): return partial + Double(fraction)
      case .playable, .missing, .upcoming: return partial
      }
    }
    let percent = count == 0 ? 0 : Int((watched / Double(count) * 100).rounded())
    return "\(season) сезон, \(count) \(episodesWord(count))    Просмотрено \(percent)%"
  }

  static func episodesWord(_ count: Int) -> String {
    let tens = count % 100
    let ones = count % 10
    if ones == 1, tens != 11 { return "серия" }
    if (2...4).contains(ones), !(12...14).contains(tens) { return "серии" }
    return "серий"
  }
}
