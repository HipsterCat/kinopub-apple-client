//
//  LibraryFilter.swift
//
//

import Foundation

/// How the library listing is sorted.
///
/// `kinopoisk_rating` and `imdb_rating` are absent from the published docs but the
/// service accepts them and orders correctly — verified against live responses.
public enum MediaSortOrder: String, CaseIterable, Identifiable, Hashable, Sendable {
  case recentlyAdded
  case recentlyUpdated
  case views
  case title
  case year
  case kinopoiskRating
  case imdbRating

  public var id: Self { self }

  /// The `sort` parameter. A `-` prefix means descending.
  public var apiValue: String {
    switch self {
    case .recentlyAdded: return "-created"
    case .recentlyUpdated: return "-updated"
    case .views: return "-views"
    case .title: return "title"
    case .year: return "-year"
    case .kinopoiskRating: return "-kinopoisk_rating"
    case .imdbRating: return "-imdb_rating"
    }
  }

  /// Localization key.
  public var titleKey: String {
    switch self {
    case .recentlyAdded: return "Sort_RecentlyAdded"
    case .recentlyUpdated: return "Sort_RecentlyUpdated"
    case .views: return "Sort_Views"
    case .title: return "Sort_Title"
    case .year: return "Sort_Year"
    case .kinopoiskRating: return "Sort_KinopoiskRating"
    case .imdbRating: return "Sort_ImdbRating"
    }
  }
}

/// kino.pub's quality ids (`GET /v1/references/video-quality`). As a `quality=` filter
/// the id means "at least": 1 → 32205 films, 2 → 27861, 3 → 26070, 4 → 2737 (2026-09-26).
public enum VideoQuality: Int, CaseIterable, Hashable, Sendable {
  case sd480 = 1
  case hd720 = 2
  case fullHD1080 = 3
  case uhd4K = 4

  public var title: String {
    switch self {
    case .sd480: "480p"
    case .hd720: "720p"
    case .fullHD1080: "1080p"
    case .uhd4K: "4K"
    }
  }
}

/// A release-year window. Decades rather than a free range: a two-ended numeric
/// picker is miserable to drive with a remote.
public struct YearRange: Identifiable, Hashable, Sendable {
  public let from: Int
  public let to: Int

  public var id: String { "\(from)-\(to)" }

  public init(from: Int, to: Int) {
    self.from = from
    self.to = to
  }

  /// "1990-1999", the format the `year` parameter takes.
  public var apiValue: String { "\(from)-\(to)" }

  public var title: String {
    from == to ? "\(from)" : "\(from)–\(to)"
  }

  /// The current decade down to the 1950s, newest first.
  public static func decades(upTo year: Int) -> [YearRange] {
    let currentDecade = (year / 10) * 10
    return stride(from: currentDecade, through: 1950, by: -10).map {
      YearRange(from: $0, to: $0 + 9)
    }
  }
}

/// Hot/popular window for `/v1/items?period=`. Server-side (unlike rating/HD facets).
/// DESIGN: chip chrome in `LibraryFiltersBar` TBD — values are ready to send.
public enum CatalogPeriod: String, CaseIterable, Identifiable, Hashable, Sendable {
  case day
  case week
  case month
  case year

  public var id: Self { self }

  /// Localization key for when the filter chrome lands.
  public var titleKey: String {
    switch self {
    case .day: return "Period_Day"
    case .week: return "Period_Week"
    case .month: return "Period_Month"
    case .year: return "Period_Year"
    }
  }
}

/// Everything the library listing filters on. `nil` means "any".
///
/// Rating / quality / AC3 facets are applied **client-side**. The mobile `/v1/items`
/// API only honors type/genre/country/year/sort/cast/director/`period` — `imdb` /
/// `kinopoisk` / `quality` / `conditions` query params are silently ignored (verified
/// by the dungeon-master-xx fork against the live API). Each `MediaItem` already carries
/// `imdbRating` / `kinopoiskRating` / `quality` / `ac3`, so we filter the page locally.
public struct LibraryFilter: Equatable, Hashable, Sendable {
  public var contentType: MediaType?
  /// Several content types at once — `type=movie,serial` is OR on the server (verified
  /// live 2026-09-25). Empty means every type; it wins over `contentType` when set.
  public var contentTypes: Set<MediaType> = []
  /// kino.pub's sections as a person names them (`CatalogKind`). Wins over
  /// `contentType(s)`; a genre kind (anime, cartoons, shorts, stand-up) also owns
  /// `genre` — the API has no genre AND. Empty = everything.
  public var kinds: Set<CatalogKind> = []
  public var sort: MediaSortOrder
  public var genreID: Int?
  /// Several genres at once — `/v1/items` reads a comma as OR on `genre`. Set instead
  /// of `genreID` when asking "more like this" of a title filed under six of them.
  public var genreIDs: [Int] = []
  public var countryID: Int?
  /// Several countries at once — a comma is OR on `country`, like on `genre`.
  public var countryIDs: Set<Int> = []
  /// `finished=1` — ended series only. There is no "airing": `finished=0` (what
  /// kino.pub's web client sends for "В эфире") is answered exactly as no parameter
  /// (2026-09-26, ended titles on its pages).
  public var finishedOnly: Bool = false
  public var years: YearRange?
  /// Set for a person's credits, which are the same listing narrowed to one name.
  public var person: MediaPerson?
  /// Popularity window (`day`/`week`/`month`/`year`) — sent server-side.
  public var period: CatalogPeriod?

