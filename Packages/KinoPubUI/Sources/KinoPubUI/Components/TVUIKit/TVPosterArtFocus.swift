#if os(tvOS)
//
//  TVPosterArtFocus.swift
//  KinoPubUI
//
//  Keeps a poster's art from wearing the focused look when something other than its own cell
//  holds focus. The one place that touches UIKit's private names for it; every name and the
//  method's shape are checked first, so if Apple renames or reshapes it the art is left exactly
//  as the system leaves it (see below) and nothing crashes.
//
//  **Why it exists (measured 2026-10-06, tvOS 26.5 simulator, `-KINOPUBDetailFixture film`).**
//  A `TVPosterView`'s art is a `UIImageView` with `adjustsImageWhenAncestorFocused`, and UIKit
//  draws that as a *stack* (`_UIStackedImageContainerView`): layers that tilt and a glass
//  sheen, switched on by one flag, `isStackFocused`. The flag is not only set by a focus
//  update. `-[UIImageView _updateLayeredImageIsFocusedWithFocusedView:focusAnimationCoordinator:]`
//  also runs on every layout of the image and when it gets an image — with no coordinator —
//  and it asks, of the focus system's *focused view*, "is the art inside it?".
//
//  On the detail page the posters sit in a collection that is a child of a SwiftUI scroll
//  view, next to the hero's buttons, and SwiftUI's focus items answer to that scroll view's
//  container view (`HostingScrollView.PlatformGroupContainer`) — an ancestor of every poster.
//  While the hero holds focus the focused view *is* that container, so the answer for every
//  poster is yes: **every poster of every shelf wears the focused look at once** — a lighter
//  plate with a bright rim (left-edge brightness 153 and an interior 15% lighter, against a flat
//  93 on 27.2). Nothing takes it back until a focus update of the poster's own reaches it:
//  UIKit tells the views *under the item that loses focus*, and the hero's item is not a view and
//  has no subviews. Measured: 15 of 15 posters on the page flagged, across every move of the
//  remote inside the page; one read 0 once the remote had been on it and left, or when it was
//  built after focus was already inside the page. A page of posters that is not under a SwiftUI
//  focus item (Home, the templates gallery) reads 0 — and 1 on the focused poster only.
//  tvOS 27.2 has no such method at all, reads the same 0 / 1, and this finds nothing to do there.
//
//  The art of a poster *can* be focused by exactly one thing: its own cell, which is the
//  focused leaf of a poster here (see `TVPageLockupPosterCell`). So the question is answered
//  for it: asked about any other focused view, the art is told that nothing is focused.
//

import ObjectiveC
import UIKit

enum TVPosterArtFocus {
  /// Declares that `imageView` — the art of a poster lockup — is focused when `cell` is, and
  /// only then.
  @MainActor
  static func bind(_ imageView: UIImageView, to cell: UIView) {
    _ = installed
    owners.setObject(cell, forKey: imageView)
  }

  /// Image view → the cell whose focus it follows. Weak both ways; only touched on the main
  /// thread, where UIKit lays out and updates focus.
  nonisolated(unsafe) private static let owners = NSMapTable<UIImageView, UIView>(
    keyOptions: .weakMemory, valueOptions: .weakMemory)

  /// Swizzled once. A no-op when the method is not there — tvOS 27.2 has none — or not in the
  /// shape this expects: `void (id focusedView, id coordinator)`.
  private static let installed: Void = {
    let selector = NSSelectorFromString("_updateLayeredImageIsFocusedWithFocusedView:focusAnimationCoordinator:")
    guard let method = class_getInstanceMethod(UIImageView.self, selector),
          method_getNumberOfArguments(method) == 4,
          typeEncoding(ofReturnOf: method) == "v",
          typeEncoding(ofArgument: 2, of: method) == "@",
          typeEncoding(ofArgument: 3, of: method) == "@" else { return }

    typealias Original = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?) -> Void
    let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
    let replacement: @convention(block) (UIImageView, AnyObject?, AnyObject?) -> Void = { imageView, focusedView, coordinator in
      var answered = focusedView
      if let focusedView, let owner = owners.object(forKey: imageView), owner !== focusedView {
        answered = nil
      }
      original(imageView, selector, answered, coordinator)
    }
    method_setImplementation(method, imp_implementationWithBlock(replacement))
  }()

  private static func typeEncoding(ofReturnOf method: Method) -> String {
    let raw = method_copyReturnType(method)
    defer { free(raw) }
    return String(cString: raw)
  }

  private static func typeEncoding(ofArgument index: UInt32, of method: Method) -> String? {
    guard let raw = method_copyArgumentType(method, index) else { return nil }
    defer { free(raw) }
    return String(cString: raw)
  }
}
#endif
