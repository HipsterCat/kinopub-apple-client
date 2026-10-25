//
//  MediaScoresView.swift
//
//

import Foundation
import SwiftUI

/// A rating source's logo. Template for tinted metadata lines; colour assets for
/// the detail score tiles.
public struct MediaScoreLogo: View {

  public enum Source: String, Sendable {
    case imdb
    case kinopoisk
    case tmdb
    /// Us. A rating source like any other now that the community thumbs feed the
    /// aggregate, so it wears a logo in the same row rather than a thumbs glyph.
    case kinopub

    fileprivate var colorAssetName: String {
      switch self {
      case .imdb: return "imdb_big_color"
      case .kinopoisk: return "kinopoisk_big_color"
      case .tmdb: return "tmdb_big_color"
      case .kinopub: return "kinopub_big_color"
      }
    }

    /// Vector marks drawn for small sizes, one per source. Their aspect ratios differ
    /// wildly — the IMDb wordmark is wide, the kino.pub mark is nearly square — which
    /// is the whole reason `.compact` refuses to clamp width.
    fileprivate var compactAssetName: String {
      switch self {
      case .imdb: return "imdb_small"
      case .kinopoisk: return "kinopoisk_small"
      case .tmdb: return "tmdb_small"
      case .kinopub: return "kinopub_small"
      }
    }

    /// The full-colour marks drawn for the score cards (`Media.xcassets/ratings`, Sasha,
    /// 2026-10-11) — vector, so they take the card's mark height.
    fileprivate var cardAssetName: String {
      switch self {
      case .imdb: return "imdb_big_color"
      case .kinopoisk: return "kinopoisk_big_color"
      case .tmdb: return "tmdb_big_color"
      case .kinopub: return "kinopub_big_color"
      }
    }
  }

  public enum Style {
    /// Single-colour glyph that takes the surrounding foreground.
    case template
    /// Full-colour brand mark from the asset catalogue.
    case color
    /// The mark drawn for score chips and mini rating rows.
    case compact
    /// The large full-colour mark of a score card.
    case card
  }

  private let source: Source
  private let height: CGFloat
  private let style: Style

  public init(_ source: Source, height: CGFloat, style: Style = .color) {
    self.source = source
    self.height = height
    self.style = style
  }

  /// **Height is fixed, width follows the artwork.** A logo row lines up on the
  /// baseline of the marks, not on a grid of equal squares — boxing every one into
  /// `height × height` letterboxed the wide wordmarks down to nothing.
  public var body: some View {
    Image(assetName, bundle: .module)
      .renderingMode(style == .template ? .template : .original)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(height: height)
      .fixedSize(horizontal: true, vertical: false)
  }

  private var assetName: String {
    switch style {
    case .template:
      switch source {
      case .imdb: return "IMDb"
      case .kinopoisk: return "kinopoisk"
      case .tmdb: return "tmdb"
      case .kinopub: return "kinopub_small"
      }
    case .color: return source.colorAssetName
    case .compact: return source.compactAssetName
    case .card: return source.cardAssetName
    }
  }
}

#if canImport(UIKit)
import UIKit

public extension MediaScoreLogo.Source {
  /// The mark as a `UIImage`, for the surfaces drawn in UIKit (the TVUIKit cards). The
  /// same artwork `MediaScoreLogo` draws — vector, so it takes any height.
  func uiImage(style: MediaScoreLogo.Style = .color) -> UIImage? {
    let name: String
    switch style {
    case .template:
      switch self {
      case .imdb: name = "IMDb"
      case .kinopoisk: name = "kinopoisk"
      case .tmdb: name = "tmdb"
      case .kinopub: name = "kinopub_small"
      }
    case .color: name = colorAssetName
    case .compact: name = compactAssetName
    case .card: name = cardAssetName
    }
    return UIImage(named: name, in: .module, compatibleWith: nil)
  }
}
#endif

/// Rating scores row for the Hero and detail metadata.
/// Renders available sources (IMDb, Kinopoisk, TMDb, KinoPub) ordered by audience turnout,
/// with KinoPub placed last and known scores prioritized over unknown.
public struct MediaScoresView: View {

  private let scores: MediaScores
  public var limit: Int?
  public var showsVotes: Bool
  public var deduplicateAgainstAggregate: Bool

  public init(
    _ scores: MediaScores,
    limit: Int? = nil,
    showsVotes: Bool = true,
    deduplicateAgainstAggregate: Bool = false
  ) {
    self.scores = scores
    self.limit = limit
    self.showsVotes = showsVotes
    self.deduplicateAgainstAggregate = deduplicateAgainstAggregate
  }

  /// Convenience for previews / call sites that still pass loose numbers.
  public init(
    imdb: Double?,
    kinopoisk: Double?,
    imdbVotes: Int? = nil,
    kinopoiskVotes: Int? = nil,
    limit: Int? = nil,
    showsVotes: Bool = true,
    deduplicateAgainstAggregate: Bool = false
  ) {
    self.init(MediaScores(
      imdb: imdb,
      imdbVotes: imdbVotes,
      kinopoisk: kinopoisk,
      kinopoiskVotes: kinopoiskVotes
    ), limit: limit, showsVotes: showsVotes, deduplicateAgainstAggregate: deduplicateAgainstAggregate)
  }

  public var body: some View {
    let items = scores.heroScores(deduplicateAgainstAggregate: deduplicateAgainstAggregate)
    let slice = limit.map { Array(items.prefix($0)) } ?? items
    HStack(spacing: Self.groupSpacing) {
      ForEach(slice) { item in
        score(item: item)
      }
    }
  }

  /// Font and colour come from whatever this is dropped into. Scores read as part of
  /// the metadata line, with primary numbers and secondary vote turnout count. Primary,
  /// not white: over art the caller forces dark, on the system background in the light
  /// appearance white numbers vanished.
  private func score(item: MediaScoreItem) -> some View {
    HStack(spacing: 6) {
      MediaScoreLogo(item.source, height: Self.iconHeight)
      if !item.displayScore.isEmpty {
        Text(item.displayScore)
          .fontDesign(.rounded)
          .fontWeight(.semibold)
          .foregroundStyle(Color.KinoPub.text)
      }
      if showsVotes, let votes = item.votesCompact {
        Text("(\(votes))")
          .font(.caption2)
          .fontWeight(.medium)
          .foregroundStyle(Color.KinoPub.subtitle)
      }
    }
  }

#if os(tvOS)
  public static let groupSpacing: CGFloat = 20
  public static let iconHeight: CGFloat = 16
  public static let imdbHeight: CGFloat = 16
  public static let kinopoiskHeight: CGFloat = 16
#else
  public static let groupSpacing: CGFloat = 14
  public static let iconHeight: CGFloat = 14
  public static let imdbHeight: CGFloat = 14
  public static let kinopoiskHeight: CGFloat = 14
#endif
}

#Preview {
  VStack(alignment: .leading, spacing: 16) {
    MediaScoresView(MediaScores(imdb: 8.1, imdbVotes: 486_000, kinopoisk: 8.3, kinopoiskVotes: 92_000))
    MediaScoresView(imdb: 7.4, kinopoisk: 0)
    MediaScoresView(imdb: nil, kinopoisk: 6.2, kinopoiskVotes: 1_200)
  }
  .font(.body)
  .foregroundStyle(Color.KinoPub.text)
  .padding()
}
