//
//  MediaItemReviewsPage.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubUI
import KinoPubBackend
import KinoPubMetadata

/// What the Ratings and Reviews block opens — every card in it leads here.
///
/// The rail's cards are previews: one headline, five lines, a footer, cut to a fixed
/// height. This is where a review is actually read, so the same `BlockCard` runs full
/// width with no line limit, under the same ratings card and the review tally.
///
/// Nothing here fetches. It all travelled in the route, because it was already merged
/// into the item's metadata before the header could be tapped — which is also why the
/// destination exists even on a title nobody has reviewed: the block always leads
/// somewhere, and here that somewhere is the scores plus an honest empty note.
///
/// Not this page on tvOS — a navigating section header is an iOS/macOS affordance, and a page of
/// text with nothing focusable cannot be scrolled with a remote. The count card in the scores' row
/// opens `MediaItemReviewsTVPage` instead (`RouteDestination`).
struct MediaItemRatingsAndReviewsPage: View {
  let payload: RatingsAndReviews

  private var reviews: [Review] { payload.reviews }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: BlockMetrics.spacing) {
        // The aggregate without its chip row: on a page there is width for the
        // sources to be rows of their own, named and linked, instead of four marks
        // and four numbers with nothing saying which is which.
        MediaItemRatingsCard(mediaItem: payload.item,
                             externalMetadata: payload.metadata,
                             likeCount: payload.likeCount,
                             dislikeCount: payload.dislikeCount,
                             reviewCount: reviewCount,
                             showsSources: false)
        if !scores.isEmpty {
          MediaItemRatingSourceRows(scores: scores)
        }
        // Trakt's side of the title: how its votes fall, what its users do with it, and
        // what its reviews praise and fault (Sasha, 2026-11-09).
        if let trakt = traktScore, !payload.traktDistribution.isEmpty {
          TraktDistributionCard(score: trakt, distribution: payload.traktDistribution)
        }
        if let douban = payload.externalRatings.first(where: { $0.kind == .douban }) {
          DoubanStatsCard(score: douban, stats: payload.doubanStats)
        }
        if let stats = payload.audienceStats {
          AudienceStatsCard(stats: stats,
                            afterCredits: payload.hasAfterCreditsScene == true,
                            duringCredits: payload.hasDuringCreditsScene == true)
        }
        if let insights = payload.reviewInsights, !insights.isEmpty {
          ReviewInsightsCard(insights: insights)
        }
        if let summary = payload.summary, !summary.isEmpty, !reviews.isEmpty {
          ReviewsSummaryCard(summary: summary, width: nil)
        }
        if reviews.isEmpty {
          emptyNote
        } else {
          ForEach(reviews) { review in
            ReviewCard(review: review, mode: .expanded,
                       sourceURL: review.isFromTrakt ? review.traktCommentURL : kinopoiskReviewsURL)
          }
        }
      }
      .padding(.horizontal, MediaItemLayout.horizontalInset)
      .padding(.vertical, MediaItemLayout.sectionSpacing)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .platformNavigationTitle(payload.item.localizedTitle)
    .background(Color.KinoPub.background.ignoresSafeArea())
  }

  private var traktScore: ExternalRating? {
    payload.externalRatings.first { $0.kind == .trakt }
  }

  private var reviewCount: Int {
    let total = payload.summary.map(\.total) ?? 0
    return total > 0 ? total : reviews.count
  }

  private var scores: [RatingSources.Score] {
    RatingSources.scores(for: payload.item,
                         metadata: payload.metadata,
                         likeCount: payload.likeCount,
                         dislikeCount: payload.dislikeCount)
  }

  /// The title's review list at the source. **Not a permalink to one review** — the
  /// proxy gives the review's id but Kinopoisk's own review URL is built from a user
  /// id we never receive, so "where this came from" is as precise as we can be
  /// (`docs/providers/kinopoisk-proxy.md`).
  private var kinopoiskReviewsURL: URL? {
    guard let id = payload.item.kinopoisk, id > 0 else { return nil }
    let kind = payload.item.isSeries ? "series" : "film"
    return URL(string: "https://www.kinopoisk.ru/\(kind)/\(id)/reviews/")
  }

  private var emptyNote: some View {
    BlockCard {
      Text("MediaItem_NoReviews")
        .font(TypeScale.detailBody)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

}

#Preview("Ratings and reviews page") {
  var metadata = TitleMetadata()
  metadata.reviews = [
    Review(author: "Арсений П.",
           title: "",
           body: "Фильмы философской тематики занимают отдельное место в кинематографическом пьедестале.\n\nНе каждому зрителю дано понять смысл, который художник вкладывает в нутро киноленты.",
           sentiment: "POSITIVE",
           date: "2022-02-18T21:51:09",
           postedAt: Date(timeIntervalSince1970: 1_645_217_469),
           helpfulVotes: 3,
           unhelpfulVotes: 2),
    Review(author: "Lintandil",
           title: "Аромат беды",
           body: "Высочайший пик технических достижений в кинематографе на тот момент.",
           sentiment: "NEUTRAL",
           date: "2015-02-28T12:57:52",
           postedAt: Date(timeIntervalSince1970: 1_425_124_672),
           helpfulVotes: 7,
           unhelpfulVotes: 2)
  ]
  metadata.reviewsSummary = ReviewsSummary(total: 11, positive: 7, negative: 1, neutral: 3)
  metadata.tmdbRating = 6.3
  metadata.tmdbVotes = 1536

  return NavigationStack {
    MediaItemRatingsAndReviewsPage(
      payload: RatingsAndReviews(item: MediaItem.mock(),
                                 metadata: metadata,
                                 likeCount: 548,
                                 dislikeCount: 12)
    )
  }
  // .preferredColorScheme(.dark)
}

