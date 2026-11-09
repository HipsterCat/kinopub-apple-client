//
//  IntegrationsSettingsPane.swift
//  KinoPubAppleClient
//
//  Settings › Integrations on macOS, iOS and iPadOS, laid out like macOS Internet
//  Accounts: one row per source with its icon and state, each opening a page to add
//  one's own key, switch it off or read about the source. The catalog is `Integration`;
//  tvOS draws the same one through TVSettingKit (`TVSettingsCatalog.dataSourcesSections`).
//
//  Rows carry no subtitle: in Internet Accounts the subtitle lists what is switched on
//  inside an account, and nothing here can be switched per item yet (Sasha, 2026-11-09).
//

import SwiftUI

#if !os(tvOS)
struct IntegrationsSettingsPane: View {
  // The rows' states are read from these; observing them redraws the list when a page
  // adds a key or switches it off.
  @AppStorage(IntegrationKeyProvider.kinopoisk.validatedDefaultsKey) private var kinopoiskValidated = false
  @AppStorage(IntegrationKeyProvider.kinopoisk.enabledDefaultsKey) private var kinopoiskEnabled = true
  @AppStorage(IntegrationKeyProvider.tmdb.validatedDefaultsKey) private var tmdbValidated = false
  @AppStorage(IntegrationKeyProvider.tmdb.enabledDefaultsKey) private var tmdbEnabled = true
  @AppStorage(TraktAccount.usernameDefaultsKey) private var traktUsername: String?

  var body: some View {
    let _ = (kinopoiskValidated, kinopoiskEnabled, tmdbValidated, tmdbEnabled, traktUsername)
    Form {
      Section {
        ForEach(Integration.available) { integration in
          NavigationLink(value: SettingsDetailRoute.integration(integration)) {
            IntegrationRowLabel(integration: integration)
          }
        }
      } header: {
        Text("Available")
      }

      Section {
        ForEach(Integration.additional) { integration in
          // A source that cannot be connected yet: the row is there, disabled.
          NavigationLink(value: SettingsDetailRoute.integration(integration)) {
            IntegrationRowLabel(integration: integration)
          }
          .disabled(!integration.isSupported)
        }
      } header: {
        Text("Integrations_Section_Additional")
      }
    }
    .formStyle(.grouped)
  }
}

/// Icon and name; the state on the trailing edge for sources that work.
private struct IntegrationRowLabel: View {
  let integration: Integration
  @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 32

  var body: some View {
    HStack(spacing: 12) {
      IntegrationIconView(integration: integration, size: iconSize)
      Text(verbatim: integration.name)
      Spacer(minLength: 8)
      if integration.status.isShownInList {
        Text(verbatim: integration.status.title)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// One source's page: who it is, the viewer's own key and its switch.
struct IntegrationDetailView: View {
  let integration: Integration

  @StateObject private var keyModel: IntegrationKeySettingsModel
  @AppStorage private var keyValidated: Bool
  /// Kinopoisk: use the key. TMDB: ask TMDB directly with it (the proxy switch's inverse).
  @AppStorage private var keyEnabled: Bool
  @Environment(\.openURL) private var openURL

  @State private var isEnteringKey = false
  @State private var keyDraft = ""
  /// Set when Verify failed: the alert comes back saying why.
  @State private var keyFailure: String?
  @State private var isShowingHelp = false
  @State private var isConfirmingDisconnect = false
  @State private var isSigningIn = false
  @AppStorage(TraktAccount.usernameDefaultsKey) private var traktUsername: String?
  @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 44

  init(integration: Integration) {
    self.integration = integration
    let provider = integration.keyProvider ?? .kinopoisk
    _keyModel = StateObject(wrappedValue: IntegrationKeySettingsModel(keyProvider: provider, integration: integration))
    _keyValidated = AppStorage(wrappedValue: false, provider.validatedDefaultsKey)
    _keyEnabled = AppStorage(wrappedValue: true, provider.enabledDefaultsKey)
  }

  private var hasKey: Bool { integration.keyProvider != nil && keyValidated }
  private var isAccount: Bool { integration.connection == .account }
  /// A key added, or an account signed in to.
  private var isConnected: Bool { isAccount ? traktUsername != nil : hasKey }

  private var status: Integration.Status {
    _ = (keyValidated, keyEnabled, traktUsername)
    return integration.status
  }

  var body: some View {
    Form {
      // The description continues the header's group, secondary, as a second row.
      Section {
        header
        Text(verbatim: integration.about)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        ForEach(integration.notes, id: \.self) { note in
          Text(verbatim: note.text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      } footer: {
        if integration != .tmdb, !hasKey || isAccount {
          actions
        }
      }

      if integration == .tmdb {
        Section {
          Toggle("KinoPub proxy", isOn: proxyBinding)
            .disabled(!hasKey)
        } footer: {
          VStack(alignment: .leading, spacing: 8) {
            Text(hasKey ? "Integration_TMDB_ProxyFooter" : "Integration_TMDB_ProxyFooter_NoKey")
            actions
          }
        }
      } else if hasKey, !isAccount {
        Section {
          Toggle("Integration_Status_APIKey", isOn: $keyEnabled)
        } footer: {
          VStack(alignment: .leading, spacing: 8) {
            Text("Integration_KeyToggle_Footer")
            actions
          }
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
      String(format: (isAccount ? "Sign out of %@?" : "Disconnect %@?").localized, integration.name),
      isPresented: $isConfirmingDisconnect
    ) {
      if isAccount {
        Button("Sign Out", role: .destructive) {
          TraktAccount.shared.signOut()
        }
      } else {
        Button("Disconnect", role: .destructive) {
          keyModel.disconnect()
        }
      }
    } message: {
      Text(isAccount ? "Integration_SignOut_Message" : "Integration_Disconnect_Message")
    }
    .sheet(isPresented: $isSigningIn) {
      TraktSignInView()
    }
  }

  /// The TMDB proxy switch: on is the default path; off asks TMDB with the viewer's key.
  private var proxyBinding: Binding<Bool> {
    Binding(
      get: { !hasKey || !keyEnabled },
      set: { keyEnabled = !$0 }
    )
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: 12) {
      IntegrationIconView(integration: integration, size: iconSize)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: integration.name)
          .font(.headline)
        HStack(spacing: 6) {
          if keyModel.validationState == .checking {
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
    if status == .apiKey, keyModel.validationState == .validButQuotaExceeded {
      return "Integration_Status_APIKey_Quota".localized
    }
    return status.title
  }

  // MARK: Actions

  /// Under the last group, as Internet Accounts puts Delete Account… and its "?".
  private var actions: some View {
    HStack {
      if isAccount {
        if isConnected {
          Button("Sign Out…") { isConfirmingDisconnect = true }
        } else {
          Button("Sign In…") { isSigningIn = true }
            .disabled(!integration.isSupported)
        }
      } else if hasKey {
        Button("Change Key…") { beginKeyEntry() }
        Button("Disconnect…") { isConfirmingDisconnect = true }
      } else {
        Button("Add Key…") { beginKeyEntry() }
          .disabled(!integration.isSupported || keyModel.validationState == .checking)
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
    case .tmdb: "Integration_TMDB_KeyPrompt".localized
    default: integration.connectHelp
    }
  }

  private func beginKeyEntry() {
    keyFailure = nil
    keyDraft = ""
    isEnteringKey = true
  }

  private func verify() async {
    guard integration.keyProvider != nil else { return }
    await keyModel.check(key: keyDraft)
    if let failure = keyModel.failureText {
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
