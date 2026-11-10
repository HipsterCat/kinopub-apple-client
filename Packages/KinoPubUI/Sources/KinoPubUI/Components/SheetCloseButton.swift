//
//  SheetCloseButton.swift
//  KinoPubUI
//
//  The cross in the leading corner of a sheet, as TestFlight, the App Store and Apple's
//  own What's New draw it: a glass circle with an `xmark`, Escape on a keyboard. One
//  control for the code sign-in, What's New and the info popups instead of «Готово» and
//  «Отмена» buttons that differ per screen (Sasha, 2026-11-10).
//

import SwiftUI

#if !os(tvOS)
public struct SheetCloseButton: View {
  private let action: () -> Void

  public init(action: @escaping () -> Void) {
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .font(SheetCloseButton.glyphFont)
        .frame(width: SheetCloseButton.side, height: SheetCloseButton.side)
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.circle)
    .keyboardShortcut(.cancelAction)
    .accessibilityLabel(Text("Close"))
  }

  /// The glyph's square inside the circle; the glass adds its own margin around it.
#if os(macOS)
  public static let side: CGFloat = 20
  static let glyphFont: Font = .body.weight(.semibold)
  /// From the sheet's edges to the circle.
  public static let inset: CGFloat = 14
#else
  public static let side: CGFloat = 28
  static let glyphFont: Font = .body.weight(.semibold)
  public static let inset: CGFloat = 16
#endif
}
#endif
