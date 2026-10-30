//
//  MediaCardView.swift
//
//

import Foundation
import SwiftUI
import KinoPubBackend
import KinoPubMedia

/// What a single-click / Select on the card does.
public enum MediaCardPrimaryAction: String, Codable, Hashable, Sendable {
  /// Push the title detail page (default catalog posters).
  case openDetail
  /// Fetch + open the player at the resume point (Continue Watching).
  case play
}

/// Icon + value shown under a card title (collection watchers / views, etc.).
public struct MediaCardCaptionStat: Hashable, Codable, Sendable {
  public let systemImage: String
  public let value: String

  public init(systemImage: String, value: String) {
    self.systemImage = systemImage
    self.value = value
  }
}

/// Everything a poster card needs to draw itself, so rows can be built from any
/// endpoint's payload rather than only from a full `MediaItem`.
public struct MediaCard: Identifiable, Hashable, Codable, Sendable {
  public let id: Int
  public let posterURL: String
  public let title: String
  public let subtitle: String?
  /// When this was watched, for history surfaces. **On the card, not beside it**: the
  /// card is what `ContentStore` snapshots, so a date kept in a parallel map is lost
  /// the moment page 1 is served from cache — which is what put a warm-cache history
  /// list entirely into the "Earlier" section.
  public let watchedAt: Date?
  /// External catalogue scores. Prefer this over pulling fields off `MediaItem`.
  public let scores: MediaScores

  /// Convenience for call sites / Codable that still speak in loose doubles.
  public var imdbRating: Double? { scores.imdb }
  public var kinopoiskRating: Double? { scores.kinopoisk }

  /// The combined score shown on the poster, or nil when neither source rated it.
  public var rating: Rating? { scores.aggregate }
  /// `WatchProgress.resumeFraction` — 0…1 while this video is in progress, nil
  /// when unwatched or already finished. Do not re-threshold it in the view.
  ///
  /// TODO: a copy of viewer state, like `isWatched` — moves to `ViewerState` read at paint
  /// time with the card's migration (docs/media-model.md step 4); not deprecated yet
  /// because every card's chrome still paints from it.
  public let progress: Double?
  public let badge: String?

  /// Wide artwork for the page behind the card, shown while it holds focus. Nil
  /// falls back to whatever the card itself draws.
  public let backdropURL: String?
  /// kino.pub sent a `wide` field for this title — not a `/wide/` path derived from big/medium.
  public let hasSpecifiedWideArtwork: Bool

  /// The plot, for the focus preview.
  public let overview: String?

  /// When set the card renders wide instead of as a poster — used by Continue
  /// Watching, where the artwork is an episode still.
  public let landscapeImageURL: String?
  /// Overlaid on a landscape card, e.g. "S2, E5 · 42 min".
  public let overlayLabel: String?
  /// The name of the video Play opens, for a title in several — a concert's next set. Continue
  /// Watching shows it in place of the title while the card is focused (Sasha, 2026-10-26).
  public let offeredName: String?
  /// The still of the episode or video the card offers, when the card itself draws the
  /// title's wide cover: shown in its place while the pointer is over the card (Sasha,
  /// 2026-10-30).
  public let hoverStillURL: String?

  /// The title this card belongs to. For an episode card this is the series id;
  /// for a normal poster it matches `id`.
  public let itemID: Int
  /// Episode/video number for `/v1/watching/toggle`. Nil when the card is just a poster.
  public let video: Int?
  /// Season number for series episodes. Nil for films.
  public let season: Int?
  /// How many seasons the series has that we know of: one, and it is the first, and the
  /// card says «E2» / «2 серия» without the season (`EpisodeText`). Nil when unknown.
  public let seasonCount: Int?
  /// How many episodes in the series/season when known.
  public let episodeCount: Int?
  /// History media id for `/v1/history/clear-for-media`. Nil clears the whole item.
  public let mediaID: Int?
  /// Whether this video is already marked watched — drives the context-menu label.
  public let isWatched: Bool
  /// True for serials, so the context menu can say "Go to Show" rather than "Go to Movie".
  public let isSeries: Bool
  /// Title appears in `/v1/history` — context menu can offer Browse History.
  public let isInHistory: Bool
  /// Follow (a series' alone) and bookmark folders as this card knows them — the
  /// payload's word, or today's state once `ContentStore` laid it over
  /// (`withViewerState`). It is what the card paints; a menu or folder picker asks
  /// `ViewerStateReader` for `ref` when it opens. Watched and progress are still their
  /// own fields above.
  public let viewerState: ViewerState
  /// Item-level 4K / HDR when known from the catalogue payload (not device caps).
  public let is4K: Bool
  public let isHDR: Bool
  public let isHD: Bool
  public let is3D: Bool
  public let hasClosedCaptions: Bool
  /// Release year when known from the catalogue.
  public let year: Int?
  /// Last air year for a show that has ended. Nil while it is ongoing, for a film,
  /// or when the listing never said. A caption of `2019–2024` needs both years.
  public let yearEnd: Int?
  /// Episodes of a followed series that are still unwatched (`/v1/watching/serials` → `new`),
  /// when the payload says; nil for everything else. A poster's caption under the cover shows
  /// it in place of the year.
  public let unwatchedEpisodes: Int?
  /// Runtime in seconds (film total, or episode when the card is an episode still).
  public let durationSeconds: Int?
  /// The title's genres as the media model has them, the primary first — facts, not
  /// words. A caption names the primary at paint time (`primaryGenre(language:)`), and a
  /// filter matches any of them.
  public let genres: [Genre]
  /// The first production country, as the source names it.
  public let country: String?
  /// Single-click / Select target. Continue Watching uses `.play`; History stays detail for now.
  public let primaryAction: MediaCardPrimaryAction
  /// A lock and these words on top of a landscape still: an episode that has aired and is
  /// not on kino.pub («Нет на Кинопабе»). Not encoded — the rail builds it every time.
  public var unavailableNotice: String? = nil
  /// When true, Select opens a curated collection rather than a media title — Home /
  /// Collections grids use this so collection ids are not mistaken for item ids.
  public let opensCollection: Bool
  /// Icon + counter stack under the title (watchers / views on collection covers).
  public let captionStats: [MediaCardCaptionStat]
  /// kino.pub's numeric IMDb and Kinopoisk ids, so a card can be looked up in external
  /// metadata (the Home banner's title logo) without fetching the item first.
  public let imdbID: Int?
  public let kinopoiskID: Int?

  public var isLandscape: Bool { landscapeImageURL != nil }

  /// What the focus backdrop draws: the wide artwork where the payload carried one,
  /// the card's own image otherwise.
  public var backdropImageURL: String {
    backdropURL ?? landscapeImageURL ?? posterURL
  }

  /// Whether a long-press  can toggle watched for this card (needs a video target).
  public var canToggleWatched: Bool { video != nil }

  /// Score for the plaque / caption, honouring the user's source preference.
  public func displayRating(source: MediaCardRatingSource) -> Rating? {
    scores.selecting(source).aggregate
  }

  /// Scores filtered to the user's source preference (for `MediaScoresView`).
  public func displayScores(source: MediaCardRatingSource) -> MediaScores {
    scores.selecting(source)
  }

  /// Compact runtime for captions when `durationSeconds` is set.
  public var durationLabel: String? {
    guard let durationSeconds, durationSeconds >= 60 else { return nil }
    return RuntimeText(seconds: durationSeconds).formatted(.short)
  }

  /// One genre, the primary, in the viewer's language — what a caption has room for (D7).
  public func primaryGenre(language: MediaLanguage = .current) -> String? {
    genres.first.map { $0.name.value(languageCode: language.rawValue) }
  }

