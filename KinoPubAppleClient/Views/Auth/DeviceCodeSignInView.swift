//
//  DeviceCodeSignInView.swift
//  KinoPubAppleClient
//
//  One screen for every sign-in with a code typed on another device: kino.pub's device
//  activation, Trakt's device code and Plex's PIN. The service's mark, the code in tiles
//  (click to copy, with the "Copied" HUD), the time left on a ring, Activate that copies
//  and opens the page, Share for another device, and a close cross where the screen can
//  be closed. Plex's sheet was a second-rate copy of kino.pub's, with no copy HUD and no
//  Share: one design, written once (Sasha, 2026-11-10).
//
//  Layout never moves. The tiles are always on screen at their final size — empty while a
//  code is in flight — and the characters blur in when it lands, instead of a spinner that
//  pushes the page around every time the code is replaced.
//

import SwiftUI
import KinoPubUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Where a code sign-in stands, whichever service asks for it.
struct DeviceCodeSignInState: Equatable {
  var code: String = ""
  /// What the viewer types into a browser: `kino.pub/device`, `plex.tv/link`.
  var displayURL: String = ""
  var validRange: ClosedRange<Date>?
  var isExpired = false
  var errorMessage: String?
  var isBusy = false

  var canCopy: Bool {
#if os(tvOS)
    false
#else
    !code.isEmpty && !isExpired
#endif
  }
}

struct DeviceCodeSignInView<Logo: View>: View {
  struct Actions {
    /// Copy the code; the host shows the HUD.
    var copy: () -> Void
    /// Copy, then open the page.
    var activate: () -> Void
    var newCode: () -> Void
    var retry: () -> Void
    /// The ring ran out: the host checks and marks the code expired.
    var ringRanOut: () -> Void = {}
    /// Nil where the screen cannot be closed (kino.pub's own sign-in).
    var close: (() -> Void)?
  }

  let title: String
  let message: String
  let activateTitle: String
  let state: DeviceCodeSignInState
  /// Tiles drawn before the first code lands, so it does not resize the screen.
  var placeholderTiles = 5
  let shareURL: URL
  let shareMessage: String
  let actions: Actions
  @ViewBuilder let logo: () -> Logo

  @State private var isCodeHovered = false
  @FocusState private var primaryFocused: Bool

  var body: some View {
    VStack(spacing: Metrics.blockSpacing) {
      header
      VStack(spacing: Metrics.codeBlockSpacing) {
        codeView
        status
      }
      footer
    }
    .padding(.horizontal, Metrics.horizontalPadding)
    .padding(.vertical, Metrics.verticalPadding)
    .frame(maxWidth: Metrics.contentWidth)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
#if !os(tvOS)
    .overlay(alignment: .topLeading) { closeButton }
#endif
  }

  // MARK: - Header

  private var header: some View {
    VStack(spacing: Metrics.headerSpacing) {
      logo()
        .padding(.bottom, Metrics.logoBottomPadding)

      Text(verbatim: title)
        .font(Metrics.titleFont)
        .foregroundStyle(.primary)

      Text(verbatim: message)
        .font(Metrics.descriptionFont)
        .foregroundStyle(.secondary)

      // Where to type it, on every platform. Even next to an Activate button that opens
      // the page for you, the address is what tells you where you are being sent — and
      // it is the only route left when the button opens the wrong browser.
      if !state.displayURL.isEmpty {
        Text(verbatim: state.displayURL)
          .font(Metrics.urlFont)
          .foregroundStyle(.primary)
      }
    }
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
  }

  // MARK: - Code

  /// The whole block is the copy target — there is no Copy button. Hovering lifts every
  /// tile at once (one gesture over the block, not per character), and a click copies.
  @ViewBuilder
  private var codeView: some View {
#if os(tvOS)
    codeTiles
#else
    Button(action: actions.copy) {
      codeTiles
    }
    .buttonStyle(.plain)
    .disabled(!state.canCopy)
    .onHover { isCodeHovered = $0 }
    .animation(.easeOut(duration: 0.15), value: isCodeHovered)
    .help("Copy")
#endif
  }

  private var tileCount: Int { max(state.code.count, placeholderTiles) }

  private var codeTiles: some View {
    HStack(spacing: Metrics.tileSpacing) {
      ForEach(0..<tileCount, id: \.self) { index in
        tile(character(at: index))
      }
    }
    .frame(maxWidth: codeWidth)
    .opacity(state.isExpired ? 0.45 : 1)
    .animation(.easeOut(duration: 0.2), value: state.isExpired)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Auth_DeviceCode"))
    .accessibilityValue(Text(state.code.map(String.init).joined(separator: " ")))
  }

