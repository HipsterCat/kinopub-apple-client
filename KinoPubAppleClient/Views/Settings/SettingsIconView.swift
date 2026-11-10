//
//  SettingsIconView.swift
//  KinoPubAppleClient
//

import SwiftUI

/// Apple Settings–style glyph in a colored rounded square.
struct SettingsIconView: View {
  /// A Settings row's icon, sidebar and list alike: 26 pt was a size short of Apple's
  /// own (Sasha, 2026-11-10: "38 → 42", the same 10 % up).
  static let rowSize: CGFloat = 29

  let systemImage: String
  let color: Color
  var size: CGFloat = SettingsIconView.rowSize

  var body: some View {
    Image(systemName: systemImage)
      .font(.system(size: size * 0.42, weight: .medium))
      .foregroundStyle(.white)
//      .preferredColorScheme(.dark)
      .frame(width: size, height: size)
      .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
  }
}
