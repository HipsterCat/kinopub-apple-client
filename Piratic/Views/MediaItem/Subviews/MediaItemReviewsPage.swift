//
//  MediaItemReviewsPage.swift
//  Piratic
//

import SwiftUI
import PiraticUI
import KinoPubBackend
import PiraticMetadata

#if !os(tvOS)
/// The title's scores and reviews, from the metadata already carried in the route.
struct MediaItemRatingsAndReviewsPage: View {
  let payload: RatingsAndReviews

  /// Opens where the card that led here says — the viewers', the critics' — or on all of it.
  @State private var tab: RatingsTab
  @State private var selectedReview: Review?

  init(payload: RatingsAndReviews) {
    self.payload = payload
    _tab = State(initialValue: payload.tab)
  }

  private var reviews: [Review] { payload.reviews }

  var body: some View {
    Group {
      if FeatureFlags.ratingsSummaryCards {
        tabbedBody
      } else {
        legacyBody
      }
    }
    .mediaReviewSheet($selectedReview, item: payload.item)
  }

  // MARK: Tabs

  private var summaries: RatingSources.Summaries {
    RatingSources.summaries(for: payload.item,
                            metadata: payload.metadata,
                            likeCount: payload.likeCount,
                            dislikeCount: payload.dislikeCount,
                            rowLimit: nil)
  }

