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
//  iPhone/iPad, and a panel on macOS. A UIKit screen presents the same view through
//  `InfoPopupPresenter`. What's New, the changelog and the licences use it too. `.claude/skills/tvos-surface/SKILL.md` —
//  `description handlesOverflow` is a popup, and there is exactly one of it.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Metrics

public enum InfoPopupMetrics {
#if os(tvOS)
  public static let maxWidth: CGFloat = 1280
  public static let padding: CGFloat = 64
  /// The system sheet's corner.
  public static let cornerRadius: CGFloat = 56
  public static let titleFont: Font = .title3
  public static let subtitleFont: Font = .subheadline
  public static let bodyFont: Font = .caption
  /// Smaller than the body: fact labels, the facts line, genres.
  public static let captionFont: Font = .caption2
  /// A section heading inside the popup («Информация»).
  public static let sectionFont: Font = .headline
  public static let contentSpacing: CGFloat = 28
  public static let scrimOpacity: Double = 0.5
#elseif os(macOS)
  public static let maxWidth: CGFloat = 620
  public static let padding: CGFloat = 28
  public static let cornerRadius: CGFloat = 16
  public static let titleFont: Font = .title2
  public static let subtitleFont: Font = .subheadline
  public static let bodyFont: Font = .body
  public static let captionFont: Font = .footnote
  public static let sectionFont: Font = .headline
  public static let contentSpacing: CGFloat = 18
  public static let scrimOpacity: Double = 0.5
#else
  public static let maxWidth: CGFloat = 640
  public static let padding: CGFloat = 24
  public static let cornerRadius: CGFloat = 16
  public static let titleFont: Font = .title2
  public static let subtitleFont: Font = .subheadline
  public static let bodyFont: Font = .body
  public static let captionFont: Font = .footnote
  public static let sectionFont: Font = .headline
  public static let contentSpacing: CGFloat = 18
  public static let scrimOpacity: Double = 0.5
#endif
}

// MARK: - Panel

/// The popup's own chrome. Everything inside is content the caller supplies — this
/// owns the frame, the scroll, and the way out.
///
/// `confirmTitle` adds a real button under the content (What's New's «Готово») and takes
/// the entry focus; without it tvOS leaves with Menu, as every other popup does. Short
/// content hugs the panel, long content scrolls inside it.
public struct InfoPopupView<Content: View>: View {
  let title: Text
  let subtitle: Text?
  let confirmTitle: Text?
  let onDismiss: (() -> Void)?
  let content: () -> Content

  @Environment(\.dismiss) private var environmentDismiss
#if os(tvOS)
  @FocusState private var confirmFocused: Bool
  @State private var scrollPosition = ScrollPosition(edge: .top)
  @State private var scrollGeometry = ScrollPage.Geometry()
#endif