  /// Kinopoisk rating range (0…10). Sent as `conditions[]=kinopoisk_rating>=…/<=…` —
  /// the server applies it (verified 2026-09-26: `<=5` → 4831 of 32206 films).
  public var kinopoiskMin: Double?
  public var kinopoiskMax: Double?
  /// IMDb rating range, the same way (`imdb_rating>=8` → 794).
  public var imdbMin: Double?
  public var imdbMax: Double?
  /// Release years, from–to, as `conditions[]=year>=…/<=…`. Wins over `years`.
  public var yearFrom: Int?
  public var yearTo: Int?
  /// At least this quality — `quality=<id>` (verified: 4 → 2737 films in 4K).
  public var minimumQuality: VideoQuality?
  /// Drop titles marked as carrying adverts (`advert`). Applied client-side — the API
  /// ignores `advert=` (2026-09-26).
  public var withoutAdverts: Bool = false
  /// Keep items whose advertised height is ≥ 720. Applied client-side.
  public var wantHD: Bool
  /// Keep items whose advertised height is ≥ 2160. Applied client-side.
  public var want4K: Bool
  /// Drop items whose advertised height is ≥ 720. Applied client-side.
  public var withoutHD: Bool
  /// Keep items with `ac3 == 1`. Applied client-side.
  public var wantAC3: Bool

  public init(
    contentType: MediaType? = nil,
    sort: MediaSortOrder = .recentlyAdded,
    genreID: Int? = nil,
    genreIDs: [Int] = [],
    countryID: Int? = nil,
    years: YearRange? = nil,
    person: MediaPerson? = nil,
    period: CatalogPeriod? = nil,
    kinopoiskMin: Double? = nil,
    imdbMin: Double? = nil,
    wantHD: Bool = false,
    want4K: Bool = false,
    withoutHD: Bool = false,
    wantAC3: Bool = false
  ) {
    self.contentType = contentType
    self.sort = sort
    self.genreID = genreID
    self.genreIDs = genreIDs
    self.countryID = countryID
    self.years = years
    self.person = person
    self.period = period
    self.kinopoiskMin = kinopoiskMin
    self.imdbMin = imdbMin
    self.wantHD = wantHD
    self.want4K = want4K
    self.withoutHD = withoutHD
    self.wantAC3 = wantAC3
  }

  /// The server-side filters as query parameters, shared by `/v1/items` and
  /// `/v1/items/search` — the search endpoint honors the same `type` / `genre` /
  /// `country` / `year` / `sort` (verified live 2026-09-25, see docs/providers/kinopub/video.md).
  /// `sort` is left to the caller: search without one is the server's relevance order.
  public var serverParameters: [String: Any] {
    var params: [String: Any] = [:]
    let genreKinds = kinds.filter { $0.axis == .genre }
    if !kinds.isEmpty {
      // One axis at a time (the picker enforces it); genre kinds win if both slip in.
      let active = genreKinds.isEmpty ? kinds : genreKinds
      params["type"] = Set(active.flatMap(\.types)).map(\.rawValue).sorted().joined(separator: ",")
    } else if !contentTypes.isEmpty {
      params["type"] = contentTypes.map(\.rawValue).sorted().joined(separator: ",")
    } else if let contentType {
      params["type"] = contentType.rawValue
    }
    // Commas are OR on `genre` — several genres ask for anything filed under any of
    // them. **Not true of `cast` / `director`**: those match the field as written, so a
    // comma there matches nothing and each name needs its own request (verified against
    // the live API 2026-08-17 — `director=Фил Лорд,Кристофер Миллер` answers empty).
    if !genreKinds.isEmpty {
      params["genre"] = genreKinds.compactMap(\.genreID).sorted().map(String.init).joined(separator: ",")
    } else if !genreIDs.isEmpty {
      params["genre"] = genreIDs.map(String.init).joined(separator: ",")
    } else if let genreID {
      params["genre"] = "\(genreID)"
    }
    if !countryIDs.isEmpty {
      params["country"] = countryIDs.sorted().map(String.init).joined(separator: ",")
    } else if let countryID {
      params["country"] = "\(countryID)"
    }
    if finishedOnly {
      params["finished"] = "1"
    }
    var conditions: [String] = []
    if yearFrom != nil || yearTo != nil {
      if let yearFrom { conditions.append("year>=\(yearFrom)") }
      if let yearTo { conditions.append("year<=\(yearTo)") }
    } else if let years {
      params["year"] = years.apiValue
    }
    func rating(_ field: String, _ min: Double?, _ max: Double?) {
      if let min, min > 0 { conditions.append("\(field)>=\(Self.format(min))") }
      if let max, max < 10 { conditions.append("\(field)<=\(Self.format(max))") }
    }
    rating("kinopoisk_rating", kinopoiskMin, kinopoiskMax)
    rating("imdb_rating", imdbMin, imdbMax)
    if !conditions.isEmpty {
      params["conditions[]"] = conditions
    }
    if let minimumQuality {
      params["quality"] = "\(minimumQuality.rawValue)"
    }
    // Popularity window — server-side (not a client facet). Sent for views/watchers
    // rankings; approximating via `created_at` would empty those lists.
    if let period {
      params["period"] = period.rawValue
    }
    // `cast` / `director`, matched on the name as it appears in the credits — one name
    // per request, see the note above.
    // (`cast`, not the docs' `actor` — see `MediaPerson.Role.itemsQueryParameter`.)
    if let person {
      params[person.role.itemsQueryParameter] = person.name
    }
    return params
  }

