#if os(tvOS)
//
//  TVUIKitTileArtwork.swift
//  KinoPubUI
//
//  Solid-tint + SF Symbol artwork for tiles that have no photograph behind them:
//  genre / category rails, and the panel a media-item cell shows while its still
//  is in flight. `TVMediaItemContentConfiguration` only takes a `UIImage`, so a
//  "coloured placeholder" has to be a real drawn image rather than a background view.
//

import UIKit

public enum TVUIKitTileArtwork {
  /// 16:9, the shape `TVMediaItemContentConfiguration.wideCell()` renders.
  public static let wideSize = CGSize(width: 640, height: 360)

  /// Tile colours. Deliberately the system palette — these read as tinted artwork on a
  /// TV rather than as brand colour, and they are what the TVUIKit gallery shows.
  nonisolated(unsafe) public static let palette: [UIColor] = [
    .systemRed, .systemOrange, .systemYellow, .systemGreen,
    .systemTeal, .systemBlue, .systemIndigo, .systemPurple, .systemPink
  ]

  /// Same name → same colour, across launches. `String.hashValue` is seeded per
  /// process, so a genre would change colour every cold start if we used it.
  public static func tint(for name: String) -> UIColor {
    palette[Int(stableHash(name) % UInt64(palette.count))]
  }

  /// How the tint is laid down.
  public enum Style: Hashable, Sendable {
    /// One flat fill, glyph centred.
    case flat
    /// A diagonal wash from a lighter tint (top-leading) to a deeper one
    /// (bottom-trailing), glyph toward the trailing edge — genre and category tiles.
    case gradient
  }

  public static func wide(tint: UIColor, symbol: String?, style: Style = .flat) -> UIImage {
    image(tint: tint, symbol: symbol, size: wideSize, style: style)
  }