  /// `onDismiss` closes a popup presented outside SwiftUI (`InfoPopupPresenter`); a
  /// sheet leaves it nil and uses its own `dismiss`.
  public init(
    title: Text,
    subtitle: Text? = nil,
    confirmTitle: Text? = nil,
    onDismiss: (() -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.subtitle = subtitle
    self.confirmTitle = confirmTitle
    self.onDismiss = onDismiss
    self.content = content
  }

  public var body: some View {
#if os(tvOS)
    ZStack {
      // The page dims behind the panel, the way the TV app's info panel does. The system
      // `.sheet` draws the same glass but neither dims nor grows: it is one fixed
      // ~1000×370 pt platter whatever the content or `presentationSizing` asks (probed on
      // tvOS 26.5, 2026-10-25), so a synopsis with an information table cannot live in it.
      Color.black.opacity(InfoPopupMetrics.scrimOpacity)
        .ignoresSafeArea()
      VStack(spacing: 0) {
        scrollingText
        if let confirmTitle {
          Button(action: close) { confirmTitle }
            .focused($confirmFocused)
            .padding(.bottom, InfoPopupMetrics.padding)
        }
      }
      .frame(maxWidth: InfoPopupMetrics.maxWidth)
      // The system's glass, rim and all — the material the tvOS sheet itself is drawn in.
      .glassEffect(.regular,
                   in: RoundedRectangle(cornerRadius: InfoPopupMetrics.cornerRadius, style: .continuous))
      .padding(60)
      .defaultFocus($confirmFocused, confirmTitle != nil, priority: .userInitiated)
      // One focus stop — the button, or the text when there is none — so Up and Down
      // have nowhere to move focus and page the text instead. With the text as a second
      // stop, Down from it jumped straight back to the button and nothing ever scrolled.
      .onMoveCommand { direction in
        guard let target = ScrollPage.target(of: scrollGeometry, direction: direction) else { return }
        withAnimation(.easeInOut(duration: 0.3)) { scrollPosition.scrollTo(y: target) }
      }
    }
    // A popup shown by UIKit has no sheet to pop; Menu closes it the same way.
    .onExitCommand(perform: close)
#else
    VStack(alignment: .leading, spacing: 0) {
      scrollingText
      Button(action: close) { confirmTitle ?? Text("Close") }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .frame(maxWidth: .infinity, alignment: confirmTitle == nil ? .leading : .center)
        .padding([.horizontal, .bottom], InfoPopupMetrics.padding)
    }
    .frame(maxWidth: InfoPopupMetrics.maxWidth, alignment: .leading)
#endif
  }

  /// The text at its natural height when it fits, a scroll view when it does not.
  private var scrollingText: some View {
    ViewThatFits(in: .vertical) {
      text
      ScrollView(.vertical) { text }
#if os(tvOS)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: ScrollPage.Geometry.self) {
          ScrollPage.Geometry(offset: $0.contentOffset.y,
                              viewport: $0.containerSize.height,
                              content: $0.contentSize.height)
        } action: { _, geometry in
          scrollGeometry = geometry
        }
#endif
        // Lines fade at the edges rather than being cut by them — the padding is the fade.
        .mask {
          LinearGradient(stops: [.init(color: .clear, location: 0),
                                 .init(color: .black, location: 0.05),
                                 .init(color: .black, location: 0.92),
                                 .init(color: .clear, location: 1)],
                         startPoint: .top, endPoint: .bottom)
        }
    }
#if os(tvOS)
    // The text is the focus stop when there is no button: a modal with no focusable
    // view never gets the Menu press.
    .focusable(confirmTitle == nil)
#endif
  }

  private var text: some View {
    VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing) {
      VStack(alignment: .leading, spacing: 8) {
        title
          .font(InfoPopupMetrics.titleFont)
          .foregroundStyle(Color.KinoPub.text)
        if let subtitle {
          subtitle
            .font(InfoPopupMetrics.subtitleFont)
            .foregroundStyle(Color.KinoPub.subtitle)
        }
      }
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(InfoPopupMetrics.padding)
  }

  private func close() {
    if let onDismiss { onDismiss() } else { environmentDismiss() }
  }
}

/// A headed block inside the popup — «Информация» under a synopsis.
public struct InfoPopupSection<Content: View>: View {
  let title: Text
  let content: () -> Content

  public init(_ title: Text, @ViewBuilder content: @escaping () -> Content) {
    self.title = title
    self.content = content
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing * 0.75) {
      title
        .font(InfoPopupMetrics.sectionFont)
        .foregroundStyle(Color.KinoPub.subtitle)
      content()
    }
    .padding(.top, InfoPopupMetrics.contentSpacing * 0.5)
  }
}

/// One fact: a grey label over its value, as the TV app's information table stacks them.
public struct InfoPopupFact: View {
  let label: Text
  let value: String

