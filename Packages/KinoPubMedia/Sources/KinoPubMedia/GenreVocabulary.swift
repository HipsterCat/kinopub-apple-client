import Foundation

/// **Our genre table**, and how each source's genres land in it.
///
/// Every source names genres its own way — kino.pub by an id from one of four sets
/// (`movie` / `docu` / `tvshow` / `music`), TMDB by an id from its movie and TV lists,
/// Kinopoisk by a Russian word — and the table is where they meet. Adding a source is
/// adding a column here, never a new `if` somewhere else.
///
/// **The table is data, not code:** `Resources/genres.json`, one file read by this package,
/// by `tools/metadata-ingest/genres.py` and by the worker, so the app and our own documents
/// say the same ids. Edit the JSON; the tests here and in the ingest check it.
///
/// **What each column rests on:**
/// - `kinopub` is kino.pub's whole reference list, `kpapp.link/config.json` →
///   `filter.genres` (v2.12.7, kept verbatim as `KinoPubBackendTests/Fixtures/kinopub_config.json`,
///   and a test maps every id in it). One idea can hold several ids because each set
///   numbers its own: Биография is 3 among films and 78 among documentaries.
/// - `tmdb` ids are TMDB's `/genre/movie/list` and `/genre/tv/list`; the TV list's folded
///   pairs are `tmdbPairs`.
/// - `aliases` are the names sources print, in both languages the API answers in. Names
///   are compared case-, diacritic- and width-insensitively.
/// - The Russian name is kino.pub's own title where one exists, so the app says what the
///   catalogue says; the English name is ours until an Apple column lands (ROADMAP stage 6).
public enum GenreVocabulary {

  public struct Definition: Sendable {
    public let genre: Genre
    /// Which of kino.pub's lists it comes from — the specificity worth keeping for
    /// filters and sections: a documentary's subject is not a film genre.
    public let group: GenreGroup
    let tmdb: [Int]
    let kinopub: [Int]
    let aliases: [String]
  }

  public static var definitions: [Definition] { table.definitions }

  /// kino.pub ids that sit in its genre lists but are not genres: "Эксклюзив" (128 among
  /// films, 133 among documentaries) says who carries the copy, not what the work is. As a
  /// first genre it would be the one word shown, so it becomes a `MediaLabel` instead.
  public static var kinopubNonGenres: Set<Int> { Set(table.kinopubLabels.keys) }

  /// The label a kino.pub genre id stands for, when it is not a genre.
  public static func kinopubLabel(id: Int) -> MediaLabel? {
    table.kinopubLabels[id].map {
      MediaLabel(id: $0.id, name: $0.name, source: .kinopub, sourceKey: "genre:\(id)")
    }
  }

  /// How kino.pub itself asks for a genre of ours (`genre=101`) — for shelves and filters
  /// that query kino.pub.
  public static func kinopubIDs(ofGenre id: String) -> [Int] {
    table.definitions.first { $0.genre.id == id }?.kinopub ?? []
  }

  public static func group(of genre: Genre) -> GenreGroup? {
    table.groups[genre.id]
  }

  public static func genre(id: String) -> Genre? {
    byID[id]
  }

  /// Genres that say what a title *is* before anything else, in the order they win: the
  /// first of them a title has leads its list, so it is the one word shown. Anime over
  /// animation — a title filed under both is anime first, the cartoon is the lesser fact
  /// (user's call, 2026-10-04). Documentary leads too, by the type it comes with
  /// (`KinoPubMediaMapping.TypeMapping.impliedGenreLeads`).
  /// TODO: the Python and worker copies of the genre table do not apply this order yet.
  public static let leadingGenreIDs = ["anime", "animation"]

  /// `genres` with the first leading genre it has moved to the front; the rest keep their
  /// order. Applied by `MediaAggregator` to whichever source's list wins.
  public static func primaryFirst(_ genres: [Genre]) -> [Genre] {
    guard let lead = leadingGenreIDs.lazy.compactMap({ id in genres.first { $0.id == id } }).first
    else { return genres }
    return [lead] + genres.filter { $0 != lead }
  }

  /// A kino.pub genre. The **id** decides — the table holds kino.pub's whole list — and the
  /// name only rescues an id the list did not have. Nil for the ids that are not genres
  /// (`kinopubNonGenres`). `domain` is the set the title's type files under, so an unknown
  /// name on a concert is looked up among music genres first.
  public static func kinopub(id: Int, title: String?, domain: GenreDomain) -> Genre? {
    guard !kinopubNonGenres.contains(id) else { return nil }
    if let known = byKinopubID[id] { return known }
    if let title, let known = named(title, domain: domain) { return known }
    return Genre.unmapped(source: .kinopub, key: String(id), name: title ?? String(id),
                          domain: domain)
  }

