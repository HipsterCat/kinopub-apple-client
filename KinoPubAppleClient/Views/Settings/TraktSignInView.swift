//
//  TraktSignInView.swift
//  KinoPubAppleClient
//
//  Signing in to an account with a code, on every platform: the code is shown here and
//  entered on the service's site on a phone or computer (trakt.tv/activate, plex.tv/link).
//  The sheet closes itself once the service confirms. A sheet on macOS / iOS, presented
//  over Settings on tvOS.
//

import SwiftUI
import KinoPubUI

/// Where a code sign-in stands: shared by Trakt's device code and Plex's PIN.
enum AccountSignIn: Equatable {
  case idle
  case requestingCode
  /// Waiting for the viewer to enter `code` at `url` on another device.
  case awaitingUser(code: String, url: URL, expiresAt: Date)
  case failed(String)
}

/// An account the app signs in to with a code entered elsewhere.
@MainActor
protocol AccountSigningIn: AnyObject, Observable {
  var signIn: AccountSignIn { get }
  var isSignedIn: Bool { get }
  func startSignIn()
  func cancelSignIn()
  func signOut()
}

/// Trakt's device code and Plex's PIN on the shared code sign-in screen
/// (`DeviceCodeSignInView`), the one kino.pub's own activation uses.
struct AccountSignInView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  let integration: Integration
  private let account: any AccountSigningIn
  @State private var hudToast: HudToast?
  /// When the code on screen arrived: the start of the ring.
  @State private var codeShownAt = Date()

  init(integration: Integration) {
    self.integration = integration
    self.account = integration.account ?? TraktAccount.shared
  }

  var body: some View {
    DeviceCodeSignInView(
      title: integration == .trakt ? "Trakt_SignIn_Title".localized
        : String(format: "Account_SignIn_Title".localized, integration.name),
      message: "Account_SignIn_Instructions".localized,
      activateTitle: "Auth_Activate".localized,
      state: state,
      // Plex PINs are four characters, Trakt codes eight.
      placeholderTiles: integration == .plex ? 4 : 8,
      shareURL: awaiting?.url ?? URL(string: "https://\(integration.host)")!,
      shareMessage: String(format: "Account_SignIn_ShareMessage %@ %@ %@".localized,
                           integration.name, state.displayURL, state.code),
      actions: .init(
        copy: copyCode,
        activate: {
          guard let url = awaiting?.url else { return }
          copyCode()
          openURL(url)
        },
        newCode: { account.startSignIn() },
        retry: { account.startSignIn() },
        close: {
          account.cancelSignIn()
          dismiss()
        }
      )
    ) {
      if let mark = integration.markImage {
        DeviceCodeSignInLogo(image: mark)
      } else {
        IntegrationIconView(integration: integration, size: DeviceCodeSignInLogo.baseSide)
      }
    }
    .hudToast($hudToast)
#if os(macOS)
    .frame(width: 480)
#endif
    .task {
      switch account.signIn {
      case .awaitingUser, .requestingCode: break
      default: account.startSignIn()
      }
    }
    .onChange(of: awaiting?.code, initial: true) { _, _ in
      codeShownAt = Date()
    }
    .onChange(of: account.isSignedIn) { _, signedIn in
      if signedIn { dismiss() }
    }
#if os(tvOS)
    // No cross on Apple TV: Menu closes the page, and stops asking the service.
    .onDisappear {
      if !account.isSignedIn { account.cancelSignIn() }
    }
#endif
  }

  private var awaiting: (code: String, url: URL, expiresAt: Date)? {
    if case .awaitingUser(let code, let url, let expiresAt) = account.signIn {
      return (code, url, expiresAt)
    }
    return nil
  }

  private var state: DeviceCodeSignInState {
    switch account.signIn {
    case .idle, .requestingCode:
      return DeviceCodeSignInState(isBusy: true)
    case .awaitingUser(let code, let url, let expiresAt):
      return DeviceCodeSignInState(
        code: code,
        displayURL: displayHost(url),
        validRange: min(codeShownAt, expiresAt)...expiresAt
      )
    case .failed(let message):
      return DeviceCodeSignInState(errorMessage: message)
    }
  }

  private func copyCode() {
    guard let code = awaiting?.code else { return }
    DeviceCodePasteboard.copy(code)
    hudToast = HudToast(systemImage: "document.on.document.fill", title: "Copied".localized)
  }

  private func displayHost(_ url: URL) -> String {
    let host = url.host()?.replacingOccurrences(of: "www.", with: "") ?? integration.host
    let path = url.path()
    return path.isEmpty || path == "/" ? host : host + path
  }
}