  public init(_ label: Text, value: String) {
    self.label = label
    self.value = value
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      label
        .font(InfoPopupMetrics.captionFont)
        .foregroundStyle(Color.KinoPub.subtitle)
      Text(verbatim: value)
        .font(InfoPopupMetrics.bodyFont)
        .foregroundStyle(Color.KinoPub.text)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

#if os(tvOS)
/// Up / Down on the remote, as a page of the popup's text.
public enum ScrollPage {
  public struct Geometry: Equatable {
    public var offset: CGFloat
    public var viewport: CGFloat
    public var content: CGFloat

    public init(offset: CGFloat = 0, viewport: CGFloat = 0, content: CGFloat = 0) {
      self.offset = offset
      self.viewport = viewport
      self.content = content
    }
  }

  /// Where a press moves the text: most of a page, so a line or two stays on screen
  /// for the eye to follow. Nil when it would not move.
  public static func target(of geometry: Geometry, direction: MoveCommandDirection) -> CGFloat? {
    let step: CGFloat
    switch direction {
    case .up: step = -geometry.viewport * 0.8
    case .down: step = geometry.viewport * 0.8
    default: return nil
    }
    let maxOffset = max(0, geometry.content - geometry.viewport)
    let target = min(max(0, geometry.offset + step), maxOffset)
    return abs(target - geometry.offset) > 0.5 ? target : nil
  }
}
#endif

// MARK: - Presentation

public extension View {
  /// Presents `content` in the shared info popup.
  ///
  /// Prefer `expandsIntoInfoPopup` — it makes the clipped content itself the control,
  /// which is the whole point. Use this directly only when the trigger genuinely is
  /// somewhere else.
  func infoPopup<Content: View>(
    _ title: Text,
    subtitle: Text? = nil,
    confirmTitle: Text? = nil,
    isPresented: Binding<Bool>,
    onDismiss: (() -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    modifier(InfoPopupModifier(title: title, subtitle: subtitle, confirmTitle: confirmTitle,
                               isPresented: isPresented, onDismiss: onDismiss,
                               popupContent: content))
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
  let subtitle: Text?
  let confirmTitle: Text?
  @Binding var isPresented: Bool
  let onDismiss: (() -> Void)?
  @ViewBuilder let popupContent: () -> PopupContent

  func body(content: Content) -> some View {
#if os(tvOS)
    // A cover, not a sheet: our own scrim + panel draw the popup, and a tvOS sheet frames
    // them in a second, larger platter of its own. Clear, or the cover lays an opaque
    // page behind them and it reads as a pushed screen rather than a popup.
    content
      .fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss) {
        panel
          .presentationBackground(.clear)
      }
#else
    content
      .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
        panel
#if os(iOS)
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
#endif
      }
#endif
  }

  private var panel: some View {
    InfoPopupView(title: title, subtitle: subtitle, confirmTitle: confirmTitle,
                  content: popupContent)
  }
}

#if canImport(UIKit)
/// The same popup, for a UIKit screen that has no SwiftUI view to hang `.infoPopup` on
/// (tvOS Settings runs on TVSettingKit). Over the full screen with a crossfade, as the
/// tvOS sheet draws it.
@MainActor
public enum InfoPopupPresenter {
  public static func controller<Content: View>(
    title: Text,
    subtitle: Text? = nil,
    confirmTitle: Text? = nil,
    onDismiss: (() -> Void)? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) -> UIViewController {
    let controller = UIHostingController(rootView: AnyView(EmptyView()))
    controller.rootView = AnyView(
      InfoPopupView(title: title, subtitle: subtitle, confirmTitle: confirmTitle,
                    onDismiss: { [weak controller] in
                      controller?.presentingViewController?.dismiss(animated: true, completion: onDismiss)
                    },
                    content: content)
    )
    controller.view.backgroundColor = .clear
    controller.modalPresentationStyle = .overFullScreen
    controller.modalTransitionStyle = .crossDissolve
    return controller
  }
}
#endif

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
          .foregroundStyle(Color.KinoPub.subtitle)
      }
  }
  .padding(40)
  .frame(maxWidth: 820, alignment: .leading)
  // .preferredColorScheme(.dark)
}
#endif
