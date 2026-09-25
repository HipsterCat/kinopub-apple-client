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

  public static func wide(tint: UIColor, symbol: String?) -> UIImage {
    image(tint: tint, symbol: symbol, size: wideSize)
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
                           traits: UITraitCollection? = nil) -> UIImage {
    let traits = traits ?? .current
    let resolved = tint.resolvedColor(with: traits)
    let key = "\(resolved.hashValue)-\(symbol ?? "-")-\(Int(size.width))x\(Int(size.height))-r\(Int(cornerRadius))-a\(fillAlpha)-\(traits.userInterfaceStyle.rawValue)" as NSString
    if let cached = cache.object(forKey: key) { return cached }

    let renderer = UIGraphicsImageRenderer(size: size)
    let drawn = renderer.image { context in
      resolved.withAlphaComponent(fillAlpha).setFill()
      if cornerRadius > 0 {
        UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius).fill()
      } else {
        context.fill(CGRect(origin: .zero, size: size))
      }
      guard let symbol else { return }
      let config = UIImage.SymbolConfiguration(
        pointSize: min(size.width, size.height) * 0.32,
        weight: .semibold
      )
      guard let glyph = UIImage(systemName: symbol, withConfiguration: config)?
          .withTintColor(.label.withAlphaComponent(0.9), renderingMode: .alwaysOriginal)
      else { return }
      glyph.draw(at: CGPoint(x: (size.width - glyph.size.width) / 2,
                             y: (size.height - glyph.size.height) / 2))
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
  /// A person with no photo: initials on a quiet disc, the look of the system
  /// monogram, as a plain image. The monogram *view* is a focusable lockup of its own
  /// and lifts itself, layer by layer, inside a focused card — this does nothing.
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
    let fill = UIColor.label.withAlphaComponent(0.16).resolvedColor(with: traits)
    let ink = UIColor.secondaryLabel.resolvedColor(with: traits)
    let font = UIFont.systemFont(ofSize: diameter * 0.36, weight: .medium)
    return UIGraphicsImageRenderer(size: size).image { _ in
      fill.setFill()
      UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
      let text = initials.uppercased() as NSString
      let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
      let box = text.size(withAttributes: attributes)
      text.draw(at: CGPoint(x: (size.width - box.width) / 2, y: (size.height - box.height) / 2),
                withAttributes: attributes)
    }
  }

  public static func placeholder(size: CGSize = wideSize,
                                 cornerRadius: CGFloat = 0,
                                 traits: UITraitCollection? = nil) -> UIImage {
    image(tint: .label, symbol: nil, size: size, cornerRadius: cornerRadius, fillAlpha: 0.12, traits: traits)
  }

  /// `NSCache` is documented thread-safe, so the artwork helper does not need to be
  /// main-actor bound — `TVUIKitMediaItem` builds tinted tiles off the actor.
  nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

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
