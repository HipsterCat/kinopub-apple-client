//
//  UnavailableView.swift
//

import SwiftUI

/// The one unavailable-content state, built on the system `ContentUnavailableView`:
/// symbol, title, optional description, optional actions. Used for load failures
/// (retry button included), empty lists and empty searches alike — same look
/// everywhere, no hand-styled stand-ins.
///
/// Full-screen only when there is no content to show. A failed page deep in a
/// paginated grid never swaps loaded items for this view — it surfaces as a toast
/// plus an inline retry at the bottom of the grid.
public struct UnavailableView: View {

  private let title: Text
  private let systemImage: String
  private let message: String?
  /// A second, quieter line under the message: what exactly failed (`HTTP 502 · bad
  /// gateway`), for the viewer to quote back.
  private let detail: String?
  private let retryTitle: LocalizedStringKey?
  private let onRetry: (() -> Void)?
  private let secondaryTitle: LocalizedStringKey?
  private let onSecondary: (() -> Void)?

  /// The remote needs somewhere to land when this is the only thing on screen.
  @FocusState private var retryFocused: Bool

  public init(
    title: LocalizedStringKey,
    systemImage: String,
    message: String? = nil,
    detail: String? = nil,
    retryTitle: LocalizedStringKey? = nil,
    onRetry: (() -> Void)? = nil,
    secondaryTitle: LocalizedStringKey? = nil,
    onSecondary: (() -> Void)? = nil
  ) {
    self.title = Text(title)
    self.systemImage = systemImage
    self.message = message
    self.detail = detail
    self.retryTitle = retryTitle
    self.onRetry = onRetry
    self.secondaryTitle = secondaryTitle
    self.onSecondary = onSecondary
  }

  /// For a headline the caller has already localized (a load failure's own words).
  public init(
    verbatimTitle: String,
    systemImage: String,
    message: String? = nil,
    detail: String? = nil,
    retryTitle: LocalizedStringKey? = nil,
    onRetry: (() -> Void)? = nil
  ) {
    self.title = Text(verbatim: verbatimTitle)
    self.systemImage = systemImage
    self.message = message
    self.detail = detail
    self.retryTitle = retryTitle
    self.onRetry = onRetry
    self.secondaryTitle = nil
    self.onSecondary = nil
  }

  public var body: some View {
    ContentUnavailableView {
      Label { title } icon: { Image(systemName: systemImage) }
    } description: {
      VStack(spacing: 8) {
        if let message {
          Text(message)
        }
        if let detail {
          Text(verbatim: detail)
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.tertiary)
#if !os(tvOS)
            .textSelection(.enabled)
#endif
        }
      }
    } actions: {
      HStack(spacing: 16) {
        if let retryTitle, let onRetry {
          Button(retryTitle, action: onRetry)
            .focused($retryFocused)
            .accessibilityIdentifier("kinopub.unavailable.retry")
#if !os(tvOS)
            .buttonStyle(.glass)
            .controlSize(.large)
#endif
        }

        if let secondaryTitle, let onSecondary {
          Button(secondaryTitle, action: onSecondary)
#if !os(tvOS)
            .buttonStyle(.glass)
            .controlSize(.large)
#endif
        }
      }
    }
    .onAppear {
      // An empty list has no button. Focusing a binding nothing uses pulled the
      // remote off the header chips beside this view.
      if onRetry != nil {
        retryFocused = true
      }
    }
  }
}

#Preview {
  UnavailableView(title: "Couldn't Load",
                  systemImage: "wifi.exclamationmark",
                  message: "Check your connection and try again.",
                  retryTitle: "Try Again",
                  onRetry: {})
    .background(Color.KinoPub.background)
}