  /// «3 сезона» for a series whose season count is known; nil for a film and for a listed
  /// series, whose payload carries no seasons.
  public func seasonCountText(language: MediaLanguage = .current) -> String? {
    guard isSeries else { return nil }
    return SeasonCountText(seasonCount)?.formatted(language: language)
  }

  /// A film's year, an ongoing series' year, or `2019–2024` once a show has ended
  /// in a later year. Same year twice is just the year.
  public var yearLabel: String? {
    if isSeries, let start = year, let end = yearEnd, end > start {
      return "\(start)–\(end)"
    }
    return year.map(String.init)
  }

  /// `Год Жанр` / `2019–2024 Жанр` — the line under a cover in a catalog grid
  /// (search, collections, person credits, Library bookmarks). Year first so
  /// titles of the same genre sort by eye; an ended series keeps its span.
  ///
  /// A concert says the tour instead of the genre: kino.pub's title is
  /// "Artist / The Eras Tour", and the half after "/" is that continuation.
  /// `omittingGenreIDs` is the section the cover is already in (documentary,
  /// anime, animation), so the line names the next genre rather than repeating it.
  public func catalogCaption(language: MediaLanguage = .current,
                             omittingGenreIDs: Set<String> = []) -> String? {
    switch (yearLabel, catalogDetail(language: language, omittingGenreIDs: omittingGenreIDs)) {
    case let (year?, detail?): return "\(year) \(detail)"
    case let (year?, nil): return year
    case let (nil, detail?): return detail
    default: return nil
    }
  }

  /// The words after the year: a concert's tour, otherwise one genre.
  func catalogDetail(language: MediaLanguage = .current,
                     omittingGenreIDs: Set<String> = []) -> String? {
    if let tour = concertContinuation { return tour }
    let genre = omittingGenreIDs.isEmpty
      ? genres.first
      : genres.first { !omittingGenreIDs.contains($0.id) }
    return genre?.name.value(languageCode: language.rawValue)
  }

  /// "Artist / The Eras Tour" — the card's title is the artist, `subtitle` the tour.
  /// A film's subtitle is a translation, so this stays nil unless the genres are music
  /// (or the title is filed as a concert and nothing else).
  private var concertContinuation: String? {
    guard genres.contains(where: { $0.domain == .music || $0.id == "concert" }) else { return nil }
    guard let subtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
          !subtitle.isEmpty,
          subtitle.caseInsensitiveCompare(title) != .orderedSame else { return nil }
    return subtitle
  }

  /// Finds the primary meaningful genre, skipping obvious generic categories (anime, animation, cartoon).
  public func usefulGenre(language: MediaLanguage = .current) -> String? {
    let genericKeywords = ["anime", "аниме", "animation", "анимация", "мультфильм", "мультфильмы", "cartoon"]
    for genre in genres {
      let id = genre.id.lowercased()
      let ru = genre.name.ru.lowercased()
      let en = genre.name.en.lowercased()
      let isGeneric = genericKeywords.contains { id.contains($0) || ru.contains($0) || en.contains($0) }
      if !isGeneric {
        return genre.name.value(languageCode: language.rawValue)
      }
    }
    return primaryGenre(language: language)
  }

  /// Duration or volume line for banner:
  /// - Series with 2+ seasons: "2 сезона" / "2 seasons"
  /// - Series with 1 season: episode count "8 серий" / "8 episodes"
  /// - Film: runtime (e.g. "135 мин")
  public func bannerDurationText(language: MediaLanguage = .current) -> String? {
    if isSeries {
      let seasons = seasonCount ?? 1
      if seasons > 1 {
        return SeasonCountText(seasons)?.formatted(language: language)
      } else {
        let episodes = episodeCount ?? (unwatchedEpisodes ?? 8)
        return EpisodesLeftText(episodes)?.formatted(language: language)
      }
    } else {
      return durationLabel
    }
  }

  /// Formats year/span for banner: 2026, 2024–26.
  public var bannerYearSpan: String? {
    guard let start = year else { return nil }
    if isSeries, let end = yearEnd, end > start {
      if start / 100 == end / 100 {
        return "\(start)–\(String(format: "%02d", end % 100))"
      } else {
        return "\(start)–\(end)"
      }
    }
    return String(start)
  }

  /// Exact-geometry placeholder card for skeleton rows.
  public static func placeholder(id: Int = -1) -> MediaCard {
    MediaCard(
      id: id,
      posterURL: "",
      title: "",
      overview: nil
    )
  }

  public init(id: Int,
              posterURL: String,
              title: String,
              subtitle: String? = nil,
              watchedAt: Date? = nil,
              scores: MediaScores? = nil,
              imdbRating: Double? = nil,
              imdbVotes: Int? = nil,
              kinopoiskRating: Double? = nil,
              kinopoiskVotes: Int? = nil,
              progress: Double? = nil,
              badge: String? = nil,
              backdropURL: String? = nil,
              hasSpecifiedWideArtwork: Bool = false,
              overview: String? = nil,
              landscapeImageURL: String? = nil,
              overlayLabel: String? = nil,
              offeredName: String? = nil,
              hoverStillURL: String? = nil,
              itemID: Int? = nil,
              video: Int? = nil,
              season: Int? = nil,
              seasonCount: Int? = nil,
              episodeCount: Int? = nil,
              mediaID: Int? = nil,
              isWatched: Bool = false,
              isSeries: Bool = false,
              isInHistory: Bool = false,
              viewerState: ViewerState = .unknown,
              is4K: Bool = false,
              isHDR: Bool = false,
              isHD: Bool = false,
              is3D: Bool = false,
              hasClosedCaptions: Bool = false,
              year: Int? = nil,
              yearEnd: Int? = nil,
              unwatchedEpisodes: Int? = nil,
              durationSeconds: Int? = nil,
              genres: [Genre] = [],
              country: String? = nil,
              primaryAction: MediaCardPrimaryAction = .openDetail,
              opensCollection: Bool = false,
              captionStats: [MediaCardCaptionStat] = [],
              imdbID: Int? = nil,
              kinopoiskID: Int? = nil) {
    self.id = id
    self.posterURL = posterURL
    self.title = title
    self.subtitle = subtitle
    self.watchedAt = watchedAt
    self.scores = scores ?? MediaScores(
      imdb: imdbRating,
      imdbVotes: imdbVotes,
      kinopoisk: kinopoiskRating,
      kinopoiskVotes: kinopoiskVotes
    )
    self.progress = progress
    self.badge = badge
    self.backdropURL = backdropURL
    self.hasSpecifiedWideArtwork = hasSpecifiedWideArtwork
    self.overview = overview
    self.landscapeImageURL = landscapeImageURL
    self.overlayLabel = overlayLabel
    self.offeredName = offeredName
    self.hoverStillURL = hoverStillURL
    self.itemID = itemID ?? id
    self.video = video
    self.season = season
    self.seasonCount = seasonCount
    self.episodeCount = episodeCount
    self.mediaID = mediaID
    self.isWatched = isWatched
    self.isSeries = isSeries
    self.isInHistory = isInHistory
    self.viewerState = viewerState
    self.is4K = is4K
    self.isHDR = isHDR
    self.isHD = isHD
    self.is3D = is3D
    self.hasClosedCaptions = hasClosedCaptions
    self.year = year
    self.yearEnd = yearEnd
    self.unwatchedEpisodes = unwatchedEpisodes
    self.durationSeconds = durationSeconds
    self.genres = genres
    self.country = country
    self.primaryAction = primaryAction
    self.opensCollection = opensCollection
    self.captionStats = captionStats
    self.imdbID = imdbID
    self.kinopoiskID = kinopoiskID
  }

