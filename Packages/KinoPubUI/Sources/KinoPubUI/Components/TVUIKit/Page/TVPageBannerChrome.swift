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
public enum TVPageBannerRow: String, CaseIterable, Sendable {
  /// The first platter starts at the same inset as the poster rails and the row
  /// scrolls continuously. Focus starts on the first title.
  case leading
  /// One platter centred, half a neighbour on either side, paging to the middle.
  case centered
}

/// How wide one platter is.
public enum TVPageBannerWidth: Sendable {
  /// Two platters and the gutter fill the content box — the same sum the shelves
  /// use. The second platter's trailing edge lands on the trailing side inset.
  case pair
  /// Half the screen. The size the centred row used.
  case halfScreen
  /// The rail's content width, minus `peek` points of the next platter.
  case content(peek: CGFloat)
}

/// Where the title logo (or the name, when there is no logo) sits inside the card.
public enum TVPageBannerLogoPlacement: String, CaseIterable, Hashable, Sendable {
  /// The top inset. The artwork's top edge is that inset — the view is sized to
  /// the image, so a wide logo does not float down inside a tall box.
  case top
  /// In the copy column, directly above the description.
  case aboveCopy
}

/// How the logo, the words and the poster sit as a group.
public enum TVPageBannerContentAlignment: String, CaseIterable, Hashable, Sendable {
  /// Words at the leading inset, poster at the trailing inset.
  case leading
  /// The group in the middle of the card.
  case center
}

/// Vertical positioning of the content block inside the banner.
public enum TVPageBannerVerticalAlignment: String, CaseIterable, Hashable, Sendable {
  case bottom
  case center
  case top

  public var title: String {
    switch self {
    case .bottom: return "Снизу"
    case .center: return "По центру"
    case .top: return "Сверху"
    }
  }
}

/// What darkens the backdrop behind the words.
public enum TVPageBannerScrim: Sendable {
  /// Seamless 2D legibility vignette (`HeroBannerOverlay` / `HeroLegibilityScrim`):
  /// a subtle 6% wash across the whole image, leading-edge darkening ramped vertically
  /// from `sideDarkeningStart` (`0.34`), and an eased 8-stop bottom fade (`bottomFadeTop: 0.58`,
  /// `edgePeak: 0.55`). Uses the pre-rendered `HeroBannerOverlay` alpha asset when
  /// `usesCachedTexture` is true, or the analytic multi-layer gradient otherwise.
  case legibility(
    color: UIColor = .black,
    edgePeak: CGFloat = 0.55,
    wash: CGFloat = 0.06,
    sideDarkeningStart: CGFloat = 0.34,
    bottomFadeTop: CGFloat = 0.58,
    usesCachedTexture: Bool = true
  )
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
public enum TVPageBannerBlend: String, CaseIterable, Hashable, Sendable {
  case normal
  case multiply
  case screen
  case overlay
  case softLight
  case darken

  public var filterName: String? {
    switch self {
    case .normal: return nil
    case .multiply: return "multiplyBlendMode"
    case .screen: return "screenBlendMode"
    case .overlay: return "overlayBlendMode"
    case .softLight: return "softLightBlendMode"
    case .darken: return "darkenBlendMode"
    }
  }

  public static var allSupportedCases: [TVPageBannerBlend] {
    [.normal, .multiply, .screen, .overlay, .softLight, .darken]
  }

  public var title: String {
    switch self {
    case .normal: return "Normal"
    case .multiply: return "Multiply"
    case .screen: return "Screen"
    case .overlay: return "Overlay"
    case .softLight: return "Soft light"
    case .darken: return "Darken"
    }
  }
}

/// Defaults are the banner Watch Now draws. Edit them; `current` is this value.
public struct TVPageBannerChrome: Sendable {
  public static let current = TVPageBannerChrome()

  public static let bannerGutter: CGFloat = 60

