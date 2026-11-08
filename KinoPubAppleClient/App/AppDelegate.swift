//
//  AppDelegate.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 24.07.2023.
//

import Foundation
import SwiftUI
#if os(tvOS)
import KinoPubUI
#endif

#if os(iOS)
class AppDelegate: NSObject, UIApplicationDelegate {

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    MenuTypeSelectSuppression.install()
    return true
  }

  /// Relaunched in the background to finish events for a background URLSession.
  func application(_ application: UIApplication,
                   handleEventsForBackgroundURLSession identifier: String,
                   completionHandler: @escaping () -> Void) {
    AppContext.shared.downloadManager.backgroundCompletionHandler = completionHandler
  }
}
#endif

#if os(tvOS)
class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    // After the first scene is up: Search's field and keyboard are ready before
    // the tab is opened. No-op if a later `TVSearchTabModel` already pre-warmed.
    Task { @MainActor in
      TVSearchChrome.prewarm()
    }
    return true
  }
}
#endif

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {

  var window: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // No Safari-style tabs. AppKit merges new windows into the frontmost window's tab
    // group by default, which swallowed the player: it opened as a tab of the library
    // window, wearing that window's back button and title bar, and ⌘W then closed the
    // whole app window instead of the film. A player is not a document you keep several
    // of in one frame.
    NSWindow.allowsAutomaticWindowTabbing = false
  }
}
#endif

#if os(macOS)
import AppKit
import ObjectiveC

/// No sidebar in the app collapses, as none of System Settings' does: Sasha dragged the
/// Settings window's sidebar to zero and could not get it back (2026-11-08). SwiftUI has
/// no switch for it — `navigationSplitViewColumnWidth` is a hint the divider can be
/// dragged past, `.toolbar(removing: .sidebarToggle)` only hides the button, and View ›
/// Hide Sidebar still works. AppKit asks `NSSplitViewItem.canCollapse` for every drag
/// and toggle, and SwiftUI sets it back on its own items, so the getter answers `false`
/// for sidebar items — the same swizzle `system-settings` (Sasha's reference app) installs
/// at launch. Other items (inspectors, content columns) keep their own answer.
///
/// The widths are `MacFixedSidebar`'s (`TabsNavigationView.swift`).
@MainActor
enum SidebarCollapseLock {
  private static var installed = false

  /// Once, from `App.init`, before the first window's split view exists.
  static func install() {
    guard !installed else { return }
    installed = true
    guard let method = class_getInstanceMethod(NSSplitViewItem.self,
                                               #selector(getter: NSSplitViewItem.canCollapse)) else {
      return
    }
    let original = method_getImplementation(method)
    let block: @convention(block) (NSSplitViewItem) -> Bool = { item in
      if item.behavior == .sidebar { return false }
      typealias Fn = @convention(c) (NSSplitViewItem, Selector) -> Bool
      return unsafeBitCast(original, to: Fn.self)(item, #selector(getter: NSSplitViewItem.canCollapse))
    }
    method_setImplementation(method, imp_implementationWithBlock(block))
  }
}
#endif