  /// Continue Watching paint-time overlay: progress / offered S/E change without
  /// rebuilding the rest of the card (artwork, badges, identity).
  public func withContinueWatching(progress: Double?,
                                   season: Int?,
                                   video: Int?,
                                   overlayLabel: String?,
                                   durationSeconds: Int? = nil) -> MediaCard {
    MediaCard(id: id,
              posterURL: posterURL,
              title: title,
              subtitle: subtitle,
              watchedAt: watchedAt,
              scores: scores,
              progress: progress,
              badge: badge,
              backdropURL: backdropURL,
              hasSpecifiedWideArtwork: hasSpecifiedWideArtwork,
              overview: overview,
              landscapeImageURL: landscapeImageURL,
              overlayLabel: overlayLabel,
              offeredName: offeredName,
              hoverStillURL: hoverStillURL,
              itemID: itemID,
              video: video,
              season: season,
              seasonCount: seasonCount,
              episodeCount: episodeCount,
              mediaID: mediaID,
              isWatched: isWatched,
              isSeries: isSeries,
              isInHistory: isInHistory,
              viewerState: viewerState,
              is4K: is4K,
              isHDR: isHDR,
              isHD: isHD,
              is3D: is3D,
              hasClosedCaptions: hasClosedCaptions,
              year: year,
              yearEnd: yearEnd,
              unwatchedEpisodes: unwatchedEpisodes,
              durationSeconds: durationSeconds ?? self.durationSeconds,
              genres: genres,
              country: country,
              primaryAction: primaryAction,
              opensCollection: opensCollection,
              captionStats: captionStats,
              imdbID: imdbID,
              kinopoiskID: kinopoiskID)
  }

  public func withBackdropURL(_ backdropURL: String?) -> MediaCard {
    MediaCard(id: id,
              posterURL: posterURL,
              title: title,
              subtitle: subtitle,
              watchedAt: watchedAt,
              scores: scores,
              progress: progress,
              badge: badge,
              backdropURL: backdropURL ?? self.backdropURL,
              hasSpecifiedWideArtwork: hasSpecifiedWideArtwork,
              overview: overview,
              landscapeImageURL: landscapeImageURL,
              overlayLabel: overlayLabel,
              offeredName: offeredName,
              hoverStillURL: hoverStillURL,
              itemID: itemID,
              video: video,
              season: season,
              seasonCount: seasonCount,
              episodeCount: episodeCount,
              mediaID: mediaID,
              isWatched: isWatched,
              isSeries: isSeries,
              isInHistory: isInHistory,
              viewerState: viewerState,
              is4K: is4K,
              isHDR: isHDR,
              isHD: isHD,
              is3D: is3D,
              hasClosedCaptions: hasClosedCaptions,
              year: year,
              yearEnd: yearEnd,
              unwatchedEpisodes: unwatchedEpisodes,
              durationSeconds: durationSeconds,
              genres: genres,
              country: country,
              primaryAction: primaryAction,
              opensCollection: opensCollection,
              captionStats: captionStats,
              imdbID: imdbID,
              kinopoiskID: kinopoiskID)
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(Int.self, forKey: .id)
    posterURL = try c.decode(String.self, forKey: .posterURL)
    title = try c.decode(String.self, forKey: .title)
    subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
    watchedAt = try c.decodeIfPresent(Date.self, forKey: .watchedAt)
    scores = MediaScores(
      imdb: try c.decodeIfPresent(Double.self, forKey: .imdbRating),
      imdbVotes: try c.decodeIfPresent(Int.self, forKey: .imdbVotes),
      kinopoisk: try c.decodeIfPresent(Double.self, forKey: .kinopoiskRating),
      kinopoiskVotes: try c.decodeIfPresent(Int.self, forKey: .kinopoiskVotes)
    )
    progress = try c.decodeIfPresent(Double.self, forKey: .progress)
    badge = try c.decodeIfPresent(String.self, forKey: .badge)
    backdropURL = try c.decodeIfPresent(String.self, forKey: .backdropURL)
    hasSpecifiedWideArtwork = try c.decodeIfPresent(Bool.self, forKey: .hasSpecifiedWideArtwork) ?? false
    overview = try c.decodeIfPresent(String.self, forKey: .overview)
    landscapeImageURL = try c.decodeIfPresent(String.self, forKey: .landscapeImageURL)
    overlayLabel = try c.decodeIfPresent(String.self, forKey: .overlayLabel)
    offeredName = try c.decodeIfPresent(String.self, forKey: .offeredName)
    hoverStillURL = try c.decodeIfPresent(String.self, forKey: .hoverStillURL)
    itemID = try c.decodeIfPresent(Int.self, forKey: .itemID) ?? id
    video = try c.decodeIfPresent(Int.self, forKey: .video)
    season = try c.decodeIfPresent(Int.self, forKey: .season)
    seasonCount = try c.decodeIfPresent(Int.self, forKey: .seasonCount)
    episodeCount = try c.decodeIfPresent(Int.self, forKey: .episodeCount)
    mediaID = try c.decodeIfPresent(Int.self, forKey: .mediaID)
    isWatched = try c.decodeIfPresent(Bool.self, forKey: .isWatched) ?? false
    isSeries = try c.decodeIfPresent(Bool.self, forKey: .isSeries) ?? false
    isInHistory = try c.decodeIfPresent(Bool.self, forKey: .isInHistory) ?? false
    is4K = try c.decodeIfPresent(Bool.self, forKey: .is4K) ?? false
    isHDR = try c.decodeIfPresent(Bool.self, forKey: .isHDR) ?? false
    isHD = try c.decodeIfPresent(Bool.self, forKey: .isHD) ?? false
    is3D = try c.decodeIfPresent(Bool.self, forKey: .is3D) ?? false
    hasClosedCaptions = try c.decodeIfPresent(Bool.self, forKey: .hasClosedCaptions) ?? false
    year = try c.decodeIfPresent(Int.self, forKey: .year)
    yearEnd = try c.decodeIfPresent(Int.self, forKey: .yearEnd)
    unwatchedEpisodes = try c.decodeIfPresent(Int.self, forKey: .unwatchedEpisodes)
    durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
    if let genres = try c.decodeIfPresent([Genre].self, forKey: .genres) {
      self.genres = genres
    } else if let line = try c.decodeIfPresent(String.self, forKey: .genreLine),
              let name = line.components(separatedBy: ", ").first, !name.isEmpty {
      // A card written before genres were facts kept the primary's name only.
      self.genres = [Genre.unmapped(source: .kinopub, key: name, name: name, domain: .video)]
    } else {
      self.genres = []
    }
    country = try c.decodeIfPresent(String.self, forKey: .country)
      ?? c.decodeIfPresent(String.self, forKey: .countryLine)
    if let state = try c.decodeIfPresent(ViewerState.self, forKey: .viewerState) {
      viewerState = state
    } else {
      // A card written before the three copies became one value.
      let following = try c.decodeIfPresent(Bool.self, forKey: .isInWatchlist)
      let folders = try c.decodeIfPresent([Int].self, forKey: .bookmarkFolderIDs) ?? []
      viewerState = ViewerState(isFollowing: isSeries ? following : nil,
                                bookmarkFolderIDs: folders.isEmpty ? nil : Set(folders))
    }
    // Old row snapshots omit this key — keep opening detail until the next CW fetch.
    primaryAction = try c.decodeIfPresent(MediaCardPrimaryAction.self, forKey: .primaryAction)
      ?? .openDetail
    opensCollection = try c.decodeIfPresent(Bool.self, forKey: .opensCollection) ?? false
    captionStats = try c.decodeIfPresent([MediaCardCaptionStat].self, forKey: .captionStats) ?? []
    imdbID = try c.decodeIfPresent(Int.self, forKey: .imdbID)
    kinopoiskID = try c.decodeIfPresent(Int.self, forKey: .kinopoiskID)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(posterURL, forKey: .posterURL)
    try c.encode(title, forKey: .title)
    try c.encodeIfPresent(subtitle, forKey: .subtitle)
    try c.encodeIfPresent(watchedAt, forKey: .watchedAt)
    try c.encodeIfPresent(scores.imdb, forKey: .imdbRating)
    try c.encodeIfPresent(scores.imdbVotes, forKey: .imdbVotes)
    try c.encodeIfPresent(scores.kinopoisk, forKey: .kinopoiskRating)
    try c.encodeIfPresent(scores.kinopoiskVotes, forKey: .kinopoiskVotes)
    try c.encodeIfPresent(progress, forKey: .progress)
    try c.encodeIfPresent(badge, forKey: .badge)
    try c.encodeIfPresent(backdropURL, forKey: .backdropURL)
    try c.encode(hasSpecifiedWideArtwork, forKey: .hasSpecifiedWideArtwork)
    try c.encodeIfPresent(overview, forKey: .overview)
    try c.encodeIfPresent(landscapeImageURL, forKey: .landscapeImageURL)
    try c.encodeIfPresent(overlayLabel, forKey: .overlayLabel)
    try c.encodeIfPresent(offeredName, forKey: .offeredName)
    try c.encodeIfPresent(hoverStillURL, forKey: .hoverStillURL)
    try c.encode(itemID, forKey: .itemID)
    try c.encodeIfPresent(video, forKey: .video)
    try c.encodeIfPresent(season, forKey: .season)
    try c.encodeIfPresent(seasonCount, forKey: .seasonCount)
    try c.encodeIfPresent(episodeCount, forKey: .episodeCount)
    try c.encodeIfPresent(mediaID, forKey: .mediaID)
    try c.encode(isWatched, forKey: .isWatched)
    try c.encode(isSeries, forKey: .isSeries)
    try c.encode(isInHistory, forKey: .isInHistory)
    try c.encode(is4K, forKey: .is4K)
    try c.encode(isHDR, forKey: .isHDR)
    try c.encode(isHD, forKey: .isHD)
    try c.encode(is3D, forKey: .is3D)
    try c.encode(hasClosedCaptions, forKey: .hasClosedCaptions)
    try c.encodeIfPresent(year, forKey: .year)
    try c.encodeIfPresent(yearEnd, forKey: .yearEnd)
    try c.encodeIfPresent(unwatchedEpisodes, forKey: .unwatchedEpisodes)
    try c.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
    try c.encode(genres, forKey: .genres)
    try c.encodeIfPresent(country, forKey: .country)
    try c.encode(viewerState, forKey: .viewerState)
    try c.encode(primaryAction, forKey: .primaryAction)
    try c.encode(opensCollection, forKey: .opensCollection)
    try c.encode(captionStats, forKey: .captionStats)
    try c.encodeIfPresent(imdbID, forKey: .imdbID)
    try c.encodeIfPresent(kinopoiskID, forKey: .kinopoiskID)
  }

