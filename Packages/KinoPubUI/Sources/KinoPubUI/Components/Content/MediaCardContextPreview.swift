//
//  MediaCardContextPreview.swift
//  KinoPubUI
//
//  One Apple-style context-menu preview for poster / video cards: enlarged artwork,
//  underlay, loading while art arrives, and a fixed aspect per card kind. SwiftUI
//  surfaces use `MediaCardContextPreview`; tvOS UIKit menus use the matching
//  `TVMediaCardContextPreviewController`.
//

import SwiftUI

/// Artwork + aspect for a card's long-press preview. Built from what the surface paints.
public struct MediaCardContextPreviewSpec: Equatable, Sendable {
  public let url: URL?
  public let aspect: CardAspect

  public init(url: URL?, aspect: CardAspect) {
    self.url = url
    self.aspect = aspect
  }

  /// Normalized preview box — one size per aspect so every rail looks the same.
  public var preferredSize: CGSize {
    switch aspect {
    case .poster: return CGSize(width: 420, height: 630)
    case .landscape: return CGSize(width: 640, height: 360)
    case .square: return CGSize(width: 420, height: 420)
    }
  }

  public static func from(card: MediaCard, surface: MediaCardContextSurface) -> MediaCardContextPreviewSpec {
    let aspect: CardAspect
    switch surface {
    case .banner, .episodeRail:
      aspect = .landscape
    case .shelf:
      aspect = card.isLandscape ? .landscape : .poster
    }
    let raw: String
    switch surface {
    case .shelf, .episodeRail:
      if let landscape = card.landscapeImageURL, !landscape.isEmpty {
        raw = landscape
      } else {
        raw = card.coverURL
      }
    case .banner:
      if let backdrop = card.backdropURL, !backdrop.isEmpty {
        raw = backdrop
      } else {
        raw = card.coverURL
      }
    }
    return MediaCardContextPreviewSpec(url: URL(string: raw), aspect: aspect)
  }
}

/// Enlarged artwork with a dark underlay and a spinner until the image lands.
public struct MediaCardContextPreview: View {
  private let spec: MediaCardContextPreviewSpec

  public init(spec: MediaCardContextPreviewSpec) {
    self.spec = spec
  }

  public var body: some View {
    let size = spec.preferredSize
    ZStack {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.black.opacity(0.55))
      ArtworkImage(url: spec.url, size: size) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .scaledToFill()
        case .empty, .failure:
          ProgressView()
            .controlSize(.large)
            .tint(.white)
        }
      }
      .frame(width: size.width, height: size.height)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .frame(width: size.width, height: size.height)
    .onAppear {
      Artwork.prefetch([spec.url])
    }
  }
}
