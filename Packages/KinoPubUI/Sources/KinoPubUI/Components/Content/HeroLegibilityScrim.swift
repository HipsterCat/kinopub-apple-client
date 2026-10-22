//
//  HeroLegibilityScrim.swift
//  KinoPubUI
//

#if canImport(SwiftUI)
import SwiftUI

/// A seamless legibility vignette for hero and homepage banners.
///
/// Replaces a single directional scrim (which pooled the darkening on one side —
/// obvious over a mostly-white hero) with two things layered together:
///   1. a faint **all-over wash** that darkens the whole image a touch, so a
///      bright hero doesn't read as blown-out; and
///   2. a **symmetric or directional edge vignette** — darkening on the chosen
///      edges — that fades to clear through the middle.
///
/// Each edge reaches `edgePeak`, and because the horizontal and vertical passes
/// overlap, the corners land a little darker — the even, seamless vignette look.
public struct HeroLegibilityScrim: View {
  /// Which edges the vignette darkens.
  public struct Edges: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let leading = Edges(rawValue: 1 << 0)
    public static let trailing = Edges(rawValue: 1 << 1)
    public static let top = Edges(rawValue: 1 << 2)
    public static let bottom = Edges(rawValue: 1 << 3)

    public static let all: Edges = [.leading, .trailing, .top, .bottom]
  }

  private let tone: Color
  private let edgePeak: Double
  private let wash: Double
  private let edges: Edges
  private let sideDarkeningStart: Double
  private let bottomFadeTop: Double

  /// - Parameters:
  ///   - tone: Mode-appropriate scrim colour (dark in dark mode, light in light).
  ///   - edgePeak: Opacity at each edge — set to the content-side strength so the
  ///     readable side is never lightened.
  ///   - wash: Flat opacity applied across the whole image (the subtle overall
  ///     darkening). Defaults to a gentle 6%.
  ///   - edges: Which edges to darken. Defaults to all four.
  ///   - sideDarkeningStart: How far DOWN the hero the left/right darkening
  ///     ramps in, as a fraction of height. `0` darkens the full column
  ///     evenly (the symmetric default). A higher value keeps the upper
  ///     corners clean and brings the wash in only where content sits.
  ///   - bottomFadeTop: The upper edge of the bottom-anchored fade. Lower values
  ///     make the fade taller while leaving its bottom edge unchanged.
  public init(
    tone: Color,
    edgePeak: Double = 0.55,
    wash: Double = 0.06,
    edges: Edges = .all,
    sideDarkeningStart: Double = 0,
    bottomFadeTop: Double = 0.58
  ) {
    self.tone = tone
    self.edgePeak = edgePeak
    self.wash = wash
    self.edges = edges
    self.sideDarkeningStart = sideDarkeningStart
    self.bottomFadeTop = bottomFadeTop
  }

  public var body: some View {
    ZStack {
      tone.opacity(wash)
      if edges.contains(.leading) || edges.contains(.trailing) {
        edgeGradient(
          startPoint: .leading,
          endPoint: .trailing,
          startsDark: edges.contains(.leading),
          endsDark: edges.contains(.trailing)
        )
        .mask(sideDarkeningMask)
      }
      if edges.contains(.top) || edges.contains(.bottom) {
        edgeGradient(
          startPoint: .top,
          endPoint: .bottom,
          startsDark: edges.contains(.top),
          endsDark: edges.contains(.bottom),
          bottomFadeTop: bottomFadeTop
        )
      }
    }
  }

  /// Ramps the side darkening in vertically, so the upper corners keep the
  /// artwork's own contrast while the wash still arrives at full strength over
  /// the title, metadata and buttons lower down.
  ///
  /// Opaque (no masking) when `sideDarkeningStart` is 0, so the symmetric
  /// default is untouched.
  @ViewBuilder
  private var sideDarkeningMask: some View {
    if sideDarkeningStart <= 0 {
      Color.black
    } else {
      LinearGradient(
        stops: Self.sideMaskStops(sideDarkeningStart: sideDarkeningStart).map {
          .init(color: .black.opacity($0.opacity), location: $0.location)
        },
        startPoint: .top,
        endPoint: .bottom
      )
    }
  }

  /// One axis of the vignette: `edgePeak` at both ends, fading to a clear centre
  /// band so most of the image stays untinted.
  private func edgeGradient(
    startPoint: UnitPoint,
    endPoint: UnitPoint,
    startsDark: Bool,
    endsDark: Bool,
    bottomFadeTop: Double = 0.58
  ) -> some View {
    LinearGradient(
      stops: edgeStops(
        startsDark: startsDark,
        endsDark: endsDark,
        bottomFadeTop: bottomFadeTop
      ),
      startPoint: startPoint,
      endPoint: endPoint
    )
  }

  private func edgeStops(
    startsDark: Bool,
    endsDark: Bool,
    bottomFadeTop: Double
  ) -> [Gradient.Stop] {
    Self.calculatedEdgeStops(
      edgePeak: edgePeak,
      startsDark: startsDark,
      endsDark: endsDark,
      bottomFadeTop: bottomFadeTop
    ).map { stop in
      .init(
        color: stop.opacity > 0 ? tone.opacity(stop.opacity) : .clear,
        location: stop.location
      )
    }
  }

  // MARK: - Shared Calculation Helpers (SwiftUI + UIKit)

  public struct StopSpec: Sendable, Equatable {
    public let location: Double
    public let opacity: Double

    public init(location: Double, opacity: Double) {
      self.location = location
      self.opacity = opacity
    }
  }

  public static func sideMaskStops(sideDarkeningStart: Double) -> [StopSpec] {
    guard sideDarkeningStart > 0 else {
      return [
        StopSpec(location: 0, opacity: 1),
        StopSpec(location: 1, opacity: 1)
      ]
    }
    return [
      StopSpec(location: 0, opacity: 0),
      StopSpec(location: sideDarkeningStart, opacity: 0.35),
      StopSpec(location: min(1, sideDarkeningStart + 0.28), opacity: 1)
    ]
  }

  public static func calculatedEdgeStops(
    edgePeak: Double,
    startsDark: Bool,
    endsDark: Bool,
    bottomFadeTop: Double = 0.58
  ) -> [StopSpec] {
    if startsDark, endsDark {
      return [
        StopSpec(location: 0, opacity: edgePeak),
        StopSpec(location: 0.42, opacity: 0),
        StopSpec(location: 0.58, opacity: 0),
        StopSpec(location: 1, opacity: edgePeak)
      ]
    }
    if startsDark {
      return [
        StopSpec(location: 0, opacity: edgePeak),
        StopSpec(location: 0.42, opacity: 0),
        StopSpec(location: 1, opacity: 0)
      ]
    }
    guard endsDark else {
      return [
        StopSpec(location: 0, opacity: 0),
        StopSpec(location: 1, opacity: 0)
      ]
    }

    let span = 1 - bottomFadeTop
    return [
      StopSpec(location: 0, opacity: 0),
      StopSpec(location: max(0, bottomFadeTop - span * 0.10), opacity: 0),
      StopSpec(location: bottomFadeTop + span * 0.04, opacity: edgePeak * 0.01),
      StopSpec(location: bottomFadeTop + span * 0.18, opacity: edgePeak * 0.04),
      StopSpec(location: bottomFadeTop + span * 0.34, opacity: edgePeak * 0.12),
      StopSpec(location: bottomFadeTop + span * 0.54, opacity: edgePeak * 0.28),
      StopSpec(location: bottomFadeTop + span * 0.74, opacity: edgePeak * 0.52),
      StopSpec(location: bottomFadeTop + span * 0.90, opacity: edgePeak * 0.76),
      StopSpec(location: 1, opacity: edgePeak)
    ]
  }
}

#if DEBUG
#Preview("Scrim") {
  Color.white
    .overlay {
      HeroLegibilityScrim(tone: .black, edgePeak: 0.55)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
}
#endif
#endif