  private enum CodingKeys: String, CodingKey {
    case id, posterURL, title, subtitle, watchedAt, imdbRating, imdbVotes, kinopoiskRating, kinopoiskVotes
    case progress, badge, backdropURL, hasSpecifiedWideArtwork, overview
    case landscapeImageURL, overlayLabel, offeredName, hoverStillURL, itemID, video, season, seasonCount, episodeCount, mediaID
    case isWatched, isSeries, isInHistory, viewerState, is4K, isHDR
    case isHD, is3D, hasClosedCaptions, year, yearEnd, unwatchedEpisodes, durationSeconds
    case genres, country, primaryAction
    case opensCollection, captionStats, imdbID, kinopoiskID
    /// Read from cards written before `viewerState` and `genres`, never written.
    case isInWatchlist, bookmarkFolderIDs, genreLine, countryLine
  }
}

public extension MediaCard {
  /// The standard mapping from a catalog item, so grids and rows draw the same card:
  /// the payload into the media model (`KinoPubMediaMapping`), then the model's card
  /// (`MediaCard(ref:entity:state:)`).
  init(_ item: MediaItem) {
    self.init(ref: item.titleRef, entity: item.mediaEntity, state: ViewerState(reportedBy: item))
  }
}

/// Where a card's name is drawn, if anywhere.
public enum MediaCardCaption {
  /// Never — the screen names the focused item somewhere else, as the home rows do
  /// in their preview.
  case none
  /// Only while the card holds focus, over space kept free for it so the grid does
  /// not shift as focus moves. What a grid with no preview of its own uses.
  case onFocus
  /// Always, for platforms with no focus at all.
  case always
}

private struct CatalogCaptionOmittedGenreIDsKey: EnvironmentKey {
  static let defaultValue: Set<String> = []
}

public extension EnvironmentValues {
  /// Genre ids the catalog listing already is — documentary, anime, animation —
  /// so a cover's caption names the next genre instead of repeating the section.
  var catalogCaptionOmittedGenreIDs: Set<String> {
    get { self[CatalogCaptionOmittedGenreIDsKey.self] }
    set { self[CatalogCaptionOmittedGenreIDsKey.self] = newValue }
  }
}

/// Poster or landscape card. Width comes from the parent (`containerRelativeFrame` /
/// grid column); height from `CardAspect`. Landscape cards follow the episode-rail
/// layout: play glyph + progress on the still, title / meta in the caption below —
/// no ⋯ overflow control on the card (long-press context menu only).
///
/// Behavioural identity: same focus animation, caption reveal, progress semantics,
/// watched treatment and existing badge slots; only aspect and which slots have
/// content differ. New badge slots (editorial awards etc.) wait on design (D10).
public struct MediaCardView: View {

  private let card: MediaCard
  private let caption: MediaCardCaption
  private let playChromeStyle: LandscapePlayChromeStyle
  /// When true, play chrome stays visible (previews / VariantGallery).
  private let forcePlayChrome: Bool

  public init(card: MediaCard,
              caption: MediaCardCaption = .always,
              playChromeStyle: LandscapePlayChromeStyle = .glass,
              forcePlayChrome: Bool = false) {
    self.card = card
    self.caption = caption
    self.playChromeStyle = playChromeStyle
    self.forcePlayChrome = forcePlayChrome
  }

  @Environment(\.isFocused) private var cardFocused
#if os(macOS)
  @State private var isHovered = false
#endif

  /// A watched card's artwork sits dimmed, and on macOS hovering it restores it to full.
  /// `isHovered` only exists there — there is no pointer on tvOS or iOS — so the dim is
  /// simply constant off macOS rather than reading a state that does not compile.
  private var watchedArtworkOpacity: Double {
    guard dimsWatchedArtwork else { return 1 }
#if os(macOS)
    return isHovered ? 1 : 0.5
#else
    return 0.5
#endif
  }
  /// The artwork's own width, so its height is derived rather than negotiated. Nil for
  /// exactly one layout pass; `frame(height: nil)` leaves the natural size meanwhile.
  @State private var artworkWidth: CGFloat?

