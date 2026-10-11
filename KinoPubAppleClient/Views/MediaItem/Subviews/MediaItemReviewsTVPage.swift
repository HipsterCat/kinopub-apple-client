#if os(tvOS)
//
//  MediaItemReviewsTVPage.swift
//  KinoPubAppleClient
//
//  The reviews, read. The detail page does not carry their words any more — its scores' row ends
//  in a card that counts them (Sasha, 2026-10-11) — and Select on that card is how you get here.
//
//  A grid of the same review cards the row used to hold, three across: a headline (the author when
//  there is none), as much of the text as fits, how it was meant, the date. Select on one reads it
//  whole in the shared info popup. Nothing here fetches: it all travelled in the route
//  (`RatingsAndReviews`), already merged into the item's metadata.
//
//  The count on the card is the source's total; what is here is what we carry — the proxy pages its
//  reviews and we take the first page (`ReviewsSummary`).
//

import SwiftUI
import KinoPubUI
import KinoPubMetadata

struct MediaItemReviewsTVPage: View {
  let payload: RatingsAndReviews

  @State private var openReview: Int?

  private var reviews: [Review] { payload.reviews }

  var body: some View {
    TVPage(sections: sections,
           status: reviews.isEmpty ? .message("MediaItem_NoReviews".localized) : .content,
           accessibilityID: "kinopub.page.reviews",
           onSelect: { _, item in select(item) })
      .infoPopup(popupTitle, isPresented: popupBinding) { popupContent }
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
    guard case .info(.review(let review)) = item, let index = Int(review.id) else { return }
    openReview = index
  }

  private var popupBinding: Binding<Bool> {
    Binding(get: { openReview != nil }, set: { if !$0 { openReview = nil } })
  }

  private var popupTitle: Text {
    guard let index = openReview, reviews.indices.contains(index) else { return Text("") }
    let review = reviews[index]
    return Text(review.title.isEmpty ? review.author : review.title)
  }

  @ViewBuilder
  private var popupContent: some View {
    if let index = openReview, reviews.indices.contains(index) {
      ReviewPopupBody(review: reviews[index])
    }
  }
}

/// A review read in full: the text, then who wrote it, when, and how it was meant.
private struct ReviewPopupBody: View {
  let review: Review

  var body: some View {
    VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing) {
      Text(review.body)
        .font(InfoPopupMetrics.bodyFont)
        .foregroundStyle(Color.KinoPub.text)
        .multilineTextAlignment(.leading)
      HStack(spacing: 16) {
        if let sentiment = review.sentimentTitle {
          Text(sentiment).foregroundStyle(review.sentimentColor)
        }
        Text(review.author).foregroundStyle(.secondary)
        if let date = review.displayDate {
          Text(date).foregroundStyle(.secondary)
        }
      }
      .font(.callout)
    }
  }
}
#endif
