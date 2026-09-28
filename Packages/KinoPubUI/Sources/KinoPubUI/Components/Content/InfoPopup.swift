//
//  InfoPopup.swift
//  KinoPubUI
//
//  One popup for "show me the rest of this", on every platform.
//
//  The reference app hangs its expanded info off a small round `i` button. We do not:
//  the thing that was clipped is the thing you select. A synopsis that got cut at five
//  lines opens itself; a column of facts that got summarised opens itself. That keeps
//  the affordance where the content is instead of adding a second, tiny target beside
//  it — and on a remote it means one Select on the paragraph you were already reading,
//  not a trip sideways to an icon.
//
//  Presentation is the system's, per platform: a sheet everywhere, drawn as a centred
//  panel over a scrim on tvOS (where Menu dismisses it for free), with detents on
//  iPhone/iPad, and a panel on macOS. `.claude/skills/tvos-surface/SKILL.md` —
//  `description handlesOverflow` is a popup, and there is exactly one of it.
//

import SwiftUI

// MARK: - Metrics

public enum InfoPopupMetrics {
#if os(tvOS)
  public static let maxWidth: CGFloat = 1100
  public static let padding: CGFloat = 64
  public static let cornerRadius: CGFloat = 28
  public static let titleFont: Font = .title
  public static let bodyFont: Font = .body
  public static let contentSpacing: CGFloat = 28
#elseif os(macOS)
  public static let maxWidth: CGFloat = 620
  public static let padding: CGFloat = 28
  public static let cornerRadius: CGFloat = 16
  public static let titleFont: Font = .title2
  public static let bodyFont: Font = .body
  public static let contentSpacing: CGFloat = 18
#else
  public static let maxWidth: CGFloat = 640
  public static let padding: CGFloat = 24
  public static let cornerRadius: CGFloat = 16
  public static let titleFont: Font = .title2
  public static let bodyFont: Font = .body
  public static let contentSpacing: CGFloat = 18
#endif
}

// MARK: - Panel

/// The popup's own chrome. Everything inside is content the caller supplies — this
/// owns the frame, the scroll, and the way out.
private struct InfoPopupPanel<Content: View>: View {
  let title: Text
  @ViewBuilder let content: () -> Content

  @Environment(\.dismiss) private var dismiss

  var body: some View {
#if os(tvOS)
    ZStack {
      // A scrim, not a faded material: `.opacity` on a material draws the full-strength
      // effect semi-transparently instead of weakening it (materials-blur-and-chrome).
      Color.black.opacity(0.55)
        .ignoresSafeArea()
      panel
        .frame(maxWidth: InfoPopupMetrics.maxWidth)
        .background {
          RoundedRectangle(cornerRadius: InfoPopupMetrics.cornerRadius, style: .continuous)
            .fill(.regularMaterial)
        }
        .padding(60)
    }
#else
    panel
      .frame(maxWidth: InfoPopupMetrics.maxWidth, alignment: .leading)
#endif
  }

  private var panel: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing) {
        title
          .font(InfoPopupMetrics.titleFont)
          .foregroundStyle(Color.KinoPub.text)

        content()

#if !os(tvOS)
        // tvOS dismisses with Menu; every other platform wants a visible way out that
        // is not "guess the gesture".
        Button("Close") { dismiss() }
          .buttonStyle(.bordered)
#endif
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(InfoPopupMetrics.padding)
    }
    // Nothing in here is necessarily a control, and on tvOS a scroll view with nothing
    // focusable inside it will not move — this lets the remote pan the text directly.
#if os(tvOS)
    .focusable()
#endif
  }
}

// MARK: - Presentation

public extension View {
  /// Presents `content` in the shared info popup.
  ///
  /// Prefer `expandsIntoInfoPopup` — it makes the clipped content itself the control,
  /// which is the whole point. Use this directly only when the trigger genuinely is
  /// somewhere else.
  func infoPopup<Content: View>(
    _ title: Text,
    isPresented: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    modifier(InfoPopupModifier(title: title, isPresented: isPresented, popupContent: content))
  }

