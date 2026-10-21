#if os(tvOS)
//
//  TVPageBannerHost.swift
//  KinoPubUI
//
//  Hosting and sample art for TVPageBannerCell in SwiftUI previews and the Settings
//  Banner Lab. Uses real URLs (tvoe.live / staticpop) and high-fidelity fallback art
//  tuned to dominant color #C80202.
//

import KinoPubMedia
import SwiftUI
import UIKit

/// Hosts a standalone TVPageBannerCell inside SwiftUI. Sizes the cell to the HIG pair width
/// (or custom size) and drives platter layout and chrome configuration.
public struct TVPageBannerHost: UIViewRepresentable {
  public var chrome: TVPageBannerChrome
  public var feature: TVPageFeature
  public var customItemSize: CGSize? = nil
  public var usePreviewFillOnly: Bool = false

  public init(
    chrome: TVPageBannerChrome,
    feature: TVPageFeature,
    customItemSize: CGSize? = nil,
    usePreviewFillOnly: Bool = false
  ) {
    self.chrome = chrome
    self.feature = feature
    self.customItemSize = customItemSize
    self.usePreviewFillOnly = usePreviewFillOnly
  }

  @MainActor
  public static var itemSize: CGSize {
    let art = TVHIGGrid.cardWidth(columns: 2, contentWidth: TVHIGGrid.referenceContentWidth)
    return TVPageCellMetrics.recipe(kind: .banner, artWidth: art, caption: .always).itemSize
  }

  public func makeUIView(context: Context) -> TVPageBannerPreviewHost {
    let size = customItemSize ?? Self.itemSize
    let host = TVPageBannerPreviewHost(frame: CGRect(origin: .zero, size: size))
    host.configure(feature: feature, chrome: chrome, usePreviewFillOnly: usePreviewFillOnly)
    return host
  }

  public func updateUIView(_ host: TVPageBannerPreviewHost, context: Context) {
    let size = customItemSize ?? Self.itemSize
    if host.frame.size != size {
      host.frame = CGRect(origin: .zero, size: size)
    }
    host.configure(feature: feature, chrome: chrome, usePreviewFillOnly: usePreviewFillOnly)
  }
}

@MainActor
public final class TVPageBannerPreviewHost: UIView {
  let cell = TVPageBannerCell(frame: .zero)
  public var currentFeatureID: Int?
  public var currentLogo: TitleLogoResolution?

  public override init(frame: CGRect) {
    super.init(frame: frame)
    cell.laysOutPlatterForPreview = true
    addSubview(cell)
  }

  public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  public override func layoutSubviews() {
    super.layoutSubviews()
    cell.frame = bounds
    if bounds.width > 2 {
      cell.apply(recipe: TVPageCellMetrics.recipe(
        kind: .banner,
        artWidth: bounds.width,
        caption: .always
      ))
    }
    cell.layoutIfNeeded()
  }

  public func configure(feature: TVPageFeature, chrome: TVPageBannerChrome, usePreviewFillOnly: Bool = false) {
    if bounds.width > 2 {
      cell.apply(recipe: TVPageCellMetrics.recipe(
        kind: .banner,
        artWidth: bounds.width,
        caption: .always
      ))
    }
    currentFeatureID = feature.card.id
    currentLogo = feature.logo

    if usePreviewFillOnly {
      cell.configure(feature: feature)
      cell.previewFill(
        backdrop: BannerPreviewArt.backdrop,
        poster: feature.card.posterURL.isEmpty ? nil : BannerPreviewArt.poster,
        logo: feature.logo.url != nil ? BannerPreviewArt.logo : nil
      )
    } else {
      cell.configure(feature: feature)
    }
    cell.installChrome(chrome)
    setNeedsLayout()
    layoutIfNeeded()
  }

  public func installChrome(_ chrome: TVPageBannerChrome) {
    cell.installChrome(chrome)
    setNeedsLayout()
    layoutIfNeeded()
  }
}

// MARK: - Sample Art & Data

public enum TVPageBannerSamples {
  public static let dominantColor = UIColor(red: 200 / 255.0, green: 2 / 255.0, blue: 2 / 255.0, alpha: 1.0) // #C80202
  public static let dominantSwiftUIColor = Color(red: 200 / 255.0, green: 2 / 255.0, blue: 2 / 255.0)

