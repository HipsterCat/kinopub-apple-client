#if os(tvOS)
//
//  TVPageBannerChrome.swift
//  KinoPubUI
//
//  The Home banner's look, in one place. Watch Now and the templates gallery read
//  `TVPageBannerChrome.current`. Change the defaults below and rebuild.
//  The preview at the bottom draws one platter with the logo, words and poster,
//  and its controls try a draft on top of these defaults.
//
//  A few swaps, written as the assignment itself:
//
//    logoPlacement = .aboveCopy          // logo sits on the description, not at the top
//    alignment = .center                 // logo, words and poster as one group, centred
//    showsPoster = false
//    scrim = .wash(UIColor(white: 0.2, alpha: 0.45))
//    scrim = .radial(edge: UIColor(white: 0, alpha: 0.55), mid: .clear)
//    blend = .multiply                   // or .softLight, .overlay, .screen
//    row = .centered                     // the old paging: one platter in the middle
//    width = .halfScreen                 // one platter, half the screen
//    width = .content(peek: 180)         // one wide platter, a sliver of the next
//    textVibrance = 0                    // flat secondaryLabel; 1 is opaque white
//

import KinoPubMedia
import UIKit

/// How the banner row sits in the page.
enum TVPageBannerRow {
  /// The first platter starts at the same inset as the poster rails and the row
  /// scrolls continuously. Focus starts on the first title.
  case leading
  /// One platter centred, half a neighbour on either side, paging to the middle.
  case centered
}

/// How wide one platter is.
enum TVPageBannerWidth {
  /// Two platters and the gutter fill the content box — the same sum the shelves
  /// use. The second platter's trailing edge lands on the trailing side inset.
  case pair
  /// Half the screen. The size the centred row used.
  case halfScreen
  /// The rail's content width, minus `peek` points of the next platter.
  case content(peek: CGFloat)
}

/// Where the title logo (or the name, when there is no logo) sits inside the card.
enum TVPageBannerLogoPlacement: Hashable {
  /// The top inset. The artwork's top edge is that inset — the view is sized to
  /// the image, so a wide logo does not float down inside a tall box.
  case top
  /// In the copy column, directly above the description.
  case aboveCopy
}

/// How the logo, the words and the poster sit as a group.
enum TVPageBannerContentAlignment: Hashable {
  /// Words at the leading inset, poster at the trailing inset.
  case leading
  /// The group in the middle of the card.
  case center
}

/// What darkens the backdrop behind the words.
enum TVPageBannerScrim {
  /// Bands at the top and bottom. Reach is a fraction of the card's height; alpha
  /// is the dark end (the other end is clear). `color` is the band — black, or a
  /// swatch you pass in / sample from the art.
  case edges(color: UIColor, topReach: CGFloat, topAlpha: CGFloat, bottomReach: CGFloat, bottomAlpha: CGFloat)
  /// One colour over the whole card. Alpha is the colour's own.
  case wash(UIColor)
  /// Radial: `mid` at the centre, `edge` at the rim.
  case radial(edge: UIColor, mid: UIColor)
}

/// Compositing of the scrim over the backdrop. `.normal` draws the gradient as it is.
enum TVPageBannerBlend: Hashable {
  case normal
  case multiply
  case screen
  case overlay
  case softLight
  case darken

  var filterName: String? {
    switch self {
    case .normal: return nil
    case .multiply: return "multiplyBlendMode"
    case .screen: return "screenBlendMode"
    case .overlay: return "overlayBlendMode"
    case .softLight: return "softLightBlendMode"
    case .darken: return "darkenBlendMode"
    }
  }
}

/// Defaults are the banner Watch Now draws. Edit them; `current` is this value.
struct TVPageBannerChrome {
  static let current = TVPageBannerChrome()