  public var row: TVPageBannerRow = .leading
  public var width: TVPageBannerWidth = .pair
  public var logoPlacement: TVPageBannerLogoPlacement = .top
  public var alignment: TVPageBannerContentAlignment = .leading
  public var verticalAlignment: TVPageBannerVerticalAlignment = .bottom
  public var showsPoster: Bool = false
  /// Seamless 2D legibility vignette (`HeroBannerOverlay` / `HeroLegibilityScrim`).
  public var scrim: TVPageBannerScrim = .legibility()
  public var blend: TVPageBannerBlend = .normal
  /// Description, rating digits and genres. One style, the font's own weight.
  public var textStyle: UIFont.TextStyle = .caption2
  /// Secondary label for unfocused description.
  public var textColor: UIColor = .secondaryLabel
  public var textVibrance: CGFloat = 0.65
  public var vibranceEnabled: Bool = false
  public var isFocusedState: Bool = false
  public var padding: CGFloat = 32
  /// Reduced top padding above title/logo (~25% less than 32pt side inset).
  public var topPadding: CGFloat = 24
  /// Reduced bottom padding under meta line (~30% less than 32pt side inset).
  public var bottomPadding: CGFloat = 22
  public var copySpacing: CGFloat = 12
  /// Caps for the logo box. The view is then shrunk to the image's own aspect,
  /// pinned to the top of that box.
  public var logoMaxHeightRatio: CGFloat = 0.22
  public var logoMaxWidthRatio: CGFloat = 0.65
  /// Poster is 40% of banner height in the bottom corner.
  public var posterHeightRatio: CGFloat = 0.40
  /// Rating-mark height. `nil` uses the caption font's cap height, so the mark
  /// sits on the digits.
  public var scoreIconHeight: CGFloat? = nil
  /// Whether to display voter turnout in parentheses after the rating: `(12K)`.
  public var showsRatingVotes: Bool = false
  /// Maximum number of rating badges in the banner meta row (default 2).
  public var ratingMaxCount: Int = 2
  /// Filter out noisy ratings with < 10 votes when higher turnout ratings exist.
  public var filterLowTurnout: Bool = true
  /// When a single rating source holds > 90% of total votes, collapse to that 1 source.
  public var filterDominantScore: Bool = true
  /// Whether to display our weighted aggregate score plaque at the start of the ratings row.
  public var showsAggregateScore: Bool = false
  /// When true, renders only the aggregate score badge without individual source breakdowns.
  public var aggregateOnly: Bool = false
  /// Omits duplicate rating digits when the aggregate score is derived from only 1 source.
  public var deduplicateSingleSourceAggregate: Bool = true

  public init(
    row: TVPageBannerRow = .leading,
    width: TVPageBannerWidth = .pair,
    logoPlacement: TVPageBannerLogoPlacement = .top,
    alignment: TVPageBannerContentAlignment = .leading,
    verticalAlignment: TVPageBannerVerticalAlignment = .bottom,
    showsPoster: Bool = false,
    scrim: TVPageBannerScrim = .legibility(),
    blend: TVPageBannerBlend = .normal,
    textStyle: UIFont.TextStyle = .caption2,
    textColor: UIColor = .secondaryLabel,
    textVibrance: CGFloat = 0.65,
    vibranceEnabled: Bool = false,
    isFocusedState: Bool = false,
    padding: CGFloat = 32,
    topPadding: CGFloat = 24,
    bottomPadding: CGFloat = 22,
    copySpacing: CGFloat = 12,
    logoMaxHeightRatio: CGFloat = 0.22,
    logoMaxWidthRatio: CGFloat = 0.65,
    posterHeightRatio: CGFloat = 0.40,
    scoreIconHeight: CGFloat? = nil,
    showsRatingVotes: Bool = false,
    ratingMaxCount: Int = 2,
    filterLowTurnout: Bool = true,
    filterDominantScore: Bool = true,
    showsAggregateScore: Bool = false,
    aggregateOnly: Bool = false,
    deduplicateSingleSourceAggregate: Bool = true
  ) {
    self.row = row
    self.width = width
    self.logoPlacement = logoPlacement
    self.alignment = alignment
    self.verticalAlignment = verticalAlignment
    self.showsPoster = showsPoster
    self.scrim = scrim
    self.blend = blend
    self.textStyle = textStyle
    self.textColor = textColor
    self.textVibrance = textVibrance
    self.vibranceEnabled = vibranceEnabled
    self.isFocusedState = isFocusedState
    self.padding = padding
    self.topPadding = topPadding
    self.bottomPadding = bottomPadding
    self.copySpacing = copySpacing
    self.logoMaxHeightRatio = logoMaxHeightRatio
    self.logoMaxWidthRatio = logoMaxWidthRatio
    self.posterHeightRatio = posterHeightRatio
    self.scoreIconHeight = scoreIconHeight
    self.showsRatingVotes = showsRatingVotes
    self.ratingMaxCount = ratingMaxCount
    self.filterLowTurnout = filterLowTurnout
    self.filterDominantScore = filterDominantScore
    self.showsAggregateScore = showsAggregateScore
    self.aggregateOnly = aggregateOnly
    self.deduplicateSingleSourceAggregate = deduplicateSingleSourceAggregate
  }