  /// Makes this view the control that opens its own expanded form.
  ///
  /// `isEnabled: false` leaves the view as plain, unfocusable content — for the case
  /// where nothing was clipped and there is nothing more to show. Focus bindings and
  /// accessibility belong on the call site, outside this modifier: it does not know
  /// which focus target it is.
  ///
  /// `chrome` says what the content is: `.card` for a container of facts (a column, a
  /// tile), `.text` for running prose that sits on artwork, such as the hero synopsis.
  func expandsIntoInfoPopup<Expanded: View>(
    title: Text,
    isEnabled: Bool = true,
    chrome: InfoPopupTriggerChrome = .card,
    @ViewBuilder expanded: @escaping () -> Expanded
  ) -> some View {
    modifier(InfoPopupTrigger(title: title, isEnabled: isEnabled, chrome: chrome, expanded: expanded))
  }
}

private struct InfoPopupModifier<PopupContent: View>: ViewModifier {
  let title: Text
  @Binding var isPresented: Bool
  @ViewBuilder let popupContent: () -> PopupContent

  func body(content: Content) -> some View {
    content
      .sheet(isPresented: $isPresented) {
        InfoPopupPanel(title: title, content: popupContent)
#if os(tvOS)
          // Our own scrim + panel draw the popup; without this the sheet lays an opaque
          // page behind them and it reads as a pushed screen rather than a popup.
          .presentationBackground(.clear)
#elseif os(iOS)
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
#endif
      }
  }
}

private struct InfoPopupTrigger<Expanded: View>: ViewModifier {
  let title: Text
  let isEnabled: Bool
  let chrome: InfoPopupTriggerChrome
  @ViewBuilder let expanded: () -> Expanded

  @State private var isPresented = false

  func body(content: Content) -> some View {
    if isEnabled {
      trigger(content)
        .infoPopup(title, isPresented: $isPresented) {
          expanded()
        }
    } else {
      content
    }
  }

  @ViewBuilder
  private func trigger(_ content: Content) -> some View {
    let button = Button {
      isPresented = true
    } label: {
      content
    }
    switch chrome {
    case .card:
      button.buttonStyle(InfoPopupTriggerStyle.buttonStyle)
    case .text:
      button.buttonStyle(InfoPopupTriggerStyle.textButtonStyle)
    }
  }
}

/// What the trigger looks like at rest.
public enum InfoPopupTriggerChrome: Sendable {
  /// A platter at rest and the card lift on focus — for containers.
  case card
  /// Nothing at rest; the platform's own treatment only while focused. On tvOS `.card`
  /// draws its platter whether or not the control is focused, so a synopsis wearing it
  /// looked focused next to the button that actually was (Sasha, on device, 2026-09-28).
  case text
}

/// `.card` on tvOS, `.plain` elsewhere — the same pairing Apple's own `DestinationVideo`
/// sample applies to every card in the app, and the one this project already settled on
/// after a hand-rolled focus style read as non-native.
public enum InfoPopupTriggerStyle {
  public static var buttonStyle: some PrimitiveButtonStyle {
#if os(tvOS)
    .card
#else
    .plain
#endif
  }

  /// The stock borderless style on tvOS: no chrome at rest, the platform's own treatment
  /// on focus. The same choice the season tabs made (`SeasonsRailView`).
  public static var textButtonStyle: some PrimitiveButtonStyle {
#if os(tvOS)
    .borderless
#else
    .plain
#endif
  }
}

#if DEBUG
#Preview("Info popup trigger") {
  VStack(alignment: .leading, spacing: 24) {
    Text("Select the paragraph, not an icon beside it.")
      .font(.headline)
    Text(String(repeating: "Синопсис, который не поместился целиком. ", count: 8))
      .lineLimit(3)
      .expandsIntoInfoPopup(title: Text("Synopsis")) {
        Text(String(repeating: "Синопсис, который не поместился целиком. ", count: 8))
          .font(InfoPopupMetrics.bodyFont)
          .foregroundStyle(Color.KinoPub.text)
      }
  }
  .padding(40)
  .frame(maxWidth: 900, alignment: .leading)
  // .preferredColorScheme(.dark)
}
#endif
