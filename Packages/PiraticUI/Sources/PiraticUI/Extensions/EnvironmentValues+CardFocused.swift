//
//  EnvironmentValues+CardFocused.swift
//
//

import SwiftUI

private struct CardFocusedKey: EnvironmentKey {
  static let defaultValue = false
}

private struct HidesMediaCardBookmarkSymbolKey: EnvironmentKey {
  static let defaultValue = false
}

public extension EnvironmentValues {
  /// Whether the card's enclosing button is focused. Set by the card button styles
  /// and read by `MediaCardView`, because a label subtree cannot rely on reading
  /// `\.isFocused` directly — only the focusable button sees it.
  var cardFocused: Bool {
    get { self[CardFocusedKey.self] }
    set { self[CardFocusedKey.self] = newValue }
  }

  /// When true, cards never paint the bookmark ribbon. For surfaces where every item
  /// is already subscribed or bookmarked (Watching / Library Following / folders) —
  /// the glyph would sit on every poster and say nothing.
  var hidesMediaCardBookmarkSymbol: Bool {
    get { self[HidesMediaCardBookmarkSymbolKey.self] }
    set { self[HidesMediaCardBookmarkSymbolKey.self] = newValue }
  }
}
