//
//  TypeScale.swift
//  KinoPubUI
//

import SwiftUI

/// Text styles for cards, shelves, heroes and chrome. Prefer these over `.system(size:)`.
public enum TypeScale {
    public static let cardTitle: Font = {
#if os(tvOS)
        .body
#endif
         #if os(iOS)
    .subheadline
         #endif
         #if os(macOS)
    .body
         #endif
    }()
  /// An episode's name under its still on the title page: a step above `cardTitle`
  /// (Sasha, 2026-10-30). The line under it stays `cardMeta`.
  public static let episodeCardTitle: Font = {
#if os(tvOS)
        .body
#endif
         #if os(iOS)
    .subheadline
         #endif
         #if os(macOS)
    .body
         #endif
    }()
  public static let cardSubtitle: Font = {
#if os(tvOS)
        .caption
#endif
         #if os(iOS)
    .caption
         #endif
         #if os(macOS)
    .subheadline
         #endif
    }()
  public static let cardMeta: Font = {
#if os(tvOS)
        .caption
#endif
         #if os(iOS)
    .caption
         #endif
         #if os(macOS)
    .subheadline
         #endif
    }()
    /// tvOS catalog shelves: Sketch `Headers/Section Header/Dark/Secondary/1 Line`
    /// = Headline emphasized. Sasha: **semibold**, not `.headline.bold()`. Not Title 2
    /// (~57pt), not Primary / Subtitle / Eyebrow / App Icon / Pill.
    public static let rowHeader: Font = {
#if os(tvOS)
        .headline.weight(.semibold)
#endif
         #if os(iOS)
    .title3.weight(.semibold)
         #endif
         #if os(macOS)
    .title2.weight(.semibold)
         #endif
    }()
     public static let rowCount: Font = {
     #if os(tvOS)
               .subheadline.weight(.semibold)
#endif
         #if os(iOS)
    .subheadline.weight(.semibold)
         #endif
         #if os(macOS)
    .title3.weight(.semibold)
                    
     #endif
     }()
  public static let rowChevron: Font = {
#if os(tvOS)
        .headline.weight(.bold)
#endif
         #if os(iOS)
    .subheadline.weight(.semibold)
         #endif
         #if os(macOS)
    .title3.weight(.semibold)
         #endif
    }()

  public static let heroTitle: Font = {
#if os(tvOS)
    return .title3.weight(.semibold)
#elseif os(macOS)
    return .largeTitle.weight(.semibold)
#else
    return .title.weight(.bold)
#endif
  }()

  public static let heroSecondary: Font = {
#if os(tvOS)
    return .callout
#elseif os(macOS)
    return .body
#else
    return .footnote
#endif
  }()
    

  /// **The** running-text size on an item page. Everything that is prose or a
  /// label-and-value pair takes this: the hero's metadata row, synopsis and credit
  /// lines, the vote counts under the rating tiles, and every row of the information
  /// table. They used to be four hand-picked point sizes between 12 and 15 that were
  /// never quite the same as each other; one token means they cannot drift apart again.
  ///
  /// A text style rather than `.system(size:)`, so it tracks Dynamic Type. Add `.weight`
  /// where a value needs to stand out from its caption — never a size.
  /// It is `.body` — the platform's own running-text style — rather than a step down
  /// from it. The old sizes were all *below* body (12–15pt on a Mac, 20–25 on a TV):
  /// small enough that the synopsis read as a caption on the artwork instead of as the
  /// thing you are meant to read. Levelling them meant levelling **up**.
    public static let detailBody: Font = {
#if os(tvOS)
         .caption2
#endif
         #if os(iOS)
    .callout
         #endif
         #if os(macOS)
    .body
         #endif
    }()
     public static let filterControl: Font = .subheadline.weight(.medium)
  public static let actionLabel: Font = .subheadline.weight(.medium)
  public static let detailSection: Font = .title3.weight(.medium)
     public static let settingsTitle: Font = .largeTitle.weight(.semibold)
  public static let settingsTip: Font = .title3

  /// Rating digits on a poster's corner badge, next to the laurel-wing icon
  /// (`RatingBadgeView.wingHeight`). The nearest text style to the old fixed point
  /// size (13pt / 22pt on tvOS) on each platform, so it now tracks Dynamic Type
  /// instead of sitting still while the rest of the badge scales around it.
  public static let ratingBadge: Font = {
#if os(tvOS)
      .system(.caption, design: .rounded, weight: .semibold)
#else
      .system(.body, design: .rounded, weight: .semibold)
#endif
  }()

  /// Large rating digits on the detail page's ratings row (`AggregateRatingLabel`) —
  /// nearest text style to the old fixed size (28pt / 44pt on tvOS), same reasoning
  /// as `ratingBadge`.
  public static let ratingAggregate: Font = {
#if os(tvOS)
      .system(.title3, design: .rounded, weight: .semibold)

#else
      .system(.largeTitle, design: .rounded, weight: .semibold)

#endif
  }()
}
