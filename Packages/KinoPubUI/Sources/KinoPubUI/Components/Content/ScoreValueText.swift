//
//  ScoreValueText.swift
//
//  A score string, with the percent sign smaller than the digits.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
public typealias ScoreFont = UIFont
#elseif canImport(AppKit)
import AppKit
public typealias ScoreFont = NSFont
#endif

/// How a score is drawn when it carries a percent sign.
///
/// SF Pro (and Compact, and Rounded) has a superscript feature and a Small Symbols
/// set. Neither substitutes a smaller percent — probed 2026-10-26: superscript scales
/// the figures and leaves `%` at full size, Small Symbols does not touch it, and the
/// SF Symbol `percent` at `.small` is the same size as the text glyph. The sign is
/// the same character, set smaller and lifted so it centres on the digits' cap height.
public enum ScoreValueTypography {
  public static let percentScale: CGFloat = 0.75

  public static func rounded(size: CGFloat, weight: ScoreFont.Weight) -> ScoreFont {
    let base = ScoreFont.systemFont(ofSize: size, weight: weight)
    let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
#if canImport(UIKit)
    return UIFont(descriptor: descriptor, size: size)
#else
    return NSFont(descriptor: descriptor, size: size) ?? base
#endif
  }

  /// The detail page's running text, the same styles as `TypeScale.detailBody`.
  public static var runningText: ScoreFont {
#if os(tvOS)
    // SwiftUI's `.caption` (`TypeScale.detailBody` on tvOS). UIKit has no `.caption`.
    ScoreFont.preferredFont(forTextStyle: .caption1)
#else
    ScoreFont.preferredFont(forTextStyle: .body)
#endif
  }

  public static func attributed(_ text: String, font: ScoreFont) -> AttributedString {
    var string = AttributedString(text)
    string.font = Font(font)
    guard let range = string.range(of: "%") else { return string }
    let small = smallerPercent(of: font)
    string[range].font = Font(small.font)
    string[range].baselineOffset = small.offset
    return string
  }

  public static func nsAttributed(_ text: String, font: ScoreFont) -> NSAttributedString {
    let result = NSMutableAttributedString(string: text, attributes: [.font: font])
    guard let range = text.range(of: "%") else { return result }
    let small = smallerPercent(of: font)
    let ns = NSRange(range, in: text)
    result.addAttributes([.font: small.font, .baselineOffset: small.offset], range: ns)
    return result
  }

  private static func smallerPercent(of font: ScoreFont) -> (font: ScoreFont, offset: CGFloat) {
    let small = font.withSize(font.pointSize * percentScale)
    let offset = (font.capHeight - small.capHeight) / 2
    return (small, offset)
  }
}

/// Digits at the surrounding score size, percent sign smaller. A string with no
/// percent is the font as given.
public struct ScoreValueText: View {
  public let text: String
  public let font: ScoreFont
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(_ text: String, font: ScoreFont) {
    self.text = text
    self.font = font
  }

  public var body: some View {
    let _ = dynamicTypeSize
    Text(ScoreValueTypography.attributed(text, font: font))
      .accessibilityLabel(text)
  }
}