  var row: TVPageBannerRow = .leading
  var width: TVPageBannerWidth = .pair
  var logoPlacement: TVPageBannerLogoPlacement = .top
  var alignment: TVPageBannerContentAlignment = .leading
  var showsPoster = true
  /// Short, light bands. The old ones reached 45% / 65% of the card at alpha 0.65–0.9.
  var scrim: TVPageBannerScrim = .edges(
    color: .black,
    topReach: 0.18,
    topAlpha: 0.28,
    bottomReach: 0.34,
    bottomAlpha: 0.40
  )
  var blend: TVPageBannerBlend = .normal
  /// Description, rating digits and genres. One style, the font's own weight —
  /// focus does not change the colour.
  var textStyle: UIFont.TextStyle = .caption2
  /// Secondary label. `textVibrance` pulls it toward opaque white so it stays
  /// vivid on the art: 0 is the system secondary, 1 is white.
  var textColor: UIColor = .secondaryLabel
  var textVibrance: CGFloat = 0.65
  var padding: CGFloat = 32
  var copySpacing: CGFloat = 8
  /// Caps for the logo box. The view is then shrunk to the image's own aspect,
  /// pinned to the top of that box.
  var logoMaxHeightRatio: CGFloat = 0.20
  var logoMaxWidthRatio: CGFloat = 0.60
  var posterHeightRatio: CGFloat = 0.42
  /// Rating-mark height. `nil` uses the caption font's cap height, so the mark
  /// sits on the digits.
  var scoreIconHeight: CGFloat? = nil

  var textFont: UIFont { UIFont.preferredFont(forTextStyle: textStyle) }

  /// `textColor` mixed toward white by `textVibrance`.
  var resolvedTextColor: UIColor {
    let amount = min(max(textVibrance, 0), 1)
    let base = textColor
    guard amount > 0 else { return base }
    return UIColor { traits in
      let resolved = base.resolvedColor(with: traits)
      var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
      guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return resolved }
      return UIColor(red: red + (1 - red) * amount,
                     green: green + (1 - green) * amount,
                     blue: blue + (1 - blue) * amount,
                     alpha: alpha + (1 - alpha) * amount)
    }
  }

  func cardWidth(containerWidth: CGFloat, sideInset: CGFloat) -> CGFloat {
    switch width {
    case .pair:
      let content = max(containerWidth - sideInset * 2, 1)
      return TVHIGGrid.cardWidth(columns: 2, contentWidth: content)
    case .halfScreen:
      return TVPageLayout.bannerWidth(containerWidth: containerWidth)
    case .content(let peek):
      let content = max(containerWidth - sideInset * 2, 1)
      return max((content - peek).rounded(.down), 1)
    }
  }
}

#if DEBUG
import SwiftUI

#Preview("Banner chrome") {
  TVPageBannerChromeCanvas()
}

/// One platter at the Watch Now pair width, plus the knobs. A bare cell never
/// runs `TVCardView`'s platter pass, so the host frames it and the cell lays the
/// platter out itself.
private struct TVPageBannerChromeCanvas: View {
  @State private var placement = TVPageBannerChrome.current.logoPlacement
  @State private var alignment = TVPageBannerChrome.current.alignment
  @State private var showsPoster = TVPageBannerChrome.current.showsPoster
  @State private var scrim = BannerPreviewScrim.file
  @State private var blend = TVPageBannerChrome.current.blend
  @State private var vibrance = Double(TVPageBannerChrome.current.textVibrance)

  private var chrome: TVPageBannerChrome {
    var draft = TVPageBannerChrome.current
    draft.logoPlacement = placement
    draft.alignment = alignment
    draft.showsPoster = showsPoster
    draft.blend = blend
    draft.textVibrance = CGFloat(vibrance)
    if let scrim = scrim.value { draft.scrim = scrim }
    return draft
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      BannerChromeHost(chrome: chrome)
        .frame(width: BannerChromeHost.itemSize.width, height: BannerChromeHost.itemSize.height)
      Picker("Logo", selection: $placement) {
        Text("Top").tag(TVPageBannerLogoPlacement.top)
        Text("Above copy").tag(TVPageBannerLogoPlacement.aboveCopy)
      }
      Picker("Alignment", selection: $alignment) {
        Text("Leading").tag(TVPageBannerContentAlignment.leading)
        Text("Center").tag(TVPageBannerContentAlignment.center)
      }
      Toggle("Poster", isOn: $showsPoster)
      Picker("Scrim", selection: $scrim) {
        ForEach(BannerPreviewScrim.allCases) { choice in
          Text(choice.label).tag(choice)
        }
      }
      Picker("Blend", selection: $blend) {
        Text("Normal").tag(TVPageBannerBlend.normal)
        Text("Multiply").tag(TVPageBannerBlend.multiply)
        Text("Screen").tag(TVPageBannerBlend.screen)
        Text("Overlay").tag(TVPageBannerBlend.overlay)
        Text("Soft light").tag(TVPageBannerBlend.softLight)
        Text("Darken").tag(TVPageBannerBlend.darken)
      }
      HStack(spacing: 16) {
        Button("−") { vibrance = max(0, ((vibrance - 0.05) * 20).rounded() / 20) }
        Text("Vibrance \(String(format: "%.2f", vibrance))")
        Button("+") { vibrance = min(1, ((vibrance + 0.05) * 20).rounded() / 20) }
      }
    }
    .padding(24)
  }
}

