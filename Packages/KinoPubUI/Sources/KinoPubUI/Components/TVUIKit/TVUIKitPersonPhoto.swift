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
    let result = isPlaceholder(image) ? nil : squared(image)
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
    let format = UIGraphicsImageRendererFormat.preferred()
    format.scale = image.scale
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
      image.draw(at: CGPoint(x: -origin.x, y: -origin.y))
    }
  }

  /// Almost every pixel light and colourless: the Kinopoisk card. Checked on a 16×16
  /// thumbnail, so it costs one tiny draw per URL. A real portrait has skin, hair and
  /// shadow — nowhere near nine tenths pale grey.
  private static func isPlaceholder(_ image: UIImage) -> Bool {
    let side = 16
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    guard let cgImage = image.cgImage,
          let context = CGContext(data: &pixels, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return false }
    context.interpolationQuality = .low
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

    var pale = 0
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
      let chroma = max(r, g, b) - min(r, g, b)
      if chroma < 18 && min(r, g, b) > 150 { pale += 1 }
    }
    return Double(pale) / Double(side * side) > 0.9
  }
}
#endif
