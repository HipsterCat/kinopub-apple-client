#if os(tvOS)
//
//  TVCardViewFocusRelease.swift
//  KinoPubUI
//
//  Puts a card's platter back down when focus left its cell for a view that *contains*
//  the card. The one place that touches TVUIKit's private names for it; every name is
//  checked first, so if Apple renames one the platter is left exactly as the system
//  leaves it (lifted — the defect below), and nothing crashes.
//
//  **Why it exists (measured 2026-10-06, tvOS 27.2 simulator, `-KINOPUBDetailFixture
//  film`).** A cell here holds focus and the `TVCardView` inside it only follows. TVUIKit
//  follows by asking, on every focus update (`_ancestorWillUpdateFocusInContext:`),
//  whether the view that now has focus is one of the lockup's ancestors — it keeps the
//  answer in `ancestorFocused` and lifts the platter while it is yes. It cannot tell the
//  cell from any other ancestor. On the detail page the cards sit in a collection that is
//  a child of a SwiftUI scroll view, and SwiftUI's own focusable things — the hero's
//  buttons above, the footer's link below — take focus *as that scroll view's container
//  view* (`HostingScrollView.PlatformGroupContainer`), which is an ancestor of every card.
//  Focus leaving a card for them is answered "an ancestor is focused": `ancestorFocused`
//  stays 1, the floating content view is never told to put itself down, and the platter
//  stays lifted and white while the text goes back to light-on-dark — a white card with
//  white text under the page. Moving between cards (or to anything that is not an
//  ancestor) is answered correctly.
//
//  The same ancestor does the same to a poster's *art* on tvOS 26.x, from the other side —
//  see `TVPosterArtFocus`.
//

import ObjectiveC
import TVUIKit
import UIKit

extension TVCardView {
  /// Takes the platter back to rest — what the system does when it reads a focus update
  /// right — inside the update's own animation coordinator, and clears the stale "an
  /// ancestor is focused" answer so the next time focus enters the cell it lifts again.
  ///
  /// Call it from the cell's `didUpdateFocus` only for the case it is for: focus went to a
  /// view the card is inside (`cardView.isDescendant(of: next)`) and not to the cell.
  func releaseFocusedLook(with coordinator: UIFocusAnimationCoordinator) {
    let getter = NSSelectorFromString("ancestorFocused")
    guard responds(to: getter),
          responds(to: NSSelectorFromString("setAncestorFocused:")),
          value(forKey: "ancestorFocused") as? Bool == true else { return }
    setValue(false, forKey: "ancestorFocused")

    let setState = NSSelectorFromString("setControlState:withAnimationCoordinator:")
    guard let floating = floatingContentView(),
          floating.responds(to: setState),
          let implementation = class_getMethodImplementation(type(of: floating), setState) else { return }
    typealias SetControlState = @convention(c) (AnyObject, Selector, UInt, UIFocusAnimationCoordinator) -> Void
    unsafeBitCast(implementation, to: SetControlState.self)(floating, setState,
                                                            UIControl.State.normal.rawValue, coordinator)
  }

  /// The view that draws the lift: TVUIKit's own card flavour of `_UIFloatingContentView`,
  /// two levels down.
  private func floatingContentView() -> UIView? {
    var pending = subviews
    while !pending.isEmpty {
      let view = pending.removeFirst()
      if String(describing: type(of: view)) == "_TVUICardFloatingContentView" { return view }
      pending.append(contentsOf: view.subviews)
    }
    return nil
  }
}
#endif