private enum BannerPreviewScrim: String, CaseIterable, Identifiable {
  case file, edges, wash, radial
  var id: String { rawValue }
  var label: String {
    switch self {
    case .file: return "From file"
    case .edges: return "Edges"
    case .wash: return "Wash"
    case .radial: return "Radial"
    }
  }
  var value: TVPageBannerScrim? {
    switch self {
    case .file: return nil
    case .edges:
      return .edges(color: .black, topReach: 0.18, topAlpha: 0.28, bottomReach: 0.34, bottomAlpha: 0.40)
    case .wash:
      return .wash(UIColor(white: 0.2, alpha: 0.45))
    case .radial:
      return .radial(edge: UIColor(white: 0, alpha: 0.55), mid: .clear)
    }
  }
}

private struct BannerChromeHost: UIViewRepresentable {
  var chrome: TVPageBannerChrome

  @MainActor
  static var itemSize: CGSize {
    let art = TVHIGGrid.cardWidth(columns: 2, contentWidth: TVHIGGrid.referenceContentWidth)
    return TVPageCellMetrics.recipe(kind: .banner, artWidth: art, caption: .always).itemSize
  }

  func makeUIView(context: Context) -> BannerPreviewHost {
    let host = BannerPreviewHost(frame: CGRect(origin: .zero, size: Self.itemSize))
    host.cell.apply(recipe: TVPageCellMetrics.recipe(
      kind: .banner,
      artWidth: TVHIGGrid.cardWidth(columns: 2, contentWidth: TVHIGGrid.referenceContentWidth),
      caption: .always
    ))
    host.cell.configure(feature: TVPageFeature(card: MediaCard(
      id: 1,
      posterURL: "",
      title: "Паук-Нуар",
      imdbRating: 8.8,
      kinopoiskRating: 7.8,
      overview: "Одноклассники называют Кохару Сато «неприступным цветком» — холодной и отстранённой девушкой, чья вечно серьёзная мина держит всех на расстоянии.",
      seasonCount: 1,
      isSeries: true,
      genres: [GenreVocabulary.genre(id: "anime"), GenreVocabulary.genre(id: "drama")].compactMap { $0 }
    )))
    host.cell.previewFill(backdrop: BannerPreviewArt.backdrop, poster: BannerPreviewArt.poster, logo: BannerPreviewArt.logo)
    host.cell.installChrome(chrome)
    return host
  }

  func updateUIView(_ host: BannerPreviewHost, context: Context) {
    host.cell.installChrome(chrome)
    host.setNeedsLayout()
    host.layoutIfNeeded()
  }
}

private final class BannerPreviewHost: UIView {
  let cell = TVPageBannerCell(frame: .zero)

  override init(frame: CGRect) {
    super.init(frame: frame)
    addSubview(cell)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    cell.frame = bounds
    cell.layoutIfNeeded()
  }
}

private enum BannerPreviewArt {
  static var backdrop: UIImage {
    let size = CGSize(width: 960, height: 540)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      let colors = [UIColor(red: 0.45, green: 0.72, blue: 0.95, alpha: 1).cgColor,
                    UIColor(red: 0.95, green: 0.78, blue: 0.55, alpha: 1).cgColor] as CFArray
      let space = CGColorSpaceCreateDeviceRGB()
      guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
      ctx.cgContext.drawLinearGradient(gradient, start: .zero,
                                      end: CGPoint(x: 0, y: size.height), options: [])
    }
  }

  static var poster: UIImage {
    let size = CGSize(width: 200, height: 300)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      UIColor(red: 0.55, green: 0.28, blue: 0.32, alpha: 1).setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
    }
  }

  /// A wide solid mark, so the top inset is the artwork's top — no clear pixels above it.
  static var logo: UIImage {
    let size = CGSize(width: 280, height: 72)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      UIColor.white.setFill()
      UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8).fill()
    }
  }
}
#endif
#endif
