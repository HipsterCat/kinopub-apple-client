//
//  TVUIKitPosterEnvironment.swift
//  PiraticUI
//
//  Gates native TVUIKit posters (shelves + grids share one atom) and provides a
//  NavigationStack-friendly open handler for UIKit selection.
//

import SwiftUI

private struct UsesTVUIKitPostersKey: EnvironmentKey {
  static let defaultValue = true
}

private struct MediaNavigationKey: EnvironmentKey {
  static let defaultValue: (@MainActor (any Hashable) -> Void)? = nil
}

extension EnvironmentValues {
  /// When true on tvOS, shelves and grids render `TVPosterView` / `TVCardView`
  /// cells instead of SwiftUI `MediaCardView`.
  public var usesTVUIKitPosters: Bool {
    get { self[UsesTVUIKitPostersKey.self] }
    set { self[UsesTVUIKitPostersKey.self] = newValue }
  }

  /// Opens a `navigationDestination` value from a UIKit poster selection.
  /// Main-actor isolated: the handler pushes a route, and a `@MainActor` function
  /// type is `Sendable`, which a stored environment default has to be.
  public var mediaNavigation: (@MainActor (any Hashable) -> Void)? {
    get { self[MediaNavigationKey.self] }
    set { self[MediaNavigationKey.self] = newValue }
  }
}
