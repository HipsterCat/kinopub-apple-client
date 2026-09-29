//
//  KinoPubMediaMapping.swift
//
//  kino.pub's side of the media model: how this one source's payload lands in ours.
//  Only mapping lives here. Which source wins a field is `MediaPrecedence`'s call, and
//  what an episode borrows from its show is `MediaContext`'s — never this file's.
//

import Foundation
import KinoPubMedia

public enum KinoPubMediaMapping {

  /// kino.pub files seven content types. Our model knows shapes, and files the rest as
  /// genre, the way Apple does: `documovie` is a movie filed under Documentary, `concert`
  /// a movie whose genres are music genres, `3D` a movie (3D is a format of this copy,
  /// not another kind of work).
  public struct TypeMapping: Equatable, Sendable {
    public let kind: MediaKind
    /// Which vocabulary the type's genres come from — kino.pub's `concert` set is music.
    public let genreDomain: GenreDomain
    /// The genre the type itself stands for.
    public let impliedGenre: Genre?
    /// Whether that genre leads the list or follows it. Documentary leads, as Apple files
    /// it; Concert follows, so a concert's one word is its music.
    public let impliedGenreLeads: Bool

    init(kind: MediaKind, genreDomain: GenreDomain, impliedGenre: Genre? = nil,
         impliedGenreLeads: Bool = false) {
      self.kind = kind
      self.genreDomain = genreDomain
      self.impliedGenre = impliedGenre
      self.impliedGenreLeads = impliedGenreLeads
    }
  }

  public static func typeMapping(_ type: String, hasSeasons: Bool = false) -> TypeMapping {
    switch type.lowercased() {
    case "movie", "3d":
      return TypeMapping(kind: .movie, genreDomain: .video)
    case "serial", "tvshow":
      return TypeMapping(kind: .show, genreDomain: .video)
    case "documovie":
      return TypeMapping(kind: .movie, genreDomain: .video,
                         impliedGenre: GenreVocabulary.genre(id: "documentary"),
                         impliedGenreLeads: true)
    case "docuserial":
      return TypeMapping(kind: .show, genreDomain: .video,
                         impliedGenre: GenreVocabulary.genre(id: "documentary"),
                         impliedGenreLeads: true)
    case "concert":
      return TypeMapping(kind: .movie, genreDomain: .music,
                         impliedGenre: GenreVocabulary.genre(id: "concert"))
    default:
      return TypeMapping(kind: hasSeasons ? .show : .movie, genreDomain: .video)
    }
  }

  /// A title's genres in our vocabulary, **in kino.pub's order** — its first is the
  /// primary genre — minus the ids that are not genres ("Эксклюзив"). The genre the type
  /// implies leads for documentaries (Documentary, as Apple files them) and follows for
  /// concerts (a concert filed under Electronic leads with Electronic).
  public static func genres(_ genres: [TypeClass], type: String) -> [Genre] {
    let mapping = typeMapping(type)
    var result: [Genre] = []
    for genre in genres {
      guard let mapped = GenreVocabulary.kinopub(id: genre.id, title: genre.title,
                                                 domain: mapping.genreDomain),
            !result.contains(mapped) else { continue }
      result.append(mapped)
    }
    if let implied = mapping.impliedGenre {
      result.removeAll { $0 == implied }
      if mapping.impliedGenreLeads {
        result.insert(implied, at: 0)
      } else {
        result.append(implied)
      }
    }
    return result
  }

  /// kino.pub numbers some shows' season blocks from 1 while naming them "Сезон 14"; the
  /// number in the name is the real one. Our model only ever carries the real one.
  public static func seasonNumber(_ season: Season) -> Int {
    season.titleSeasonNumber ?? season.number
  }

  /// Everything kino.pub knows about one playback, level by level. `title` is the
  /// film or series it belongs to, when the caller has it.
  public static func draft(playing item: any PlayableItem,
                           title: MediaItem?,
                           isTrailer: Bool = false) -> MediaContextDraft {
    let parent = title.map { [$0.mediaFragment] } ?? []
    if isTrailer, let title {
      return MediaContextDraft(item: [title.trailerFragment], parent: parent)
    }
    switch item {
    case let episode as Episode:
      let season = title.flatMap { Self.seasonContaining(episode, in: $0) }
      var show = parent
      // Without the series payload, the name the page stamped on the episode is still
      // the show's name.
      if show.isEmpty, let name = episode.seriesTitle {
        show = [MediaFragment(.kinopub, .show) { $0.title = name }]
      }
      return MediaContextDraft(item: [episode.mediaFragment(in: season)],
                               season: season.map { [$0.mediaFragment] } ?? [],
                               parent: show)
    case let variant as PlaybackVariant:
      // An edition of the film, not a child of it: the film's facts and the edition's
      // name describe the same item.
      return MediaContextDraft(item: parent + [variant.mediaFragment])
    case let media as MediaItem:
      return MediaContextDraft(item: [media.mediaFragment])
    default:
      return MediaContextDraft(item: parent)
    }
  }

