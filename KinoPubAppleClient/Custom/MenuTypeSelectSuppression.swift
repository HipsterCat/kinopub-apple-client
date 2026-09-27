//
//  MenuTypeSelectSuppression.swift
//  KinoPubAppleClient
//
//  Created by AI on 02.09.2026.
//

#if os(iOS)
import GameController
import UIKit

/// Apple API limitation (iOS 26/27): UIKit attaches a hidden `_UITypeSelectKeyInput`
/// to large `UIMenu` submenu trees for type-ahead filtering. In the system player's
/// overflow menu (Speed / Audio / Subtitles) that input becomes first responder and
/// summons the soft keyboard over the video. The keyboard is scene-hosted: the app
/// receives no `keyboardWillShow`/`DidShow`, no `UITextField` exists in-process, and
/// resign-first-responder has nothing to act on — verified by probe (iOS 27.0 sim).
/// There is no public opt-out; denying the key input's `becomeFirstResponder` is the
/// only point that prevents the summon while leaving the menu itself fully functional.
/// With a hardware keyboard attached the input is left alone, keeping menu type-ahead.
/// Re-probe on the next SDK: if Apple adds a public switch or stops summoning the
/// soft keyboard for touch, delete this.
@MainActor
enum MenuTypeSelectSuppression {

  private static var installed = false

  /// Installs the swizzle once, from launch (`AppDelegate`). No-ops when the private
  /// class does not exist (older SDKs) so this never breaks on an OS update.
  static func install() {
    guard !installed else { return }
    installed = true

    guard let keyInputClass = objc_getClass("_UITypeSelectKeyInput") as? AnyClass,
          let method = class_getInstanceMethod(keyInputClass, #selector(UIResponder.becomeFirstResponder)) else {
      return
    }

    // The block keeps its own copy of the original implementation, so it reads no
    // shared state from whatever thread UIKit calls it on.
    let original = method_getImplementation(method)
    let block: @convention(block) (AnyObject) -> Bool = { receiver in
      guard GCKeyboard.coalesced != nil else { return false }
      typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
      return unsafeBitCast(original, to: Fn.self)(receiver, #selector(UIResponder.becomeFirstResponder))
    }
    method_setImplementation(method, imp_implementationWithBlock(block))
  }
}
#endif
