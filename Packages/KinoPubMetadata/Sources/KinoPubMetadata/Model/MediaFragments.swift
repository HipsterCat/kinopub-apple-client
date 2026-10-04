//
//  MediaFragments.swift
//
//  The enrichment sources' side of the media model: how what TMDB (and the Kinopoisk
//  overlay merged into `TitleMetadata`) says lands in ours. Only mapping — precedence is
//  `MediaPrecedence`'s, inheritance is `MediaContext`'s.
//

import Foundation
import KinoPubMedia

public extension TitleMetadata {

  /// The title itself, labeled by its main contributor. On the gap-filled overlay a poster
  /// Kinopoisk supplied travels under TMDB's name when TMDB answered too — which is why
  /// `mediaFragments(kind:)` reads TMDB's own part instead.
  @available(*, deprecated, message: "Use mediaFragments(kind:): each source under its own name.")
  func mediaFragment(kind: MediaKind) -> MediaFragment {
    overlayFragment(kind: kind)
  }

  /// The gap-filled overlay as one fragment, labelled by its main contributor.
  internal func overlayFragment(kind: MediaKind) -> MediaFragment {
    let source: MediaSource = attribution.contains(.tmdb) ? .tmdb : .kinopoisk
    return MediaFragment(source, kind, language: language) { entity in
      if let tmdbId { entity.ids = [ExternalID(.tmdb, String(tmdbId))] }
      entity.synopsis = Synopsis(full: overview, tagline: tagline)
      entity.genres = genres
      let premiere = kind == .show ? firstAirDate : releaseDate
      entity.release = premiere.map { ReleaseDate(date: $0) }
      entity.ended = kind == .show ? lastAirDate.map { ReleaseDate(date: $0) } : nil
      entity.seasonCount = kind == .show ? numberOfSeasons : nil
      entity.contentRating = ContentRating(ageRating)
      entity.scores = [Score(.tmdb, value: tmdbRating, votes: tmdbVotes)].compactMap { $0 }
      entity.artwork = ArtworkSet(poster: artwork.poster, backdrop: artwork.backdrop,
                                  logo: artwork.titleLogo)
    }
  }

  /// **Every enrichment source's statement about the title**, each under its own name:
  /// TMDB's from its own part, Kinopoisk's details as Kinopoisk's. This is what the media
  /// model merges; `mediaFragment(kind:)` alone is the gap-filled overlay under one label.
  func mediaFragments(kind: MediaKind) -> [MediaFragment] {
    let overlay = parts[.tmdb]?.overlayFragment(kind: kind) ?? overlayFragment(kind: kind)
    let own = fragments.map { fragment -> MediaFragment in
      var filed = fragment
      filed.entity.kind = kind
      return filed
    }
    return [overlay] + own
  }

  /// A season TMDB lists, by TMDB's number.
  func seasonFragment(number: Int) -> MediaFragment? {
    seasonSummaries.first { $0.seasonNumber == number }?.mediaFragment
  }
}

public extension SeasonSummary {
  var mediaFragment: MediaFragment {
    MediaFragment(.tmdb, .season) { entity in
      entity.seasonNumber = seasonNumber
      entity.title = name
      entity.synopsis = Synopsis(full: overview)
      entity.release = airDate.map { ReleaseDate(date: $0) }
      entity.scores = [Score(.tmdb, value: voteAverage)].compactMap { $0 }
      entity.artwork = ArtworkSet(poster: poster)
    }
  }
}

public extension EpisodeSchedule {
  var mediaFragment: MediaFragment {
    MediaFragment(.tmdb, .episode) { entity in
      entity.title = name
      entity.seasonNumber = seasonNumber
      entity.episodeNumber = episodeNumber
      entity.synopsis = Synopsis(full: overview)
      entity.release = airDate.map { ReleaseDate(date: $0) }
      entity.runtime = runtime.map { TimeInterval($0 * 60) }
      entity.scores = [Score(.tmdb, value: voteAverage, votes: voteCount)].compactMap { $0 }
      entity.artwork = ArtworkSet(still: still)
    }
  }
}

/// **Which TMDB season a kino.pub season block is.** kino.pub sometimes re-numbers its
/// blocks from 1 while titling them "Сезон N"; TMDB numbers by the real season. The
/// title's number wins when TMDB has that season, then the block's own number, else there
/// is no counterpart — asking TMDB for "season 1" of a block that is really season 14
/// produced decade-old "missing episodes" on a current show.
public enum TMDBSeasonMatch {
  public static func tmdbSeason(kinoNumber: Int, titleNumber: Int?,
                                tmdbSeasons: Set<Int>) -> Int? {
    if let titleNumber, tmdbSeasons.contains(titleNumber) { return titleNumber }
    if tmdbSeasons.isEmpty || tmdbSeasons.contains(kinoNumber) { return kinoNumber }
    return nil
  }
}