  @AppStorage(MediaCardDisplayPreferences.ratingPlacementKey)
  private var ratingPlacementRaw = MediaCardDisplayPreferences.defaultRatingPlacement.rawValue
  @AppStorage(MediaCardDisplayPreferences.ratingSourceKey)
  private var ratingSourceRaw = MediaCardDisplayPreferences.defaultRatingSource.rawValue
  @AppStorage(MediaCardDisplayPreferences.capabilityPlacementKey)
  private var capabilityPlacementRaw = MediaCardDisplayPreferences.defaultCapabilityPlacement.rawValue
  @AppStorage(MediaCardDisplayPreferences.show4KKey)
  private var show4K = MediaCardDisplayPreferences.defaultShow4K
  @AppStorage(MediaCardDisplayPreferences.showHDRKey)
  private var showHDR = MediaCardDisplayPreferences.defaultShowHDR
  @AppStorage(MediaCardDisplayPreferences.showHDKey)
  private var showHD = MediaCardDisplayPreferences.defaultShowHD
  @AppStorage(MediaCardDisplayPreferences.show3DKey)
  private var show3D = MediaCardDisplayPreferences.defaultShow3D
  @AppStorage(MediaCardDisplayPreferences.showCCKey)
  private var showCC = MediaCardDisplayPreferences.defaultShowCC
  @AppStorage(MediaCardDisplayPreferences.editorialPlacementKey)
  private var editorialPlacementRaw = MediaCardDisplayPreferences.defaultEditorialPlacement.rawValue
  @AppStorage(MediaCardDisplayPreferences.showOriginalTitleKey)
  private var showOriginalTitle = MediaCardDisplayPreferences.defaultShowOriginalTitle
  @AppStorage(MediaCardDisplayPreferences.showYearKey)
  private var showYear = MediaCardDisplayPreferences.defaultShowYear
  @AppStorage(MediaCardDisplayPreferences.showDurationKey)
  private var showDuration = MediaCardDisplayPreferences.defaultShowDuration
  @AppStorage(MediaCardDisplayPreferences.showGenreKey)
  private var showGenre = MediaCardDisplayPreferences.defaultShowGenre
  @Environment(\.catalogCaptionOmittedGenreIDs) private var omittedGenreIDs
  @Environment(\.mediaCardTitleFont) private var titleFont
  @AppStorage(MediaCardDisplayPreferences.showCountryKey)
  private var showCountry = MediaCardDisplayPreferences.defaultShowCountry
  @AppStorage(MediaCardDisplayPreferences.showBookmarkSymbolKey)
  private var showBookmarkSymbol = MediaCardDisplayPreferences.defaultShowBookmarkSymbol
  @AppStorage(MediaCardDisplayPreferences.progressVisibilityKey)
  private var progressVisibilityRaw = MediaCardDisplayPreferences.defaultProgressVisibility.rawValue
  @AppStorage(MediaCardDisplayPreferences.watchedStyleKey)
  private var watchedStyleRaw = MediaCardDisplayPreferences.defaultWatchedStyle.rawValue
  @AppStorage(CoverArtworkPreferences.languageKey) private var coverLanguage = ""

  private var ratingPlacement: MediaCardChromePlacement {
    MediaCardChromePlacement(rawValue: ratingPlacementRaw)
      ?? MediaCardDisplayPreferences.defaultRatingPlacement
  }
  private var ratingSource: MediaCardRatingSource {
    // With the aggregate off there is no source picker in Settings either, so every
    // card shows whatever it has, each score under its own logo.
    guard RatingFeature.combinedEnabled else { return .combined }
    return MediaCardRatingSource(rawValue: ratingSourceRaw)
      ?? MediaCardDisplayPreferences.defaultRatingSource
  }
  private var capabilityPlacement: MediaCardChromePlacement {
    MediaCardChromePlacement(rawValue: capabilityPlacementRaw)
      ?? MediaCardDisplayPreferences.defaultCapabilityPlacement
  }
  private var editorialPlacement: MediaCardChromePlacement {
    MediaCardChromePlacement(rawValue: editorialPlacementRaw)
      ?? MediaCardDisplayPreferences.defaultEditorialPlacement
  }
  private var watchedStyle: MediaCardWatchedStyle {
    MediaCardWatchedStyle(rawValue: watchedStyleRaw)
      ?? MediaCardDisplayPreferences.defaultWatchedStyle
  }
  private var progressVisibility: MediaCardProgressVisibility {
    MediaCardProgressVisibility(rawValue: progressVisibilityRaw)
      ?? MediaCardDisplayPreferences.defaultProgressVisibility
  }

  private var aspect: CardAspect { card.isLandscape ? .landscape : .poster }

  private var imageURL: String {
    _ = coverLanguage
    if card.isLandscape {
      return card.landscapeImageURL ?? card.posterURL
    }
    return card.coverURL
  }

  private var playsOnSelect: Bool { card.primaryAction == .play }

  private var activeRating: Rating? {
    card.displayRating(source: ratingSource)
  }

  private var filteredCapabilityBadges: MediaCapabilityBadges {
    MediaCapabilityBadges(
      is4K: show4K && card.is4K,
      isHD: showHD && card.isHD,
      isHDR: showHDR && card.isHDR,
      is3D: show3D && card.is3D,
      hasClosedCaptions: showCC && card.hasClosedCaptions
    )
  }

  private var capabilityChips: [String] {
    var chips: [String] = []
    let badges = filteredCapabilityBadges
    if badges.is4K { chips.append("4K") }
    else if badges.isHD { chips.append("HD") }
    if badges.isHDR { chips.append("HDR") }
    if badges.is3D { chips.append("3D") }
    if badges.hasClosedCaptions { chips.append("CC") }
    return chips
  }

  private var captionMetaParts: [String] {
    var parts: [String] = []
    // Duration lives on landscape artwork (Apple-style time chip), not in the caption.
    if showYear, showGenre,
       let caption = card.catalogCaption(omittingGenreIDs: omittedGenreIDs) {
      parts.append(caption)
    } else {
      if showYear, let year = card.yearLabel {
        parts.append(year)
      }
      if showGenre, let detail = card.catalogDetail(omittingGenreIDs: omittedGenreIDs) {
        parts.append(detail)
      }
    }
    if showCountry, let country = card.country, !country.isEmpty {
      parts.append(country)
    }
    return parts
  }

  private var captionScores: MediaScores {
    // With the aggregate off there is no source picker — show whatever we have.
    guard RatingFeature.combinedEnabled else { return card.scores }
    return card.displayScores(source: ratingSource)
  }

  private var showsCaptionScores: Bool {
    guard captionScores.hasDisplayableScore else { return false }
    // Labelled scores are the only rating a card has while the aggregate is off —
    // they are not the "Under title" branch of a setting that is no longer shown.
    guard RatingFeature.combinedEnabled else { return true }
    return ratingPlacement == .inCaption
  }

  private var showsPlayChrome: Bool {
    guard playsOnSelect else { return false }
    if forcePlayChrome { return true }
#if os(tvOS)
    return cardFocused
#elseif os(macOS)
    return isHovered
#else
    // Touch: the time chip's play glyph already says "this resumes". A second glyph
    // parked in the middle of every still only covers the picture.
    return false
#endif
  }

  private var dimsWatchedArtwork: Bool {
    card.isWatched && watchedStyle.dimsArtwork
  }

  private var isPointerActive: Bool {
#if os(macOS)
    isHovered
#elseif os(tvOS)
    cardFocused
#else
    true
#endif
  }

  /// The fraction the bar draws: the same `resumeFraction` the time chip reads for «Ещё N
  /// мин», so the two cannot disagree — a chip saying how much is left always has a bar,
  /// a watched or untouched card has neither. It used to drop the bar for anything past
  /// half watched: a fraction rounded to a whole number and compared with 1 (Sasha,
  /// 2026-10-30: «12m left» with no bar).
  private var inProgressFraction: Double? {
    guard !card.isWatched, let progress = card.progress, progress > 0, progress < 1 else { return nil }
    return progress
  }

  private var showsProgressBarNow: Bool {
    guard inProgressFraction != nil else { return false }
    switch progressVisibility {
    case .always: return true
    case .onFocusHover: return isPointerActive
    }
  }

  private var showsBookmarkOnArtwork: Bool {
    showBookmarkSymbol && (card.viewerState.isBookmarked || card.viewerState.isFollowing == true)
  }

  private var landscapeTimeBadge: LandscapeTimeBadge? {
    guard showDuration, card.isLandscape else { return nil }
    return LandscapeTimeBadge(
      durationSeconds: card.durationSeconds,
      progress: card.progress,
      isWatched: card.isWatched
    )
  }

  /// One caption line for landscape: "S1, E12 + 3 more", "E6 + 2 more", or either half alone.
  static let showsMoreEpisodesCount = false

