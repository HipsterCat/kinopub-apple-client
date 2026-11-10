//
//  AuthView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 24.07.2023.
//
import SwiftUI
import KinoPubUI

/// Full-screen kino.pub device activation: the shared code sign-in screen
/// (`DeviceCodeSignInView`, also Trakt's and Plex's) over a static material backdrop.
/// Nothing to close: the app has nothing to show until the device is activated.
struct AuthView: View {

  @StateObject var model: AuthModel
  @Environment(\.scenePhase) private var scenePhase

  init(model: @autoclosure @escaping () -> AuthModel) {
    _model = StateObject(wrappedValue: model())
  }

  var body: some View {
    ZStack {
      // Static backdrop, not the live app behind glass: the catalog underneath used to blink
      // through the blur every time a poster or the hero swapped.
      Color.KinoPub.background
        .ignoresSafeArea()
      Rectangle()
        .fill(.ultraThinMaterial)
        .ignoresSafeArea()

      DeviceCodeSignInView(
        title: "Auth_CodeActivationTitle".localized,
        message: "Auth_CodeActivationText".localized,
        activateTitle: "Auth_Activate".localized,
        state: DeviceCodeSignInState(
          code: model.deviceCode,
          displayURL: model.verificationURL,
          validRange: model.codeValidRange,
          isExpired: model.isExpired,
          errorMessage: model.errorMessage,
          isBusy: model.isRefreshing
        ),
        // kino.pub device codes are five characters.
        placeholderTiles: 5,
        shareURL: model.shareURL,
        shareMessage: model.shareMessage,
        actions: .init(
          copy: { model.copyCode() },
          activate: { model.activate() },
          newCode: { Task { await model.requestNewCode() } },
          retry: { Task { await model.retry() } },
          ringRanOut: { model.checkExpiration() }
        )
      ) {
        DeviceCodeSignInLogo(image: Image("kinopub_icon"))
      }
    }
    .hudToast($model.hudToast)
    .task {
      await model.run()
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .background:
        model.handleDidEnterBackground()
      case .active:
        Task {
          await model.handleDidBecomeActive()
        }
      case .inactive:
        break
      @unknown default:
        break
      }
    }
  }
}