  /// A flat tint with a centred glyph, cached per (tint, symbol, size, corners,
  /// appearance) — a rail re-drawing this on every cell reuse is a renderer pass per
  /// scroll tick.
  ///
  /// `traits` resolves a dynamic tint: a `.quaternaryLabel` drawn into a bitmap keeps
  /// whatever appearance was current at draw time, which from a layout probe is light —
  /// near-white panels on a dark page. `cornerRadius` bakes the rounding in for a host
  /// that rounds real art but not this one (`TVPosterView`).
  public static func image(tint: UIColor,
                           symbol: String?,
                           size: CGSize,
                           cornerRadius: CGFloat = 0,
                           fillAlpha: CGFloat = 0.85,
                           style: Style = .flat,
                           traits: UITraitCollection? = nil) -> UIImage {
    let traits = traits ?? .current
    let resolved = tint.resolvedColor(with: traits)
    let key = "\(resolved.hashValue)-\(symbol ?? "-")-\(Int(size.width))x\(Int(size.height))-r\(Int(cornerRadius))-a\(fillAlpha)-\(style)-\(traits.userInterfaceStyle.rawValue)" as NSString
    if let cached = cache.object(forKey: key) { return cached }

    let bounds = CGRect(origin: .zero, size: size)
    let drawn = render(size: size) { context in
      if cornerRadius > 0 {
        UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).addClip()
      }
      switch style {
      case .flat:
        context.setFillColor(resolved.withAlphaComponent(fillAlpha).cgColor)
        context.fill(bounds)
      case .gradient:
        let colors = [shade(resolved, brightness: 1.25), shade(resolved, brightness: 0.55)]
          .map { $0.withAlphaComponent(fillAlpha).cgColor } as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
          context.drawLinearGradient(gradient, start: .zero,
                                     end: CGPoint(x: size.width, y: size.height), options: [])
        }
      }
      guard let symbol else { return }
      let config = UIImage.SymbolConfiguration(
        pointSize: min(size.width, size.height) * (style == .gradient ? 0.42 : 0.32),
        weight: .semibold
      )
      guard let glyph = UIImage(systemName: symbol, withConfiguration: config)?
          .withTintColor(UIColor.label.resolvedColor(with: traits).withAlphaComponent(0.9), renderingMode: .alwaysOriginal)
      else { return }
      let x = style == .gradient
        ? size.width - glyph.size.width - size.height * 0.14
        : (size.width - glyph.size.width) / 2
      glyph.draw(at: CGPoint(x: x, y: (size.height - glyph.size.height) / 2))
    }
    cache.setObject(drawn, forKey: key)
    return drawn
  }

  /// Neutral panel for a still that has not arrived (or does not exist) — same shape as
  /// the artwork it stands in for, so the cell never resizes when the image lands.
  ///
  /// A twelfth of the label colour: a quiet panel on either appearance. tvOS's label
  /// hierarchy in dark mode is *bright* all the way down — `.quaternaryLabel` resolves
  /// to (220, 220, 220) there — so a label-tier colour at its own alpha reads as a
  /// white card on a dark page, not as an empty slot.
  /// A person with no photo: initials on a solid disc, as a plain image — not the
  /// system monogram lockup (that paints a white plate and lifts itself). Label-tier
  /// fills wash out on tvOS (secondaryLabel on white@0.16, or light gray on glass).
  /// Solid mid/dark discs with high-contrast ink stay readable on light and dark,
  /// matching the search person cards.
  public static func monogram(name: String, diameter: CGFloat, traits: UITraitCollection? = nil) -> UIImage {
    let traits = traits ?? .current
    let formatter = PersonNameComponentsFormatter()
    formatter.style = .abbreviated
    var initials = ""
    if let components = formatter.personNameComponents(from: name) {
      initials = formatter.string(from: components)
    }
    if initials.isEmpty || initials.count > 3 {
      initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
    let size = CGSize(width: diameter, height: diameter)
    let dark = traits.userInterfaceStyle == .dark
    // Solid fills, not label@alpha. Dark page: charcoal disc + white letters.
    // Light page: medium gray disc + near-black letters. No white plate.
    let fill = (dark ? UIColor(white: 0.22, alpha: 1) : UIColor(white: 0.62, alpha: 1))
      .resolvedColor(with: traits)
    let ink = (dark ? UIColor(white: 1.0, alpha: 1) : UIColor(white: 0.08, alpha: 1))
      .resolvedColor(with: traits)
    let font = UIFont.systemFont(ofSize: diameter * 0.36, weight: .semibold)
    let key = "mono-v2-\(initials)-\(Int(diameter))-\(dark ? "d" : "l")" as NSString
    if let cached = cache.object(forKey: key) { return cached }
    let drawn = render(size: size) { _ in
      fill.setFill()
      UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
      let text = initials.uppercased() as NSString
      let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
      let box = text.size(withAttributes: attributes)
      text.draw(at: CGPoint(x: (size.width - box.width) / 2, y: (size.height - box.height) / 2),
                withAttributes: attributes)
    }
    cache.setObject(drawn, forKey: key)
    return drawn
  }

  public static func placeholder(size: CGSize = wideSize,
                                 cornerRadius: CGFloat = 0,
                                 traits: UITraitCollection? = nil) -> UIImage {
    image(tint: .label, symbol: nil, size: size, cornerRadius: cornerRadius, fillAlpha: 0.12, traits: traits)
  }

  /// Draws `size` points into a 32-bit BGRA, premultiplied sRGB bitmap at the screen's
  /// scale, origin top-left as in UIKit, and returns it as an image.
  ///
  /// Not `UIGraphicsImageRenderer`: it picks the bitmap format from what is drawn, and
  /// content with no colour in it — the placeholder, the monogram — came back as grey
  /// with alpha, two bytes a pixel (measured on the CI tvOS 27.2 simulator,
  /// 2026-10-02). The focus effect `TVPosterView` and `adjustsImageWhenAncestorFocused`
  /// put on an image reads it as ARGB8888 regardless and ran off the end of the
  /// placeholder: EXC_BAD_ACCESS in `vImageConvert_ARGB8888toPlanar8` under
  /// `TVPosterView(image:)`, from the poster probe in `TVPageCellMetrics`.
  /// `TVUIKitTileArtworkTests` checks the format.
  static func render(size: CGSize, scale: CGFloat? = nil, _ draw: (CGContext) -> Void) -> UIImage {
    let scale = scale ?? UIGraphicsImageRendererFormat.preferred().scale
    let width = max(Int((size.width * scale).rounded(.up)), 1)
    let height = max(Int((size.height * scale).rounded(.up)), 1)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return UIImage() }
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: scale, y: -scale)
    UIGraphicsPushContext(context)
    draw(context)
    UIGraphicsPopContext()
    guard let image = context.makeImage() else { return UIImage() }
    return UIImage(cgImage: image, scale: scale, orientation: .up)
  }

  /// `NSCache` is documented thread-safe, so the artwork helper does not need to be
  /// main-actor bound — `TVUIKitMediaItem` builds tinted tiles off the actor.
  nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

  /// The same hue at a scaled brightness, for the two ends of a gradient tile.
  private static func shade(_ color: UIColor, brightness factor: CGFloat) -> UIColor {
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
    guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return color }
    return UIColor(hue: hue, saturation: saturation, brightness: min(brightness * factor, 1), alpha: alpha)
  }

  /// FNV-1a over UTF-8 — stable across processes and platforms.
  private static func stableHash(_ value: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x100_0000_01b3
    }
    return hash
  }
}
#endif
