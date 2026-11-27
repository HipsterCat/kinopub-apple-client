//
//  AppDelegate.swift
//  Piratic
//
//  Created by Kirill Kunst on 24.07.2023.
//

import Foundation
import SwiftUI
#if os(tvOS)
import PiraticUI
#endif

#if os(iOS)
class AppDelegate: NSObject, UIApplicationDelegate {

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    MenuTypeSelectSuppression.install()
    return true
  }

  /// Woken (or relaunched) in the background for a download session's events. The handler
  /// goes to the session it names, and that session is reconnected so the events are
  /// delivered at all: both are created lazily, and a session nobody creates hears
  /// nothing — the HLS one never got its handler, and a finished film went unrecorded.
  func application(_ application: UIApplication,
                   handleEventsForBackgroundURLSession identifier: String,
                   completionHandler: @escaping () -> Void) {
    let context = AppContext.shared
    if identifier == HLSAssetDownloadManager.sessionIdentifier {
      context.hlsDownloadManager.backgroundCompletionHandler = completionHandler
      context.hlsDownloadManager.connect()
    } else {
      context.downloadManager.backgroundCompletionHandler = completionHandler
      _ = context.downloadManager.session
    }
  }
}
#endif

#if os(tvOS)
class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    // After the first scene is up: Search's stack is loaded before the tab is
    // opened. No-op if the tab already took it, or a later `TVSearchTabModel`
    // already pre-warmed.
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
    // Finder-style tabs on the library WindowGroup (KP-105). The player, Settings,
    // About and Activity scenes set `tabbingMode = .disallowed` so they never join a
    // library tab group — that merge used to swallow the player into the library
    // window (back button + title bar of the wrong scene; ⌘W closed everything).
    NSWindow.allowsAutomaticWindowTabbing = true
  }

  /// Recently played titles above the Dock menu's window list, as IINA has them.
  @MainActor
  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    RecentPlaybacks.shared.dockMenu()
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