  private var landscapeEpisodeLine: String? {
    guard card.isLandscape else { return nil }
    let episode = card.overlayLabel.flatMap { $0.isEmpty ? nil : $0 }
    let moreCount: Int? = {
      guard let badge = card.badge else { return nil }
      let digits = badge.filter(\.isNumber)
      guard let value = Int(digits), value > 0 else { return nil }
      return value
    }()
    // «+ ещё N» is off (Sasha, 2026-10-30): the line names the episode instead.
    guard Self.showsMoreEpisodesCount else { return episode }
    switch (episode, moreCount) {
    case (let episode?, let count?):
      return String(format: String(localized: "%@ + %d more"), episode, count)
    case (let episode?, nil):
      return episode
    case (nil, let count?):
      return String(format: String(localized: "+ %d more"), count)
    case (nil, nil):
      return nil
    }
  }

  public var body: some View {
      VStack(alignment: .center, spacing: Metrics.cardCaptionSpacing) {
      artwork

      if caption != .none {
        captionBlock
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(accessibilityTitle))
    .accessibilityValue(Text(accessibilityValue))
    .accessibilityHint(Text(accessibilityHint))
  }

  private var accessibilityHint: String {
    if card.opensCollection { return String(localized: "Opens the collection") }
    return playsOnSelect ? String(localized: "Plays or resumes") : String(localized: "Opens the title")
  }

  private var accessibilityTitle: String {
    if let subtitle = card.subtitle, !subtitle.isEmpty, subtitle != card.title {
      return "\(card.title), \(subtitle)"
    }
    return card.title
  }

  private var accessibilityValue: String {
    var parts: [String] = []
    if let rating = card.rating {
      parts.append("Rating \(rating.formatted)")
    }
    if let progress = card.progress {
      parts.append("\(Int((progress * 1).rounded())) percent watched")
    }
    for stat in card.captionStats {
      parts.append(stat.value)
    }
    if card.is4K { parts.append("4K") }
    if card.isHDR { parts.append("HDR") }
    if card.isWatched { parts.append("Watched") }
    return parts.joined(separator: ", ")
  }

  // MARK: - Artwork

  /// The cell's own width, measured where nothing can clamp it.
  ///
  /// A zero-height `Color.clear` under `maxWidth: .infinity` takes the full width it is
  /// offered whatever the height proposal is, which is the whole point: measuring the
  /// artwork itself made the height it derived feed back into the width it was measured
  /// from, and `aspectRatio(_:contentMode: .fit)` treats *every* width ≤ the offered one
  /// as a valid answer to that. So the card kept whatever width it happened to land on
  /// first — a window resize widened the column and the poster stayed put while the
  /// caption under it grew to the new column, which is the gap that opened between rows.
  private var widthProbe: some View {
    Color.clear
      .frame(maxWidth: .infinity)
      .frame(height: 0)
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.width
      } action: { width in
        if width > 0 { artworkWidth = width }
      }
  }

  @ViewBuilder
  private var artwork: some View {
    VStack(spacing: 0) {
      widthProbe
      artworkBox
    }
  }

  @ViewBuilder
  private var artworkBox: some View {
    ZStack {
      stillImage

      if card.isLandscape {
        landscapeOverlays
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if showsProgressBarNow, card.isLandscape, let progress = inProgressFraction {
        progressBar(progress)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      }

      // Top-trailing chips (4K + bookmark). Editorial +N on landscape is a caption label.
      artworkTopTrailing
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

      if !card.isLandscape {
        posterOverlays
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

#if os(macOS)
      // Cheap pointer affordance — dim the still, keep the glass rim on top.
        // Not on a landscape card with nothing to play (an episode not out, or not on
        // kino.pub): the dim is the play affordance there (Sasha, 2026-10-30).
        Color.black.opacity(card.isLandscape && !playsOnSelect ? 0
                            : (isHovered && !card.isWatched && dimsWatchedArtwork) ? 0.34
                            : (isHovered && !dimsWatchedArtwork) ? 0.34 : 0)
        .allowsHitTesting(false)
#endif

      if showsPlayChrome {
        LandscapePlayChromeView(style: playChromeStyle)
          .transition(.opacity.combined(with: .scale(scale: 0.92)))
          .allowsHitTesting(false)
      }
    }
    // Height measured from the card's own width, never negotiated with the caption.
    //
    // This was `.aspectRatio(_:contentMode: .fit)`, which means "fit inside whatever
    // you are offered" — so in a horizontal rail, where the row equalises card heights,
    // a two-line caption ("S1, E1 + 2 more") ate into the artwork and the tile beside a
    // one-line caption came out taller. Continue Watching showed both in the same row.
    // A grid hid the bug because its rows leave height free.
    //
    // Width → height is the only direction that holds in every container.
    .frame(maxWidth: .infinity)
    // Sized correctly on the *first* pass too. Without this the unmeasured frame is
    // `height: nil` — the stack's natural size, which is far larger than the card —
    // and the snap to the measured height rode the subtree's transaction animation,
    // so every card scrolling into view zoomed down from giant. `.fit` gives the right
    // box immediately; the measured frame below then holds it against a caption that
    // would otherwise squeeze it.
    .aspectRatio(aspect.ratio, contentMode: .fit)
    // Pinned in both directions once the probe has reported: `fit` inside exactly
    // `w × w/ratio` is exactly `w × w/ratio`, so the artwork fills its column instead
    // of settling for any narrower box that also satisfies the ratio.
    .frame(width: artworkWidth, height: artworkWidth.map { $0 / aspect.ratio })
    // Never animated: this is a layout fact arriving, not a state change worth showing.
    // `ArtworkImage` sets an animation on its whole subtree for the image fade, and
    // this frame was being carried along by it.
    .animation(nil, value: artworkWidth)
    .opacity(watchedArtworkOpacity)
    .animation(.easeOut(duration: 0.2), value: showsPlayChrome)
#if os(tvOS)
    // One composited lockup so `.borderless` lift/specular stays a single unit —
    // rating/status chips sit inside the hover group rather than as sibling images.
    .hoverEffect(.highlight)
#else
    .clipShape(Self.artworkShape)
    .kinoGlassRim(in: Self.artworkShape)
#if os(macOS)
    .onHover { isHovered = $0 }
    .animation(.easeOut(duration: 0.2), value: isHovered)
    .pointingHandCursorOnHover()
#endif
#endif
  }

  private static var artworkShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
  }

  @ViewBuilder
  private var posterOverlays: some View {
    ZStack(alignment: .topLeading) {
      Color.clear
      if RatingFeature.combinedEnabled, ratingPlacement == .onArtwork, let rating = activeRating {
        RatingBadgeView(rating: rating)
          .padding(3)
          .accessibilityLabel(Text("Rating \(rating.formatted)"))
      }
    }
    .overlay(alignment: .topTrailing) {
      if !card.isLandscape, card.isWatched, watchedStyle.showsCheckmark {
        Image(systemName: "checkmark.circle.fill")
          .font(.caption.weight(.bold))
          .foregroundStyle(.white)
//#if !os(tvOS)
          // Per-card shadow, rendered on every visible watched glyph in a shelf —
          // measurable tvOS shelf-scroll cost for a barely-visible glow. Off there.
//          .shadow(radius: 4)
//#endif
          .padding(3)
      }
    }
  }

  /// Capability chips + optional bookmark on the artwork (bookmark is rightmost).
  /// Landscape keeps +N out of this corner — it becomes a caption label instead.
  private var artworkTopTrailing: some View {
    HStack(alignment: .top, spacing: 6) {
      if !card.isLandscape, editorialPlacement == .onArtwork, let badge = card.badge {
        editorialBadge(badge)
      }
      if capabilityPlacement == .onArtwork, !capabilityChips.isEmpty {
        capabilityBadgesRow
      }
      if showsBookmarkOnArtwork {
        Image(systemName: "bookmark.fill")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white)
//#if !os(tvOS)
//          .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
//#endif
          .accessibilityLabel(Text("Bookmarked"))
      }
    }
    .padding(6)
  }

