import Foundation

/// **Our genre table**, and how each source's genres land in it.
///
/// Every source names genres its own way — kino.pub by an id from one of four sets
/// (`movie` / `docu` / `tvshow` / `music`), TMDB by an id from its movie and TV lists,
/// Kinopoisk by a Russian word — and the table is where they meet. Adding a source is
/// adding a column here, never a new `if` somewhere else.
///
/// **What each column rests on:**
/// - `kinopub` ids are **only the ones seen in captured payloads** (the test fixtures and
///   the ids `CatalogKind` already relies on). The full list lives in
///   `kpapp.link/config.json` → `filter.genres`; until it is folded in, names do the rest.
/// - `tmdb` ids are TMDB's `/genre/movie/list` and `/genre/tv/list`. The TV list folds some
///   pairs into one id (10759 Action & Adventure), which is why one TMDB id can land on
///   two of our genres.
/// - `aliases` are the names sources print, in both languages the API answers in. Names
///   are compared case-, diacritic- and width-insensitively.
public enum GenreVocabulary {

  public struct Definition: Sendable {
    public let genre: Genre
    let tmdb: [Int]
    let kinopub: [Int]
    let aliases: [String]
  }

  public static let definitions: [Definition] = video + music

  public static func genre(id: String) -> Genre? {
    byID[id]
  }

  /// A kino.pub genre. The **name** is tried first: it is the source's own statement of
  /// what it means, while the id table is our inference from captured payloads — and a
  /// test asserts the two agree for every id we hold. `domain` is the genre set the
  /// title's type files under, so a concert's "Comedy" is looked up among music genres
  /// before film ones.
  public static func kinopub(id: Int, title: String?, domain: GenreDomain) -> Genre {
    if let title, let known = named(title, domain: domain) { return known }
    if let known = byKinopubID[id] { return known }
    return Genre.unmapped(source: .kinopub, key: String(id), name: title ?? String(id),
                          domain: domain)
  }

