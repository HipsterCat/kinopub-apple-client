//
//  SettingsMacChrome.swift
//  KinoPubAppleClient
//
//  System Settings–style detail chrome for our custom Settings window (not the
//  SwiftUI Settings scene): the title, and Back / Forward that walk the window's
//  history — across sidebar panes too, as System Settings' do (Sasha, 2026-11-09).
//  Public API only — no swizzling.
//

import SwiftUI

#if os(macOS)
/// Where the Settings window is: a sidebar pane and what was pushed inside it.
struct SettingsLocation: Hashable {
  var category: SettingsCategory
  var path: [SettingsDetailRoute] = []
}

/// The Settings window's Back / Forward history. Every pane picked in the sidebar and
/// every page pushed is a step; Back and Forward move along them like a browser's.
@Observable
@MainActor
final class SettingsHistory {
  private(set) var current: SettingsLocation
  private var backStack: [SettingsLocation] = []
  private var forwardStack: [SettingsLocation] = []

  init(_ start: SettingsLocation) {
    current = start
  }

  var canGoBack: Bool { !backStack.isEmpty }
  var canGoForward: Bool { !forwardStack.isEmpty }

  func visit(_ location: SettingsLocation) {
    guard location != current else { return }
    backStack.append(current)
    forwardStack.removeAll()
    current = location
  }

  func goBack() {
    guard let previous = backStack.popLast() else { return }
    forwardStack.append(current)
    current = previous
  }

  func goForward() {
    guard let next = forwardStack.popLast() else { return }
    backStack.append(current)
    current = next
  }

  /// Moves without leaving a step (the first pane, chosen once the catalog is known).
  func replace(with location: SettingsLocation) {
    current = location
  }

  /// A path the detail `NavigationStack` wrote: a `NavigationLink(value:)` pushed, or the
  /// stack popped on its own. A pop to where Back would go is Back.
  func stackDidChange(to path: [SettingsDetailRoute]) {
    let next = SettingsLocation(category: current.category, path: path)
    guard next != current else { return }
    if backStack.last == next {
      goBack()
    } else {
      visit(next)
    }
  }
}

extension View {
  /// Every Settings page, root or pushed: its title and the window's Back / Forward.
  /// The stack's own back button is hidden — Back here is the one way back.
  func settingsMacChrome(title: LocalizedStringKey, isRoot: Bool = true) -> some View {
    modifier(SettingsMacChromeModifier(title: title))
  }
}

private struct SettingsMacChromeModifier: ViewModifier {
  let title: LocalizedStringKey
  @Environment(SettingsHistory.self) private var history: SettingsHistory?

  func body(content: Content) -> some View {
    content
      .navigationTitle(title)
      .navigationBarBackButtonHidden(true)
      .toolbar {
        ToolbarItem(placement: .navigation) {
          HStack(spacing: 6) {
            Button("Back", systemImage: "chevron.left") { history?.goBack() }
              .disabled(history?.canGoBack != true)
              .keyboardShortcut("[", modifiers: .command)
              .help("Back")
            Button("Forward", systemImage: "chevron.right") { history?.goForward() }
              .disabled(history?.canGoForward != true)
              .keyboardShortcut("]", modifiers: .command)
              .help("Forward")
          }
        }
      }
  }
}
#endif
