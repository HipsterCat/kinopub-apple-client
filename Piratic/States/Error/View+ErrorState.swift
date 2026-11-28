//
//  View+ErrorState.swift
//  Piratic
//
//  Created by Kirill Kunst on 6.08.2023.
//

import Foundation
import SwiftUI
import KinoPubBackend
import PiraticUI

/// Extension for the View protocol to handle error states.
extension View {

  /// Shows a transient bottom toast with the error message. Used for failures that
  /// leave content on screen (a pagination page, an action) — a screen with nothing
  /// to show uses `UnavailableView` instead.
  /// - Parameter state: A binding to the error state.
  /// - Returns: A modified view with error handling.
  func handleError(state: Binding<ErrorHandler.State>) -> some View {
    self.statusToast(isPresented: state.showError, message: state.wrappedValue.error,
                     duration: errorToastDuration)
#if os(iOS)
    // The haptic belongs to the error surfacing, not to any view component —
    // it fires once when the toast appears, only on platforms that have haptics.
    .sensoryFeedback(.error, trigger: state.wrappedValue.showError) { _, shown in shown }
#endif
  }

}

/// How long the error toast stays up. DEBUG `-PIRATICStatusToastSeconds N` holds it
/// for screenshots.
private var errorToastDuration: Swift.Duration {
#if DEBUG
  let seconds = UserDefaults.standard.double(forKey: "PIRATICStatusToastSeconds")
  if seconds > 0 { return .seconds(seconds) }
#endif
  return .seconds(4)
}

extension UnavailableView {

  /// The one load-failure state: the error's own headline, advice and kind
  /// (`Error.loadFailureText`), with Try Again — or Sign In when the session is dead
  /// (`user_banned` / refused grant). `nil` (failure without a captured error) reads
  /// as a connection problem, as it always did.
  init(loadError: Error?,
       isRetrying: Bool = false,
       onRetry: @escaping () -> Void,
       onSignIn: (() -> Void)? = nil) {
    let text = loadError?.loadFailureText ?? LoadFailureText(
      title: "Couldn't Load".localized,
      systemImage: "wifi.exclamationmark",
      message: "Check your connection and try again.".localized,
      detail: nil
    )
    let needsSignIn = (loadError as? APIClientError)?.requiresInteractiveReauthentication == true
      || (loadError as? APIClientError)?.isUserBanned == true
    if needsSignIn {
      self.init(verbatimTitle: text.title,
                systemImage: text.systemImage,
                message: text.message,
                detail: text.detail,
                retryTitle: "Sign In…",
                onRetry: onSignIn ?? onRetry,
                isRetrying: false)
    } else {
      self.init(verbatimTitle: text.title,
                systemImage: text.systemImage,
                message: text.message,
                detail: text.detail,
                retryTitle: "Try Again",
                onRetry: onRetry,
                isRetrying: isRetrying)
    }
  }
}