  private var capabilityBadgesRow: some View {
    HStack(spacing: 6) {
      ForEach(capabilityChips, id: \.self) { chip in
        Text(chip)
          .font(MediaCapabilityBadgesView.font)
          .foregroundStyle(.white)
          .padding(.horizontal, MediaCapabilityBadgesView.horizontalPadding)
          .padding(.vertical, MediaCapabilityBadgesView.verticalPadding)
          .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
          .accessibilityLabel(Text(chip))
      }
    }
  }

  private func editorialBadge(_ badge: String) -> some View {
    Text(badge)
      .font(.caption.weight(.bold))
      .padding(.horizontal, 4)
      .padding(.vertical, 3)
      .background(Color.KinoPub.accent, in: Capsule())
      .foregroundStyle(.black)
//#if !os(tvOS)
//      .shadow(radius: 4)
//#endif
  }

  private var stillImage: some View {
    // Clear + overlay is the reliable fill: the loader's ideal size otherwise
    // letterboxes inside the 16:9 lockup.
    Color.clear
      .overlay {
        CachedRemoteImage(
          url: URL(string: imageURL),
          contentMode: .fill,
          placeholder: { Color.KinoPub.placeholder },
          failure: { Color.KinoPub.placeholder }
        )
      }
      .overlay {
        // The offered episode's own still over the title's cover while hovered, crossfaded.
        if showsHoverStill, let url = card.hoverStillURL.flatMap(URL.init(string:)) {
          CachedRemoteImage(url: url, contentMode: .fill)
            .transition(.opacity)
        }
      }
      .animation(.easeInOut(duration: 0.3), value: showsHoverStill)
      .clipped()
  }

  private var showsHoverStill: Bool {
#if os(macOS)
    card.isLandscape && isPointerActive && card.hoverStillURL?.isEmpty == false
#else
    false
#endif
  }

  /// Progress along the bottom + time chip pinned bottom-leading (never centered).
  @ViewBuilder
  private var landscapeOverlays: some View {
    ZStack(alignment: .bottomLeading) {
      if showsProgressBarNow, card.isLandscape, let progress = inProgressFraction {
        progressBar(progress)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .bottomLeading) {
      if let landscapeTimeBadge {
        landscapeTimeBadge
          .padding(6)
      }
    }
    .overlay(alignment: .topLeading) {
      if let notice = card.unavailableNotice {
        // The time chip's look: the system's thin material, dark, over the still.
        Label(notice, systemImage: "lock.fill")
          .font(.caption2.weight(.medium))
          .labelStyle(.titleAndIcon)
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(.thinMaterial, in: Capsule(style: .continuous))
          .environment(\.colorScheme, .dark)
          .padding(6)
      }
    }
  }

  private func progressBar(_ progress: Double) -> some View {
    GeometryReader { geometry in
      // On the still, so not the page's colours: `subtitle` is near black in light mode
      // and the watched part vanished into the picture.
      ZStack(alignment: .leading) {
        Capsule().fill(Color.white.opacity(0.35))
        Capsule()
          .fill(Color.white)
          .frame(width: geometry.size.width * min(max(progress, 0), 1))
          .frame(height: 3)
      }
    }
    .frame(height: 3)
    .padding(.horizontal, 1)
  }

  // MARK: - Caption

  /// Hidden rather than absent while unfocused, so neighbouring cards keep their
  /// baselines and the row does not jump as focus travels along it.
  private var captionBlock: some View {
    VStack(alignment: .center, spacing: 4) {
      titleRow

      // History's "when did I watch this" line. Shown on landscape cards too, which
      // the original-title rule below deliberately excludes — a history row without a
      // date is the one thing this caption exists to say.
      if let watchedAt = card.watchedAt {
        Text(watchedAt.formatted(date: .abbreviated, time: .shortened))
          .font(TypeScale.cardMeta)
          .foregroundStyle(Color.KinoPub.subtitle)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .center)
      }

      // Original title is poster-only — landscape captions stay a single title line.
      // Collection covers reuse `subtitle` for the updated date; always show it
      // (independent of the "Original title" appearance toggle).
      if !card.isLandscape,
         (showOriginalTitle || card.opensCollection),
         let subtitle = card.subtitle,
         !subtitle.isEmpty,
         subtitle != card.title {
        Text(subtitle)
          .font(TypeScale.cardSubtitle)
          .foregroundStyle(Color.KinoPub.subtitle)
          .lineLimit(1)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity, alignment: .center)
      }

      if card.isLandscape, let line = landscapeEpisodeLine {
        Text(line)
          .font(TypeScale.cardMeta)
          .foregroundStyle(Color.KinoPub.subtitle)
          .lineLimit(1)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity, alignment: .center)
      }

      if showsCaptionScores {
        MediaScoresView(captionScores, collapsesVotesToFit: true)
          .font(TypeScale.cardMeta)
          .foregroundStyle(Color.KinoPub.subtitle)
      }

