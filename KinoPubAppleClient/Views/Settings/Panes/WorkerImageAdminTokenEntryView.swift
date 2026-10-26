//
//  WorkerImageAdminTokenEntryView.swift
//

import SwiftUI
import KinoPubUI

/// Bearer token for TMDB proxy `POST /admin/*`. Keychain on this device only.
struct WorkerImageAdminTokenEntryView: View {
#if os(tvOS)
  @Environment(\.dismiss) private var dismiss
#endif
  @State private var token = WorkerImageAdminTokenStore.token ?? ""

  var body: some View {
#if os(tvOS)
    WorkerAdminTextEntryViewControllerRepresentable(
      initialText: token,
      onCommit: { text in
        let filtered = WorkerAdminTokenSanitizer.filter(text)
        WorkerImageAdminTokenStore.token = filtered.isEmpty ? nil : filtered
        dismiss()
      },
      onCancel: { dismiss() }
    )
    .ignoresSafeArea()
#else
    iosMacBody
#endif
  }

  private var iosMacBody: some View {
    Form {
      Section {
        SecureField("Bearer token", text: $token)
          .textContentType(.password)
      } footer: {
        Text("Bearer token for POST /admin/* on the metadata worker. Stored in Keychain on this device.")
      }
    }
    .navigationTitle("Worker admin token")
    .onChange(of: token) { _, new in
      token = WorkerAdminTokenSanitizer.filter(new)
      WorkerImageAdminTokenStore.token = token
    }
  }
}

#if os(tvOS)
private struct WorkerAdminTextEntryViewControllerRepresentable: UIViewControllerRepresentable {
  let initialText: String
  let onCommit: (String) -> Void
  let onCancel: () -> Void

  func makeUIViewController(context: Context) -> WorkerAdminTextEntryViewController {
    WorkerAdminTextEntryViewController(
      initialText: initialText,
      onCommit: onCommit,
      onCancel: onCancel
    )
  }

  func updateUIViewController(_ uiViewController: WorkerAdminTextEntryViewController, context: Context) {}
}
#endif

enum WorkerAdminTokenSanitizer {
  /// Bearer tokens and worker picks: ASCII letters, digits, `_-._`
  static func filter(_ raw: String) -> String {
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.")
    return String(raw.unicodeScalars.filter { allowed.contains($0) })
  }
}
