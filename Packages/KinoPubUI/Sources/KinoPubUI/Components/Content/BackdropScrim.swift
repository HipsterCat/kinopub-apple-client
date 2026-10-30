//
//  BackdropScrim.swift
//  KinoPubUI
//
//  The legibility scrim the tvOS page backdrop draws over a title's picture.
//

import SwiftUI

/// Black in any appearance: what is drawn over a picture is forced dark. A light shade
/// over the whole frame, the leading edge (where the logo and the text start) and the
/// bottom band (synopsis, metadata, buttons). Stops are fractions of the picture's own
/// height, so it fits a full screen or a 16:9 band alike.
public struct BackdropScrim: View {

  public init() {}

  public var body: some View {
    ZStack {
      Color.black.opacity(0.22)

      LinearGradient(stops: [
        .init(color: .clear, location: 0.35),
        .init(color: .black.opacity(0.28), location: 0.55),
        .init(color: .black.opacity(0.55), location: 0.82),
        .init(color: .black.opacity(0.72), location: 1)
      ], startPoint: .top, endPoint: .bottom)

      LinearGradient(stops: [
        .init(color: .black.opacity(0.35), location: 0),
        .init(color: .clear, location: 0.35)
      ], startPoint: .leading, endPoint: .trailing)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
