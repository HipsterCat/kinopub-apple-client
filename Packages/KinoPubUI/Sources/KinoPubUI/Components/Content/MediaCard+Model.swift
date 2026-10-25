//
//  MediaCard+Model.swift
//  KinoPubUI
//
//  A poster card worded from the media model — the facts (`MediaEntity`) and what the
//  viewer has done (`ViewerState`) — instead of from one source's payload.
//

import Foundation
import KinoPubBackend
import KinoPubMedia

public extension MediaCard {

  /// A title's poster card from the model. Every catalogue card goes through here
  /// (`MediaCard(_ item:)` maps its payload first), so a fact reads the same on every row.
  ///
  /// The card keeps facts — genres, country, season count, year, runtime — and words them
  /// when it is painted, in the viewer's language.
  init(ref: MediaRef, entity: MediaEntity, state: ViewerState) {
    self.init(id: ref.itemID,
              posterURL: (entity.artwork.posterPreview ?? entity.artwork.poster)?.absoluteString ?? "",
              title: entity.title ?? "",
              subtitle: entity.originalTitle,
              scores: MediaScores(entity.scores),
              backdropURL: entity.artwork.backdrop?.absoluteString,
              hasSpecifiedWideArtwork: entity.artwork.backdropFromSpecifiedWide,
              overview: entity.synopsis.best,
              seasonCount: entity.seasonCount,
              isSeries: entity.kind == .show,
              viewerState: Self.cardState(state, isSeries: entity.kind == .show),
              is4K: entity.formats.contains(.uhd),
              isHDR: entity.formats.contains(.hdr),
              isHD: entity.formats.contains(.hd),
              is3D: entity.formats.contains(.threeD),
              hasClosedCaptions: entity.formats.contains(.closedCaptions),
              year: entity.release?.year,
              yearEnd: entity.kind == .show ? entity.ended?.year : nil,
              durationSeconds: entity.kind == .movie ? entity.runtime.map { Int($0) } : nil,
              genres: entity.genres,
              country: entity.countries.first,
              imdbID: entity.id(.imdb).flatMap { Int($0.drop { !$0.isNumber }) },
              kinopoiskID: entity.id(.kinopoisk).flatMap(Int.init))
  }
}

public extension MediaScores {
  /// The scores the card draws, from the model's side-by-side list.
  init(_ scores: [Score]) {
    func score(_ provider: ScoreProvider) -> Score? { scores.first { $0.provider == provider } }
    self.init(imdb: score(.imdb)?.value, imdbVotes: score(.imdb)?.votes,
              kinopoisk: score(.kinopoisk)?.value, kinopoiskVotes: score(.kinopoisk)?.votes,
              tmdb: score(.tmdb)?.value, tmdbVotes: score(.tmdb)?.votes)
  }
}

// MARK: - The viewer's state, at paint time

public extension MediaCard {

  /// The thing this card stands for: the title, or the episode / version it offers.
  var ref: MediaRef { MediaRef(itemID: itemID, season: season, number: video) }

  /// What the card's payload said about the viewer when it was fetched — the "reported"
  /// side of `ViewerState`, for a reader to lay this device's knowledge over.
  var reportedState: ViewerState {
    let watch = durationSeconds.flatMap { duration in
      progress.map { WatchProgress(position: $0 * Double(duration), duration: Double(duration)) }
    }
    return ViewerState(progress: watch,
                       isWatched: isWatched,
                       isFollowing: isSeries ? viewerState.isFollowing : nil,
                       bookmarkFolderIDs: viewerState.bookmarkFolderIDs)
  }

  /// The part of the viewer's state a card keeps: follow — a series' alone — and folders.
  /// An empty folder set is "not bookmarked", said as nil like the payload says it.
  static func cardState(_ state: ViewerState, isSeries: Bool) -> ViewerState {
    let folders = state.bookmarkFolderIDs ?? []
    return ViewerState(isFollowing: isSeries ? state.isFollowing : nil,
                       bookmarkFolderIDs: folders.isEmpty ? nil : folders)
  }

  /// The same card with the viewer's state replaced — watched, progress, follow, folders.
  /// Words and artwork are untouched.
  func withViewerState(_ state: ViewerState) -> MediaCard {
    MediaCard(id: id, posterURL: posterURL, title: title, subtitle: subtitle,
                     watchedAt: watchedAt, scores: scores,
                     progress: state.resumeFraction ?? (state.isWatched ? nil : progress),
                     badge: badge, backdropURL: backdropURL,
                     hasSpecifiedWideArtwork: hasSpecifiedWideArtwork,
                     overview: overview, landscapeImageURL: landscapeImageURL,
                     overlayLabel: overlayLabel, itemID: itemID, video: video, season: season,
                     seasonCount: seasonCount, mediaID: mediaID, isWatched: state.isWatched,
                     isSeries: isSeries, isInHistory: isInHistory,
                     viewerState: Self.cardState(state, isSeries: isSeries),
                     is4K: is4K, isHDR: isHDR, isHD: isHD, is3D: is3D,
                     hasClosedCaptions: hasClosedCaptions, year: year, yearEnd: yearEnd,
                     unwatchedEpisodes: unwatchedEpisodes,
                     durationSeconds: durationSeconds, genres: genres, country: country,
                     primaryAction: primaryAction, opensCollection: opensCollection,
                     captionStats: captionStats, imdbID: imdbID, kinopoiskID: kinopoiskID)
  }
}
