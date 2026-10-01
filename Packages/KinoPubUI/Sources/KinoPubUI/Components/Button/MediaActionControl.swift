//
//  MediaActionControl.swift
//  KinoPubUI
//
//  The button that draws a `MediaActionAppearance`. Owns spacing, the loading
//  swap, symbol transitions, and the system chrome application so callers do
//  not re-pad or restyle each time. Behaviour (Menu / PlayerLink / plain action)
//  stays at the call site — wrap `MediaActionLabel` or use `MediaActionButton`.
//

import SwiftUI

// MARK: - Label

/// Glyph + optional progress + title, with loading replacing the content. Spacing
/// and type come from `MediaActionMetrics` — do not pad around this.
public struct MediaActionLabel: View {
  public var appearance: MediaActionAppearance

  public init(_ appearance: MediaActionAppearance) {
    self.appearance = appearance
  }

  public var body: some View {
    Group {
      if appearance.isLoading {
        ProgressView()
#if !os(tvOS)
          .controlSize(.small)
#endif
          .frame(
            width: appearance.chrome == .circle ? MediaActionMetrics.circleGlyphSlot : nil,
            height: appearance.chrome == .circle ? MediaActionMetrics.circleGlyphSlot : nil
          )
      } else {
        content
      }
    }
    .font(MediaActionMetrics.labelFont)
    .accessibilityLabel(Text(appearance.accessibilityLabel))
    .animation(.easeOut(duration: 0.2), value: appearance.isLoading)
  }

  @ViewBuilder
  private var content: some View {
    switch appearance.chrome {
    case .circle:
      if let circular = appearance.circularProgress {
        ZStack {
          Circle()
            .stroke(.tertiary, lineWidth: 2)
          Circle()
            .trim(from: 0, to: min(max(circular, 0), 1))
            .stroke(.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(-90))
          Image(systemName: appearance.systemImage)
        }
        .frame(width: MediaActionMetrics.circleGlyphSlot,
               height: MediaActionMetrics.circleGlyphSlot)
      } else {
        Image(systemName: appearance.systemImage)
          .contentTransition(.symbolEffect(.replace))
          .symbolEffect(.bounce, value: appearance.systemImage)
          .frame(width: MediaActionMetrics.circleGlyphSlot,
                 height: MediaActionMetrics.circleGlyphSlot)
          .animation(.easeOut(duration: 0.25), value: appearance.systemImage)
      }
    case .playPill, .pill:
      HStack(spacing: MediaActionMetrics.contentSpacing) {
        Image(systemName: appearance.systemImage)
          .contentTransition(.symbolEffect(.replace))
          .symbolEffect(.bounce, value: appearance.systemImage)
        if let progress = appearance.progress {
          MediaActionProgressTrack(progress: progress)
        }
        if let title = appearance.title {
          Text(title)
            .lineLimit(1)
            .contentTransition(.opacity)
        }
      }
      .animation(.easeOut(duration: 0.25), value: appearance.systemImage)
      .animation(.easeOut(duration: 0.25), value: appearance.title)
    }
  }
}

// MARK: - Plain button

/// `Button` + label + chrome. Prefer this for actions that are not a `Menu` or
/// `PlayerLink`. Those wrap `MediaActionLabel` and call `mediaActionStyle(_:)`.
public struct MediaActionButton: View {
  public var appearance: MediaActionAppearance
  public var action: () -> Void

  public init(_ appearance: MediaActionAppearance, action: @escaping () -> Void) {
    self.appearance = appearance
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      MediaActionLabel(appearance)
    }
    .mediaActionStyle(appearance.chrome)
    .disabled(appearance.isLoading)
    .accessibilityLabel(Text(appearance.accessibilityLabel))
  }
}

// MARK: - Row

/// Horizontal stack with catalog row spacing. Insert/remove transitions match the
/// Mark Watched "scale out on success" sketch — animate **ids only**, not glyph
/// swaps, so a bell toggle cannot look like the gaps grew.
public struct MediaActionRow<Content: View>: View {
  private let content: Content

  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  public var body: some View {
    HStack(alignment: .center, spacing: MediaActionMetrics.rowSpacing) {
      content
    }
  }
}

/// Typed row over appearances — use when every slot is a plain `MediaActionButton`.
/// Hero / detail pass a custom content builder because Play is a `PlayerLink` and
/// Bookmark is a `Menu`.
public struct MediaActionButtonRow: View {
  public var appearances: [MediaActionAppearance]
  public var action: (MediaActionID) -> Void

  public init(
    _ appearances: [MediaActionAppearance],
    action: @escaping (MediaActionID) -> Void
  ) {
    self.appearances = appearances
    self.action = action
  }

  public var body: some View {
    MediaActionRow {
      ForEach(appearances) { appearance in
        MediaActionButton(appearance) {
          action(appearance.id)
        }
        .transition(.asymmetric(
          insertion: .scale(scale: 0.85).combined(with: .opacity),
          removal: .scale(scale: 0.85).combined(with: .opacity)
        ))
      }
    }
    .animation(.easeOut(duration: 0.25), value: appearances.map(\.id))
  }
}

// MARK: - Chrome application

public extension View {
  /// Apply the catalog chrome to a `Button`, `Menu`, or `PlayerLink` label host.
  @ViewBuilder
  func mediaActionStyle(_ chrome: MediaActionChrome) -> some View {
    switch chrome {
    case .playPill:
      self.mediaActionPlayPillStyle()
    case .pill:
      self.mediaActionPillStyle()
    case .circle:
      self.mediaActionCircleStyle()
    }
  }
}
