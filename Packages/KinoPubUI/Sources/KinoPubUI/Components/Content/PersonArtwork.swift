//
//  PersonArtwork.swift
//  KinoPubUI
//
//  Shared person-photo helpers. Kinopoisk (and some CDNs) answer a real image for a
//  missing portrait: a flat pale card with their mark. Drawn as a face it is a white
//  disc with a logo — that is a missing photo, so initials win instead.
//

import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum PersonArtwork {

  /// True when almost every pixel is light and colourless — Kinopoisk's "no photo"
  /// card. Checked on a 16×16 thumbnail so it costs one tiny draw per URL. A real
  /// portrait has skin, hair and shadow — nowhere near nine tenths pale grey.
  public static func isPlaceholder(_ image: CGImage) -> Bool {
    let side = 16
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    guard let context = CGContext(data: &pixels, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return false }
    context.interpolationQuality = .low
    context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

    var pale = 0
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
      let chroma = max(r, g, b) - min(r, g, b)
      if chroma < 18 && min(r, g, b) > 150 { pale += 1 }
    }
    return Double(pale) / Double(side * side) > 0.9
  }

#if canImport(UIKit)
  public static func isPlaceholder(_ image: UIImage) -> Bool {
    guard let cgImage = image.cgImage else { return false }
    return isPlaceholder(cgImage)
  }
#elseif canImport(AppKit)
  public static func isPlaceholder(_ image: NSImage) -> Bool {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return false
    }
    return isPlaceholder(cgImage)
  }
#endif
}