// MARK: - Trakt

/// Trakt's score over how its votes fall, ten scores folded into five bars as Trakt's own
/// app draws them (1–2, 3–4 … 9–10), the tallest bar brightest.
struct TraktDistributionCard: View {
  let score: ExternalRating
  let distribution: [Int: Int]

  /// Trakt's ten scores folded into five bars.
  private var buckets: [Double] {
    (0..<5).map { index in
      let low = index * 2 + 1
      return Double((distribution[low] ?? 0) + (distribution[low + 1] ?? 0))
    }
  }

  var body: some View {
    RatingDistributionCard(title: "MediaItem_TraktRatingTitle",
                           score: "\(Int((score.value * 10).rounded()))%",
                           votes: score.votes,
                           buckets: buckets,
                           tint: .purple)
  }

  static func unit(_ votes: Int) -> String {
    switch localizedPluralForm(votes) {
    case 0: "MediaItem_UnitRatingOne".localized
    case 1: "MediaItem_UnitRatingFew".localized
    default: "MediaItem_UnitRatingMany".localized
    }
  }
}

/// A source's score beside five bars, 1 to 5 stars: Trakt's folded ten, Douban's own five.
struct RatingDistributionCard<Footer: View>: View {
  let title: LocalizedStringKey
  let score: String
  let votes: Int?
  /// Votes or shares per bar, 1★…5★; only their proportions matter.
  let buckets: [Double]
  let tint: Color
  @ViewBuilder var footer: Footer

  var body: some View {
    let peak = max(buckets.max() ?? 0, .leastNonzeroMagnitude)
    BlockCard {
      VStack(alignment: .leading, spacing: 12) {
        Text(title)
          .font(TypeScale.detailBody.weight(.semibold))
          .foregroundStyle(.secondary)
        HStack(alignment: .bottom, spacing: 24) {
          VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: score)
              .font(.system(.largeTitle, design: .rounded, weight: .semibold))
              .foregroundStyle(Color.KinoPub.text)
            if let votes, votes > 0 {
              Text(verbatim: "\(votes.formatted(.number.grouping(.automatic))) \(TraktDistributionCard.unit(votes))")
                .font(TypeScale.detailBody)
                .foregroundStyle(.secondary)
            }
          }
          .fixedSize()
          if !buckets.isEmpty {
            HStack(alignment: .bottom, spacing: 10) {
              ForEach(Array(buckets.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 6) {
                  GeometryReader { proxy in
                    let share = CGFloat(value / peak)
                    ZStack(alignment: .bottom) {
                      RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                      RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(value == peak ? 0.9 : 0.55))
                        .frame(height: max(proxy.size.height * share, value > 0 ? 6 : 0))
                    }
                  }
                  .frame(height: 72)
                  Text(verbatim: "\(index + 1)")
                    .font(TypeScale.detailBody)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 56)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(index + 1): \(Int((value / max(buckets.reduce(0, +), 1) * 100).rounded()))%"))
              }
            }
            .frame(maxWidth: .infinity)
          }
        }
        footer
      }
    }
  }
}

extension RatingDistributionCard where Footer == EmptyView {
  init(title: LocalizedStringKey, score: String, votes: Int?, buckets: [Double], tint: Color) {
    self.init(title: title, score: score, votes: votes, buckets: buckets, tint: tint) { EmptyView() }
  }
}

/// Douban: its score over five stars, what its users did with the title, and where it
/// ranks in its genres — "better than 99% of crime films". Numbers and English only
/// reach the app; the genre names are ours (Sasha, 2026-11-09).
struct DoubanStatsCard: View {
  let score: ExternalRating
  let stats: DoubanStats?

  private var counts: [(symbol: String, title: LocalizedStringKey, value: Int)] {
    guard let stats else { return [] }
    let list: [(String, LocalizedStringKey, Int?)] = [
      ("checkmark.circle", "MediaItem_DoubanWatched", stats.watched),
      ("bookmark", "MediaItem_DoubanWantToWatch", stats.wantToWatch),
      ("play.circle", "MediaItem_DoubanWatching", stats.watching),
    ]
    return list.compactMap { entry in
      guard let value = entry.2, value > 0 else { return nil }
      return (symbol: entry.0, title: entry.1, value: value)
    }
  }

