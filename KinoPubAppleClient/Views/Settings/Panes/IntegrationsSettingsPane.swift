//
//  IntegrationsSettingsPane.swift
//  KinoPubAppleClient
//
//  Settings › Integrations on macOS, iOS and iPadOS, laid out like macOS Internet
//  Accounts: one row per source with its icon and state, each opening a page to connect,
//  switch off or read about it. The catalog is `Integration`; tvOS draws the same one
//  through TVSettingKit (`TVSettingsCatalog.integrationsSections`).
//

import SwiftUI

#if !os(tvOS)
struct IntegrationsSettingsPane: View {
  // The rows' states are read from these; observing them redraws the list when a page
  // connects or switches a source off.
  @AppStorage(KinopoiskKeyValidation.defaultsKey) private var kinopoiskValidated = false
  @AppStorage(KinopoiskKeyValidation.enabledKey) private var kinopoiskEnabled = true

  var body: some View {
    let _ = (kinopoiskValidated, kinopoiskEnabled)
    Form {
      Section {
        ForEach(Integration.supported) { row($0) }
      } footer: {
        Text("Integrations_Footer")
      }

      Section {
        ForEach(Integration.upcoming) { row($0) }
      } header: {
        Text("Coming soon")
      }
    }
    .formStyle(.grouped)
  }

  private func row(_ integration: Integration) -> some View {
    NavigationLink(value: SettingsDetailRoute.integration(integration)) {
      IntegrationRowLabel(integration: integration)
    }
  }
}

/// Icon, name, what the source gives; its state on the trailing edge.
private struct IntegrationRowLabel: View {
  let integration: Integration
  @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 32

  var body: some View {
    HStack(spacing: 12) {
      IntegrationIconView(integration: integration, size: iconSize)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: integration.name)
        Text(verbatim: integration.summary)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      if integration.isSupported {
        Text(verbatim: integration.status.title)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// One source's page: who it is, what it gives, and connecting it.
struct IntegrationDetailView: View {
  let integration: Integration

  @StateObject private var kinopoisk: KinopoiskKeySettingsModel
  @AppStorage(KinopoiskKeyValidation.defaultsKey) private var kinopoiskValidated = false
  @AppStorage(KinopoiskKeyValidation.enabledKey) private var kinopoiskEnabled = true
  @Environment(\.openURL) private var openURL

  @State private var isEnteringKey = false
  @State private var keyDraft = ""
  /// Set when Verify failed: the alert comes back saying why.
  @State private var keyFailure: String?
  @State private var isShowingHelp = false
  @State private var isConfirmingDisconnect = false
  @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 44

  init(integration: Integration, keyProvider: KinopoiskKeyProvider) {
    self.integration = integration
    _kinopoisk = StateObject(wrappedValue: KinopoiskKeySettingsModel(keyProvider: keyProvider))
  }

  private var status: Integration.Status {
    _ = (kinopoiskValidated, kinopoiskEnabled)
    return integration.status
  }

  private var isConnected: Bool { status == .connected || status == .off }

  var body: some View {
    Form {
      Section {
        header
      }

      Section {
        Text(verbatim: integration.about)
          .fixedSize(horizontal: false, vertical: true)
        ForEach(integration.notes, id: \.self) { note in
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: note.title)
            Text(verbatim: note.text)
              .font(.callout)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      } footer: {
        if !isConnected {
          actions
        }
      }

      if integration == .kinopoisk, isConnected {
        Section {
          Toggle("Use on title pages", isOn: $kinopoiskEnabled)
        } footer: {
          actions
        }
      }
    }
    .formStyle(.grouped)
    .alert(String(format: "Connect %@".localized, integration.name), isPresented: $isEnteringKey) {
      SecureField("API key", text: $keyDraft)
#if os(iOS)
        .textContentType(.password)
#endif
      Button("Cancel", role: .cancel) {
        keyFailure = nil
      }
      Button("Verify", role: .confirm) {
        Task { await verify() }
      }
      .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    } message: {
      Text(verbatim: keyFailure ?? keyPrompt)
    }
    .confirmationDialog(
      String(format: "Disconnect %@?".localized, integration.name),
      isPresented: $isConfirmingDisconnect
    ) {
      Button("Disconnect", role: .destructive) {
        kinopoisk.disconnect()
      }
    } message: {
      Text("Integration_Disconnect_Message")
    }
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: 12) {
      IntegrationIconView(integration: integration, size: iconSize)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: integration.name)
          .font(.headline)
        HStack(spacing: 6) {
          if kinopoisk.validationState == .checking, integration == .kinopoisk {
            ProgressView()
              .controlSize(.small)
            Text("Checking…")
          } else {
            Text(verbatim: statusLine)
          }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Button("Learn More…") { openURL(integration.website) }
        .help(integration.website.absoluteString)
    }
  }

  private var statusLine: String {
    if integration == .kinopoisk, status == .connected,
       kinopoisk.validationState == .validButQuotaExceeded {
      return "Connected · today's quota is used up".localized
    }
    return status.title
  }

  // MARK: Actions

  /// Under the last group, as Internet Accounts puts Delete Account… and its "?".
  private var actions: some View {
    HStack {
      switch integration.connection {
      case .builtIn:
        EmptyView()
      case .apiKey, .account:
        if isConnected {
          Button("Change Key…") { beginKeyEntry() }
          Button("Disconnect…") { isConfirmingDisconnect = true }
        } else {
          Button(integration.connection == .account ? "Sign In…" : "Connect…") { beginKeyEntry() }
            .disabled(!integration.isSupported || kinopoisk.validationState == .checking)
        }
      }
      Spacer()
      helpButton
    }
    .padding(.top, 8)
  }

  @ViewBuilder
  private var helpButton: some View {
#if os(macOS)
    HelpLink { isShowingHelp = true }
      .popover(isPresented: $isShowingHelp, arrowEdge: .bottom) { help }
#else
    Button {
      isShowingHelp = true
    } label: {
      Image(systemName: "questionmark")
    }
    .buttonStyle(.bordered)
    .buttonBorderShape(.circle)
    .accessibilityLabel("Help")
    .popover(isPresented: $isShowingHelp) {
      help.presentationCompactAdaptation(.popover)
    }
#endif
  }

  private var help: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(verbatim: integration.name)
        .font(.headline)
      Text(verbatim: integration.connectHelp)
        .fixedSize(horizontal: false, vertical: true)
      if let keyURL = integration.keyURL {
        Link(String(format: "Get a key at %@".localized, keyURL.host() ?? integration.host),
             destination: keyURL)
      }
      Link(integration.host, destination: integration.website)
    }
    .padding()
    .frame(idealWidth: 340, maxWidth: 380, alignment: .leading)
  }

  private var keyPrompt: String {
    switch integration {
    case .kinopoisk: "Integration_Kinopoisk_KeyPrompt".localized
    default: integration.connectHelp
    }
  }

  private func beginKeyEntry() {
    keyFailure = nil
    keyDraft = ""
    isEnteringKey = true
  }

  private func verify() async {
    guard integration == .kinopoisk else { return }
    await kinopoisk.check(key: keyDraft)
    if let failure = kinopoisk.failureText {
      // Back to the alert, the key still in the field, with why it failed.
      keyFailure = failure
      isEnteringKey = true
    } else {
      keyFailure = nil
      keyDraft = ""
    }
  }
}
#endif