  public static let primaryID = 125269
  public static let primaryLogoURL = "https://tvoe.live/_next/image?url=https%3A%2F%2Fstatic.cdn.tvoe.live%2Fimages%2F6a4b7d883cd582e10f37a4df.png&w=1024&q=80"
  public static let primaryPosterURL = "https://m.staticpop.net/poster/item/big/125269.jpg"
  public static let primaryLandscapeURL = "https://m.staticpop.net/poster/item/wide/125269.jpg"
  public static let primaryBackdropURL = "https://tvoe.live/_next/image?url=https%3A%2F%2Fstatic.cdn.tvoe.live%2Fimages%2F6a79e07abf36453f3033b821.jpg&w=3840&q=80"
  public static let primaryOverview = "Одноклассники называют Кохару Сато «неприступным цветком» — холодной и отстранённой девушкой, чья вечно серьёзная мина держит всех на расстоянии."

  public static func makeFeature(
    id: Int = primaryID,
    title: String = "Паук-Нуар",
    overview: String = primaryOverview,
    hasLogo: Bool = true,
    hasBackdrop: Bool = true,
    hasPoster: Bool = true,
    seasonCount: Int? = 1,
    isSeries: Bool = true,
    genres: [Genre] = [GenreVocabulary.genre(id: "anime"), GenreVocabulary.genre(id: "drama")].compactMap { $0 },
    imdbScore: Double = 8.8,
    kinopoiskScore: Double = 7.8
  ) -> TVPageFeature {
    let posterURL: String
    if !hasPoster {
      posterURL = ""
    } else if id == primaryID {
      posterURL = primaryPosterURL
    } else {
      posterURL = "https://m.staticpop.net/poster/item/big/\(id).jpg"
    }

    let landscapeURL: String?
    let backdropURL: String?
    if !hasBackdrop {
      landscapeURL = nil
      backdropURL = nil
    } else if id == primaryID {
      landscapeURL = primaryLandscapeURL
      backdropURL = primaryBackdropURL
    } else {
      landscapeURL = "https://m.staticpop.net/poster/item/wide/\(id).jpg"
      backdropURL = "https://m.staticpop.net/poster/item/wide/\(id).jpg"
    }

    let card = MediaCard(
      id: id,
      posterURL: posterURL,
      title: title,
      imdbRating: imdbScore,
      kinopoiskRating: kinopoiskScore,
      backdropURL: backdropURL,
      overview: overview,
      landscapeImageURL: landscapeURL,
      seasonCount: seasonCount,
      isSeries: isSeries,
      genres: genres
    )

    let logo: TitleLogoResolution
    if hasLogo, id == primaryID, let url = URL(string: primaryLogoURL) {
      logo = .url(url)
    } else {
      logo = .missing
    }

    return TVPageFeature(card: card, logo: logo)
  }
}

// MARK: - High Fidelity Fallback Art (#C80202)

