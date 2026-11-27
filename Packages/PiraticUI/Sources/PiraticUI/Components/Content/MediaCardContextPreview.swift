//
//  MediaCardContextPreview.swift
//  PiraticUI
//
//  Apple TV–style sneak peek for poster / video long-press: native art aspect
//  (poster 2:3, wide 16:9), plate hugs the loaded bitmap (no letterbox gutters),
//  and a metadata footer with the title, subtitle and playback time.
//  SwiftUI surfaces use `MediaCardContextPreview`; tvOS UIKit menus use
//  `TVMediaCardContextPreviewController`.
//

import SwiftUI
import PiraticMedia
import PiraticMetadata
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Artwork + metadata for a card's long-press sneak peek.
public struct MediaCardContextPreviewSpec: Equatable, Sendable {
  public let artworkURLs: [URL]
  public var url: URL? { artworkURLs.first }
  public let aspect: CardAspect
  public let title: String
  /// Secondary line under the title — `2026 · Drama`, `В закладках`, `1h 55m`, …
  public let subtitle: String?
  public let time: String?

  public init(url: URL?, aspect: CardAspect, title: String, subtitle: String? = nil) {
    self.init(artworkURLs: [url].compactMap { $0 }, aspect: aspect, title: title,
              subtitle: subtitle, time: nil)
  }

  private init(artworkURLs: [URL], aspect: CardAspect, title: String, subtitle: String?, time: String?) {
    self.artworkURLs = artworkURLs
    self.aspect = aspect
    self.title = title
    self.time = time
    self.subtitle = subtitle.flatMap { line in
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
  }

  /// Max art box while loading / before we know the bitmap's ratio.
  public var artSize: CGSize {
    switch aspect {
    case .poster: return CGSize(width: 280, height: 420)
    case .landscape: return CGSize(width: 340, height: 191)
    case .square: return CGSize(width: 280, height: 280)
    }
  }

  /// Full peek including the metadata footer (preferredContentSize for UIKit).
  public var preferredSize: CGSize {
    preferredSize(art: artSize)
  }

  public func preferredSize(art: CGSize) -> CGSize {
    CGSize(width: art.width, height: art.height + footerHeight)
  }

  var footerHeight: CGFloat {
    // SwiftUI can grow beyond this minimum when a caption wraps.
    52 + (subtitle == nil ? 0 : 18) + (time == nil ? 0 : 18)
  }

  /// Shrink the max box so it matches the bitmap's aspect — no letterbox gutters.
  public func artDisplaySize(forImageSize imageSize: CGSize) -> CGSize {
    let maxBox = artSize
    guard imageSize.width > 1, imageSize.height > 1 else { return maxBox }
    let scale = min(maxBox.width / imageSize.width, maxBox.height / imageSize.height)
    let width = max(1, (imageSize.width * scale).rounded(.toNearestOrAwayFromZero))
    let height = max(1, (imageSize.height * scale).rounded(.toNearestOrAwayFromZero))
    return CGSize(width: width, height: height)
  }

  public static func from(card: MediaCard,
                          surface: MediaCardContextSurface,
                          images: TitleImageRoute = TitleImageRoute(baseURL: nil),
                          scale: CGFloat = 2) -> MediaCardContextPreviewSpec {
    let aspect: CardAspect
    switch surface {
    case .banner, .episodeRail:
      aspect = .landscape
    case .shelf:
      aspect = card.isLandscape ? .landscape : .poster
    }

    return MediaCardContextPreviewSpec(
      artworkURLs: card.sneakPeekArtwork(surface: surface, images: images, scale: scale),
      aspect: aspect,
      title: card.title,
      subtitle: card.sneakPeekSubtitle(surface: surface),
      time: surface == .episodeRail || (surface == .shelf && card.isLandscape)
        ? card.peekTime(language: .current) : nil
    )
  }
}

public extension MediaCard {
  /// Artwork URL for the long-press peek — same language ladder as the cell for
  /// posters (`coverURL`), and the same still as macOS hover for series/episodes.
  func sneakPeekArtworkURL(surface: MediaCardContextSurface,
                           images: TitleImageRoute = TitleImageRoute(baseURL: nil),
                           scale: CGFloat = 2) -> URL? {
    sneakPeekArtwork(surface: surface, images: images, scale: scale).first
  }

  fileprivate func sneakPeekArtwork(surface: MediaCardContextSurface,
                                    images: TitleImageRoute, scale: CGFloat) -> [URL] {
    switch surface {
    case .shelf where isLandscape && isSeries && video != nil:
      guard let still = pointerArtwork(images: images, points: 340, scale: scale)
      else { return artworkLadder }
      let urls = [still.primary, still.fallback].compactMap { $0 }
      return urls + artworkLadder.filter { !urls.contains($0) }
    case .shelf, .episodeRail:
      return artworkLadder
    case .banner:
      let urls = [backdropURL, landscapeArtworkURL].compactMap { raw -> URL? in
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
      }
      return urls + coverLadder
    }
  }

  /// Secondary line for the context-menu sneak peek — more than the cell caption.
  func sneakPeekSubtitle(surface: MediaCardContextSurface,
                         language: MediaLanguage = .current) -> String? {
    switch surface {
    case .episodeRail:
      return episodePeekReference(language: language)
    case .banner:
      return catalogPeekSubtitle(language: language)
    case .shelf:
      if isLandscape {
        let reference = episodePeekReference(language: language).map { reference in
          let caption = nonEmpty(overlayLabel)
          // A bookmark-only caption may still have an episode resolved for Play.
          // Older snapshots stored the translated caption without the reason.
          return caption == continuePeekHint || caption == "Bookmarked" || caption == "В закладках"
            ? reference : (caption ?? reference)
        }
        return reference ?? nonEmpty(overlayLabel) ?? nonEmpty(continuePeekHint)
          ?? nonEmpty(offeredName) ?? catalogPeekSubtitle(language: language, includesDuration: false)
      }
      return catalogPeekSubtitle(language: language)
    }
  }