  /// The season block an episode came from — by identity first, then by the number the
  /// page stamped on it.
  public static func seasonContaining(_ episode: Episode, in title: MediaItem) -> Season? {
    let seasons = title.seasons ?? []
    return seasons.first { $0.episodes.contains(episode) }
      ?? seasons.first { $0.number == episode.seasonNumber }
  }

  static func poster(_ posters: Posters) -> URL? {
    [posters.big, posters.medium, posters.small].lazy.compactMap { ArtworkSet.url($0) }.first
  }
}

// MARK: - Fragments

public extension MediaItem {

  /// The title itself — a movie or a show.
  var mediaFragment: MediaFragment {
    let mapping = KinoPubMediaMapping.typeMapping(type, hasSeasons: isSeries)
    return MediaFragment(.kinopub, mapping.kind) { entity in
      entity.ids = mediaIDs
      entity.title = localizedTitle
      // "Русское / Original" — without the slash there is no separate original title.
      entity.originalTitle = title.contains("/") ? originalTitle : nil
      entity.synopsis = Synopsis(full: plot)
      entity.genres = KinoPubMediaMapping.genres(genres, type: type)
      entity.release = ReleaseDate(year: year)
      if mapping.kind == .movie {
        // `total` sums every version of a multi-version film; `average` is the film.
        let seconds = playbackVariants.isEmpty ? duration.total : duration.average
        entity.runtime = seconds > 0 ? seconds : nil
      }
      entity.scores = [
        Score(.imdb, value: imdbRating, votes: imdbVotes),
        Score(.kinopoisk, value: kinopoiskRating, votes: kinopoiskVotes),
        // kino.pub's own vote is a thumbs tally; its percentage is the score.
        Score(.kinopub, value: ratingPercentage, scale: 100, votes: ratingVotes),
      ].compactMap { $0 }
      entity.artwork = ArtworkSet(poster: KinoPubMediaMapping.poster(posters),
                                  backdrop: ArtworkSet.url(posters.wideURL))
      entity.countries = countries.map(\.title)
    }
  }

  /// This title's trailer, as an extra of it.
  var trailerFragment: MediaFragment {
    MediaFragment(.kinopub, .extra) { entity in
      entity.extraKind = .trailer
    }
  }

  private var mediaIDs: [ExternalID] {
    var ids = [ExternalID(.kinopub, String(id))]
    if let imdb, imdb > 0 {
      let digits = String(imdb)
      let padded = String(repeating: "0", count: max(0, 7 - digits.count)) + digits
      ids.append(ExternalID(.imdb, "tt" + padded))
    }
    if let kinopoisk, kinopoisk > 0 {
      ids.append(ExternalID(.kinopoisk, String(kinopoisk)))
    }
    return ids
  }
}

public extension Season {
  var mediaFragment: MediaFragment {
    MediaFragment(.kinopub, .season) { entity in
      entity.seasonNumber = KinoPubMediaMapping.seasonNumber(self)
      entity.title = title
    }
  }
}

public extension Episode {
  /// The episode's season is passed in because an `Episode` does not know which block
  /// it came from, and only the season knows the real season number.
  func mediaFragment(in season: Season? = nil) -> MediaFragment {
    MediaFragment(.kinopub, .episode) { entity in
      entity.title = title
      entity.seasonNumber = season.map(KinoPubMediaMapping.seasonNumber) ?? seasonNumber
      entity.episodeNumber = number
      entity.runtime = duration > 0 ? TimeInterval(duration) : nil
      entity.artwork = ArtworkSet(still: ArtworkSet.url(thumbnail))
    }
  }
}

public extension PlaybackVariant {
  var mediaFragment: MediaFragment {
    MediaFragment(.kinopub, .movie) { entity in
      entity.title = movieTitle
      entity.edition = title
      entity.runtime = duration > 0 ? TimeInterval(duration) : nil
      entity.artwork = ArtworkSet(still: ArtworkSet.url(thumbnail))
    }
  }
}
