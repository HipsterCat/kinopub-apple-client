//
//  RootView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 17.07.2023.
//

import SwiftUI
import KinoPubUI
import KinoPubBackend
import KinoPubLogging

struct RootView: View {

  @Environment(\.appContext) var appContext
  @EnvironmentObject var authState: AuthState
  @Environment(NavigationState.self) var navigationState
  /// Off unless switched on in Settings › Advanced › Diagnostics.
  @AppStorage(DiagnosticsSettings.activityOverlayKey) private var showsActivityOverlay = false
#if os(macOS)
  @Environment(\.openWindow) private var openWindow
#endif

  var body: some View {
    // Keychain token → Tabs immediately; `authState.check()` refreshes underneath.
    // No full-screen auth spinner — that gate was the hostile cold-launch wait.
    //
    // iOS/tvOS still swap Auth↔Tabs entirely — a live catalog behind the code used to
    // keep loading artwork, and UIKit's TabView asserts when tabs are removed mid-update.
    //
    // macOS keeps the tab shell mounted and presents Auth as a non-dismissible sheet so
    // the window chrome does not jump from a title-less auth layout into the library.
    rootContent
      .networkActivityOverlay(isEnabled: showsActivityOverlay)
      .task {
        await authState.check()
      }
#if os(macOS)
      .sheet(isPresented: macAuthSheetPresented) {
        AuthView(model: AuthModel(authService: appContext.authService, authState: authState))
          .frame(minWidth: 440, idealWidth: 520, minHeight: 360, idealHeight: 400)
          .interactiveDismissDisabled()
      }
      .onChange(of: navigationState.playerWindowRequestID) { _, requestID in
        guard requestID != nil else { return }
        openWindow(id: PlaybackWindowState.windowID)
      }
#endif
  }

  @ViewBuilder
  private var rootContent: some View {
#if os(tvOS) && DEBUG
    if DetailFixture.isActive {
      DetailFixtureRoot()
    } else if DebugLaunch.libraryFixture {
      LibraryFixtureRoot()
    } else if DebugLaunch.menuBackProbe {
      TVPageMenuBackProbeRoot()
    } else if DebugLaunch.templatesGallery {
      TVPageTemplatesGallery()
    } else {
      phaseContent
    }
#else
    phaseContent
#endif
  }

  @ViewBuilder
  private var phaseContent: some View {
    switch authState.phase {
#if os(macOS)
    case .signedOut, .signedIn:
      TabsNavigationView()
#else
    case .signedOut:
      AuthView(model: AuthModel(authService: appContext.authService, authState: authState))
    case .signedIn:
      TabsNavigationView()
#endif
    }
  }

#if os(macOS)
  /// Sheet stays up for the whole signed-out phase; dismiss is auth success only.
  private var macAuthSheetPresented: Binding<Bool> {
    Binding(
      get: { authState.phase == .signedOut },
      set: { _ in }
    )
  }
#endif
}

/// What outstanding network work is waiting for, in words.
///
/// Used to label the old blocking auth splash. Auth no longer gates on refresh
/// (optimistic Keychain launch), but the label still names in-flight families via
/// `NetworkActivity` — useful in previews and anywhere a surface wants the same copy.
///
/// Ships in release. Product decision, 2026-08-16 (label); gate removed 2026-10-01.
struct LaunchStatusLabel: View {
  @StateObject private var activity = NetworkActivity.shared

  var body: some View {
    Text(joined)
      .font(TypeScale.cardMeta)
      .foregroundStyle(Color.KinoPub.subtitle)
      .multilineTextAlignment(.center)
      .lineLimit(2)
      .padding(.horizontal, 32)
      // No flicker when one request settles a frame before the next starts, and no
      // layout jump between "nothing registered yet" and the first name.
      .opacity(joined.isEmpty ? 0 : 1)
      .animation(.easeOut(duration: 0.2), value: joined)
  }

  /// Distinct, in the order they started. Three catalogue pages in flight are one thing
  /// the user is waiting for, not three — repeating the name would read as a stutter.
  private var joined: String {
    var seen = Set<String>()
    return activity.inFlight
      .compactMap { seen.insert($0.nameKey).inserted ? $0.nameKey : nil }
      .map { NSLocalizedString($0, comment: "Launch status: what the app is waiting for") }
      .joined(separator: " · ")
  }
}

struct RootView_Previews: PreviewProvider {
  static var previews: some View {
    RootView()
  }
}

#Preview("Launch status") {
  ZStack {
    Color.KinoPub.background.ignoresSafeArea()
    LaunchStatusLabel()
  }
  .task {
    _ = NetworkActivity.begin(nameKey: "Activity_Session", detail: "/v1/user")
    _ = NetworkActivity.begin(nameKey: "Activity_History", detail: "/v1/history")
  }
}
