#if os(tvOS)
//
//  TVPageInfoCard.swift
//  KinoPubUI
//
//  What a `TVPageCellKind.infoCard` says. The HIG calls the shape a card — "a header,
//  footer, and content view to present ratings and reviews for media items" — and the
//  system view for it is `TVCardView`. A score, a review, a fact, a strip of stills and a
//  column of specifications are five contents of that one platter, not five components:
//  the platter, its focus lift and its white fill on focus are the card view's, and the
//  cell family draws the content inside it.
//
//  Every string here is already in the reader's language. KinoPubUI has no string catalog
//  of its own for this — the page that builds the cards does the wording.
//

import Foundation
import UIKit

public enum TVPageInfoCard: Hashable {
  case rating(Rating)
  case reviews(Reviews)
  case review(Review)
  case fact(Fact)
  case gallery(Gallery)
  case spec(Spec)

  public var id: String {
    switch self {
    case .rating(let rating): return "rating.\(rating.id)"
    case .reviews(let reviews): return "reviews.\(reviews.id)"
    case .review(let review): return "review.\(review.id)"
    case .fact(let fact): return "fact.\(fact.id)"
    case .gallery(let gallery): return "gallery.\(gallery.id)"
    case .spec(let spec): return "spec.\(spec.id)"
    }
  }

  var registration: TVPageRegistration {
    switch self {
    case .rating: return .rating
    case .reviews: return .reviews
    case .review: return .review
    case .fact: return .fact
    case .gallery: return .gallery
    case .spec: return .spec
    }
  }

  /// What the layout needs to know to size the card, so a change in it is a relayout.
  var layoutToken: String {
    switch self {
    // A column is as tall as its rows, and a row that wraps is as tall as its words.
    case .spec(let spec): return "spec.\(spec.rows.map { "\($0.style.rawValue):\($0.text)" }.joined(separator: ","))"
    default: return "card"
    }
  }

  // MARK: Score

  /// One source's score: its mark, the number, and how many people stand behind it.
  public struct Rating: Hashable {
    public let id: String
    /// The source's brand mark, drawn before the number. Nil draws `title` in its place.
    public let source: MediaScoreLogo.Source?
    public let title: String
    /// Printed as the source prints it: `6.5`, `87%`. Nil while the source has voters but
    /// has not published a score yet — the card draws a dash, in secondary ink, where the
    /// number would be, and `caption` still says how many voted.
    public let value: String?
    public let caption: String?
    /// kino.pub's own score is thumbs, and shows how many of each.
    public let thumbs: Thumbs?

    public struct Thumbs: Hashable {
      public let up: String
      public let down: String

      public init(up: String, down: String) {
        self.up = up
        self.down = down
      }
    }

    public init(id: String, source: MediaScoreLogo.Source?, title: String,
                value: String?, caption: String? = nil, thumbs: Thumbs? = nil) {
      self.id = id
      self.source = source
      self.title = title
      self.value = value
      self.caption = caption
      self.thumbs = thumbs
    }
  }

  // MARK: Reviews, counted

  /// How many reviews there are, and how they were meant — a card of the same shape and size as a
  /// score, in the scores' row, in place of the reviews' own text, which is read on a page of its
  /// own (Sasha, 2026-10-11).
  public struct Reviews: Hashable {
    public let id: String
    /// "Отзывы".
    public let title: String
    /// The total, as the reader writes it: "63".
    public let count: String
    /// How many were meant well, badly and neither. Nil when the source has not said.
    public let tones: Tones?
    /// What VoiceOver reads: the title, the total and the tones, in words.
    public let accessibilityLabel: String

    public struct Tones: Hashable {
      public let positive: String
      public let negative: String
      public let neutral: String

      public init(positive: String, negative: String, neutral: String) {
        self.positive = positive
        self.negative = negative
        self.neutral = neutral
      }
    }

    public init(id: String, title: String, count: String, tones: Tones? = nil, accessibilityLabel: String) {
      self.id = id
      self.title = title
      self.count = count
      self.tones = tones
      self.accessibilityLabel = accessibilityLabel
    }
  }

