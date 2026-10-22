//
//  HeroLegibilityTexture.swift
//  KinoPubUI
//

#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Pre-rendered alpha for the shared Home/detail legibility treatment (`HeroBannerOverlay`).
/// Only the image shading is baked; the theme's opaque black/white tone stays live.
public struct HeroLegibilityTexture: View {
  public static let assetName = "HeroBannerOverlay"

  private let tone: Color
  private let extendsLeadingFade: Bool
  @Environment(\.layoutDirection) private var layoutDirection

  public init(tone: Color = .black, extendsLeadingFade: Bool = false) {
    self.tone = tone
    self.extendsLeadingFade = extendsLeadingFade
  }

  @ViewBuilder
  public var body: some View {
    if layoutDirection == .leftToRight && !extendsLeadingFade && (tone == .black || tone == .white) {
      Image(Self.assetName, bundle: .module)
        .resizable()
        .renderingMode(.template)
        .foregroundStyle(tone)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    } else {
      HeroLegibilityScrim(
        tone: tone,
        edgePeak: 0.55,
        edges: [.leading, .bottom],
        sideDarkeningStart: extendsLeadingFade ? 0 : 0.34
      )
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }

#if canImport(UIKit)
  /// Template `UIImage` for UIKit / TVUIKit banner cells (`TVPageBannerCell`).
  public static func templateUIImage() -> UIImage? {
    (UIImage(named: assetName, in: .module, compatibleWith: nil)
      ?? UIImage(named: "HomeBannerOverlay", in: .module, compatibleWith: nil))?
      .withRenderingMode(.alwaysTemplate)
  }
#endif
}

public typealias HomeHeroLegibilityTexture = HeroLegibilityTexture
#endif
