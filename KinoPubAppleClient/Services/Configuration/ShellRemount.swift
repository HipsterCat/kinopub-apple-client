//
//  ShellRemount.swift
//  KinoPubAppleClient
//
//  Blocking full-screen loader → prepare → recreate the root scene. Used when the
//  interface language changes and when launch-time feature flags need a clean
//  shell (tabs, TVUIKit hosts, sidebar) without quitting the process.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class ShellRemount {
  static let shared = ShellRemount()

  /// Bumped to recreate `RootView` (and embedded TVUIKit hosts).
  private(set) var remountID = UUID()

  /// Full-screen blocking loader while the remount runs.
  private(set) var isApplying = false

  /// Attached from the app scene — lives for the process.
  weak var navigation: NavigationState?

  private init() {}

  /// Freeze UI → run `prepare` → clear stacks → remount → resume.
  func run(prepare: @MainActor () -> Void = {}) async {
    guard !isApplying else { return }
    isApplying = true
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(120))

    prepare()
    navigation?.clearStacksForShellRemount()

    remountID = UUID()
    try? await Task.sleep(for: .milliseconds(280))
    isApplying = false
  }
}

extension View {
  /// Pins the interface locale and remounts the root when `ShellRemount` bumps.
  func kinopubAppLanguage(_ language: AppLanguage) -> some View {
    modifier(KinopubShellLocaleModifier(language: language, remount: .shared))
  }
}

private struct KinopubShellLocaleModifier: ViewModifier {
  @Bindable var language: AppLanguage
  @Bindable var remount: ShellRemount

  func body(content: Content) -> some View {
    ZStack {
      content
        .environment(\.locale, language.locale)
        .id(remount.remountID)
        .allowsHitTesting(!remount.isApplying)

      if remount.isApplying {
        ShellRemountOverlay()
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.2), value: remount.isApplying)
  }
}

/// System-style freeze: dimmed veil + spinner.
private struct ShellRemountOverlay: View {
  var body: some View {
    ZStack {
      Color.black.opacity(0.45)
        .ignoresSafeArea()
      ProgressView()
        .controlSize(.large)
#if os(tvOS)
        .tint(.white)
#endif
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text("Loading"))
  }
}