  public var textFont: UIFont { UIFont.preferredFont(forTextStyle: textStyle) }

  /// `textColor` mixed toward white by `textVibrance` when enabled, or bright white in focus.
  /// When vibrance is disabled, returns `textColor` directly so UIKit handles dynamic accessibility
  /// contrast (Increase Contrast) out of the box.
  public var resolvedTextColor: UIColor {
    if isFocusedState {
      return .white
    }
    guard vibranceEnabled else {
      return textColor
    }
    let amount = min(max(textVibrance, 0), 1)
    guard amount > 0 else { return textColor }
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    guard textColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return textColor }
    return UIColor(red: red + (1 - red) * amount,
                   green: green + (1 - green) * amount,
                   blue: blue + (1 - blue) * amount,
                   alpha: alpha + (1 - alpha) * amount)
  }

  func cardWidth(containerWidth: CGFloat, sideInset: CGFloat) -> CGFloat {
    switch width {
    case .pair:
      let content = max(containerWidth - sideInset * 2, 1)
      let usable = max(content - TVPageBannerChrome.bannerGutter, 1)
      return (usable / 2).rounded(.down)
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

// MARK: - Previews

#Preview("1. Canonical (Top Logo, Leading)") {
  bannerPreviewCanvas(title: "Canonical Banner", note: "Логотип в верхнем инсете, выравнивание слева, постер включен, градиентные полосы по краям (edges).") {
    TVPageBannerChrome.current
  }
}

#Preview("2. Logo Above Copy") {
  bannerPreviewCanvas(title: "Logo Above Copy", note: "Логотип смещен вниз в колонку контента непосредственно над синопсисом.") {
    var chrome = TVPageBannerChrome.current
    chrome.logoPlacement = .aboveCopy
    return chrome
  }
}

#Preview("3. Centered + Dominant Wash") {
  bannerPreviewCanvas(title: "Centered Alignment + Wash Scrim", note: "Центрированная группа (лого + текст + постер) с заливкой wash доминантным цветом #C80202.") {
    var chrome = TVPageBannerChrome.current
    chrome.alignment = .center
    chrome.logoPlacement = .aboveCopy
    chrome.scrim = .wash(TVPageBannerSamples.dominantColor.withAlphaComponent(0.40))
    return chrome
  }
}

#Preview("4. Typography Title (No Logo)") {
  bannerPreviewCanvas(title: "Typography Title (No Logo)", note: "Тайтл без логотипа — отображение шрифтового заголовка в колонке контента.") {
    var chrome = TVPageBannerChrome.current
    chrome.logoPlacement = .aboveCopy
    return chrome
  } feature: {
    TVPageBannerSamples.makeFeature(hasLogo: false)
  }
}

#Preview("5. Cinematic Wide (No Poster)") {
  bannerPreviewCanvas(title: "Cinematic Wide (No Poster)", note: "Широкий арт без вертикального постера — акцент на бэкдроп и логотип.") {
    var chrome = TVPageBannerChrome.current
    chrome.showsPoster = false
    return chrome
  }
}

#Preview("6. Dominant Wash + Multiply Blend") {
  bannerPreviewCanvas(title: "Dominant Wash (#C80202) + Multiply", note: "Заливка wash цветом #C80202 в режиме multiplyBlendMode.") {
    var chrome = TVPageBannerChrome.current
    chrome.scrim = .wash(TVPageBannerSamples.dominantColor.withAlphaComponent(0.50))
    chrome.blend = .multiply
    return chrome
  }
}

#Preview("7. Radial Scrim + Soft Light Blend") {
  bannerPreviewCanvas(title: "Radial Scrim + Soft Light", note: "Радиальное затемнение от краев к центру с фильтром softLightBlendMode.") {
    var chrome = TVPageBannerChrome.current
    chrome.scrim = .radial(edge: TVPageBannerSamples.dominantColor.withAlphaComponent(0.65), mid: .clear)
    chrome.blend = .softLight
    return chrome
  }
}

