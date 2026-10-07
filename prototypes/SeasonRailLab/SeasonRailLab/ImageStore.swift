import UIKit

/// One decoded cache, thumbnails sized to the card. The placeholder is a
/// gradient of the backdrop's average color with an SF Symbol, drawn once
/// and shared by every cell that does not have a still yet.
enum ImageStore {
  private static let cache = NSCache<NSURL, UIImage>()
  private static let context = CIContext(options: [.cacheIntermediates: false])

  static func cached(_ url: URL) -> UIImage? {
    cache.object(forKey: url as NSURL)
  }

  static func load(_ url: URL, pointSize: CGSize, scale: CGFloat) async -> UIImage? {
    if let hit = cached(url) { return hit }
    do {
      let (data, response) = try await URLSession.shared.data(from: url)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        return nil
      }
      guard let image = downsample(data, to: pointSize, scale: max(scale, 1)) else { return nil }
      cache.setObject(image, forKey: url as NSURL)
      return image
    } catch {
      return nil
    }
  }

  static func averageColor(of image: UIImage) -> UIColor? {
    guard let ci = CIImage(image: image) else { return nil }
    let extent = ci.extent
    guard extent.width > 1, extent.height > 1 else { return nil }
    guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
      kCIInputImageKey: ci,
      kCIInputExtentKey: CIVector(cgRect: extent),
    ]), let output = filter.outputImage else { return nil }
    var bitmap = [UInt8](repeating: 0, count: 4)
    context.render(
      output,
      toBitmap: &bitmap,
      rowBytes: 4,
      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      format: .RGBA8,
      colorSpace: CGColorSpaceCreateDeviceRGB()
    )
    return UIColor(
      red: CGFloat(bitmap[0]) / 255,
      green: CGFloat(bitmap[1]) / 255,
      blue: CGFloat(bitmap[2]) / 255,
      alpha: 1
    )
  }

  /// Solid-enough gradient that a template symbol reads on it. The top stop
  /// is the sampled color pulled toward black; the bottom stop is further
  /// down, so a bright poster still leaves a field under the glyph.
  static func placeholder(color: UIColor, size: CGSize, scale: CGFloat) -> UIImage {
    let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    let top = resolved.mixed(with: .black, amount: 0.28)
    let bottom = resolved.mixed(with: .black, amount: 0.62)
    let format = UIGraphicsImageRendererFormat()
    format.scale = max(scale, 1)
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { context in
      let colors = [top.cgColor, bottom.cgColor] as CFArray
      let space = CGColorSpaceCreateDeviceRGB()
      guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
      context.cgContext.drawLinearGradient(
        gradient,
        start: .zero,
        end: CGPoint(x: 0, y: size.height),
        options: []
      )
      let symbolConfig = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
      let symbol = UIImage(systemName: "photo", withConfiguration: symbolConfig)?
        .withTintColor(.white, renderingMode: .alwaysOriginal)
      guard let symbol else { return }
      let symbolSize = symbol.size
      symbol.draw(in: CGRect(
        x: (size.width - symbolSize.width) / 2,
        y: (size.height - symbolSize.height) / 2,
        width: symbolSize.width,
        height: symbolSize.height
      ))
    }
  }

  private static func downsample(_ data: Data, to pointSize: CGSize, scale: CGFloat) -> UIImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
    let maxDimension = max(pointSize.width, pointSize.height) * scale
    let options = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxDimension,
    ] as [CFString: Any] as CFDictionary
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
    return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
  }
}

extension UIColor {
  func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
    let traits = UITraitCollection(userInterfaceStyle: .dark)
    let from = resolvedColor(with: traits)
    let to = other.resolvedColor(with: traits)
    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
    var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
    guard from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
          to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return self }
    return UIColor(
      red: r1 + (r2 - r1) * amount,
      green: g1 + (g2 - g1) * amount,
      blue: b1 + (b2 - b1) * amount,
      alpha: 1
    )
  }
}

enum RailMetrics {
  /// A 16:9 still, wide enough to read as a landscape cover. The description
  /// sits under it and is not part of the image's frame.
  static let imageWidth: CGFloat = 480
  static let imageHeight: CGFloat = 270
  /// Half the focused growth of a 480pt control lands in the gutter.
  static let gutter: CGFloat = 64

  static func cellHeight(traits: UITraitCollection) -> CGFloat {
    let title = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traits).lineHeight
    let body = UIFont.preferredFont(forTextStyle: .callout, compatibleWith: traits).lineHeight
    return imageHeight + 18 + title + 10 + body * 5 + 12
  }
}
