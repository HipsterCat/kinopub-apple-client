import Foundation

/// **Our genre table**, and how each source's genres land in it.
///
/// Every source names genres its own way — kino.pub by an id from one of four sets
/// (`movie` / `docu` / `tvshow` / `music`), TMDB by an id from its movie and TV lists,
/// Kinopoisk by a Russian word — and the table is where they meet. Adding a source is
/// adding a column here, never a new `if` somewhere else.
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
    let tmdb: [Int]
    let kinopub: [Int]
    let aliases: [String]
  }

  public static let definitions: [Definition] = video + documentarySubjects + television + music

  /// kino.pub ids that are in its genre lists but are not genres: "Эксклюзив" (128 among
  /// films, 133 among documentaries) says who carries the copy, not what the work is. A
  /// badge candidate, never a genre — as the first genre it would be the one word shown.
  public static let kinopubNonGenres: Set<Int> = [128, 133]

  public static func genre(id: String) -> Genre? {
    byID[id]
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

  // MARK: - Film and TV — kino.pub's `movie` set, TMDB's lists

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
           kinopub: [3, 78], aliases: ["биографический", "biopic"]),
    define("comedy", .video, en: "Comedy", ru: "Комедия",
           tmdb: [35], kinopub: [1], aliases: ["комедии", "юмор", "humor"]),
    define("concert", .video, en: "Concert", ru: "Концерт",
           aliases: ["концерты", "concerts", "concert film"]),
    define("crime", .video, en: "Crime", ru: "Криминал",
           tmdb: [80], kinopub: [17, 63], aliases: ["криминальный"]),
    define("documentary", .video, en: "Documentary", ru: "Документальный",
           tmdb: [99], kinopub: [24],
           aliases: ["документальные", "документальное", "документалистика", "docu"]),
    define("dorama", .video, en: "Asian Drama", ru: "Дорама", kinopub: [107],
           aliases: ["dorama", "дорамы"]),
    define("drama", .video, en: "Drama", ru: "Драма", tmdb: [18], kinopub: [9]),
    define("erotic", .video, en: "Erotic", ru: "Эротика", kinopub: [21]),
    define("family", .video, en: "Family", ru: "Семейный",
           tmdb: [10751], kinopub: [6], aliases: ["семейные", "семейное"]),
    define("fantasy", .video, en: "Fantasy", ru: "Фэнтези",
           tmdb: [14], kinopub: [5], aliases: ["фентези"]),
    define("history", .video, en: "History", ru: "Исторический",
           tmdb: [36], kinopub: [18, 51], aliases: ["история", "исторические"]),
    define("horror", .video, en: "Horror", ru: "Ужасы", tmdb: [27], kinopub: [12],
           aliases: ["хоррор"]),
    define("kids", .video, en: "Kids", ru: "Детский",
           tmdb: [10762], aliases: ["детские", "детское", "детям", "children"]),
    define("music", .video, en: "Music", ru: "Музыкальный",
           tmdb: [10402], kinopub: [19, 70], aliases: ["музыка", "музыкальное", "музыкальные"]),
    define("musical", .video, en: "Musical", ru: "Мюзикл", aliases: ["мюзиклы"]),
    define("mystery", .video, en: "Mystery", ru: "Детектив",
           tmdb: [9648], kinopub: [13], aliases: ["детективы"]),
    define("news", .video, en: "News", ru: "Новости", tmdb: [10763]),
    define("noir", .video, en: "Film Noir", ru: "Нуар", kinopub: [105],
           aliases: ["фильм-нуар", "noir", "film-noir"]),
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
           kinopub: [20, 71], aliases: ["спортивный", "спортивное", "спортивные", "sports"]),
    define("stand-up", .video, en: "Stand-Up", ru: "Стендап",
           kinopub: [101], aliases: ["стенд-ап", "standup", "stand up"]),
    define("supernatural", .video, en: "Supernatural", ru: "Мистика", kinopub: [11]),
    define("theater", .video, en: "Theater", ru: "Спектакль", kinopub: [27],
           aliases: ["theatre", "спектакли", "театр"]),
    define("thriller", .video, en: "Thriller", ru: "Триллер", tmdb: [53], kinopub: [7],
           aliases: ["триллеры"]),
    define("tv-movie", .video, en: "TV Movie", ru: "Телефильм", tmdb: [10770]),
    define("vaudeville", .video, en: "Vaudeville", ru: "Водевиль", kinopub: [116]),
    define("war", .video, en: "War", ru: "Военный",
           tmdb: [10752], kinopub: [15, 56],
           aliases: ["война", "военные", "оружие / война", "оружие/война"]),
    define("western", .video, en: "Western", ru: "Вестерн", tmdb: [37], kinopub: [14],
           aliases: ["вестерны"]),
  ]

  // MARK: - What documentaries are about — kino.pub's `docu` set

  private static let documentarySubjects: [Definition] = [
    define("technology", .video, en: "Technology", ru: "IT технологии", kinopub: [93],
           aliases: ["технологии", "it"]),
    define("aviation", .video, en: "Aviation", ru: "Авиация", kinopub: [90]),
    define("cars", .video, en: "Cars", ru: "Автомобили", kinopub: [87]),
    define("paranormal", .video, en: "Paranormal", ru: "Аномалии", kinopub: [62]),
    define("business", .video, en: "Business", ru: "Бизнес", kinopub: [64]),
    define("general-interest", .video, en: "General Interest", ru: "Всё обо всём",
           kinopub: [52], aliases: ["все обо всем"]),
    define("space", .video, en: "Space", ru: "Космос", kinopub: [60]),
    define("universe", .video, en: "Universe", ru: "Вселенная", kinopub: [81]),
    define("survival", .video, en: "Survival", ru: "Выживание", kinopub: [122, 123]),
    define("health", .video, en: "Health & Medicine", ru: "Здоровье и медицина", kinopub: [61]),
    define("celebrities", .video, en: "Celebrities", ru: "Знаменитости", kinopub: [57]),
    define("gold", .video, en: "Gold", ru: "Золото", kinopub: [92]),
    define("art", .video, en: "Art", ru: "Искусство", kinopub: [68]),
    define("disasters", .video, en: "Disasters", ru: "Катастрофы", kinopub: [66]),
    define("cinema", .video, en: "Cinema", ru: "Кино", kinopub: [82]),
    define("pseudoscience", .video, en: "Pseudoscience", ru: "Лженаука", kinopub: [75]),
    define("literature", .video, en: "Literature", ru: "Литература", kinopub: [84]),
    define("people", .video, en: "People", ru: "Люди", kinopub: [83]),
    define("animals", .video, en: "Animals", ru: "Мир животных", kinopub: [58],
           aliases: ["животные"]),
    define("fashion", .video, en: "Fashion", ru: "Мода", kinopub: [104]),
    define("science", .video, en: "Science", ru: "Наука", kinopub: [55],
           aliases: ["научный", "научно-популярный"]),
    define("education", .video, en: "Education", ru: "Обучающее видео", kinopub: [76]),
    define("ocean", .video, en: "Ocean", ru: "Океан", kinopub: [85]),
    define("relationships", .video, en: "Relationships", ru: "Он и она", kinopub: [67]),
    define("discoveries", .video, en: "Discoveries", ru: "Открытия", kinopub: [88]),
    define("politics", .video, en: "Politics", ru: "Политика", kinopub: [59],
           aliases: ["политический"]),
    define("nature", .video, en: "Nature", ru: "Природа", kinopub: [73]),
    define("aliens", .video, en: "Aliens", ru: "Пришельцы", kinopub: [80]),
    define("psychology", .video, en: "Psychology", ru: "Психология", kinopub: [65]),
    define("travel", .video, en: "Travel", ru: "Путешествия", kinopub: [54, 112]),
    define("investigation", .video, en: "Investigation", ru: "Расследование", kinopub: [77]),
    define("religion", .video, en: "Religion", ru: "Религия", kinopub: [69]),
    define("construction", .video, en: "Construction", ru: "Строительство", kinopub: [79]),
    define("engineering", .video, en: "Engineering", ru: "Техника", kinopub: [53]),
    define("physiology", .video, en: "Physiology", ru: "Физиология", kinopub: [98]),
    define("navy", .video, en: "Navy", ru: "Флот", kinopub: [91]),
    define("photography", .video, en: "Photography", ru: "Фотография", kinopub: [86]),
    define("hobbies", .video, en: "Hobbies", ru: "Хобби", kinopub: [74]),
    define("ecology", .video, en: "Ecology", ru: "Экология", kinopub: [72]),
  ]

  // MARK: - TV shows — kino.pub's `tvshow` set, TMDB's TV list

  private static let television: [Definition] = [
    define("quiz", .video, en: "Quiz", ru: "Интеллектуальные", kinopub: [124],
           aliases: ["интеллектуальные", "викторина", "игровое шоу", "game show"]),
    define("cooking", .video, en: "Cooking", ru: "Кулинария", kinopub: [111],
           aliases: ["кулинарное", "еда", "food"]),
    define("entertainment", .video, en: "Entertainment", ru: "Развлекательные", kinopub: [110],
           aliases: ["развлекательное", "юмористическое"]),
    define("reality", .video, en: "Reality", ru: "Реалити-шоу",
           tmdb: [10764], kinopub: [114],
           aliases: ["реалити", "реальное тв", "reality tv", "reality-tv"]),
    define("talk", .video, en: "Talk Show", ru: "Ток-шоу",
           tmdb: [10767], kinopub: [113], aliases: ["talk", "ток шоу"]),
  ]

  // MARK: - Music — kino.pub's `music` set (concerts)

  private static let music: [Definition] = [
    define("music.alternative", .music, en: "Alternative", ru: "Альтернатива", kinopub: [30],
           aliases: ["alternative rock", "альтернативный рок"]),
    define("music.blues", .music, en: "Blues", ru: "Блюз", kinopub: [31]),
    define("music.chillout", .music, en: "Chillout", ru: "Чиллаут",
           kinopub: [102], aliases: ["chill out", "chill-out", "чилаут"]),
    define("music.classical", .music, en: "Classical", ru: "Классика", kinopub: [32],
           aliases: ["классическая", "классическая музыка", "classic"]),
    define("music.country", .music, en: "Country", ru: "Кантри", kinopub: [33]),
    define("music.dance", .music, en: "Dance", ru: "Танцевальная", kinopub: [34],
           aliases: ["танцевальная музыка", "edm"]),
    define("music.downtempo", .music, en: "Downtempo", ru: "Даунтемпо", kinopub: [103]),
    define("music.easy-listening", .music, en: "Easy Listening", ru: "Лёгкая музыка",
           kinopub: [35]),
    define("music.electronic", .music, en: "Electronic", ru: "Электроника",
           kinopub: [36], aliases: ["электронная", "электронная музыка", "electronica"]),
    define("music.folk", .music, en: "Folk", ru: "Фолк", kinopub: [118],
           aliases: ["народная", "народная музыка"]),
    define("music.hip-hop", .music, en: "Hip-Hop/Rap", ru: "Хип-хоп", kinopub: [37],
           aliases: ["hip-hop", "hip hop", "rap", "рэп", "хип хоп"]),
    define("music.house", .music, en: "House", ru: "Хаус", kinopub: [99]),
    define("music.indie", .music, en: "Indie", ru: "Инди", kinopub: [119]),
    define("music.industrial", .music, en: "Industrial", ru: "Индастриал", kinopub: [38]),
    define("music.instrumental", .music, en: "Instrumental", ru: "Инструментальная",
           kinopub: [39]),
    define("music.jazz", .music, en: "Jazz", ru: "Джаз", kinopub: [40]),
    define("music.k-pop", .music, en: "K-Pop", ru: "K-pop", kinopub: [117], aliases: ["kpop"]),
    define("music.latin", .music, en: "Latin", ru: "Латино", kinopub: [41],
           aliases: ["латиноамериканская"]),
    define("music.metal", .music, en: "Metal", ru: "Метал", kinopub: [50],
           aliases: ["heavy metal", "хэви-метал", "металл"]),
    define("music.new-age", .music, en: "New Age", ru: "Нью-эйдж",
           kinopub: [42], aliases: ["new-age"]),
    define("music.opera", .music, en: "Opera", ru: "Опера", kinopub: [43]),
    define("music.pop", .music, en: "Pop", ru: "Поп", kinopub: [44], aliases: ["поп-музыка"]),
    define("music.progressive", .music, en: "Progressive", ru: "Прогрессив", kinopub: [120]),
    define("music.rnb", .music, en: "R&B/Soul", ru: "R&B/Соул", kinopub: [45],
           aliases: ["r&b", "rnb", "r'n'b", "soul", "соул", "rhythm and blues", "ритм-н-блюз"]),
    define("music.reggae", .music, en: "Reggae", ru: "Регги", kinopub: [46]),
    define("music.rock", .music, en: "Rock", ru: "Рок", kinopub: [47]),
    define("music.trance", .music, en: "Trance", ru: "Транс", kinopub: [100]),
    define("music.trip-hop", .music, en: "Trip-Hop", ru: "Трип-хоп", kinopub: [121]),
    define("music.vocal", .music, en: "Vocal", ru: "Вокал", kinopub: [48]),
    define("music.world", .music, en: "World", ru: "Этника", kinopub: [49],
           aliases: ["world music", "этническая", "этно"]),
    define("music.ballet", .music, en: "Ballet", ru: "Балет", kinopub: [109]),
  ]
}
