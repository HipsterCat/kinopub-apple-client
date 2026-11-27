import Foundation
import KinoPubMedia
import KinoPubMetadata
import SwiftUI

/// The review fields shared by the SwiftUI card, the TVUIKit card and the sheet.
public struct ReviewPresentation: Hashable, Sendable {
  enum Tone: String, Hashable, Sendable {
    case positive, neutral, negative

    var asset: String { "review_\(rawValue)" }

    var color: Color {
      switch self {
      case .positive: .green
      case .neutral: .secondary
      case .negative: .red
      }
    }

    func title(locale: Locale) -> String {
      switch self {
      case .positive: String(localized: "Positive", locale: locale)
      case .neutral: String(localized: "Neutral", locale: locale)
      case .negative: String(localized: "Negative", locale: locale)
      }
    }
  }

  struct Counter: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
      case replies, likes, helpful, unhelpful

      var symbol: String {
        switch self {
        case .replies: "text.bubble.fill"
        case .likes, .helpful: "hand.thumbsup.fill"
        case .unhelpful: "hand.thumbsdown.fill"
        }
      }

      func title(locale: Locale) -> String {
        switch self {
        case .replies: String(localized: "MediaItem_ReviewReplies", locale: locale)
        case .likes: String(localized: "MediaItem_ReviewLikes", locale: locale)
        case .helpful: String(localized: "MediaItem_ReviewHelpful", locale: locale)
        case .unhelpful: String(localized: "MediaItem_ReviewUnhelpful", locale: locale)
        }
      }
    }

    var id: Kind { kind }
    let kind: Kind
    let value: String
    let label: String
  }

  public let review: Review
  let title: String?
  let excerpt: AttributedString
  let date: String?
  let tone: Tone?
  let toneTitle: String?
  let score: Double?
  let scoreText: String?
  let source: MediaScoreLogo.Source
  let sourceName: String
  let counters: [Counter]

  var body: AttributedString { Self.text(review.body, isMarkdown: review.isFromTrakt) }

  public init(_ review: Review, locale: Locale) {
    self.review = review
    let title = review.title.trimmingCharacters(in: .whitespacesAndNewlines)
    self.title = title.isEmpty ? nil : title
    let singleParagraph = review.body.replacingOccurrences(of: #"\s*\n+\s*"#, with: " ", options: .regularExpression)
    excerpt = Self.text(singleParagraph, isMarkdown: review.isFromTrakt)
    date = Self.date(review, locale: locale)
    tone = review.sentiment.map { $0.lowercased() }.flatMap(Tone.init(rawValue:))
    toneTitle = tone?.title(locale: locale)
    score = review.authorRating.flatMap { (1...10).contains($0) ? Double($0) / 2 : nil }
    scoreText = score.map { $0.formatted(.number.locale(locale)) }
    source = review.isFromTrakt ? .trakt : .kinopoisk
    sourceName = review.isFromTrakt ? "Trakt" : String(localized: "MediaItem_ReviewSourceKinopoisk", locale: locale)
    let counts: [(Counter.Kind, Int)] = review.isFromTrakt
      ? [(.replies, review.replyCount), (.likes, review.helpfulVotes)]
      : [(.unhelpful, review.unhelpfulVotes), (.helpful, review.helpfulVotes)]
    counters = counts.compactMap { kind, count in
      guard count > 0 else { return nil }
      return Counter(kind: kind, value: count.formatted(.number.locale(locale)), label: kind.title(locale: locale))
    }
  }

  private static func text(_ body: String, isMarkdown: Bool) -> AttributedString {
    guard isMarkdown, let parsed = try? AttributedString(
      markdown: body,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) else { return AttributedString(body) }
    return parsed
  }

  /// Only underline a tag where it opens a web link.
  func styled(_ text: AttributedString, linksEnabled: Bool) -> AttributedString {
    var styled = text
    for run in text.runs {
      guard let link = run.link else { continue }
      if linksEnabled, ["http", "https"].contains(link.scheme?.lowercased() ?? ""), link.host != nil {
        styled[run.range].underlineStyle = .single
      } else {
        styled[run.range].link = nil
      }
    }
    return styled
  }

  private static func date(_ review: Review, locale: Locale) -> String? {
    if let date = review.postedAt {
      let calendar = Calendar.current
      if calendar.isDateInToday(date) { return String(localized: "Today", locale: locale) }
      if calendar.isDateInYesterday(date) { return String(localized: "Yesterday", locale: locale) }
      return date.formattedForDisplay(.dateTime.day().month(.abbreviated).year().locale(locale))
    }
    return review.date.map { String($0.prefix(10)) }
  }
}

// MARK: - Card

#if !os(tvOS)
public struct ReviewCard: View {
  let review: Review
  let width: CGFloat?
  let height: CGFloat?
  let action: () -> Void

