//
//  LoadingIndicatorView.swift
//
//

import SwiftUI

/// The spinner every loading surface uses, held back for a beat so a fast response
/// shows content instead of a flash of chrome. The Apple TV app does the same: an
/// empty screen first, a spinner only once the wait becomes noticeable.
public struct LoadingIndicatorView: View {

  private let delay: Duration

  @State private var isVisible: Bool = false
#if os(tvOS)
  @FocusState private var holdsRemoteFocus: Bool
#endif

  /// - Parameter delay: how long the screen stays empty before the spinner appears.
  public init(delay: Duration = .milliseconds(300)) {
    self.delay = delay
  }

  public var body: some View {
    ZStack {
#if os(tvOS)
      // Spinner-only pages had no focus target — Menu quit the app instead of going back.
      Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($holdsRemoteFocus)
#endif
      ProgressView()
#if !os(tvOS)
        .tint(Color.KinoPub.text)
#endif
        .controlSize(.large)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeIn(duration: 0.2), value: isVisible)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(tvOS)
    .focusSection()
    .onAppear { holdsRemoteFocus = true }
#endif
    .task {
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      isVisible = true
    }
  }
}

#Preview {
  LoadingIndicatorView()
    .background(Color.KinoPub.background)
}
