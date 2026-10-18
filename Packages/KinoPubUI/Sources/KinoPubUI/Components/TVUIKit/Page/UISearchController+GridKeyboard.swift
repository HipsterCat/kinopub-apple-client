#if os(tvOS)
//
//  UISearchController+GridKeyboard.swift
//  KinoPubUI
//
//  Adapter (docs/engineering/adapters.md): the grid keyboard — the one on the left,
//  Settings → General → Keyboard — slides away while focus is in the results and comes
//  back on Left from their first column; the results take the screen's width meanwhile.
//  UIKit has that behaviour but no public switch: `_setShouldHideGridKeyboardUnfocused:`
//  on `UISearchController` (property `_shouldHideGridKeyboardUnfocused`, NO by default;
//  tvOS 26.5 and 27.2). Without it the keyboard stays on screen and the results keep
//  two thirds of it. The linear keyboard is not affected. Re-probe on the next SDK.
//

import UIKit

extension UISearchController {
  /// The grid keyboard hides while the search field's half has no focus. A no-op where
  /// UIKit lacks the switch.
  func hidesGridKeyboardWhenUnfocused() {
    let setter = NSSelectorFromString("_setShouldHideGridKeyboardUnfocused:")
    guard responds(to: setter) else { return }
    setValue(true, forKey: "_shouldHideGridKeyboardUnfocused")
  }
}
#endif