#Preview("8. No Backdrop (Poster Fallback)") {
  bannerPreviewCanvas(title: "No Backdrop (Poster Fallback)", note: "Тайтл без бэкдропа — проверка поведения плашки при отсутствии широкого арта.") {
    TVPageBannerChrome.current
  } feature: {
    TVPageBannerSamples.makeFeature(hasBackdrop: false)
  }
}

#Preview("All Banner Variants (Stacked)") {
  ScrollView {
    VStack(alignment: .leading, spacing: 48) {
      variantRow(
        number: "1",
        title: "Canonical (Top Logo, Leading)",
        note: "Default: логотип сверху, выравнивание слева, постер, градиенты edges."
      ) {
        TVPageBannerChrome.current
      }

      variantRow(
        number: "2",
        title: "Logo Above Copy",
        note: "Логотип в колонке над описанием."
      ) {
        var c = TVPageBannerChrome.current
        c.logoPlacement = .aboveCopy
        return c
      }

      variantRow(
        number: "3",
        title: "Centered Alignment + Wash Scrim",
        note: "Центрированная колонка + заливка wash доминантным цветом #C80202."
      ) {
        var c = TVPageBannerChrome.current
        c.alignment = .center
        c.logoPlacement = .aboveCopy
        c.scrim = .wash(TVPageBannerSamples.dominantColor.withAlphaComponent(0.40))
        return c
      }

      variantRow(
        number: "4",
        title: "Typography Title (No Logo)",
        note: "Шрифтовой заголовок без логотипа."
      ) {
        var c = TVPageBannerChrome.current
        c.logoPlacement = .aboveCopy
        return c
      } feature: {
        TVPageBannerSamples.makeFeature(hasLogo: false)
      }

      variantRow(
        number: "5",
        title: "Cinematic Wide (No Poster)",
        note: "Без постера — широкий бэкдроп на всю плашку."
      ) {
        var c = TVPageBannerChrome.current
        c.showsPoster = false
        return c
      }

      variantRow(
        number: "6",
        title: "Dominant Wash + Multiply Blend",
        note: "Wash цветом #C80202 + multiplyBlendMode."
      ) {
        var c = TVPageBannerChrome.current
        c.scrim = .wash(TVPageBannerSamples.dominantColor.withAlphaComponent(0.50))
        c.blend = .multiply
        return c
      }

      variantRow(
        number: "7",
        title: "Radial Scrim + Soft Light Blend",
        note: "Радиальный градиент + softLightBlendMode."
      ) {
        var c = TVPageBannerChrome.current
        c.scrim = .radial(edge: TVPageBannerSamples.dominantColor.withAlphaComponent(0.65), mid: .clear)
        c.blend = .softLight
        return c
      }

      variantRow(
        number: "8",
        title: "No Backdrop (Poster Fallback)",
        note: "Без бэкдропа — фоллбек на чистый постер."
      ) {
        TVPageBannerChrome.current
      } feature: {
        TVPageBannerSamples.makeFeature(hasBackdrop: false)
      }
    }
    .padding(40)
  }
}

// MARK: - Preview Helpers

@MainActor
@ViewBuilder
private func bannerPreviewCanvas(
  title: String,
  note: String,
  chrome: () -> TVPageBannerChrome,
  feature: () -> TVPageFeature = { TVPageBannerSamples.makeFeature() }
) -> some View {
  VStack(alignment: .leading, spacing: 20) {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.title3)
        .fontWeight(.semibold)
      Text(note)
        .font(.caption)
        .foregroundStyle(.secondary)
//        .fixedSize(horizontal: false, vertical: true)
    }

    TVPageBannerHost(chrome: chrome(), feature: feature())
      .frame(width: TVPageBannerHost.itemSize.width, height: TVPageBannerHost.itemSize.height)
  }
  .padding(32)
}

@MainActor
@ViewBuilder
private func variantRow(
  number: String,
  title: String,
  note: String,
  chrome: () -> TVPageBannerChrome,
  feature: () -> TVPageFeature = { TVPageBannerSamples.makeFeature() }
) -> some View {
  VStack(alignment: .leading, spacing: 14) {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(number)
        .font(.headline)
        .foregroundStyle(.secondary)
      Text(title)
        .font(.headline)
        .fontWeight(.semibold)
    }
    Text(note)
      .font(.caption)
      .foregroundStyle(.secondary)

    TVPageBannerHost(chrome: chrome(), feature: feature())
      .frame(width: TVPageBannerHost.itemSize.width, height: TVPageBannerHost.itemSize.height)
  }
}
#endif
#endif