  private static func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(value)
  }

  /// True when anything other than the default sort is in play.
  public var hasActiveFilters: Bool {
    contentType != nil
      || !contentTypes.isEmpty
      || !kinds.isEmpty
      || !countryIDs.isEmpty
      || finishedOnly
      || genreID != nil
      || !genreIDs.isEmpty
      || countryID != nil
      || years != nil
      || yearFrom != nil
      || yearTo != nil
      || period != nil
      || kinopoiskMin != nil
      || kinopoiskMax != nil
      || imdbMin != nil
      || imdbMax != nil
      || minimumQuality != nil
      || hasClientSideFacets
  }

  /// Facets the server ignores — applied to each fetched page locally. Ratings are no
  /// longer among them: `conditions[]` does those on the server.
  public var hasClientSideFacets: Bool {
    wantHD
      || withoutHD
      || want4K
      || wantAC3
      || withoutAdverts
  }

  /// Applies the client-side-only facets to a fetched item.
  public func clientSideMatches(_ item: MediaItem) -> Bool {
    if wantAC3, (item.ac3 ?? 0) != 1 { return false }
    if withoutAdverts, item.advert { return false }
    if want4K, item.quality < 2160 { return false }
    if wantHD, item.quality < 720 { return false }
    if withoutHD, item.quality >= 720 { return false }
    return true
  }
}

// MARK: - Saved

extension LibraryFilter {
  /// The picks a person makes in the search tab's filter row, as they are kept on disk
  /// between launches — ids and raw values only, so a renamed case drops the pick
  /// instead of failing the whole decode.
  public struct Saved: Codable, Equatable, Sendable {
    public var kinds: [String] = []
    public var genreIDs: [Int] = []
    public var countryIDs: [Int] = []
    public var finishedOnly = false
    public var yearFrom: Int?
    public var yearTo: Int?
    public var kinopoiskMin: Double?
    public var kinopoiskMax: Double?
    public var imdbMin: Double?
    public var imdbMax: Double?
    public var minimumQuality: Int?
    public var sort: String?

    public init() {}
  }

  public var saved: Saved {
    var saved = Saved()
    saved.kinds = CatalogKind.allCases.filter(kinds.contains).map(\.rawValue)
    saved.genreIDs = genreIDs
    saved.countryIDs = countryIDs.sorted()
    saved.finishedOnly = finishedOnly
    saved.yearFrom = yearFrom
    saved.yearTo = yearTo
    saved.kinopoiskMin = kinopoiskMin
    saved.kinopoiskMax = kinopoiskMax
    saved.imdbMin = imdbMin
    saved.imdbMax = imdbMax
    saved.minimumQuality = minimumQuality?.rawValue
    saved.sort = sort.rawValue
    return saved
  }

  public init(saved: Saved) {
    self.init(sort: saved.sort.flatMap(MediaSortOrder.init(rawValue:)) ?? .recentlyAdded)
    kinds = Set(saved.kinds.compactMap(CatalogKind.init(rawValue:)))
    genreIDs = saved.genreIDs
    countryIDs = Set(saved.countryIDs)
    finishedOnly = saved.finishedOnly
    yearFrom = saved.yearFrom
    yearTo = saved.yearTo
    kinopoiskMin = saved.kinopoiskMin
    kinopoiskMax = saved.kinopoiskMax
    imdbMin = saved.imdbMin
    imdbMax = saved.imdbMax
    minimumQuality = saved.minimumQuality.flatMap(VideoQuality.init(rawValue:))
  }

  /// What a typed search sends: the type (kinds) only — kino.pub's site offers nothing
  /// else next to a query. The rest stays picked for browsing.
  public var searchSubset: LibraryFilter {
    var subset = LibraryFilter()
    subset.kinds = kinds
    return subset
  }
}
