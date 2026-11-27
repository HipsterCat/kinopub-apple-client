//
//  SheetCloseButton.swift
//  PiraticUI
//
//  The cross in the leading corner of a sheet — same control as Choose a Version /
//  Settings: hierarchical `xmark.circle.fill`, Escape on a keyboard. Used by What's New,
//  detail info popups and the code sign-in (Sasha, 2026-11-21: replace the solid glass
//  disc that read as a black ball on Mac).
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
      Image(systemName: "xmark.circle.fill")
        .symbolRenderingMode(.hierarchical)
        .font(SheetCloseButton.glyphFont)
        .foregroundStyle(.secondary)
        .frame(width: SheetCloseButton.side, height: SheetCloseButton.side)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .keyboardShortcut(.cancelAction)
    .accessibilityLabel(Text("Close"))
  }

#if os(macOS)
  public static let side: CGFloat = 28
  static let glyphFont: Font = .title2
  public static let inset: CGFloat = 14
#else
  public static let side: CGFloat = 30
  static let glyphFont: Font = .title2
  public static let inset: CGFloat = 16
#endif
}
#endif