  private func tile(_ character: Character?) -> some View {
    ZStack {
      if let character {
        Text(String(character))
          .font(.system(size: Metrics.tileFontSize, weight: .semibold, design: .rounded))
          .minimumScaleFactor(0.5)
          // Characters swap in place: the tile is already there at full size, so a new
          // code dissolves through blur instead of relaying the screen out.
          .transition(.blurReplace)
      }
    }
    // The code is the point of this screen — it is never dimmed. Hover lifts the tile
    // behind it, not the glyph.
    .foregroundStyle(.primary)
    // Eight Trakt characters on a phone: tiles narrow to fit, keeping their shape.
    .frame(maxWidth: Metrics.tileSize.width)
    .aspectRatio(Metrics.tileSize.width / Metrics.tileSize.height, contentMode: .fit)
    // Quaternary fill, not a material: with a static backdrop a material has nothing to
    // blur and the tiles sink into the background.
    .background(tileFill, in: RoundedRectangle(cornerRadius: Metrics.tileCornerRadius,
                                               style: .continuous))
    .animation(.easeOut(duration: 0.25), value: state.code)
  }

  private var tileFill: AnyShapeStyle {
    isCodeHovered ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary)
  }

  private func character(at index: Int) -> Character? {
    let code = state.code
    guard index < code.count else { return nil }
    return code[code.index(code.startIndex, offsetBy: index)]
  }

  /// Width the code block occupies at full tile size; the buttons match it.
  private var codeWidth: CGFloat {
    let count = CGFloat(tileCount)
    return max(count, 5) * Metrics.tileSize.width + (max(count, 5) - 1) * Metrics.tileSpacing
  }

  // MARK: - Expiry & status

  /// Draining ring plus the remaining time in figures, or the expired / error state.
  @ViewBuilder
  private var status: some View {
    ZStack {
      if state.isExpired {
        statusLine(systemImage: "clock.badge.exclamationmark",
                   text: "Auth_CodeExpired".localized)
      } else if let errorMessage = state.errorMessage {
        statusLine(systemImage: "exclamationmark.triangle.fill", text: errorMessage)
      } else if let range = state.validRange {
        TimelineView(.periodic(from: range.lowerBound, by: 1)) { context in
          let total = range.upperBound.timeIntervalSince(range.lowerBound)
          let left = max(0, range.upperBound.timeIntervalSince(context.date))
          let fraction = total > 0 ? left / total : 0

          HStack(spacing: Metrics.ringSpacing) {
            ZStack {
              Circle()
                .stroke(.quaternary, lineWidth: Metrics.ringLineWidth)
              Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.KinoPub.accent,
                        style: StrokeStyle(lineWidth: Metrics.ringLineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            }
            .frame(width: Metrics.ringSize, height: Metrics.ringSize)

            Text(Swift.Duration.seconds(left).formatted(.time(pattern: .minuteSecond)))
              .font(Metrics.expiryFont)
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
          .onChange(of: left <= 0) { _, ranOut in
            if ranOut { actions.ringRanOut() }
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel(Text("Auth_DeviceCode"))
          .accessibilityValue(Text(Swift.Duration.seconds(left).formatted(.time(pattern: .minuteSecond))))
        }
      } else if state.isBusy {
        ProgressView()
          .controlSize(.small)
      }
    }
    .frame(minHeight: Metrics.ringRowHeight)
  }

  private func statusLine(systemImage: String, text: String) -> some View {
    HStack(spacing: Metrics.ringSpacing) {
      Image(systemName: systemImage)
        .foregroundStyle(.orange)
      Text(verbatim: text)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .multilineTextAlignment(.center)
    }
    .font(Metrics.expiryFont)
    .accessibilityElement(children: .combine)
  }

  // MARK: - Footer

  /// Activation or recovery, with Share right under it so the link and the code can be
  /// AirDropped or sent to the device that will open them.
  @ViewBuilder
  private var footer: some View {
    if state.isExpired {
      primaryButton("Auth_GetNewCode".localized, action: actions.newCode)
        .disabled(state.isBusy)
    } else if state.errorMessage != nil {
      VStack(spacing: Metrics.footerButtonSpacing) {
        primaryButton("Try Again".localized, action: actions.retry)
          .disabled(state.isBusy)
#if !os(tvOS)
        if !state.code.isEmpty { shareButton }
#endif
      }
    } else {
#if !os(tvOS)
      VStack(spacing: Metrics.footerButtonSpacing) {
        primaryButton(activateTitle, action: actions.activate)
          .disabled(state.code.isEmpty)
        shareButton
      }
#else
      Color.clear
        .frame(height: Metrics.footerHeight)
#endif
    }
  }

  private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(verbatim: title)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.glassProminent)
    .controlSize(.large)
#if !os(tvOS)
    .keyboardShortcut(.defaultAction)
#endif
    .focused($primaryFocused)
    .frame(maxWidth: codeWidth, minHeight: Metrics.footerHeight)
    .onAppear { primaryFocused = true }
  }

#if !os(tvOS)
  private var shareButton: some View {
    ShareLink(item: shareURL, subject: Text(verbatim: title), message: Text(verbatim: shareMessage)) {
      Label("Auth_Share", systemImage: "square.and.arrow.up")
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.glass)
    .controlSize(.large)
    .disabled(state.code.isEmpty || state.isExpired)
    .frame(maxWidth: codeWidth, minHeight: Metrics.footerHeight)
  }

  @ViewBuilder
  private var closeButton: some View {
    if let close = actions.close {
      SheetCloseButton(action: close)
        .padding(SheetCloseButton.inset)
    }
  }
#endif
}

