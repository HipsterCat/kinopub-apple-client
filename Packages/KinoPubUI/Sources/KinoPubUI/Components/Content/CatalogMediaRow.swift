//
//  CatalogMediaRow.swift
//  KinoPubUI
//
//  Poster + title + meta table row for Catalog / Search list layout
//  (macOS search list reference: compact poster, title, type · genre · year).
//

import SwiftUI
import KinoPubBackend

/// A full-width list row for a media title: small poster, title, secondary meta.
public struct CatalogMediaRow: View {
  public let card: MediaCard
  /// Invalidate when Appearance › Covers changes — same key `MediaCardView` reads so
  /// list rows follow the poster grid's Russian / English cover pick.
  @AppStorage(CoverArtworkPreferences.languageKey) private var coverLanguage = ""

  public init(card: MediaCard) {
    self.card = card
  }

  public init(item: MediaItem) {
    self.card = MediaCard(item)
  }

  public var body: some View {
    let _ = coverLanguage
    HStack(alignment: .center, spacing: Metrics.spacing) {
      poster
        .frame(width: Metrics.posterWidth, height: Metrics.posterHeight)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.posterCorner, style: .continuous))

      VStack(alignment: .leading, spacing: 4) {
        Text(card.title)
          .font(TypeScale.detailSection)
          .foregroundStyle(Color.Piratic.text)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        if let meta = metaLine, !meta.isEmpty {
          Text(meta)
            .font(TypeScale.cardMeta)
            .foregroundStyle(Color.Piratic.subtitle)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, Metrics.verticalPadding)
    .contentShape(Rectangle())
  }

  /// Same ladder as the poster grid (`coverURL` → kino.pub): list used to read raw
  /// `posterURL` only, so Russian covers vanished on poster→list and never recovered.
  @ViewBuilder
  private var poster: some View {
    let ladder = card.artworkLadder
    if let first = ladder.first {
      CachedRemoteImage(
        url: first,
        contentMode: .fill,
        placeholder: { Color.clear },
        failure: {
          if ladder.count > 1 {
            CachedRemoteImage(url: ladder[1], contentMode: .fill)
          } else {
            Color.clear
          }
        }
      )
    } else {
      Color.clear
    }
  }

  /// "Series · 2024 Drama" — same facts the poster caption already carries.
  private var metaLine: String? {
    var parts: [String] = []
    if card.isSeries {
      parts.append(String(localized: String.LocalizationValue("Kind_series_One")))
    }
    if let caption = card.catalogCaption() {
      parts.append(caption)
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private enum Metrics {
    static let spacing: CGFloat = 14
    static let posterWidth: CGFloat = 52
    static let posterHeight: CGFloat = 78
    static let posterCorner: CGFloat = 8
    static let verticalPadding: CGFloat = 10
  }
}

#if DEBUG
#Preview("Catalog list row") {
  VStack(spacing: 0) {
    CatalogMediaRow(card: MediaCard(
      id: 1,
      posterURL: "",
      title: "Insidious: Out of the Further",
      isSeries: false,
      year: 2026
    ))
    Divider()
    CatalogMediaRow(card: MediaCard(
      id: 2,
      posterURL: "",
      title: "The Last Airbender",
      isSeries: true,
      year: 2010
    ))
  }
  .padding(.horizontal)
  .background(Color.Piratic.background)
}
#endif
