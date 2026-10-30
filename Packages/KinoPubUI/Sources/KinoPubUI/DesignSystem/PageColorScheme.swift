//
//  PageColorScheme.swift
//  KinoPubUI
//
//  The appearance the window itself is in, kept apart from `colorScheme` so a subtree
//  that forces itself dark (the hero over a picture) can still hand its own sheets the
//  real one. A sheet inherits the presenter's environment: the synopsis popup opened
//  from the dark hero drew white text on the light sheet (Sasha, 2026-10-30).
//

import SwiftUI

public extension EnvironmentValues {
  /// Nil outside `capturesPageColorScheme()`; read it as `pageColorScheme ?? colorScheme`.
  @Entry var pageColorScheme: ColorScheme? = nil
}

private struct PageColorSchemeCapture: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    content.environment(\.pageColorScheme, colorScheme)
  }
}

public extension View {
  /// At the window root, inside any `preferredColorScheme`.
  func capturesPageColorScheme() -> some View {
    modifier(PageColorSchemeCapture())
  }

  /// For a sheet's content: back to the window's appearance.
  func pageColorScheme() -> some View {
    modifier(PageColorSchemeRestore())
  }
}

private struct PageColorSchemeRestore: ViewModifier {
  @Environment(\.pageColorScheme) private var pageColorScheme
  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    content.environment(\.colorScheme, pageColorScheme ?? colorScheme)
  }
}
