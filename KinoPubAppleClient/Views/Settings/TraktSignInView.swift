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
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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

struct AccountSignInView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 64
  let integration: Integration
  private let account: any AccountSigningIn

  init(integration: Integration) {
    self.integration = integration
    self.account = integration.account ?? TraktAccount.shared
  }

  var body: some View {
    VStack(spacing: 20) {
      IntegrationIconView(integration: integration, size: iconSize)
      Text(verbatim: integration == .trakt ? "Trakt_SignIn_Title".localized
           : String(format: "Account_SignIn_Title".localized, integration.name))
        .font(.title2.weight(.bold))

      content
        .frame(maxWidth: .infinity)

      Button("Cancel", role: .cancel) {
        account.cancelSignIn()
        dismiss()
      }
#if !os(tvOS)
      .keyboardShortcut(.cancelAction)
#endif
    }
    .multilineTextAlignment(.center)
    .padding(32)
#if os(macOS)
    .frame(width: 420)
#endif
    .task {
      switch account.signIn {
      case .awaitingUser, .requestingCode: break
      default: account.startSignIn()
      }
    }
    .onChange(of: account.isSignedIn) { _, signedIn in
      if signedIn { dismiss() }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch account.signIn {
    case .idle, .requestingCode:
      ProgressView()
    case .awaitingUser(let code, let url, _):
      VStack(spacing: 16) {
        Text(String(format: "Trakt_SignIn_Instructions".localized, displayHost(url)))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Text(verbatim: code)
          .font(.system(.largeTitle, design: .monospaced).weight(.bold))
#if !os(tvOS)
          .textSelection(.enabled)
#endif
          .accessibilityLabel(code.map(String.init).joined(separator: " "))
#if !os(tvOS)
        Button(String(format: "Open %@".localized, displayHost(url))) {
          copy(code)
          openURL(url)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        Text("Trakt_SignIn_CodeCopied")
          .font(.footnote)
          .foregroundStyle(.secondary)
#endif
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text(verbatim: integration == .trakt ? "Trakt_SignIn_Waiting".localized
               : String(format: "Account_SignIn_Waiting".localized, integration.name))
        }
        .font(.callout)
        .foregroundStyle(.secondary)
      }
    case .failed(let message):
      VStack(spacing: 12) {
        Text(verbatim: message)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Button("Try Again") { account.startSignIn() }
      }
    }
  }

  private func displayHost(_ url: URL) -> String {
    let host = url.host()?.replacingOccurrences(of: "www.", with: "") ?? integration.host
    let path = url.path()
    return path.isEmpty || path == "/" ? host : host + path
  }

  private func copy(_ code: String) {
#if os(iOS)
    UIPasteboard.general.string = code
#elseif os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(code, forType: .string)
#endif
  }
}