public enum BannerPreviewArt {
  public static var backdrop: UIImage {
    let size = CGSize(width: 960, height: 540)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      let cgCtx = ctx.cgContext
      // Base dark graphite fill
      UIColor(red: 0.08, green: 0.06, blue: 0.07, alpha: 1.0).setFill()
      cgCtx.fill(CGRect(origin: .zero, size: size))

      // Radial spotlight with dominant #C80202
      let colors = [
        UIColor(red: 200 / 255.0, green: 2 / 255.0, blue: 2 / 255.0, alpha: 0.75).cgColor,
        UIColor(red: 100 / 255.0, green: 0 / 255.0, blue: 0 / 255.0, alpha: 0.35).cgColor,
        UIColor(red: 0.08, green: 0.06, blue: 0.07, alpha: 0.0).cgColor
      ] as CFArray
      let space = CGColorSpaceCreateDeviceRGB()
      if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.45, 1]) {
        cgCtx.drawRadialGradient(
          gradient,
          startCenter: CGPoint(x: size.width * 0.65, y: size.height * 0.35),
          startRadius: 0,
          endCenter: CGPoint(x: size.width * 0.65, y: size.height * 0.35),
          endRadius: size.width * 0.60,
          options: []
        )
      }
    }
  }

  public static var poster: UIImage {
    let size = CGSize(width: 200, height: 300)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      let cgCtx = ctx.cgContext
      // Deep dark base
      UIColor(red: 0.12, green: 0.10, blue: 0.12, alpha: 1.0).setFill()
      cgCtx.fill(CGRect(origin: .zero, size: size))

      // Subtle crimson gradient from bottom
      let colors = [
        UIColor(red: 200 / 255.0, green: 2 / 255.0, blue: 2 / 255.0, alpha: 0.55).cgColor,
        UIColor.clear.cgColor
      ] as CFArray
      let space = CGColorSpaceCreateDeviceRGB()
      if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
        cgCtx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
      }

      // Subtle hairline border
      UIColor(white: 1.0, alpha: 0.15).setStroke()
      let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), cornerRadius: 8)
      path.lineWidth = 1.5
      path.stroke()
    }
  }

  /// A clean title mark with the title typography drawn onto transparent art
  public static var logo: UIImage {
    let size = CGSize(width: 320, height: 80)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      let title = "ПАУК-НУАР" as NSString
      let font = UIFont.systemFont(ofSize: 34, weight: .heavy)
      let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: UIColor.white
      ]
      let textSize = title.size(withAttributes: attrs)
      let point = CGPoint(x: 0, y: (size.height - textSize.height) / 2)
      title.draw(at: point, withAttributes: attrs)
    }
  }
}

// MARK: - Banner Lab Options

public enum BannerLabPreset: String, CaseIterable, Identifiable, Sendable {
  case primaryFull
  case typographyOnly
  case noPoster
  case noBackdrop
  case catalog125268
  case catalog125260

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .primaryFull: return "Паук-Нуар 125269 (Full)"
    case .typographyOnly: return "125269 Без лого (Текст)"
    case .noPoster: return "125269 Без постера (Wide)"
    case .noBackdrop: return "125269 Без бэкдропа"
    case .catalog125268: return "Каталог ID 125268"
    case .catalog125260: return "Каталог ID 125260"
    }
  }
}

public enum BannerLabScrim: String, CaseIterable, Identifiable, Sendable {
  case file
  case edgesBlack
  case edgesDominant
  case washBlack
  case washDominant
  case radialBlack
  case radialDominant

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .file: return "Default (nil)"
    case .edgesBlack: return "Edges (Black)"
    case .edgesDominant: return "Edges (#C80202)"
    case .washBlack: return "Wash (Black 45%)"
    case .washDominant: return "Wash (#C80202 45%)"
    case .radialBlack: return "Radial (Black)"
    case .radialDominant: return "Radial (#C80202)"
    }
  }

  public var explanation: String {
    switch self {
    case .file:
      return "Без дополнительного программного затемнения."
    case .edgesBlack:
      return "Градиентные полосы черного цвета по верхнему и нижнему краям."
    case .edgesDominant:
      return "Градиентные полосы доминантного оттенка #C80202."
    case .washBlack:
      return "Сплошная полупрозрачная черная подложка по всей площади карточки."
    case .washDominant:
      return "Сплошная полупрозрачная подложка оттенка #C80202 (45%)."
    case .radialBlack:
      return "Радиальное затемнение черным цветом от краев к центру."
    case .radialDominant:
      return "Радиальное затемнение оттенком #C80202 от краев к центру."
    }
  }

  public var value: TVPageBannerScrim? {
    let dominant = TVPageBannerSamples.dominantColor
    switch self {
    case .file:
      return nil
    case .edgesBlack:
      return .edges(color: .black, topReach: 0.18, topAlpha: 0.28, bottomReach: 0.34, bottomAlpha: 0.40)
    case .edgesDominant:
      return .edges(color: dominant, topReach: 0.22, topAlpha: 0.35, bottomReach: 0.40, bottomAlpha: 0.50)
    case .washBlack:
      return .wash(UIColor(white: 0.1, alpha: 0.45))
    case .washDominant:
      return .wash(dominant.withAlphaComponent(0.45))
    case .radialBlack:
      return .radial(edge: UIColor(white: 0, alpha: 0.60), mid: .clear)
    case .radialDominant:
      return .radial(edge: dominant.withAlphaComponent(0.60), mid: .clear)
    }
  }
}
#endif
