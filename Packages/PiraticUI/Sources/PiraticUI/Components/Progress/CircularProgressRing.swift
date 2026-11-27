//
//  CircularProgressRing.swift
//  PiraticUI
//
//  A small progress ring: 0 is empty, 1 is a full turn, clockwise from the top.
//  The skip chip uses it for an automatic-skip countdown. Downloads can use the
//  same view later for a fraction complete — pass that fraction as `progress`.
//

import SwiftUI

public struct CircularProgressRing: View {
  /// 0 is empty, 1 is a full ring.
  public var progress: Double
  public var lineWidth: CGFloat
  public var color: Color
  public var track: Color

  public init(progress: Double,
              lineWidth: CGFloat = 2.5,
              color: Color = .primary,
              track: Color = .primary.opacity(0.28)) {
    self.progress = progress
    self.lineWidth = lineWidth
    self.color = color
    self.track = track
  }

  public var body: some View {
    ZStack {
      Circle()
        .stroke(track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
      Circle()
        .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .padding(lineWidth / 2)
    .accessibilityHidden(true)
  }
}
