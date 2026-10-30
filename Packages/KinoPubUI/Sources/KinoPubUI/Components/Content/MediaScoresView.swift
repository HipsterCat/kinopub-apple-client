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
      case .kinopoisk: return "kinopoisk_big_colorful"
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

    /// Colour marks for the synopsis line, exported at 32 pt. Width is the file's.
    fileprivate var lineAssetName: String {
      switch self {
      case .imdb: return "imdb_small_color"
      case .kinopoisk: return "kp_small_colorful"
      case .tmdb: return "tmdb_small_color"
      case .kinopub: return "kinopub_small"
      }
    }

    /// The full-colour marks drawn for the score cards (`Media.xcassets/ratings`, Sasha,
    /// 2026-10-11) — vector, so they take the card's mark height.
    fileprivate var cardAssetName: String {
      switch self {
      case .imdb: return "imdb_big_color"
      case .kinopoisk: return "kinopoisk_big_colorful"
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
    /// The line under the synopsis. Colour PNGs exported at 32 pt
    /// (`imdb_small_color`, `kp_small_colorful`, `tmdb_small_color`). The
    /// matching `_black` sets are the same drawings, for a later tint.
    case line
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
    let image = Image(assetName, bundle: .module)
      .renderingMode(style == .template ? .template : .original)
    if style == .line {
#if os(tvOS)
      // Already 32 pt tall. `fixedSize` keeps each file's width; the row must not
      // stretch them into one box.
      image.fixedSize()
#else
      // Sized by the row: `MediaScoresView` lays it at its score's line height
      // (`MarkFillsLineHeight`). The 32 pt files were drawn for the TV's type.
      image
        .resizable()
        .aspectRatio(contentMode: .fit)
#endif
    } else {
      image
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(height: height)
        .fixedSize(horizontal: true, vertical: false)
    }
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
    case .line: return source.lineAssetName
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
    case .line: name = lineAssetName
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
  /// The title page's line: IMDb, Kinopoisk, TMDB, in that order. Cards and banners
  /// keep the ranked lineup.
  public var detailLine: Bool
  /// The Home hero's line: the banner's lineup (`bannerScores` — two at most, a source
  /// with a handful of votes or one swamped by another dropped), in the title page's
  /// line marks.
  public var bannerLine: Bool
  /// Under a poster the line has one width. Per-source vote counts when they fit;
  /// otherwise the logos and scores plus one combined count; scores alone if that
  /// still does not fit.
  public var collapsesVotesToFit: Bool

  public init(
    _ scores: MediaScores,
    limit: Int? = nil,
    showsVotes: Bool = true,
    deduplicateAgainstAggregate: Bool = false,
    detailLine: Bool = false,
    bannerLine: Bool = false,
    collapsesVotesToFit: Bool = false
  ) {
    self.scores = scores
    self.limit = limit
    self.showsVotes = showsVotes
    self.deduplicateAgainstAggregate = deduplicateAgainstAggregate
    self.detailLine = detailLine
    self.bannerLine = bannerLine
    self.collapsesVotesToFit = collapsesVotesToFit
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
    let items = bannerLine
      ? scores.bannerScores(deduplicateAgainstAggregate: deduplicateAgainstAggregate)
      : detailLine
      ? scores.detailLine(deduplicateAgainstAggregate: deduplicateAgainstAggregate)
      : scores.heroScores(deduplicateAgainstAggregate: deduplicateAgainstAggregate)
    let slice = limit.map { Array(items.prefix($0)) } ?? items
    if collapsesVotesToFit {
      ViewThatFits(in: .horizontal) {
        scoresRow(slice, votes: .each)
        scoresRow(slice, votes: .total)
        scoresRow(slice, votes: .none)
      }
      .frame(maxWidth: .infinity, alignment: .center)
    } else {
      scoresRow(slice, votes: showsVotes ? .each : .none)
    }
  }

  private enum VoteStyle {
    case each
    case total
    case none
  }

  private func scoresRow(_ slice: [MediaScoreItem], votes: VoteStyle) -> some View {
    let total = slice.compactMap(\.votes).filter { $0 > 0 }.reduce(0, +)
    return HStack(spacing: Self.groupSpacing) {
      ForEach(slice) { item in
        score(item: item, showsVotes: votes == .each)
      }
      if votes == .total, total > 0 {
        Text("(\(MediaScores.formatVotesWholeThousands(total)))")
          .font(.caption2)
          .fontWeight(.medium)
          .foregroundStyle(Color.KinoPub.subtitle)
      }
    }
    .lineLimit(1)
  }

  /// Font and colour come from whatever this is dropped into. Scores read as part of
  /// the metadata line, with primary numbers and secondary vote turnout count. Primary,
  /// not white: over art the caller forces dark, on the system background in the light
  /// appearance white numbers vanished.
  @ViewBuilder
  private func score(item: MediaScoreItem, showsVotes: Bool) -> some View {
#if os(tvOS)
    HStack(spacing: Self.markSpacing) {
      scoreContent(item: item, showsVotes: showsVotes)
    }
#else
    if detailLine || bannerLine {
      // The title page's line follows the type: the mark fills the score's line height
      // at any Dynamic Type size (Sasha, 2026-10-29).
      MarkFillsLineHeight(spacing: Self.markSpacing) {
        scoreContent(item: item, showsVotes: showsVotes)
      }
    } else {
      HStack(spacing: Self.markSpacing) {
        scoreContent(item: item, showsVotes: showsVotes)
      }
    }
#endif
  }

  @ViewBuilder
  private func scoreContent(item: MediaScoreItem, showsVotes: Bool) -> some View {
    MediaScoreLogo(
      item.source,
      height: usesLineMarks ? Self.lineIconHeight : Self.iconHeight,
      style: usesLineMarks ? .line : .color
    )
    if !item.displayScore.isEmpty {
      Text(item.displayScore)
        .fontDesign(.rounded)
        .fontWeight(.semibold)
        .foregroundStyle(item.drawsFaint ? Color.KinoPub.subtitle : Color.KinoPub.text)
    }
    if showsVotes, let votes = item.votesCompact {
      Text("(\(votes))")
        .font(.caption2)
        .fontWeight(.medium)
        .foregroundStyle(Color.KinoPub.subtitle)
    }
  }

  private var usesLineMarks: Bool { detailLine || bannerLine }

  private static let markSpacing: CGFloat = 6

  /// The synopsis-line marks. The PNGs are this tall; the view draws them at
  /// their own width.
  public static let lineIconHeight: CGFloat = 32

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

/// A row whose first subview — a resizable mark — is as tall as the tallest of the rest,
/// its width following the mark's own aspect. Everything is centred on one line.
private struct MarkFillsLineHeight: Layout {
  var spacing: CGFloat

  private func sizes(_ subviews: Subviews) -> [CGSize] {
    guard let mark = subviews.first else { return [] }
    let rest = subviews.dropFirst().map { $0.sizeThatFits(.unspecified) }
    let height = rest.map(\.height).max() ?? 0
    let natural = mark.sizeThatFits(.unspecified)
    let width = natural.height > 0 ? natural.width * height / natural.height : 0
    return [CGSize(width: width, height: height)] + rest
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let all = sizes(subviews)
    let width = all.map(\.width).reduce(0, +) + spacing * CGFloat(max(all.count - 1, 0))
    return CGSize(width: width, height: all.map(\.height).max() ?? 0)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX
    for (subview, size) in zip(subviews, sizes(subviews)) {
      subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
      x += size.width + spacing
    }
  }
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
