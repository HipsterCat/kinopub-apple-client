//
//  StatusToast.swift
//  PiraticUI
//
//  Bottom status pill for a failure that leaves the page on screen (a page of a list,
//  an action). Replaces exyte/PopupView, which drew it with no background on tvOS
//  and pulled SwiftUIIntrospect into the app.
//
//  Look and lifecycle follow Plozz's transient status (github.com/brandomoore/Plozz,
//  Sources/CoreUI/TransientStatusPresentation.swift + ThemePalette.toast): glyph +
//  text on an opaque rounded surface with a hairline and a soft shadow, an opacity
//  transition, a generation counter so a newer message restarts the timer and an old
//  timer never hides it, and a VoiceOver announcement. Bottom placement, no hit
//  testing and the slide-down exit are from Rivulet's WatchlistToastView
//  (github.com/l984-451/Rivulet, Views/Media/PlexHome/UIKit/HomeStateViews.swift).
//  Rewritten for this app, not copied: Plozz is GPL-3.0, Rivulet PolyForm
//  Noncommercial.
//

import SwiftUI

/// Glyph + message on the toast surface. Purely visual; `statusToast` owns timing.
public struct StatusToastView: View {
  private let systemImage: String
  private let message: String

  public init(systemImage: String, message: String) {
    self.systemImage = systemImage
    self.message = message
  }

  public var body: some View {
    HStack(spacing: Metrics.toastGlyphSpacing) {
      Image(systemName: systemImage)
        .symbolRenderingMode(.monochrome)
        .foregroundStyle(.secondary)
      Text(message)
        .lineLimit(3)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    .font(Self.font)
    .foregroundStyle(.primary)
    .padding(.vertical, Metrics.toastVerticalInset)
    .padding(.horizontal, Metrics.toastHorizontalInset)
    .modifier(StatusToastSurface())
    .accessibilityElement(children: .combine)
  }

  private static var font: Font {
#if os(tvOS)
    .callout.weight(.semibold)
#else
    .subheadline.weight(.semibold)
#endif
  }
}

/// Opaque surface, light or dark with the page: no material, so the pill reads the
/// same over a poster wall, a black hero or a white list, and Reduce Transparency
/// changes nothing. Increase Contrast swaps the hairline for a solid border.
private struct StatusToastSurface: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var contrast

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: Metrics.toastCornerRadius, style: .continuous)
    let isLight = colorScheme == .light
    let increased = contrast == .increased
    content
      .background(isLight ? Color.white : Color(red: 0.24, green: 0.25, blue: 0.27), in: shape)
      .overlay {
        shape.strokeBorder(
          increased
            ? Color.primary.opacity(0.6)
            : (isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12)),
          lineWidth: increased ? Metrics.toastContrastBorder : 1
        )
      }
      .shadow(color: .black.opacity(isLight ? 0.10 : 0.20), radius: 12, y: 4)
  }
}

public extension View {
  /// Shows `message` at the bottom while `isPresented`, then sets it back to `false`
  /// after `duration`. A new message (or a new `true`) while one is up restarts the
  /// timer. Never takes focus or touches: tvOS focus stays where it was.
  func statusToast(isPresented: Binding<Bool>,
                   systemImage: String = "exclamationmark.triangle.fill",
                   message: String?,
                   duration: Duration = .seconds(4)) -> some View {
    modifier(StatusToastModifier(isPresented: isPresented, systemImage: systemImage,
                                 message: message ?? "", duration: duration))
  }
}

private struct StatusToastModifier: ViewModifier {
  @Binding var isPresented: Bool
  let systemImage: String
  let message: String
  let duration: Duration

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown: String?
  @State private var generation: UInt64 = 0
  @State private var dismissTask: Task<Void, Never>?

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .bottom) {
        ZStack {
          if let shown {
            StatusToastView(systemImage: systemImage, message: shown)
              .transition(reduceMotion
                          ? .opacity
                          : .opacity.combined(with: .offset(y: Metrics.toastExitOffset)))
          }
        }
        .padding(.horizontal, Metrics.toastScreenInset)
        .padding(.bottom, Metrics.toastBottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
      }
      .onChange(of: isPresented, initial: true) { _, presented in
        presented ? present() : hide()
      }
      .onChange(of: message) { _, _ in
        if isPresented { present() }
      }
      .onDisappear { dismissTask?.cancel() }
  }

  private func present() {
    guard !message.isEmpty else { return }
    generation &+= 1
    let expected = generation
    dismissTask?.cancel()
    withAnimation(.easeInOut(duration: 0.2)) { shown = message }
    AccessibilityNotification.Announcement(message).post()
    dismissTask = Task { @MainActor in
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled, expected == generation else { return }
      isPresented = false
    }
  }

  private func hide() {
    generation &+= 1
    dismissTask?.cancel()
    dismissTask = nil
    withAnimation(.easeInOut(duration: 0.3)) { shown = nil }
  }
}

#Preview("Status toast") {
  ZStack {
    Color.Piratic.background.ignoresSafeArea()
    StatusToastView(systemImage: "exclamationmark.triangle.fill",
                    message: "The server is not responding. Try again later.")
  }
}