      if !card.captionStats.isEmpty {
        HStack(spacing: 10) {
          ForEach(Array(card.captionStats.enumerated()), id: \.offset) { _, stat in
            HStack(spacing: 4) {
              Image(systemName: stat.systemImage)
              Text(stat.value)
                .monospacedDigit()
            }
          }
        }
        .font(TypeScale.cardMeta)
        .foregroundStyle(Color.KinoPub.subtitle)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .center)
      }

      if !captionMetaParts.isEmpty {
        Text(captionMetaParts.joined(separator: " · "))
          .font(TypeScale.cardMeta)
          .foregroundStyle(Color.KinoPub.subtitle)
          .lineLimit(2)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity, alignment: .center)
      }

      captionFiller
    }
    .frame(maxWidth: .infinity, alignment: .center)
    // Never compressed. The artwork's height is pinned to its width now, so a row that
    // equalises card heights has only the caption left to squeeze — which is what cut
    // the second line off. Ideal height, always.
    .fixedSize(horizontal: false, vertical: true)
    .opacity(caption == .always || cardFocused ? 1 : 0)
    .animation(.easeOut(duration: 0.12), value: cardFocused)
  }

  /// Blank lines padding the caption out to a constant number, so every card in a row
  /// is exactly as tall as every other one.
  ///
  /// Reserved in *lines*, not points: a fixed height in points is what
  /// `TVUIKitPosterMetrics.captionHeight` does on tvOS, and it only holds there because
  /// that surface has one type size. Here the same caption is drawn at every Dynamic
  /// Type setting, so the reserve has to be expressed in the thing that actually scales.
  @ViewBuilder
  private var captionFiller: some View {
    let missing = Self.reservedCaptionLines(for: card) - captionLineCount
    if missing > 0 {
      ForEach(0..<missing, id: \.self) { _ in
        Text(verbatim: " ")
          .font(TypeScale.cardMeta)
          .lineLimit(1)
          .accessibilityHidden(true)
      }
    }
  }

  /// How many lines this card's caption actually draws.
  private var captionLineCount: Int {
    var lines = 1 // title
    if card.watchedAt != nil { lines += 1 }
    if !card.isLandscape,
       showOriginalTitle || card.opensCollection,
       let subtitle = card.subtitle, !subtitle.isEmpty, subtitle != card.title {
      lines += 1
    }
    if card.isLandscape, landscapeEpisodeLine != nil { lines += 1 }
    if showsCaptionScores { lines += 1 }
    if !card.captionStats.isEmpty { lines += 1 }
    if !captionMetaParts.isEmpty { lines += 1 }
    return lines
  }

  /// The constant every card of this shape pads up to. Landscape cards carry at most a
  /// title, a watched date and an episode line; posters carry a title plus one meta row
  /// — reserving the worst case for posters too would leave a visible hole under most
  /// of the catalogue, which is why the two shapes differ.
  private static func reservedCaptionLines(for card: MediaCard) -> Int {
    card.isLandscape ? 3 : 2
  }

  /// Title + optional caption chips hug as one group, then the group is centered.
  private var titleRow: some View {
    HStack(spacing: 0) {
      Spacer(minLength: 0)
      HStack(spacing: 6) {
        MarqueeText(
          card.title,
          // A landscape card is the title page's episode card, title and all (Sasha,
          // 2026-10-30): Continue Watching and History use the same step-up type.
          font: titleFont ?? (card.isLandscape ? TypeScale.episodeCardTitle : TypeScale.cardTitle),
          alignment: .center,
          fillsWidth: true,
          style: .title
        )
        .frame(minWidth: 0)

        if !card.isLandscape, editorialPlacement == .inCaption, let badge = card.badge {
          editorialBadge(badge)
            .fixedSize()
        }

        if capabilityPlacement == .inCaption, !capabilityChips.isEmpty {
          capabilityBadgesRow
            .fixedSize()
        }
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
  }

  // MARK: - Legacy metrics (call sites / placeholders until fully migrated)

  /// Fallback poster width when a caller still needs a concrete size (placeholders).
  public static var cardWidth: CGFloat {
    ShelfMetrics.posters(width: referenceWidth, typeSize: .large)
      .cardWidth(in: referenceWidth)
  }

  public static var posterHeight: CGFloat { cardWidth / CardAspect.poster.ratio }
  public static var landscapeWidth: CGFloat {
    ShelfMetrics.landscape(width: referenceWidth, typeSize: .large)
      .cardWidth(in: referenceWidth)
  }
  public static var landscapeHeight: CGFloat { landscapeWidth / CardAspect.landscape.ratio }
  public static var cornerRadius: CGFloat { Metrics.cardCornerRadius }
  public static var captionSpacing: CGFloat { Metrics.cardCaptionSpacing }
  public static var titleFont: Font { TypeScale.cardTitle }
  public static var subtitleFont: Font { TypeScale.cardSubtitle }

  private static var referenceWidth: CGFloat {
#if os(tvOS)
    1920
#elseif os(macOS)
    1100
#else
    390
#endif
  }
}

// MARK: - Landscape play chrome

/// Visual treatments for the centered play affordance on play-primary landscape cards.
public enum LandscapePlayChromeStyle: String, CaseIterable, Sendable {
  /// Liquid Glass circle — shipping default.
  case glass
  /// Translucent white plate (hero secondary circle language), no backdrop sampling.
  case translucent
  /// Same glass material, larger hit-looking target.
  case glassLarge
}

/// Decorative play glyph in the middle of a landscape still. Not a Button — the
/// parent card / link owns the action.
public struct LandscapePlayChromeView: View {
  public let style: LandscapePlayChromeStyle

  public init(style: LandscapePlayChromeStyle = .glass) {
    self.style = style
  }

  private var diameter: CGFloat {
    switch style {
    case .glass: return 52
    case .translucent: return 52
    case .glassLarge: return 64
    }
  }

  private var iconSize: CGFloat {
    switch style {
    case .glass, .translucent: return 20
    case .glassLarge: return 24
    }
  }

  public var body: some View {
    Image(systemName: "play.fill")
      .font(.system(size: iconSize, weight: .semibold))
      .foregroundStyle(.primary)
      .padding(.leading, 2)
      .frame(width: diameter, height: diameter)
      .modifier(LandscapePlayChromeBackground(style: style))
  }
}

private struct LandscapePlayChromeBackground: ViewModifier {
  let style: LandscapePlayChromeStyle

  func body(content: Content) -> some View {
    switch style {
    case .glass, .glassLarge:
      content.kinoGlass(in: Circle())
    case .translucent:
      content
        .background {
          Circle().fill(Color.white.opacity(0.22))
        }
        .overlay {
          Circle()
            .strokeBorder(Color.white.opacity(0.35), lineWidth: Metrics.hairline)
        }
    }
  }
}

#Preview("Poster with 4K/HDR") {
  MediaCardView(
    card: MediaCard(
      id: 1,
      posterURL: "https://m.staticpop.net/poster/item/big/6581.jpg",
      title: "Стражи Галактики",
      subtitle: "Guardians of the Galaxy",
      imdbRating: 8.1,
      kinopoiskRating: 8.3,
      progress: 0.4,
//      badge: "+2",
      is4K: true,
      isHDR: true
    ),
    caption: .always
  )
  .frame(width: 260)
  .padding()
//  .background(Color.black)
//  .preferredColorScheme(.dark)
}

#Preview("Poster watched") {
  MediaCardView(
    card: MediaCard(
      id: 2,
      posterURL: "https://m.staticpop.net/poster/item/big/6581.jpg",
      title: "Стражи Галактики",
      imdbRating: 7.2,
      kinopoiskRating: 7.0,
      isWatched: true,
      is4K: true
    ),
    caption: .always
  )
  .frame(width: 260)
  .padding()
//  .background(Color.black)
//  .preferredColorScheme(.dark)
}

#Preview("Landscape episode") {
  MediaCardView(
    card: MediaCard(
      id: 3,
      posterURL: "https://m.staticpop.net/poster/item/big/10524.jpg",
      title: "Название эпизода подлиннее обычного",
      progress: 0.55,
      landscapeImageURL: "https://m.staticpop.net/poster/item/wide/10524.jpg",
      overlayLabel: "S1, E3",
      isSeries: true,
      viewerState: ViewerState(isFollowing: true),
      durationSeconds: 48 * 60,
      primaryAction: .play
    ),
    caption: .always,
    forcePlayChrome: true
  )
  .frame(width: 260)
  .padding()
//  .background(Color.black)
//  .preferredColorScheme(.dark)
}

#Preview("Landscape time states") {
  HStack(alignment: .top, spacing: 44) {
    MediaCardView(
      card: MediaCard(
        id: 1,
        posterURL: "https://m.staticpop.net/poster/item/wide/8581.jpg",
        title: "Unwatched",
        landscapeImageURL: "https://m.staticpop.net/poster/item/wide/100582.jpg",
        durationSeconds: 62 * 60,
        primaryAction: .play
      ),
      caption: .always,
      forcePlayChrome: false
    )
    .frame(width: 320)
    MediaCardView(
      card: MediaCard(
        id: 2,
        posterURL: "https://m.staticpop.net/poster/item/wide/100582.jpg",
        title: "In progress",
        progress: 0.35,
        landscapeImageURL: "https://m.staticpop.net/poster/item/wide/100582.jpg",
        viewerState: ViewerState(isFollowing: true),
        durationSeconds: 2 * 3600,
        primaryAction: .play
      ),
      caption: .always,
      forcePlayChrome: false
    )
    .frame(width: 360)
    MediaCardView(
      card: MediaCard(
        id: 3,
        posterURL: "https://m.staticpop.net/poster/item/wide/3581.jpg",
        title: "Watched",
        progress: 1,
        landscapeImageURL: "https://m.staticpop.net/poster/item/wide/3581.jpg",
        isWatched: true,
        durationSeconds: 2 * 60,
        primaryAction: .play
      ),
      caption: .onFocus
    )
    .frame(width: 260)
  }
  .padding()
//  .background(Color.black)
//  .preferredColorScheme(.dark)
}

public extension EnvironmentValues {
  /// The caption title's style for the cards under it; nil is `TypeScale.cardTitle`.
  /// The title page's episodes are a step up (`TypeScale.episodeCardTitle`).
  @Entry var mediaCardTitleFont: Font? = nil
}
