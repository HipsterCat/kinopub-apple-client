#if os(tvOS)
//
//  MediaItemReviewsTVPage.swift
//  KinoPubAppleClient
//
//  The TVUIKit collection of ratings and all reviews carried by the route.
//

import SwiftUI
import KinoPubUI
import KinoPubMetadata

struct MediaItemReviewsTVPage: View {
  let payload: RatingsAndReviews

  @State private var selectedReview: Review?

  private var reviews: [Review] { payload.reviews }

  var body: some View {
    let shown = FeatureFlags.ratingsSummaryCards ? tabbedSections : sections
    return TVPage(sections: shown,
           status: shown.isEmpty ? .message("MediaItem_NoReviews".localized) : .content,
           accessibilityID: "kinopub.page.reviews",
           onSelect: { _, item in select(item) })
      .mediaReviewSheet($selectedReview, item: payload.item)
  }

  /// The viewers' sources, the critics' sources and the reviews, the side the card that led
  /// here names first (Sasha, 2026-11-09): the viewers' card opens on their scores, the
  /// critics' card on the critics' and the reviews.
  private var tabbedSections: [TVPageSection] {
    let input = MediaItemTVSections.Input(mediaItem: payload.item, metadata: payload.metadata,
                                          likeCount: payload.likeCount, dislikeCount: payload.dislikeCount)
    let scores = RatingSources.scores(for: payload.item, metadata: payload.metadata,
                                      likeCount: payload.likeCount, dislikeCount: payload.dislikeCount)
      .filter { !$0.isPlaceholder }
    let summaries = RatingSources.summaries(for: payload.item, metadata: payload.metadata,
                                            likeCount: payload.likeCount, dislikeCount: payload.dislikeCount)
    func strip(_ id: String, _ summary: ScoreSummary?, critics: Bool) -> [TVPageSection] {
      let tiles = scores.filter { RatingSources.isCritic($0.logo) == critics }
        .map { TVPageItem.info(.rating(MediaItemTVSections.rating($0, input))) }
      guard !tiles.isEmpty else { return [] }
      return [.strip(id: id, title: summary?.title, count: summary?.subtitle,
                     groups: [TVPageGroup(id: "\(id)-scores", title: nil, columns: 6, items: tiles)])]
    }
    let viewers = strip("viewers", summaries.viewers, critics: false)
    let critics = strip("critics", summaries.critics, critics: true)
    switch payload.tab {
    case .viewers: return viewers + critics + sections
    case .critics: return critics + sections + viewers
    case .all: return viewers + critics + sections
    }
  }

  private var sections: [TVPageSection] {
    guard !reviews.isEmpty else { return [] }
    let total = payload.summary.map(\.total) ?? 0
    return [TVPageSection(id: "reviews",
                          title: "Reviews".localized,
                          count: (total > reviews.count ? total : reviews.count).formatted(.number.grouping(.automatic)),
                          kind: .infoCard, flow: .grid, columns: 3,
                          items: reviews.enumerated().map { .info(.review(MediaItemTVSections.review($1, index: $0))) })]
  }

  private func select(_ item: TVPageItem) {
    guard case .info(.review(let review)) = item else { return }
    selectedReview = review.presentation.review
  }
}
#endif
