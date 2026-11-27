//
//  AdvancedSettingsPane.swift
//  Piratic
//

import SwiftUI
import PiraticUI
import PiraticMetadata
import KinoPubBackend

#if !os(tvOS)
struct AdvancedSettingsPane: View {
  @AppStorage(DiagnosticsSettings.activityOverlayKey) private var showsActivityOverlay = false
  @AppStorage(DiagnosticsSettings.remoteLoggingKey) private var streamsToPulse = false
  @State private var workerAdminToken = WorkerImageAdminTokenStore.token ?? ""
#if DEBUG && os(macOS)
  @Environment(\.openWindow) private var openWindow
#endif

  var body: some View {
    Form {
      Section {
        NavigationLink("Storage & Data", value: SettingsDetailRoute.storage)
      }

      Section {
        NavigationLink("Network log", value: SettingsDetailRoute.networkLog)
        NavigationLink("Feature flags", value: SettingsDetailRoute.featureFlags)
        Toggle("Show in-flight requests", isOn: $showsActivityOverlay)
        Toggle("Stream to Pulse on Mac", isOn: $streamsToPulse)
#if DEBUG
        NavigationLink("Stream survey", value: SettingsDetailRoute.streamSurvey)
        NavigationLink("Type Styles", value: SettingsDetailRoute.typeStyles)
#endif
      } header: {
        Text("Diagnostics")
      } footer: {
        Text("The log keeps every request with its headers, body and timing for 14 days on this device. Nothing leaves the device unless you switch on streaming; tokens are redacted before they are written either way. Streaming finds the Pulse app on the same network and connects to it — the first time, the system will ask for local network access.")
      }
      .onChange(of: streamsToPulse) { _, isOn in
        NetworkDiagnostics.setRemoteLoggingEnabled(isOn)
      }

      APIHostsSection()

      Section {
        SecureField("Worker admin token", text: $workerAdminToken)
          .textContentType(.password)
          .onSubmit { WorkerImageAdminTokenStore.token = workerAdminToken }
          .onChange(of: workerAdminToken) { _, new in
            WorkerImageAdminTokenStore.token = new
          }
      } header: {
        Text("TMDB proxy admin")
      } footer: {
        Text("Bearer token for POST /admin/* on the metadata worker. Stored in Keychain on this device. When set, the detail page toolbar shows an info button before ⋯.")
      }

#if DEBUG
      Section {
#if os(macOS)
        Button("UI Lab — Adaptable Sidebar") {
          openWindow(id: UILabWindow.id, value: UILabChrome.adaptableSidebar)
        }
        Button("UI Lab — Navigation Split") {
          openWindow(id: UILabWindow.id, value: UILabChrome.navigationSplit)
        }
#else
        NavigationLink("UI Lab — Adaptable Sidebar", value: SettingsDetailRoute.uiLab(.adaptableSidebar))
        NavigationLink("UI Lab — Navigation Split", value: SettingsDetailRoute.uiLab(.navigationSplit))
#endif
        NavigationLink("UI Lab — Library Sidebar", value: SettingsDetailRoute.libraryLab)
        NavigationLink("Player cases", value: SettingsDetailRoute.playerCases)
      } header: {
        Text("UI Lab")
      } footer: {
        Text("DEBUG only. Navigation Split is the current candidate. On Search, switch Filter axis: Accessory Chips (Photos-style glass row under the field) vs Toolbar Menus (Settings-style scope + icon menus).")
      }
#endif
    }
    .formStyle(.grouped)
  }
}

/// The kino.pub API hosts, the one in use, and what each did last. Picking a row makes
/// it the host requests start from; a failure still moves on to the next one.
private struct APIHostsSection: View {
  @State private var snapshot = AppContext.apiHosts.snapshot()

  var body: some View {
    Section {
      ForEach(Array(snapshot.hosts.enumerated()), id: \.element.id) { index, host in
        Button {
          AppContext.apiHosts.select(host)
          snapshot = AppContext.apiHosts.snapshot()
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(verbatim: host.label)
                .foregroundStyle(.primary)
              Text(APIHostStatusText.outcome(snapshot.outcomes[host.id]))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if index == snapshot.currentIndex {
              Image(systemName: "checkmark")
                .foregroundStyle(.tint)
                .accessibilityLabel(Text("In use"))
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    } header: {
      Text("API server")
    } footer: {
      Text(APIHostStatusText.footer(snapshot))
    }
    .onReceive(NotificationCenter.default.publisher(for: APIHostPool.didChangeNotification)) { _ in
      snapshot = AppContext.apiHosts.snapshot()
    }
  }
}
#endif

/// Shared by the iOS / macOS section and the tvOS row.
enum APIHostStatusText {
  static func outcome(_ outcome: APIHostPool.Outcome?) -> String {
    guard let outcome else { return String(localized: "Not used yet") }
    let time = outcome.date.formatted(date: .omitted, time: .shortened)
    switch outcome.kind {
    case .answered(let status):
      return String(localized: "Answered \(status) at \(time)")
    case .failed(let reason):
      return String(localized: "Failed (\(reason)) at \(time)")
    }
  }

  static func footer(_ snapshot: APIHostPool.Snapshot) -> String {
    let rule = String(localized: "Requests go to the checked server. When it cannot be reached or answers 502–504, the request moves to the next one, and the server that answers stays in use, after a relaunch too.")
    guard let last = snapshot.lastSwitch else { return rule }
    let time = last.date.formatted(date: .abbreviated, time: .shortened)
    return rule + "\n" + String(localized: "Last switch: \(last.from) → \(last.to) (\(last.reason)), \(time).")
  }
}
