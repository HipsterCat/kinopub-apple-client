//
//  FeatureFlagsView.swift
//  KinoPubAppleClient
//
//  Settings › Diagnostics › Feature flags on iOS and macOS. The tvOS page is
//  `TVFeatureFlagsPage` in `TVProfileSettingsView`, built from the same `FeatureFlag` list.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

extension FeatureFlag {
  /// A launch-time switch only takes hold on the next launch, and on tvOS there is no
  /// quick way to get one — so the list offers to quit. Not an App Store pattern; this
  /// build does not go there.
  @MainActor
  static func quitToApply() {
#if os(macOS)
    NSApplication.shared.terminate(nil)
#else
    exit(0)
#endif
  }
}

#if !os(tvOS)
struct FeatureFlagsView: View {
  /// Mirrors what is stored, so the switches and the "quit to apply" row redraw.
  @State private var values = Self.storedValues()

  private let flags = FeatureFlag.allCases.filter(\.isRelevantHere)

  var body: some View {
    Form {
      flagSection(appliesAtLaunch: true)
      flagSection(appliesAtLaunch: false)

      Section {
        if flags.contains(where: { $0.appliesAtLaunch && values[$0] != $0.isEnabled }) {
          Button("Quit to apply") { FeatureFlag.quitToApply() }
        }
        Button("Reset to defaults", role: .destructive) {
          FeatureFlag.resetAll()
          values = Self.storedValues()
        }
      } footer: {
        Text("Stored on this device only. A build ships with the defaults.")
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Feature flags")
  }

  private func flagSection(appliesAtLaunch: Bool) -> some View {
    Section {
      ForEach(flags.filter { $0.appliesAtLaunch == appliesAtLaunch }) { flag in
        Toggle(isOn: binding(for: flag)) {
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: flag.title)
            Text(verbatim: caption(for: flag))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    } header: {
      Text(appliesAtLaunch ? "Applies on next launch" : "Applies when next opened")
    }
  }

  private func caption(for flag: FeatureFlag) -> String {
    guard values[flag] != flag.defaultValue else { return flag.summary }
    return flag.summary + " Ships " + (flag.defaultValue ? "on." : "off.")
  }

  private func binding(for flag: FeatureFlag) -> Binding<Bool> {
    Binding(
      get: { values[flag] ?? flag.defaultValue },
      set: { isOn in
        flag.set(isOn)
        values[flag] = isOn
      }
    )
  }

  private static func storedValues() -> [FeatureFlag: Bool] {
    Dictionary(uniqueKeysWithValues: FeatureFlag.allCases.map { ($0, $0.storedValue) })
  }
}

#Preview {
  NavigationStack { FeatureFlagsView() }
}
#endif
