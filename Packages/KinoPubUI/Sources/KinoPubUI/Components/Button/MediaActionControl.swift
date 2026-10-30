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
        if appearance.chrome == .circle {
          MediaActionGlyphSlot {
            ProgressView()
#if !os(tvOS)
              .controlSize(.small)
#endif
          }
        } else {
          ProgressView()
#if !os(tvOS)
            .controlSize(.small)
#endif
        }
      } else {
        content
      }
    }
    .font(MediaActionMetrics.labelFont)
#if os(iOS)
    // The monochrome Play's label (`mediaActionPlayPillStyle`). Set on the label: on iOS
    // `.glassProminent` overrides a foreground set on the button, and the label came out
    // white on the white pill.
    .modifier(PlayPillLabelColor(isPlayPill: appearance.chrome == .playPill))
#endif
#if os(tvOS)
    // UIKit draws a button's symbol at the large scale of its title font; SwiftUI's
    // default (medium) left the detail page's glyphs ~25% smaller than the Home hero's
    // at the same type size (measured 2026-10-25).
    .imageScale(.large)
#endif
    .accessibilityLabel(Text(appearance.accessibilityLabel))
    .animation(.easeOut(duration: 0.2), value: appearance.isLoading)
  }

  @ViewBuilder
  private var content: some View {
    switch appearance.chrome {
    case .circle:
      if let circular = appearance.circularProgress {
        MediaActionGlyphSlot {
          ZStack {
            Circle()
              .stroke(.tertiary, lineWidth: 2)
            Circle()
              .trim(from: 0, to: min(max(circular, 0), 1))
              .stroke(.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
              .rotationEffect(.degrees(-90))
            Image(systemName: appearance.systemImage)
          }
        }
      } else {
        MediaActionGlyphSlot {
          Image(systemName: appearance.systemImage)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: appearance.systemImage)
            .animation(.easeOut(duration: 0.25), value: appearance.systemImage)
        }
      }
    case .playPill, .pill:
      HStack(spacing: MediaActionMetrics.contentSpacing) {
        // A text-only pill («+ ещё 2») names no symbol.
        if !appearance.systemImage.isEmpty {
          Image(systemName: appearance.systemImage)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: appearance.systemImage)
        }
        if let progress = appearance.progress {
          MediaActionProgressTrack(progress: progress)
        }
        if let title = appearance.title {
          Text(title)
            .fixedSize(horizontal: true, vertical: false)
            .contentTransition(.opacity)
        }
      }
      .animation(.easeOut(duration: 0.25), value: appearance.systemImage)
      .animation(.easeOut(duration: 0.25), value: appearance.title)
    }
  }
}

#if os(iOS)
/// Only the Play pill: any other label keeps the colour its button style gives it.
/// The pill is filled with `.primary`, so its label is the other end of the scheme.
/// Not `.background`: inside an iOS button label that resolves to the button's own
/// fill, and the label vanished into the white pill.
private struct PlayPillLabelColor: ViewModifier {
  let isPlayPill: Bool

  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    if isPlayPill {
      content.foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
    } else {
      content
    }
  }
}
#endif

/// One box for every circle's glyph, so `bell` → `bell.and.waves…` (or a spinner)
/// cannot widen the button and look like the row's spacing grew.
///
/// tvOS: the measured slot. iOS / macOS: the square of the label's own type — a hidden
/// `square` symbol at the current font and Dynamic Type size — with the glyph centred
/// over it, so every circle is the same size and grows with the control's type.
private struct MediaActionGlyphSlot<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
#if os(tvOS)
    content
      .frame(width: MediaActionMetrics.circleGlyphSlot,
             height: MediaActionMetrics.circleGlyphSlot)
#else
    Image(systemName: "square")
      .hidden()
      .overlay { content }
#endif
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
    .mediaActionStyle(appearance)
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
#if os(tvOS)
    HStack(alignment: .center, spacing: MediaActionMetrics.rowSpacing) {
      content
    }
#else
    // One line while the labels fit. When they do not, the next ones drop to
    // another line — a label is never cut down to "Play…".
    ActionWrapLayout(spacing: MediaActionMetrics.rowSpacing) {
      content
    }
#endif
  }
}

/// Left-to-right rows that wrap once the next control does not fit.
private struct ActionWrapLayout: Layout {
  var spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let limit = proposal.width ?? .greatestFiniteMagnitude
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var used: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0, x + size.width > limit {
        used = max(used, x - spacing)
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      rowHeight = max(rowHeight, size.height)
      x += size.width + spacing
    }
    used = max(used, max(0, x - spacing))
    return CGSize(width: proposal.width ?? used, height: y + rowHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > bounds.minX, x + size.width > bounds.maxX {
        x = bounds.minX
        y += rowHeight + spacing
        rowHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      rowHeight = max(rowHeight, size.height)
      x += size.width + spacing
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

  /// The chrome, plus on a Mac the action's name as a tooltip on the icon-only circles:
  /// hovering a glyph is the only way to learn what it does there.
  @ViewBuilder
  func mediaActionStyle(_ appearance: MediaActionAppearance) -> some View {
#if os(macOS)
    if appearance.chrome == .circle {
      mediaActionStyle(appearance.chrome)
        .help(Text(appearance.accessibilityLabel))
    } else {
      mediaActionStyle(appearance.chrome)
    }
#else
    mediaActionStyle(appearance.chrome)
#endif
  }
}