  /// A TMDB genre. Its TV list folds pairs into one id, so the answer is a list — in the
  /// order TMDB's own name gives them.
  public static func tmdb(id: Int, name: String?) -> [Genre] {
    if let pair = table.tmdbPairs[id] { return pair.compactMap { genre(id: $0) } }
    if let known = byTMDBID[id], !known.isEmpty { return known }
    if let name, let known = named(name, domain: .video) { return [known] }
    return [Genre.unmapped(source: .tmdb, key: String(id), name: name ?? String(id),
                           domain: .video)]
  }

  /// A genre known only by name (Kinopoisk, tvoe). Unknown names stay, unmapped.
  public static func named(_ name: String, source: MediaSource, domain: GenreDomain) -> Genre {
    named(name, domain: domain)
      ?? Genre.unmapped(source: source, key: normalize(name), name: name, domain: domain)
  }

  /// The hinted domain first, then the other: a documentary concert is still filed
  /// under Documentary.
  public static func named(_ name: String, domain: GenreDomain) -> Genre? {
    let key = normalize(name)
    guard !key.isEmpty else { return nil }
    let order: [GenreDomain] = domain == .music ? [.music, .video] : [.video, .music]
    for candidate in order {
      if let hit = byAlias[candidate]?[key] { return hit }
    }
    return nil
  }

  static func normalize(_ name: String) -> String {
    name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                 locale: nil)
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  // MARK: - Indexes

  private static let byID: [String: Genre] = Dictionary(
    table.definitions.map { ($0.genre.id, $0.genre) }, uniquingKeysWith: { first, _ in first })

  private static let byKinopubID: [Int: Genre] = Dictionary(
    table.definitions.flatMap { def in def.kinopub.map { ($0, def.genre) } },
    uniquingKeysWith: { first, _ in first })

  private static let byTMDBID: [Int: [Genre]] = table.definitions.reduce(into: [:]) { index, def in
    for id in def.tmdb { index[id, default: []].append(def.genre) }
  }

  private static let byAlias: [GenreDomain: [String: Genre]] = table.definitions.reduce(into: [:]) { index, def in
    let names = [def.genre.name.en, def.genre.name.ru] + def.aliases
    for name in names {
      let key = normalize(name)
      if index[def.genre.domain]?[key] == nil {
        index[def.genre.domain, default: [:]][key] = def.genre
      }
    }
  }

  // MARK: - The file

  private struct Table: Sendable {
    struct Label: Sendable {
      let id: String
      let name: LocalizedName
    }
    let definitions: [Definition]
    let groups: [String: GenreGroup]
    /// TMDB's TV list folds pairs into one id: 10759 Action & Adventure → action, adventure.
    let tmdbPairs: [Int: [String]]
    let kinopubLabels: [Int: Label]
  }

  private struct File: Decodable {
    struct Row: Decodable {
      let id: String
      let domain: GenreDomain
      let en: String
      let ru: String
      let tmdb: [Int]?
      let kinopub: [Int]?
      let aliases: [String]?
      let group: GenreGroup
    }
    struct LabelRow: Decodable {
      let id: String
      let en: String
      let ru: String
      let kinopub: [Int]?
    }
    let genres: [Row]
    let tmdbPairs: [String: [String]]
    let labels: [LabelRow]
  }

  private static let table: Table = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let url = Bundle.module.url(forResource: "genres", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let file = try? decoder.decode(File.self, from: data) else {
      assertionFailure("KinoPubMedia's genres.json is missing or malformed")
      return Table(definitions: [], groups: [:], tmdbPairs: [:], kinopubLabels: [:])
    }
    let definitions = file.genres.map { row in
      Definition(genre: Genre(id: row.id, domain: row.domain,
                              name: LocalizedName(en: row.en, ru: row.ru)),
                 group: row.group, tmdb: row.tmdb ?? [], kinopub: row.kinopub ?? [],
                 aliases: row.aliases ?? [])
    }
    var labels: [Int: Table.Label] = [:]
    for row in file.labels {
      for id in row.kinopub ?? [] {
        labels[id] = Table.Label(id: row.id, name: LocalizedName(en: row.en, ru: row.ru))
      }
    }
    return Table(
      definitions: definitions,
      groups: Dictionary(definitions.map { ($0.genre.id, $0.group) },
                         uniquingKeysWith: { first, _ in first }),
      tmdbPairs: Dictionary(file.tmdbPairs.compactMap { key, ids in Int(key).map { ($0, ids) } },
                            uniquingKeysWith: { first, _ in first }),
      kinopubLabels: labels)
  }()
}

/// Which of kino.pub's lists a genre comes from.
public enum GenreGroup: String, Hashable, Sendable, Codable, CaseIterable {
  case film
  case documentarySubject = "documentary-subject"
  case tvFormat = "tv-format"
  case music
}
