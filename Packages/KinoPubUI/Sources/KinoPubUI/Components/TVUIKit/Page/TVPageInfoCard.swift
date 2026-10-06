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
  case review(Review)
  case fact(Fact)
  case gallery(Gallery)
  case spec(Spec)

  public var id: String {
    switch self {
    case .rating(let rating): return "rating.\(rating.id)"
    case .review(let review): return "review.\(review.id)"
    case .fact(let fact): return "fact.\(fact.id)"
    case .gallery(let gallery): return "gallery.\(gallery.id)"
    case .spec(let spec): return "spec.\(spec.id)"
    }
  }

  /// What the layout needs to know to size the card, so a change in it is a relayout.
  var layoutToken: String {
    switch self {
    case .spec(let spec): return "spec.\(spec.rows.map(\.style.rawValue).joined(separator: ","))"
    default: return "card"
    }
  }

  // MARK: Score

  /// One source's score: its mark, the number, and how many people stand behind it.
  public struct Rating: Hashable {
    public let id: String
    /// The source's brand mark. Nil draws `title` in its place.
    public let source: MediaScoreLogo.Source?
    public let title: String
    /// The mark is a glyph with no lettering of its own (Kinopoisk's, kino.pub's): the
    /// source's name goes beside it. IMDb and TMDB are wordmarks and say it themselves.
    public let showsName: Bool
    /// Printed as the source prints it: `6.5`, `87%`, `—`.
    public let value: String
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

    public init(id: String, source: MediaScoreLogo.Source?, title: String, showsName: Bool = false,
                value: String, caption: String? = nil, thumbs: Thumbs? = nil) {
      self.id = id
      self.source = source
      self.title = title
      self.showsName = showsName
      self.value = value
      self.caption = caption
      self.thumbs = thumbs
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
    /// "Show" — the control's label while hidden.
    public let revealTitle: String

    public init(id: String, text: String, isSpoiler: Bool, isRevealed: Bool,
                warning: String, revealTitle: String) {
      self.id = id
      self.text = text
      self.isSpoiler = isSpoiler
      self.isRevealed = isRevealed
      self.warning = warning
      self.revealTitle = revealTitle
    }

    public var isHidden: Bool { isSpoiler && !isRevealed }
  }

  // MARK: Stills

  /// A mosaic of a title's stills that opens the whole gallery: the first few, then a
  /// chevron cell saying there is more.
  public struct Gallery: Hashable {
    /// How many stills the mosaic shows — its 3 × 2 grid, minus the chevron cell.
    public static let stillCount = 5

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

  /// One column of the technical table: a titled list of rows.
  public struct Spec: Hashable {
    public let id: String
    /// SF Symbol drawn before the title.
    public let symbol: String
    public let title: String
    public let rows: [Row]

    public init(id: String, symbol: String, title: String, rows: [Row]) {
      self.id = id
      self.symbol = symbol
      self.title = title
      self.rows = rows
    }

    public struct Row: Hashable {
      public enum Style: String, Hashable {
        /// A small label over the value that follows it — "Duration".
        case caption
        /// A value: "2 h 20 min", "3840×1600".
        case value
        /// A language: bigger, a flag before it.
        case language
        /// A line under a language — the dub, the studio.
        case detail
        /// The row that folds the rest: "4 more languages".
        case more
      }

      public enum Leading: Hashable {
        /// A flag (or any emoji) drawn as text.
        case emoji(String)
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