  var body: some View {
    RatingDistributionCard(title: "MediaItem_DoubanRatingTitle",
                           score: String(format: "%.1f", score.value),
                           votes: score.votes,
                           buckets: stats?.shares ?? [],
                           tint: .green) {
      if !counts.isEmpty {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12, alignment: .leading)],
                  alignment: .leading, spacing: 12) {
          ForEach(counts, id: \.symbol) { tile in
            VStack(alignment: .leading, spacing: 4) {
              Image(systemName: tile.symbol)
                .foregroundStyle(.secondary)
              Text(tile.title)
                .foregroundStyle(.secondary)
              Text(verbatim: tile.value.formatted(.number.notation(.compactName)))
                .font(TypeScale.detailBody.weight(.semibold))
                .foregroundStyle(Color.KinoPub.text)
            }
            .font(TypeScale.detailBody)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
          }
        }
      }
      ForEach(stats?.ranks ?? [], id: \.genre) { rank in
        if let line = Self.rankLine(rank, isSeries: stats?.isSeries == true) {
          Label(line, systemImage: "trophy")
            .font(TypeScale.detailBody)
            .foregroundStyle(Color.KinoPub.text)
        }
      }
    }
  }

  /// «Лучше 99% фильмов жанра «криминал»». A genre we have no name for is left out.
  static func rankLine(_ rank: DoubanStats.Rank, isSeries: Bool) -> String? {
    let key = "MediaItem_DoubanGenre_\(rank.genre)"
    let genre = key.localized
    guard genre != key else { return nil }
    let percent = rank.betterThan.formatted(.percent.precision(.fractionLength(0)))
    let format = (isSeries ? "MediaItem_DoubanRankSeries" : "MediaItem_DoubanRankFilm").localized
    return String(format: format, percent, genre)
  }
}

/// What Trakt's users did with the title: played it, watched it, listed it, loved it.
/// And whether there is something after the credits, which Trakt's users mark.
struct AudienceStatsCard: View {
  let stats: AudienceStats
  var afterCredits = false
  var duringCredits = false

  private var tiles: [(symbol: String, title: LocalizedStringKey, value: Int)] {
    var list: [(String, LocalizedStringKey, Int)] = [
      ("play", "MediaItem_StatPlays", stats.plays),
      ("person.2", "MediaItem_StatWatchers", stats.watchers),
      ("list.bullet", "MediaItem_StatLists", stats.lists),
    ]
    if let favorited = stats.favorited { list.append(("heart", "MediaItem_StatFavorited", favorited)) }
    if let recommended = stats.recommended {
      list.append(("hand.thumbsup", "MediaItem_StatRecommended", recommended))
    }
    return list.filter { $0.2 > 0 }.map { (symbol: $0.0, title: $0.1, value: $0.2) }
  }

  var body: some View {
    BlockCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("MediaItem_TraktStatsTitle")
          .font(TypeScale.detailBody.weight(.semibold))
          .foregroundStyle(.secondary)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12, alignment: .leading)],
                  alignment: .leading, spacing: 12) {
          ForEach(tiles, id: \.symbol) { tile in
            VStack(alignment: .leading, spacing: 4) {
              Image(systemName: tile.symbol)
                .foregroundStyle(.secondary)
              Text(tile.title)
                .foregroundStyle(.secondary)
              Text(verbatim: tile.value.formatted(.number.notation(.compactName)))
                .font(TypeScale.detailBody.weight(.semibold))
                .foregroundStyle(Color.KinoPub.text)
            }
            .font(TypeScale.detailBody)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
          }
        }
        if afterCredits || duringCredits {
          Label(afterCredits ? LocalizedStringKey("MediaItem_AfterCreditsScene")
                             : LocalizedStringKey("MediaItem_DuringCreditsScene"),
                systemImage: "sparkles")
            .font(TypeScale.detailBody)
            .foregroundStyle(Color.KinoPub.text)
        }
      }
    }
  }
}

/// What a title's reviews praise and fault, as Trakt sums them up. Its phrases are
/// English; they are shown as written, with where they come from.
struct ReviewInsightsCard: View {
  let insights: ReviewInsights

  var body: some View {
    BlockCard {
      VStack(alignment: .leading, spacing: 14) {
        Text("MediaItem_ReviewInsightsTitle")
          .font(TypeScale.detailBody.weight(.semibold))
          .foregroundStyle(.secondary)
        group("MediaItem_ReviewInsightsGood", symbol: "plus.circle.fill", tint: .green, points: insights.good)
        group("MediaItem_ReviewInsightsBad", symbol: "minus.circle.fill", tint: .red, points: insights.bad)
        if insights.commentCount > 0 {
          Text(String(format: "MediaItem_ReviewInsightsSource".localized, insights.commentCount))
            .font(TypeScale.detailBody)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private func group(_ title: LocalizedStringKey, symbol: String, tint: Color, points: [String]) -> some View {
    if !points.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text(title)
          .font(TypeScale.detailBody.weight(.semibold))
          .foregroundStyle(Color.KinoPub.text)
        ForEach(points, id: \.self) { point in
          Label {
            Text(verbatim: point)
              .foregroundStyle(Color.KinoPub.text)
              .fixedSize(horizontal: false, vertical: true)
          } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
          }
          .font(TypeScale.detailBody)
        }
      }
    }
  }
}