  /// Poster / search / library style: `year · genre`, else duration, else one of them.
  private func catalogPeekSubtitle(language: MediaLanguage, includesDuration: Bool = true) -> String? {
    let year = yearLabel
    let genre = usefulGenre(language: language) ?? primaryGenre(language: language)
    let duration = includesDuration
      ? durationSeconds.flatMap { $0 >= 60 ? RuntimeText(seconds: $0).formatted(.short, language: language) : nil }
      : nil
    switch (year, genre) {
    case let (year?, genre?):
      return "\(year) · \(genre)"
    case let (nil, genre?):
      if let duration, !isSeries { return duration }
      return genre
    case let (year?, nil):
      if let duration, !isSeries { return "\(year) · \(duration)" }
      return year
    case (nil, nil):
      return duration
    }
  }

  private func episodePeekReference(language: MediaLanguage) -> String? {
    guard isSeries, let video else { return nil }
    return EpisodeText(season: season, number: video, seasonCount: seasonCount)
      .text(for: .continueWatchingCard, language: language)
  }

  private func nonEmpty(_ text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else { return nil }
    return trimmed
  }

  fileprivate func peekTime(language: MediaLanguage) -> String? {
    guard let durationSeconds, durationSeconds >= 60,
          let total = RuntimeText(seconds: durationSeconds).text(for: .timeBadge, language: language)
    else { return nil }
    guard !isWatched, let progress, progress.isFinite, progress > 0 else { return total }
    let remaining = RemainingText(progress: progress, durationSeconds: durationSeconds)
      .formatted(MediaSurface.timeBadge.runtimeLength, language: language)
    return "\(remaining) / \(total)"
  }
}

/// Sneak peek card: plate hugs the loaded art's aspect + title / secondary footer.
public struct MediaCardContextPreview: View {
  private let spec: MediaCardContextPreviewSpec
  @State private var image: Image?
  @State private var artFrame: CGSize
  @State private var loadFailed = false

  public init(spec: MediaCardContextPreviewSpec) {
    self.spec = spec
    _artFrame = State(initialValue: spec.artSize)
  }

  public var body: some View {
    VStack(spacing: 0) {
      ZStack {
        if let image {
          image
            .resizable()
            .scaledToFill()
            .frame(width: artFrame.width, height: artFrame.height)
            .clipped()
        } else if !loadFailed {
          ProgressView()
            .controlSize(.regular)
            .frame(width: artFrame.width, height: artFrame.height)
            .background(Color.primary.opacity(0.08))
        } else {
          Color.primary.opacity(0.08)
            .frame(width: artFrame.width, height: artFrame.height)
        }
      }
      .frame(width: artFrame.width, height: artFrame.height)

      VStack(alignment: .leading, spacing: 2) {
        Text(spec.title)
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        if let subtitle = spec.subtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }
        if let time = spec.time {
          Text(time)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .frame(width: artFrame.width, alignment: .leading)
      .frame(minHeight: spec.footerHeight)
      // Peek footer rides the system surface (Apple TV: white / dark plate under art).
      .background(footerBackground)
    }
    .frame(width: artFrame.width)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
#if os(iOS) || os(macOS)
    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
#endif
    .task(id: spec.artworkURLs) {
      await loadArt()
    }
  }

  @MainActor
  private func loadArt() async {
    image = nil
    loadFailed = false
    artFrame = spec.artSize
    let loaded = await spec.loadImage()
    guard !Task.isCancelled else { return }
    if let loaded {
      artFrame = spec.artDisplaySize(forImageSize: loaded.size)
      image = Image(platformImage: loaded)
    } else {
      loadFailed = true
    }
  }

  private var footerBackground: Color {
#if os(macOS)
    Color(nsColor: .windowBackgroundColor)
#elseif os(tvOS)
    // tvOS has no systemBackground; `Color.Piratic.background` is clear (page fill).
    Color.Piratic.glassSubstitute
#else
    Color(uiColor: .systemBackground)
#endif
  }
}

#if DEBUG
#Preview("Sneak peek portrait") {
  MediaCardContextPreview(
    spec: .from(
      card: MediaCard(
        id: 9944,
        posterURL: "https://m.staticpop.net/poster/item/big/9944.jpg",
        title: "Иностранная интрига",
        year: 2024,
        genres: [Genre(id: "thriller", domain: .video,
                       name: LocalizedName(en: "Thriller", ru: "Триллер"))]
      ),
      surface: .shelf
    )
  )
  .padding(40)
  .background(Color.gray.opacity(0.35))
}

#Preview("Sneak peek landscape") {
  MediaCardContextPreview(
    spec: .from(
      card: MediaCard(
        // wide/15042.jpg 404s; MediaCardView episode fixture uses 10524.
        id: 10524,
        posterURL: "https://m.staticpop.net/poster/item/big/10524.jpg",
        title: "Название эпизода",
        progress: 0.25,
        landscapeImageURL: "https://m.staticpop.net/poster/item/wide/10524.jpg",
        overlayLabel: "S2, E5: Pilot",
        video: 5,
        season: 2,
        isSeries: true,
        durationSeconds: 42 * 60,
        genres: [Genre(id: "drama", domain: .video,
                       name: LocalizedName(en: "Drama", ru: "Драма"))]
      ),
      surface: .shelf
    )
  )
  .padding(40)
  .background(Color.gray.opacity(0.35))
}
#endif