  private var tabbedBody: some View {
    let summaries = summaries
    return ScrollView {
      VStack(alignment: .leading, spacing: BlockMetrics.spacing) {
        Picker(selection: $tab.animation(.snappy)) {
          ForEach(RatingsTab.allCases) { tab in
            Text(verbatim: tab.title).tag(tab)
          }
        } label: {
          EmptyView()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)

        // One block per side; a tab shows its own, All shows both. Switch cases come and go
        // with the tab, crossfading and sliding a little, so the change reads as a filter.
        if tab != .critics {
          viewersBlock(summaries.viewers)
            .transition(.opacity.combined(with: .move(edge: .leading)))
        }
        if tab != .viewers {
          criticsBlock(summaries.critics)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
      }
      .padding(.horizontal, MediaItemLayout.horizontalInset)
      .padding(.vertical, MediaItemLayout.sectionSpacing)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .platformNavigationTitle(payload.item.localizedTitle)
    .background(Color.Piratic.background.ignoresSafeArea())
  }

  /// The card's head without its rows: here the sources are rows of their own, named and
  /// linked (`MediaItemRatingSourceRows`). The critics keep their tones.
  private func header(_ summary: ScoreSummary) -> some View {
    BlockCard {
      ScoreSummaryCardContent(summary: ScoreSummary(kind: summary.kind, title: summary.title,
                                                    subtitle: summary.subtitle, score: summary.score,
                                                    rows: [], tones: summary.tones))
    }
  }

  @ViewBuilder
  private func viewersBlock(_ summary: ScoreSummary?) -> some View {
    VStack(alignment: .leading, spacing: BlockMetrics.spacing) {
      if let summary { header(summary) }
      let audience = scores.filter { !RatingSources.isCritic($0.logo) }
      if !audience.isEmpty {
        MediaItemRatingSourceRows(scores: audience)
      }
      if let trakt = traktScore, !payload.traktDistribution.isEmpty {
        TraktDistributionCard(score: trakt, distribution: payload.traktDistribution)
      }
      if let douban = payload.externalRatings.first(where: { $0.kind == .douban }) {
        DoubanStatsCard(score: douban, stats: payload.doubanStats)
      }
      if let myShows = payload.externalRatings.first(where: { $0.kind == .myShows }) {
        MyShowsStatsCard(score: myShows, stats: payload.myShowsStats)
      }
      if let stats = payload.audienceStats {
        AudienceStatsCard(stats: stats,
                          afterCredits: payload.hasAfterCreditsScene == true,
                          duringCredits: payload.hasDuringCreditsScene == true)
      }
    }
  }

  @ViewBuilder
  private func criticsBlock(_ summary: ScoreSummary?) -> some View {
    VStack(alignment: .leading, spacing: BlockMetrics.spacing) {
      if let summary { header(summary) }
      let critics = scores.filter { RatingSources.isCritic($0.logo) }
      if !critics.isEmpty {
        MediaItemRatingSourceRows(scores: critics)
      }
      if let insights = payload.reviewInsights, !insights.isEmpty {
        ReviewInsightsCard(insights: insights)
      }
      LazyVStack(alignment: .leading, spacing: BlockMetrics.spacing) {
        reviewCards
      }
    }
  }

  // MARK: The combined card (Diagnostics: off)

  private var legacyBody: some View {
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
        if let myShows = payload.externalRatings.first(where: { $0.kind == .myShows }) {
          MyShowsStatsCard(score: myShows, stats: payload.myShowsStats)
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
        reviewCards
      }
      .padding(.horizontal, MediaItemLayout.horizontalInset)
      .padding(.vertical, MediaItemLayout.sectionSpacing)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .platformNavigationTitle(payload.item.localizedTitle)
    .background(Color.Piratic.background.ignoresSafeArea())
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

  @ViewBuilder
  private var reviewCards: some View {
    if reviews.isEmpty {
      emptyNote
    } else {
      ForEach(reviews) { review in
        ReviewCard(review: review, width: nil, height: BlockMetrics.textCardHeight) { selectedReview = review }
      }
    }
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
           unhelpfulVotes: 2),
    Review(author: "Big Homie",
           title: "",
           body: "[Hunter Schafer](https://app.trakt.tv/people/hunter-schafer) carries the film.\n\nThe final scene stayed with me.",
           sentiment: "POSITIVE",
           postedAt: .now,
           helpfulVotes: 24,
           source: .trakt,
           replyCount: 1,
           authorRating: 8)
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
}
#endif

extension View {
  func mediaReviewSheet(_ selection: Binding<Review?>, item: MediaItem) -> some View {
    modifier(MediaReviewSheet(selection: selection, item: item))
  }
}

private struct MediaReviewSheet: ViewModifier {
  @Binding var selection: Review?
  let item: MediaItem
  @Environment(\.appContext) private var appContext

  func body(content: Content) -> some View {
#if os(tvOS)
    content.fullScreenCover(item: $selection) { review in
      reader(for: review)
        .presentationBackground(.clear)
    }
#else
    content.sheet(item: $selection) { review in
      reader(for: review)
#if os(iOS)
        .presentationSizing(.page)
#else
        .frame(idealWidth: InfoPopupMetrics.maxWidth)
#endif
    }
#endif
  }

  private func reader(for review: Review) -> some View {
    MediaReviewReader(review: review, sourceURL: sourceURL(for: review),
                      repliesService: appContext.traktRepliesService)
      .pageColorScheme()
  }

  private func sourceURL(for review: Review) -> URL? {
#if os(tvOS)
    return nil
#else
    if review.isFromTrakt {
      return review.sourceId.flatMap { URL(string: "https://trakt.tv/comments/\($0)") }
    }
    // Kinopoisk's permalink uses a user id the proxy does not provide.
    guard let id = item.kinopoisk, id > 0 else { return nil }
    let kind = item.isSeries ? "series" : "film"
    return URL(string: "https://www.kinopoisk.ru/\(kind)/\(id)/reviews/")
#endif
  }
}

private struct MediaReviewReader: View {
  let review: Review
  let sourceURL: URL?
  let repliesService: any TraktRepliesService

  private enum Replies {
    case loading
    case loaded([TraktCommentReply])
    case failed
  }

  @Environment(\.locale) private var locale
  @State private var replies: Replies = .loading
  @State private var attempt = 0

  private var commentID: Int? {
    guard review.isFromTrakt, review.replyCount > 0, let id = review.sourceId, id > 0 else { return nil }
    return id
  }

  var body: some View {
    let presentation = ReviewPresentation(review, locale: locale)
    InfoPopupView(title: presentation.sheetTitle, showsToolbarTitle: review.authorRating != nil) {
      VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing) {
        ReviewReadingContent(review: presentation, sourceURL: sourceURL)
        if commentID != nil {
          Divider()
          InfoPopupSection(Text("MediaItem_ReviewReplies")) { repliesContent }
        }
      }
    }
    // One task for the sheet, including when the TV popup switches to scrolling.
    .task(id: attempt) { await loadReplies() }
  }

  @ViewBuilder
  private var repliesContent: some View {
    switch replies {
    case .loading:
      ProgressView()
        .controlSize(.small)
        .accessibilityLabel(Text("Loading"))
    case .loaded(let replies) where !replies.isEmpty:
      ReviewReplyList(replies: replies)
    case .loaded:
      Text("MediaItem_ReviewRepliesEmpty")
        .font(InfoPopupMetrics.bodyFont)
        .foregroundStyle(.secondary)
    case .failed:
      Text("MediaItem_ReviewRepliesFailed")
        .font(InfoPopupMetrics.bodyFont)
        .foregroundStyle(.secondary)
      Button("Try Again") { attempt += 1 }
        .buttonStyle(.bordered)
    }
  }

  private func loadReplies() async {
    guard let commentID else { return }
    replies = .loading
    do {
      let loaded = try await repliesService.replies(to: commentID)
      try Task.checkCancellation()
      replies = .loaded(loaded)
    } catch {
      if !Task.isCancelled { replies = .failed }
    }
  }
}

#Preview("Trakt review with a reply") {
  let date = Date(timeIntervalSince1970: 1_784_600_000)
  let review = Review(author: "Lintandil", title: "", body: "The last shot was worth staying for.",
                      postedAt: date, helpfulVotes: 14, sourceId: 1, source: .trakt,
                      replyCount: 1, authorRating: 6)
  let reply = TraktCommentReply(id: 2, author: "FrameByFrame", text: "That last shot stayed with me too.",
                                postedAt: date.addingTimeInterval(86_400))
  return MediaReviewReader(review: review, sourceURL: nil,
                           repliesService: TraktRepliesServiceMock(repliesByComment: [1: [reply]]))
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

  nonisolated static func unit(_ votes: Int) -> String {
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
              .foregroundStyle(Color.Piratic.text)
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

/// MyShows' side of a series: its five-star score and how many people follow it. MyShows
/// publishes no breakdown of its votes, so the card has no bars (Sasha, 2026-11-09).
struct MyShowsStatsCard: View {
  let score: ExternalRating
  let stats: MyShowsStats?

  private var counts: [(symbol: String, title: LocalizedStringKey, value: Int)] {
    guard let stats else { return [] }
    let list: [(String, LocalizedStringKey, Int)] = [
      ("play.circle", "MediaItem_MyShowsWatching", stats.watching),
      ("person.2", "MediaItem_MyShowsWatchingTotal", stats.watchingTotal),
    ]
    return list.filter { $0.2 > 0 }.map { (symbol: $0.0, title: $0.1, value: $0.2) }
  }

  var body: some View {
    RatingDistributionCard(title: "MediaItem_MyShowsRatingTitle",
                           score: String(format: "%.1f", score.value),
                           votes: score.votes,
                           buckets: [],
                           tint: .red) {
      if !counts.isEmpty {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12, alignment: .leading)],
                  alignment: .leading, spacing: 12) {
          ForEach(counts, id: \.symbol) { tile in
            VStack(alignment: .leading, spacing: 4) {
              Image(systemName: tile.symbol)
                .foregroundStyle(.secondary)
              Text(tile.title)
                .foregroundStyle(.secondary)
              Text(verbatim: CompactCountFormat.string(tile.value))
                .font(TypeScale.detailBody.weight(.semibold))
                .foregroundStyle(Color.Piratic.text)
            }
            .font(TypeScale.detailBody)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
          }
        }
      }
    }
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
              Text(verbatim: CompactCountFormat.string(tile.value))
                .font(TypeScale.detailBody.weight(.semibold))
                .foregroundStyle(Color.Piratic.text)
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
            .foregroundStyle(Color.Piratic.text)
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
              Text(verbatim: CompactCountFormat.string(tile.value))
                .font(TypeScale.detailBody.weight(.semibold))
                .foregroundStyle(Color.Piratic.text)
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
            .foregroundStyle(Color.Piratic.text)
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
          .foregroundStyle(Color.Piratic.text)
        ForEach(points, id: \.self) { point in
          Label {
            Text(verbatim: point)
              .foregroundStyle(Color.Piratic.text)
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
