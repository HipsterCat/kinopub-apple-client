//
//  MediaCard+PointerArtwork.swift
//  KinoPubUI
//
//  One rule for the picture a landscape card brings up under the pointer and in
//  the long-press sneak peek (Sasha, 2026-11-24 / 2026-11-26): episode → worker
//  still (same as the season rail); film → title backdrop; kino.pub's own frame
//  is the fallback.
//

import Foundation
import KinoPubMetadata

public extension MediaCard {
  /// Still the pointer / sneak peek should show for a landscape title card.
  /// `nil` when there is nothing better than the tile's own wide cover.
  func pointerArtwork(images: TitleImageRoute,
                      points: CGFloat,
                      scale: CGFloat) -> (primary: URL, fallback: URL?)? {
    let kinopub = hoverStillURL.flatMap { $0.isEmpty ? nil : URL(string: $0) }
    if images.isConfigured, itemID > 0 {
      if isSeries, let season, let episode = video,
         let still = images.episodeStill(
           kinopubID: itemID,
           imdb: imdbID,
           season: season,
           episode: episode,
           pixelWidth: TitleImageRoute.episodeStillPixelWidth(
             points: Double(points),
             scale: Double(scale)
           ),
           kinopubThumb: hoverStillURL
         ) {
        return (still, kinopub)
      }
      if !isSeries, offeredName == nil,
         let backdrop = images.backdrop(
           kinopubID: itemID,
           imdb: imdbID,
           width: Int((points * scale).rounded(.up))
         ) {
        return (backdrop, kinopub)
      }
    }
    if let kinopub { return (kinopub, nil) }
    return nil
  }
}
