//
//  FeatureFlagsView.swift
//  KinoPubAppleClient
//
//  Settings › Diagnostics › Feature flags on iOS and macOS. The tvOS page is
//  `TVFeatureFlagsPage` in `TVProfileSettingsView`, built from the same `FeatureFlag` list.
//

import SwiftUI

#if !os(tvOS)
struct FeatureFlagsView: View {
  /// Mirrors what is stored, so the switches and the Apply row redraw.
  @State private var values = Self.storedValues()

  private let flags = FeatureFlag.allCases.filter(\.isRelevantHere)

  private var hasPendingApply: Bool {
    flags.contains { $0.appliesAtLaunch && values[$0] != $0.isEnabled }
  }

  var body: some View {
    Form {
      flagSection(appliesAtLaunch: true)
      flagSection(appliesAtLaunch: false)

      Section {
        if hasPendingApply {
          Button("Apply") {
            Task {
              await FeatureFlag.applyPendingAsync()
              values = Self.storedValues()
            }
          }
        }
        Button("Reset to defaults", role: .destructive) {
          FeatureFlag.resetAll()
          values = Self.storedValues()
        }
      } footer: {
        Text("Stored on this device only. A build ships with the defaults. Shell switches need Apply — the interface rebuilds without quitting.")
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
      Text(appliesAtLaunch ? "Needs apply" : "Applies when next opened")
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
