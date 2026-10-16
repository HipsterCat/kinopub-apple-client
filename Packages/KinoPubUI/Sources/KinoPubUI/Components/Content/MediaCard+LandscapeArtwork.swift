//
//  MediaCard+LandscapeArtwork.swift
//  KinoPubUI
//
//  One rule for what goes in a 16:9 card that stands for a title: its wide cover.
//
//  `Posters.wideURL` *derives* that path by swapping `/item/big/` for `/item/wide/` when
//  the payload sends no `wide`; where kino.pub has none the URL 404s and the card shows
//  its placeholder. Measured 2026-10-16 on a live Continue Watching row: 24 of 24 titles
//  answered 200 (15 sent `wide`, 9 derived).
//
//  The card box itself never varies: `CardAspect.landscape` is 16:9 and the image is
//  drawn `.fill` inside it. What varies is whether the source was shaped for that box.
//

import Foundation
import KinoPubBackend

public extension MediaCard {

  /// The title's own 16:9 artwork — every landscape card that stands for a title: Home's
  /// Continue Watching, Library Continue, History. An episode's thumbnail is a random
  /// frame, often black, and not a picture of the show (Sasha, 2026-10-10 and 2026-10-16).
  static func titleWideArtwork(posters: Posters?) -> String? {
    posters?.wideURL.flatMap { $0.isEmpty ? nil : $0 }
  }
}
