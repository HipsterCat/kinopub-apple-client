//
//  TVUIKitTileArtworkTests.swift
//  KinoPubAppleClientTests
//
//  Drawn tiles go straight into the system's focus effect (`TVPosterView`, image views
//  with `adjustsImageWhenAncestorFocused`), which reads an image as 32-bit ARGB. On
//  2026-10-02 the app died on the CI tvOS simulator with EXC_BAD_ACCESS in
//  `vImageConvert_ARGB8888toPlanar8`, under `TVPosterView(image:)`, handed the grey
//  placeholder by the poster-size probe in `TVPageCellMetrics`.
//

#if os(tvOS)
import KinoPubUI
import TVUIKit
import UIKit
import XCTest

@MainActor
final class TVUIKitTileArtworkTests: XCTestCase {

  private let appearances = [UITraitCollection(userInterfaceStyle: .light),
                             UITraitCollection(userInterfaceStyle: .dark)]

  /// The probe's sizes and the tile sizes, on both appearances: the placeholder is black
  /// or white at a twelfth, the monogram a grey disc — content with no colour in it.
  func testArtworkIsFourBytesAPixel() throws {
    var images: [(String, UIImage)] = [
      ("flat tile", TVUIKitTileArtwork.wide(tint: .systemBlue, symbol: "film")),
      ("gradient tile", TVUIKitTileArtwork.wide(tint: TVUIKitTileArtwork.tint(for: "Drama"),
                                                symbol: "drop", style: .gradient))
    ]
    for traits in appearances {
      let style = traits.userInterfaceStyle == .dark ? "dark" : "light"
      images += [
        ("\(style) placeholder", TVUIKitTileArtwork.placeholder(size: CGSize(width: 289, height: 433), traits: traits)),
        ("\(style) rounded placeholder", TVUIKitTileArtwork.placeholder(size: CGSize(width: 333, height: 333),
                                                                          cornerRadius: 12, traits: traits)),
        ("\(style) monogram", TVUIKitTileArtwork.monogram(name: "Анна Петрова", diameter: 200, traits: traits))
      ]
    }
    for (name, image) in images {
      let cgImage = try XCTUnwrap(image.cgImage, name)
      XCTAssertEqual(cgImage.bitsPerPixel, 32,
                     "\(name): \(cgImage.bitsPerPixel) bits a pixel, \(cgImage.bitsPerComponent) a component, "
                       + "bitmap info \(cgImage.bitmapInfo.rawValue), \(String(describing: cgImage.colorSpace?.name))")
      XCTAssertGreaterThanOrEqual(cgImage.bytesPerRow, cgImage.width * 4, name)
    }
  }

  /// A TV channel's 4:3 card on the 16:9 still: the picture whole and full height, its
  /// outermost columns carried to the edges (a gradient plate stays one plate), drawn
  /// four bytes a pixel like every other tile.
  func testLetterboxedLogoKeepsThePictureAndExtendsItsEdges() throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let logo = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 180), format: format).image { renderer in
      let context = renderer.cgContext
      context.setFillColor(UIColor.red.cgColor)
      context.fill(CGRect(x: 0, y: 0, width: 1, height: 180))
      context.setFillColor(UIColor.blue.cgColor)
      context.fill(CGRect(x: 239, y: 0, width: 1, height: 180))
      context.setFillColor(UIColor.white.cgColor)
      context.fill(CGRect(x: 1, y: 0, width: 238, height: 180))
    }
    let tile = TVUIKitTileArtwork.letterboxed(logo, aspectRatio: 16 / 9)
    XCTAssertEqual(tile.size.width, 320)
    XCTAssertEqual(tile.size.height, 180)
    let cgImage = try XCTUnwrap(tile.cgImage)
    XCTAssertEqual(cgImage.bitsPerPixel, 32)
    XCTAssertEqual(try pixel(cgImage, x: 5, y: 90), [255, 0, 0], "left edge is the logo's first column")
    XCTAssertEqual(try pixel(cgImage, x: 314, y: 90), [0, 0, 255], "right edge is the logo's last column")
    XCTAssertEqual(try pixel(cgImage, x: 160, y: 90), [255, 255, 255], "the logo itself, uncropped, centred")

    // Already wider than the tile: bars above and below instead, still no crop.
    let wide = TVUIKitTileArtwork.letterboxed(TVUIKitTileArtwork.wide(tint: .systemBlue, symbol: nil),
                                              aspectRatio: 1)
    XCTAssertEqual(wide.size.width, wide.size.height)
  }

  /// RGB of one pixel of a premultiplied BGRA bitmap.
  private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
    let data = try XCTUnwrap(image.dataProvider?.data as Data?)
    let offset = y * image.bytesPerRow + x * 4
    return [data[offset + 2], data[offset + 1], data[offset]]
  }

  /// The crash path itself: a poster view built around the placeholder, sized and laid
  /// out the way `TVPageCellMetrics.measurePoster` does it.
  func testPosterViewTakesThePlaceholder() {
    for traits in appearances {
      for size in [CGSize(width: 289, height: 433), CGSize(width: 333, height: 333), CGSize(width: 640, height: 360)] {
        let poster = TVPosterView(image: TVUIKitTileArtwork.placeholder(size: size, traits: traits))
        poster.contentSize = size
        poster.title = "Ag"
        poster.frame = CGRect(origin: .zero, size: poster.intrinsicContentSize)
        poster.layoutIfNeeded()
        XCTAssertGreaterThan(poster.contentView.frame.width, 1, "\(size)")
      }
    }
  }
}
#endif