  @Environment(\.locale) private var locale

  public init(review: Review, width: CGFloat? = BlockMetrics.textCardWidth, height: CGFloat? = nil,
              action: @escaping () -> Void) {
    self.review = review
    self.width = width
    self.height = height
    self.action = action
  }

  public var body: some View {
    let presentation = ReviewPresentation(review, locale: locale)
    let excerpt = presentation.styled(presentation.excerpt, linksEnabled: false)
    BlockCard(.interactive(action: action), width: width, height: height, fillsHeight: true,
              tint: presentation.tone == .neutral ? nil : presentation.tone?.color) {
      VStack(alignment: .leading, spacing: 8) {
        ReviewHeading(review: presentation)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        ViewThatFits(in: .vertical) {
          grown(excerpt, font: .title2)
          grown(excerpt, font: .title3)
          FillingText(excerpt, font: TypeScale.detailBody)
        }
        .foregroundStyle(Color.Piratic.text)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        ReviewFooter(review: presentation)
          .fixedSize(horizontal: false, vertical: true)
      }
      .accessibilityElement(children: .combine)
    }
  }

  private func grown(_ excerpt: AttributedString, font: Font) -> some View {
    Text(excerpt)
      .font(font)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
#endif

// MARK: - Reading

public struct ReviewReadingContent: View {
  let review: ReviewPresentation
  var sourceURL: URL?

  public init(review: ReviewPresentation, sourceURL: URL? = nil) {
    self.review = review
    self.sourceURL = sourceURL
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing) {
      ReviewHeading(review: review)
        .fixedSize(horizontal: false, vertical: true)
      Text(review.styled(review.body, linksEnabled: linksEnabled))
        .font(InfoPopupMetrics.bodyFont)
        .foregroundStyle(Color.Piratic.text)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("kinopub.review.sheet.body")
      ReviewFooter(review: review, sourceURL: sourceURL)
      if !review.review.author.isEmpty {
        Text(verbatim: review.review.author)
          .foregroundStyle(.secondary)
          .font(InfoPopupMetrics.captionFont)
      }
    }
  }

  private var linksEnabled: Bool {
#if os(tvOS)
    false
#else
    true
#endif
  }
}

private struct ReviewHeading: View {
  let review: ReviewPresentation

  var body: some View {
    if let score = review.score, let text = review.scoreText {
      HStack(spacing: 6) {
        StarRatingRow(value: score, tint: Color.Piratic.text, font: TypeScale.detailBody)
          .accessibilityHidden(true)
        Text(verbatim: "\(text)/5")
          .monospacedDigit()
      }
      .foregroundStyle(Color.Piratic.text)
      .font(TypeScale.detailBody)
    } else if review.title != nil || review.tone != nil {
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        if let tone = review.tone {
          Image(tone.asset, bundle: .module)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: iconHeight, height: iconHeight)
            .foregroundStyle(tone.color)
            .accessibilityLabel(Text(verbatim: review.toneTitle ?? ""))
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.bottom] - 1 }
        }
        if let title = review.title {
          Text(verbatim: title)
            .font(TypeScale.detailBody)
            .foregroundStyle(Color.Piratic.text)
        }
      }
    }
  }

  @ScaledMetric(relativeTo: .body) private var iconHeight: CGFloat = {
#if os(tvOS)
    24
#else
    14
#endif
  }()
}

private struct ReviewFooter: View {
  let review: ReviewPresentation
  var sourceURL: URL?

  @ScaledMetric(relativeTo: .footnote) private var markHeight: CGFloat = {
#if os(tvOS)
    22
#else
    14
#endif
  }()

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack {
        sourceAndDate.fixedSize()
        Spacer(minLength: 8)
        counters.fixedSize()
      }
      VStack(alignment: .leading, spacing: 6) {
        sourceAndDate
        counters.frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .font(InfoPopupMetrics.captionFont)
    .foregroundStyle(.secondary)
  }

  private var sourceAndDate: some View {
    HStack(spacing: 6) {
      if let sourceURL {
        Link(destination: sourceURL) { mark }
      } else {
        mark
      }
      if let date = review.date {
        Text(verbatim: date)
      }
    }
  }

  private var mark: some View {
    MediaScoreLogo(review.source, height: markHeight, style: .color)
      .accessibilityLabel(Text(verbatim: review.sourceName))
  }

  private var counters: some View {
    HStack(spacing: 10) {
      ForEach(review.counters) { counter in
        HStack(spacing: 4) {
          Text(verbatim: counter.value)
            .monospacedDigit()
          Image(systemName: counter.kind.symbol)
            .imageScale(.large)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: counter.label))
        .accessibilityValue(Text(verbatim: counter.value))
      }
    }
  }
}