enum DeviceCodePasteboard {
  /// The pasteboard, wherever there is one worth writing to.
  static func copy(_ code: String) {
#if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(code, forType: .string)
#elseif canImport(UIKit) && !os(tvOS)
    UIPasteboard.general.string = code
#endif
  }
}

/// The service's mark at the size the sign-in screen draws it.
struct DeviceCodeSignInLogo: View {
  let image: Image
  @ScaledMetric(relativeTo: .largeTitle) private var side: CGFloat = DeviceCodeSignInLogo.baseSide

#if os(tvOS)
  static let baseSide: CGFloat = 120
#else
  static let baseSide: CGFloat = 64
#endif

  var body: some View {
    image
      .resizable()
      .scaledToFit()
      .frame(width: side, height: side)
      .accessibilityHidden(true)
  }
}

private enum Metrics {
#if os(tvOS)
  static let blockSpacing: CGFloat = 44
  static let headerSpacing: CGFloat = 14
  static let logoBottomPadding: CGFloat = 6
  static let codeBlockSpacing: CGFloat = 20
  static let horizontalPadding: CGFloat = 90
  static let verticalPadding: CGFloat = 40
  static let contentWidth: CGFloat = 900
  static let titleFont: Font = .title2.weight(.semibold)
  static let descriptionFont: Font = .caption
  static let urlFont: Font = .body.weight(.semibold)
  static let tileSpacing: CGFloat = 16
  static let tileSize = CGSize(width: 92, height: 120)
  static let tileCornerRadius: CGFloat = 18
  static let tileFontSize: CGFloat = 60
  static let footerHeight: CGFloat = 60
  static let footerButtonSpacing: CGFloat = 14
  static let ringSize: CGFloat = 22
  static let ringLineWidth: CGFloat = 3
  static let ringSpacing: CGFloat = 10
  static let ringRowHeight: CGFloat = 30
  static let expiryFont: Font = .caption
#else
  static let blockSpacing: CGFloat = 28
  static let headerSpacing: CGFloat = 10
  static let logoBottomPadding: CGFloat = 4
  static let codeBlockSpacing: CGFloat = 16
  static let horizontalPadding: CGFloat = 24
  static let verticalPadding: CGFloat = 32
  static let contentWidth: CGFloat = 480
  static let titleFont: Font = .title.weight(.bold)
  static let descriptionFont: Font = .body
  static let urlFont: Font = .body.weight(.medium)
  static let tileSpacing: CGFloat = 8
  static let tileSize = CGSize(width: 48, height: 64)
  static let tileCornerRadius: CGFloat = 10
  static let tileFontSize: CGFloat = 32
  static let footerHeight: CGFloat = 44
  static let footerButtonSpacing: CGFloat = 10
  static let ringSize: CGFloat = 13
  static let ringLineWidth: CGFloat = 2
  static let ringSpacing: CGFloat = 6
  static let ringRowHeight: CGFloat = 18
  static let expiryFont: Font = .caption
#endif
}