  /// A TMDB genre. Its TV list folds pairs into one id, so the answer is a list — in the
  /// order TMDB's own name gives them.
  public static func tmdb(id: Int, name: String?) -> [Genre] {
    if let pair = tmdbPairs[id] { return pair.compactMap { genre(id: $0) } }
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

  /// TMDB's TV list: 10759 Action & Adventure, 10765 Sci-Fi & Fantasy, 10768 War & Politics.
  private static let tmdbPairs: [Int: [String]] = [
    10759: ["action", "adventure"],
    10765: ["sci-fi", "fantasy"],
    10768: ["war", "politics"],
  ]

  // MARK: - Indexes

  private static let byID: [String: Genre] = Dictionary(
    definitions.map { ($0.genre.id, $0.genre) }, uniquingKeysWith: { first, _ in first })

  private static let byKinopubID: [Int: Genre] = Dictionary(
    definitions.flatMap { def in def.kinopub.map { ($0, def.genre) } },
    uniquingKeysWith: { first, _ in first })

  private static let byTMDBID: [Int: [Genre]] = definitions.reduce(into: [:]) { index, def in
    for id in def.tmdb { index[id, default: []].append(def.genre) }
  }

  private static let byAlias: [GenreDomain: [String: Genre]] = definitions.reduce(into: [:]) { index, def in
    let names = [def.genre.name.en, def.genre.name.ru] + def.aliases
    for name in names {
      let key = normalize(name)
      if index[def.genre.domain]?[key] == nil {
        index[def.genre.domain, default: [:]][key] = def.genre
      }
    }
  }

  private static func define(_ id: String, _ domain: GenreDomain, en: String, ru: String,
                             tmdb: [Int] = [], kinopub: [Int] = [],
                             aliases: [String] = []) -> Definition {
    Definition(genre: Genre(id: id, domain: domain, name: LocalizedName(en: en, ru: ru)),
               tmdb: tmdb, kinopub: kinopub, aliases: aliases)
  }

  // MARK: - Film and TV

  private static let video: [Definition] = [
    define("action", .video, en: "Action", ru: "Боевик",
           tmdb: [28], kinopub: [2], aliases: ["боевики"]),
    define("adventure", .video, en: "Adventure", ru: "Приключения",
           tmdb: [12], kinopub: [8], aliases: ["приключение"]),
    define("animation", .video, en: "Animation", ru: "Мультфильм",
           tmdb: [16], kinopub: [23],
           aliases: ["мультфильмы", "мультсериал", "мультсериалы", "анимация", "мультипликация",
                     "cartoon", "cartoons"]),
    define("anime", .video, en: "Anime", ru: "Аниме", kinopub: [25]),
    define("biography", .video, en: "Biography", ru: "Биография",
           aliases: ["биографический", "biopic"]),
    define("comedy", .video, en: "Comedy", ru: "Комедия",
           tmdb: [35], aliases: ["комедии", "юмор", "юмористическое", "humor"]),
    define("concert", .video, en: "Concert", ru: "Концерт",
           aliases: ["концерты", "concerts", "concert film"]),
    define("crime", .video, en: "Crime", ru: "Криминал",
           tmdb: [80], aliases: ["криминальный"]),
    define("documentary", .video, en: "Documentary", ru: "Документальный",
           tmdb: [99],
           aliases: ["документальные", "документальное", "документалистика", "docu"]),
    define("drama", .video, en: "Drama", ru: "Драма", tmdb: [18], kinopub: [9]),
    define("erotic", .video, en: "Erotic", ru: "Эротика"),
    define("family", .video, en: "Family", ru: "Семейный",
           tmdb: [10751], kinopub: [6], aliases: ["семейные", "семейное"]),
    define("fantasy", .video, en: "Fantasy", ru: "Фэнтези",
           tmdb: [14], kinopub: [5], aliases: ["фентези"]),
    define("game-show", .video, en: "Game Show", ru: "Игровое шоу",
           aliases: ["игра", "игры", "игровое", "game"]),
    define("history", .video, en: "History", ru: "История",
           tmdb: [36], aliases: ["исторический", "исторические"]),
    define("horror", .video, en: "Horror", ru: "Ужасы", tmdb: [27], aliases: ["хоррор"]),
    define("kids", .video, en: "Kids", ru: "Детский",
           tmdb: [10762], aliases: ["детские", "детское", "детям", "children"]),
    define("music", .video, en: "Music", ru: "Музыка",
           tmdb: [10402], aliases: ["музыкальный", "музыкальное", "музыкальные"]),
    define("musical", .video, en: "Musical", ru: "Мюзикл", aliases: ["мюзиклы"]),
    define("mystery", .video, en: "Mystery", ru: "Детектив",
           tmdb: [9648], aliases: ["детективы"]),
    define("news", .video, en: "News", ru: "Новости", tmdb: [10763]),
    define("noir", .video, en: "Film Noir", ru: "Фильм-нуар",
           aliases: ["нуар", "noir", "film-noir"]),
    define("politics", .video, en: "Politics", ru: "Политика",
           aliases: ["политический"]),
    define("reality", .video, en: "Reality", ru: "Реалити-шоу",
           tmdb: [10764], aliases: ["реалити", "реальное тв", "reality tv", "reality-tv"]),
    define("romance", .video, en: "Romance", ru: "Мелодрама",
           tmdb: [10749], kinopub: [10], aliases: ["мелодрамы", "романтика", "романтический"]),
    define("sci-fi", .video, en: "Science Fiction", ru: "Фантастика",
           tmdb: [878], kinopub: [4],
           aliases: ["научная фантастика", "fantastic", "sci-fi", "scifi", "science-fiction"]),
    define("short", .video, en: "Short", ru: "Короткометражка",
           kinopub: [26],
           aliases: ["короткометражный", "короткометражные", "short film", "shorts"]),
    define("soap", .video, en: "Soap", ru: "Мыльная опера",
           tmdb: [10766], aliases: ["мыльные оперы", "теленовелла", "telenovela"]),
    define("sport", .video, en: "Sport", ru: "Спорт",
           aliases: ["спортивный", "спортивное", "спортивные", "sports"]),
    define("stand-up", .video, en: "Stand-Up", ru: "Стендап",
           kinopub: [101], aliases: ["стенд-ап", "standup", "stand up"]),
    define("talk", .video, en: "Talk Show", ru: "Ток-шоу",
           tmdb: [10767], aliases: ["talk", "ток шоу"]),
    define("thriller", .video, en: "Thriller", ru: "Триллер", tmdb: [53], aliases: ["триллеры"]),
    define("tv-movie", .video, en: "TV Movie", ru: "Телефильм", tmdb: [10770]),
    define("war", .video, en: "War", ru: "Военный",
           tmdb: [10752], aliases: ["война", "военные"]),
    define("western", .video, en: "Western", ru: "Вестерн", tmdb: [37], aliases: ["вестерны"]),
    // What documentaries are about — kino.pub's `docu` set files by subject.
    define("nature", .video, en: "Nature", ru: "Природа"),
    define("animals", .video, en: "Animals", ru: "Животные"),
    define("travel", .video, en: "Travel", ru: "Путешествия"),
    define("science", .video, en: "Science", ru: "Наука",
           aliases: ["научный", "научно-популярный"]),
    define("cooking", .video, en: "Cooking", ru: "Кулинария",
           aliases: ["кулинарное", "еда", "food"]),
    define("art", .video, en: "Art", ru: "Искусство"),
  ]

  // MARK: - Music

  private static let music: [Definition] = [
    define("music.electronic", .music, en: "Electronic", ru: "Электроника",
           kinopub: [36], aliases: ["электронная", "электронная музыка", "electronica"]),
    define("music.new-age", .music, en: "New Age", ru: "Нью-эйдж",
           kinopub: [42], aliases: ["new-age"]),
    define("music.trance", .music, en: "Trance", ru: "Транс", kinopub: [100]),
    define("music.chillout", .music, en: "Chillout", ru: "Чиллаут",
           kinopub: [102], aliases: ["chill out", "chill-out", "чилаут"]),
    define("music.ambient", .music, en: "Ambient", ru: "Эмбиент"),
    define("music.house", .music, en: "House", ru: "Хаус"),
    define("music.techno", .music, en: "Techno", ru: "Техно"),
    define("music.drum-and-bass", .music, en: "Drum & Bass", ru: "Драм-н-бейс",
           aliases: ["drum and bass", "drum'n'bass", "dnb", "d&b"]),
    define("music.dance", .music, en: "Dance", ru: "Танцевальная",
           aliases: ["танцевальная музыка", "edm"]),
    define("music.pop", .music, en: "Pop", ru: "Поп", aliases: ["поп-музыка"]),
    define("music.rock", .music, en: "Rock", ru: "Рок"),
    define("music.hard-rock", .music, en: "Hard Rock", ru: "Хард-рок"),
    define("music.alternative", .music, en: "Alternative", ru: "Альтернатива",
           aliases: ["alternative rock", "альтернативный рок"]),
    define("music.indie", .music, en: "Indie", ru: "Инди"),
    define("music.metal", .music, en: "Metal", ru: "Метал",
           aliases: ["heavy metal", "хэви-метал", "металл"]),
    define("music.punk", .music, en: "Punk", ru: "Панк", aliases: ["punk rock", "панк-рок"]),
    define("music.jazz", .music, en: "Jazz", ru: "Джаз"),
    define("music.blues", .music, en: "Blues", ru: "Блюз"),
    define("music.classical", .music, en: "Classical", ru: "Классика",
           aliases: ["классическая", "классическая музыка", "classic"]),
    define("music.opera", .music, en: "Opera", ru: "Опера"),
    define("music.hip-hop", .music, en: "Hip-Hop", ru: "Хип-хоп",
           aliases: ["hip hop", "rap", "рэп", "хип хоп"]),
    define("music.rnb", .music, en: "R&B", ru: "R&B",
           aliases: ["rnb", "r'n'b", "rhythm and blues", "ритм-н-блюз"]),
    define("music.soul", .music, en: "Soul", ru: "Соул"),
    define("music.funk", .music, en: "Funk", ru: "Фанк"),
    define("music.disco", .music, en: "Disco", ru: "Диско"),
    define("music.reggae", .music, en: "Reggae", ru: "Регги"),
    define("music.country", .music, en: "Country", ru: "Кантри"),
    define("music.folk", .music, en: "Folk", ru: "Фолк",
           aliases: ["народная", "народная музыка"]),
    define("music.world", .music, en: "World", ru: "Этника",
           aliases: ["world music", "этническая", "этно"]),
    define("music.latin", .music, en: "Latin", ru: "Латино", aliases: ["латиноамериканская"]),
    define("music.soundtrack", .music, en: "Soundtrack", ru: "Саундтрек",
           aliases: ["саундтреки", "ost"]),
    define("music.chanson", .music, en: "Chanson", ru: "Шансон"),
    define("music.singer-songwriter", .music, en: "Singer-Songwriter", ru: "Авторская песня",
           aliases: ["бард", "бардовская"]),
    define("music.k-pop", .music, en: "K-Pop", ru: "K-pop", aliases: ["kpop"]),
    define("music.j-pop", .music, en: "J-Pop", ru: "J-pop", aliases: ["jpop"]),
  ]
}
