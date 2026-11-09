//
//  TraktSignInView.swift
//  KinoPubAppleClient
//
//  Signing in to Trakt with a device code, on every platform: the code is shown here
//  and entered at trakt.tv/activate on a phone or computer. The sheet closes itself
//  once Trakt confirms. A sheet on macOS / iOS, presented over Settings on tvOS.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct TraktSignInView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 64
  private let account = TraktAccount.shared

  var body: some View {
    VStack(spacing: 20) {
      IntegrationIconView(integration: .trakt, size: iconSize)
      Text("Trakt_SignIn_Title")
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
          Text("Trakt_SignIn_Waiting")
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
    let host = url.host()?.replacingOccurrences(of: "www.", with: "") ?? "trakt.tv"
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
