//
//  SettingsIconView.swift
//  KinoPubAppleClient
//

import SwiftUI

/// Apple Settings–style glyph in a colored rounded square.
struct SettingsIconView: View {
  let systemImage: String
  let color: Color
  var size: CGFloat = 26

  var body: some View {
    Image(systemName: systemImage)
     .font(.system(size: 11, weight: .medium))
      .foregroundStyle(.white)
//      .preferredColorScheme(.dark)
      .frame(width: size, height: size)
      .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
  }
}