  // MARK: Review

  public struct Review: Hashable {
    public enum Tone: String, Hashable {
      case positive, neutral, negative
    }

    public let id: String
    public let headline: String
    public let body: String
    /// "Positive" / "Негативная" — the reader's word for how the review was meant.
    public let sentiment: String?
    public let tone: Tone
    public let date: String?

    public init(id: String, headline: String, body: String, sentiment: String?, tone: Tone, date: String?) {
      self.id = id
      self.headline = headline
      self.body = body
      self.sentiment = sentiment
      self.tone = tone
      self.date = date
    }
  }

  // MARK: Fact

  /// A trivia line. A spoiler starts as a warning and a reveal control and turns into the
  /// fact when selected — the card is the control, nothing inside it is.
  public struct Fact: Hashable {
    public let id: String
    public let text: String
    public let isSpoiler: Bool
    public let isRevealed: Bool
    /// "This fact contains spoilers, be careful." — shown while it is hidden.
    public let warning: String

    public init(id: String, text: String, isSpoiler: Bool, isRevealed: Bool, warning: String) {
      self.id = id
      self.text = text
      self.isSpoiler = isSpoiler
      self.isRevealed = isRevealed
      self.warning = warning
    }

    public var isHidden: Bool { isSpoiler && !isRevealed }
  }

  // MARK: Stills

  /// A mosaic of a title's stills that opens the whole gallery: the first few, laid out in a grid
  /// that adapts to how many there are (`TVPageGalleryContent.frames`), up to six.
  public struct Gallery: Hashable {
    /// The most stills the mosaic shows (Sasha, 2026-10-11).
    public static let stillCount = 6

    public let id: String
    public let images: [URL]
    public let accessibilityLabel: String

    public init(id: String, images: [URL], accessibilityLabel: String) {
      self.id = id
      self.images = images
      self.accessibilityLabel = accessibilityLabel
    }
  }

  // MARK: Specification

  /// One item of the table under the page — a card of its own: Audio, Subtitles, the resolution, the
  /// genres. Focus moves from card to card (Sasha, 2026-10-11), so none is as tall as the screen.
  public struct Spec: Hashable {
    public let id: String
    /// SF Symbol drawn before the title, when the card has a header.
    public let symbol: String
    /// The header's words — and what the popup that reads the card in full is called.
    public let title: String
    /// Audio and Subtitles are headed; the resolution, a runtime or a genre list are just rows.
    public let showsHeader: Bool
    /// Select reads the whole card in the info popup — every language, every name. Off: it is
    /// focusable and says what it says, and Select does nothing.
    public let opensInPopup: Bool
    public let rows: [Row]

    public init(id: String, symbol: String = "info.circle", title: String, showsHeader: Bool = true,
                opensInPopup: Bool = false, rows: [Row]) {
      self.id = id
      self.symbol = symbol
      self.title = title
      self.showsHeader = showsHeader
      self.opensInPopup = opensInPopup
      self.rows = rows
    }

    public struct Row: Hashable {
      public enum Style: String, Hashable {
        /// A small label over the value that follows it — "Duration".
        case caption
        /// A value: "2 h 20 min", "3840×1600".
        case value
        /// A language.
        case language
        /// A line under a language — the dub, its studios. Wraps; never cut.
        case detail
        /// What there is more of, in secondary words and no glyph: "+ ещё 7", "Показать все".
        case more
      }

      public enum Leading: Hashable {
        case symbol(String)
      }

      public let id: String
      public let text: String
      /// Beside the text, quieter: "Original", "Forced".
      public let secondary: String?
      /// Boxed marks after the text: `CC`, `4K`.
      public let badges: [String]
      public let leading: Leading?
      public let style: Style

      public init(id: String, text: String, secondary: String? = nil, badges: [String] = [],
                  leading: Leading? = nil, style: Style = .value) {
        self.id = id
        self.text = text
        self.secondary = secondary
        self.badges = badges
        self.leading = leading
        self.style = style
      }
    }
  }
}
#endif
