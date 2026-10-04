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
  /// The card still stores pre-worded strings and a copy of the viewer's state; both are
  /// deprecated and move to paint time with the card's migration (docs/media-model.md
  /// step 4). This is the one place that fills them.
  init(ref: MediaRef, entity: MediaEntity, state: ViewerState,
       language: MediaLanguage = .current) {
    let line = TitleMetaLine(entity)
    // One genre, the primary (D7).
    let genres = entity.genres.prefix(1).map { $0.name.value(languageCode: language.rawValue) }
    let folders = (state.bookmarkFolderIDs ?? []).sorted()
    self.init(id: ref.itemID,
              posterURL: (entity.artwork.posterPreview ?? entity.artwork.poster)?.absoluteString ?? "",
              title: entity.title ?? "",
              subtitle: entity.originalTitle,
              scores: MediaScores(entity.scores),
              backdropURL: entity.artwork.backdrop?.absoluteString,
              metaLine: line.formatted(language: language),
              overview: entity.synopsis.best,
              seasonCount: entity.seasonCount,
              isSeries: entity.kind == .show,
              isInWatchlist: state.isFollowing ?? false,
              is4K: entity.formats.contains(.uhd),
              isHDR: entity.formats.contains(.hdr),
              isHD: entity.formats.contains(.hd),
              is3D: entity.formats.contains(.threeD),
              hasClosedCaptions: entity.formats.contains(.closedCaptions),
              year: entity.release?.year,
              durationSeconds: entity.kind == .movie ? entity.runtime.map { Int($0) } : nil,
              genreLine: genres.isEmpty ? nil : genres.joined(separator: ", "),
              countryLine: entity.countries.first,
              seasonsLabel: SeasonCountText(entity.seasonCount)?.formatted(language: language),
              isBookmarked: !folders.isEmpty,
              bookmarkFolderIDs: folders,
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
