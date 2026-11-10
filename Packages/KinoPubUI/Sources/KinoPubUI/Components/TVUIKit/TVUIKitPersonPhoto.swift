#if os(tvOS)
//
//  TVUIKitPersonPhoto.swift
//  KinoPubUI
//
//  What a person circle is given as its photo. Two things went wrong on device
//  (Sasha, 2026-09-28) that Search never showed, because Search people have no photo and
//  get the system's initials:
//  - Some portraits are Kinopoisk's own "no photo" card: a flat light-grey square with
//    the grey Kinopoisk mark. Drawn as a face, it is a white disc with a logo in it.
//    That is a missing photo, so it gets the monogram's initials like any other.
//  - Portraits are 2:3. `TVMonogramContentConfiguration` draws its image into a circle
//    and lifts it on focus; handed a tall image, the lifted image sat off its circle.
//    It is given a square, cut from the top of the portrait where the face is.
//

import UIKit

@MainActor
enum TVUIKitPersonPhoto {

  /// The image to hand the monogram, or nil for "no photo, draw initials".
  static func displayable(_ image: UIImage?, url: URL?) -> UIImage? {
    guard let image, let url else { return nil }
    let key = url as NSURL
    if let cached = cache.object(forKey: key) { return cached.image }
    let result = PersonArtwork.isPlaceholder(image) ? nil : squared(image)
    cache.setObject(Entry(image: result), forKey: key)
    return result
  }

  private final class Entry {
    let image: UIImage?
    init(image: UIImage?) { self.image = image }
  }

  private static let cache: NSCache<NSURL, Entry> = {
    let cache = NSCache<NSURL, Entry>()
    cache.countLimit = 300
    return cache
  }()

  /// A top-anchored square. Head-and-shoulders portraits keep the face in the upper
  /// part of the frame, so the cut starts a quarter of the way into the spare height.
  private static func squared(_ image: UIImage) -> UIImage {
    let size = image.size
    guard size.width > 0, size.height > 0, abs(size.width - size.height) > 1 else { return image }
    let side = min(size.width, size.height)
    let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 4)
    // Four bytes a pixel whatever the photo: a black-and-white one can come back grey from
    // the system renderer, narrower than the focus effect reads (`TVUIKitTileArtwork.render`).
    return TVUIKitTileArtwork.render(size: CGSize(width: side, height: side), scale: image.scale) { _ in
      image.draw(at: CGPoint(x: -origin.x, y: -origin.y))
    }
  }
}
#endif
