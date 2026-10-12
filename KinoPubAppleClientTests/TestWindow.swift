//
//  TestWindow.swift
//  KinoPubAppleClientTests
//

#if os(tvOS)
import UIKit

/// A full-screen window for view tests, on the host app's scene. `UIWindow(frame:)` is
/// deprecated since tvOS 26 in favour of `init(windowScene:)`.
@MainActor
enum TestWindow {
  static func make() -> UIWindow? {
    guard let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene }).first else { return nil }
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    return window
  }
}
#endif
