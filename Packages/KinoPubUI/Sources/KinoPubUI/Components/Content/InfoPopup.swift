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
//  panel over a scrim on tvOS (where Menu dismisses it for free), large +
//  `.presentationSizing(.page)` on iPhone/iPad (What's New and detail info), and a
//  page-hosted panel on macOS. A UIKit screen presents the same view through
//  `InfoPopupPresenter`. What's New, the changelog and the licences use it too.
//  `.claude/skills/tvos-surface/SKILL.md` — `description handlesOverflow` is a popup,
//  and there is exactly one of it.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - Metrics

public enum InfoPopupMetrics {
#if os(tvOS)
  public static let maxWidth: CGFloat = 1280
  public static let padding: CGFloat = 64
  /// The system sheet's corner. What's New and the info sheet keep this size
  /// (Sasha, 2026-11-20: the dimensions were already right).
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
  public static let cornerRadius: CGFloat = 24
  public static let titleFont: Font = .title2
  public static let subtitleFont: Font = .subheadline
  public static let bodyFont: Font = .body
  public static let captionFont: Font = .footnote
  public static let sectionFont: Font = .title2.bold()
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
  public static let sectionFont: Font = .title2.bold()
  public static let contentSpacing: CGFloat = 18
  public static let scrimOpacity: Double = 0.5
#endif
}

#if os(tvOS)
/// Chrome for «Выберите версию» only. What's New and the info sheet keep
/// `InfoPopupView`'s own size.
private enum VersionSheetChromeMetrics {
  static let maxWidth: CGFloat = 760
  static let cornerRadius: CGFloat = 46
}

public extension View {
  /// The version chooser's content-sized card. Not the info sheet.
  func tvHeroSheet() -> some View {
    modifier(TVHeroSheetChrome())
  }
}

private struct TVHeroSheetChrome: ViewModifier {
  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: VersionSheetChromeMetrics.cornerRadius, style: .continuous)
    ZStack {
      Color.clear
      content
        .frame(maxWidth: VersionSheetChromeMetrics.maxWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background {
          shape
            .fill(Color.black.opacity(0.01))
            .shadow(color: .black.opacity(0.55), radius: 40, y: 20)
        }
        .kinoGlass(in: shape)
        .overlay {
          shape.strokeBorder(Color.primary.opacity(0.28), lineWidth: 1.5)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
#endif

// MARK: - Panel

/// The popup's own chrome. Everything inside is content the caller supplies — this
/// owns the frame, the scroll, and the way out.
///
/// `confirmTitle` adds a real button under the content: on tvOS What's New's «Готово»
/// (entry focus; without it Menu alone dismisses); on iPhone / iPad / Mac
/// «Продолжить» / Continue at the bottom, with the same leading cross as detail info.
/// Short content hugs the panel on Mac (`ViewThatFits`); long content scrolls inside a
/// 560pt cap with a visible scrollbar. Phone / pad keep the large sheet top-aligned.
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
#if !os(tvOS)
  @State private var isScrolled = false
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
    // Same panel as before: the page dims, the card stays the wide sheet. The glass
    // shadow was right and too light, and the platter had no stroke (Sasha, 2026-11-20).
    ZStack {
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
      .background {
        RoundedRectangle(cornerRadius: InfoPopupMetrics.cornerRadius, style: .continuous)
          .fill(Color.black.opacity(0.01))
          .shadow(color: .black.opacity(0.8), radius: 70, y: 32)
      }
      .kinoGlass(in: RoundedRectangle(cornerRadius: InfoPopupMetrics.cornerRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: InfoPopupMetrics.cornerRadius, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5)
      }
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
    // What's New and film info share one chrome: material toolbar + hierarchical X,
    // top-aligned body, optional Continue footer (Sasha, 2026-11-21).
    phonePadMacPanel
#endif
  }

#if !os(tvOS)
  private var phonePadMacPanel: some View {
#if os(macOS)
    // Hug short notes; when the body is taller than the cap, ViewThatFits picks the
    // scrolling panel. `.fixedSize` + ScrollView was wrong: the scroll view grew to
    // its ideal height, the maxHeight clipped it, and nothing ever scrolled (Sasha,
    // 2026-11-26 — no chrome fade, no scrollbar).
    ViewThatFits(in: .vertical) {
      macColumn(scrolling: false)
      macColumn(scrolling: true)
    }
    .frame(maxHeight: 560)
#else
    VStack(spacing: 0) {
      toolbarHeader
      ScrollView(.vertical) {
        panelBody
      }
      .scrollBounceBehavior(.basedOnSize)
      .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 4 } action: { _, scrolled in
        isScrolled = scrolled
      }
      if let confirmTitle {
        continueButton(confirmTitle)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
#endif
  }

#if os(macOS)
  /// Shared Mac column: natural height when `scrolling` is false, capped ScrollView
  /// with a visible scrollbar when true.
  private func macColumn(scrolling: Bool) -> some View {
    VStack(spacing: 0) {
      toolbarHeader
      if scrolling {
        ScrollView(.vertical) {
          panelBody
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.visible)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 4 } action: { _, scrolled in
          isScrolled = scrolled
        }
      } else {
        panelBody
      }
      if let confirmTitle {
        continueButton(confirmTitle)
      }
    }
    .frame(maxWidth: InfoPopupMetrics.maxWidth)
  }
#endif

  private var panelBody: some View {
    VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing) {
      if let subtitle {
        subtitle
          .font(.subheadline)
          .foregroundStyle(Color.KinoPub.subtitle)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, SheetCloseButton.side + SheetCloseButton.inset * 2)
      }
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, InfoPopupMetrics.padding)
    .padding(.top, InfoPopupMetrics.padding * 0.35)
    .padding(.bottom, InfoPopupMetrics.padding)
  }

  /// Centred title with the version-settings cross; material bar fades in as you scroll
  /// (same language as Settings / the title page toolbar).
  private var toolbarHeader: some View {
    ZStack {
      title
        .font(.headline)
        .foregroundStyle(Color.KinoPub.text)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SheetCloseButton.side + SheetCloseButton.inset * 2)
      HStack {
        SheetCloseButton(action: close)
          .padding(.leading, SheetCloseButton.inset)
        Spacer(minLength: 0)
      }
    }
    .frame(minHeight: SheetCloseButton.side + 12)
    .padding(.top, SheetCloseButton.inset)
    .padding(.bottom, 10)
    .background {
      Rectangle()
        .fill(.bar)
        .opacity(isScrolled ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: isScrolled)
        .ignoresSafeArea(edges: .top)
    }
  }

  /// `.borderedProminent` + `Color.primary` tint: readable in light and dark.
  /// `.glassProminent` was black-on-black on Mac and white-on-white on iPhone dark.
  private func continueButton(_ title: Text) -> some View {
    Button(action: close) {
      title
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .tint(Color.primary)
    .controlSize(.large)
    .keyboardShortcut(.defaultAction)
    .padding(.horizontal, InfoPopupMetrics.padding)
#if os(macOS)
    .padding(.top, 16)
    .padding(.bottom, InfoPopupMetrics.padding)
#else
    // Extra air above Continue on phone — the button was flush under short copy.
    .padding(.top, 28)
    .padding(.bottom, InfoPopupMetrics.padding)
#endif
  }
#endif

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
#if os(tvOS)
        // Lines fade at the edges rather than being cut by them — the padding is the fade.
        .mask {
          LinearGradient(stops: [.init(color: .clear, location: 0),
                                 .init(color: .black, location: 0.05),
                                 .init(color: .black, location: 0.92),
                                 .init(color: .clear, location: 1)],
                         startPoint: .top, endPoint: .bottom)
        }
#endif
    }
#if os(tvOS)
    // The text is the focus stop when there is no button: a modal with no focusable
    // view never gets the Menu press.
    .focusable(confirmTitle == nil)
#endif
  }

  private var text: some View {
    VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing) {
#if os(tvOS)
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
#endif
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
#if os(tvOS)
        .foregroundStyle(Color.KinoPub.subtitle)
#else
        // The TV app's sheet: «Информация», «Языки» in bold primary.
        .foregroundStyle(Color.KinoPub.text)
#endif
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
#if os(tvOS)
      label
        .font(InfoPopupMetrics.captionFont)
        .foregroundStyle(Color.KinoPub.subtitle)
      if !value.isEmpty {
        Text(verbatim: value)
          .font(InfoPopupMetrics.bodyFont)
          .foregroundStyle(Color.KinoPub.text)
          .fixedSize(horizontal: false, vertical: true)
      }
#else
      // The TV app's sheet: the row's name primary, what it says secondary («Премьера»
      // over «2026»). A row with nothing to say is its name alone, not a name over a gap.
      label
        .font(InfoPopupMetrics.bodyFont)
        .foregroundStyle(Color.KinoPub.text)
      if !value.isEmpty {
        Text(verbatim: value)
          .font(InfoPopupMetrics.bodyFont)
          .foregroundStyle(Color.KinoPub.subtitle)
          .fixedSize(horizontal: false, vertical: true)
      }
#endif
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
    subtitle: Text? = nil,
    isEnabled: Bool = true,
    chrome: InfoPopupTriggerChrome = .card,
    @ViewBuilder expanded: @escaping () -> Expanded
  ) -> some View {
    modifier(InfoPopupTrigger(title: title, subtitle: subtitle, isEnabled: isEnabled,
                              chrome: chrome, expanded: expanded))
  }
}

private struct InfoPopupModifier<PopupContent: View>: ViewModifier {
  let title: Text
  let subtitle: Text?
  let confirmTitle: Text?
  @Binding var isPresented: Bool
  let onDismiss: (() -> Void)?
  @ViewBuilder let popupContent: () -> PopupContent

  /// What's New dims the Mac host; detail info stays undimmed but still outside-clickable.
  private var usesConfirmLayout: Bool { confirmTitle != nil }

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
#elseif os(macOS)
    if let host {
      // Inside a page that hosts popups: the TV app's panel, not a sheet — click outside
      // closes it. What's New also dims and blocks the page so it cannot scroll behind.
      content
        .onChange(of: isPresented) { _, presented in
          if presented {
            host.present(AnyView(hostedPanel),
                         dimsBackground: usesConfirmLayout,
                         onClose: { isPresented = false })
          } else {
            host.dismiss()
            onDismiss?()
          }
        }
    } else {
      content
        .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
          panel
            .macSheetFrame(width: 520, height: usesConfirmLayout ? 480 : 560)
        }
    }
#else
    content
      .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
        // What's New and film info: large / page at once — not a half-height drawer
        // (Sasha, 2026-11-21).
        panel
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
          .presentationSizing(.page)
      }
#endif
  }

#if os(macOS)
  @Environment(\.infoPopupHost) private var host

  private var hostedPanel: some View {
    InfoPopupView(title: title, subtitle: subtitle, confirmTitle: confirmTitle,
                  onDismiss: { isPresented = false },
                  content: popupContent)
      .pageColorScheme()
  }
#endif

  /// In the window's appearance, not the presenter's: the hero forces itself dark.
  private var panel: some View {
    InfoPopupView(title: title, subtitle: subtitle, confirmTitle: confirmTitle,
                  content: popupContent)
      .pageColorScheme()
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
  let subtitle: Text?
  let isEnabled: Bool
  let chrome: InfoPopupTriggerChrome
  @ViewBuilder let expanded: () -> Expanded

  @State private var isPresented = false

  func body(content: Content) -> some View {
    if isEnabled {
      trigger(content)
        .infoPopup(title, subtitle: subtitle, isPresented: $isPresented) {
          expanded()
        }
#if DEBUG
        // `-KINOPUBOpenSynopsis YES`: the hero synopsis opens its popup, for screenshots.
        .task {
          guard chrome == .text, UserDefaults.standard.bool(forKey: "KINOPUBOpenSynopsis") else { return }
          try? await Task.sleep(for: .seconds(2))
          isPresented = true
        }
#endif
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
  @MainActor
  public static var buttonStyle: some PrimitiveButtonStyle {
#if os(tvOS)
    .card
#else
    .plain
#endif
  }

  /// The stock borderless style on tvOS: no chrome at rest, the platform's own treatment
  /// on focus. The same choice the season tabs made (`SeasonsRailView`).
  @MainActor
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

#if os(macOS)
// MARK: - Page-hosted panel (macOS)

/// Where a page shows its info popups on a Mac: over the page, as the TV app does — a
/// panel in the window's background colour that belongs to the page, leaves the page
/// behind it live (it still scrolls) and closes on a click anywhere outside it or on
/// Escape. A system sheet blocked the whole window and only «Готово» closed it (Sasha,
/// 2026-10-30). Pages without a host keep the sheet.
@MainActor
@Observable
public final class InfoPopupHost {
  fileprivate var panel: AnyView?
  fileprivate var onClose: (() -> Void)?
  /// What's New dims the page; detail info leaves it live and undimmed.
  fileprivate var dimsBackground: Bool = false
  /// The panel's frame in the window, top-left origin, for the outside-click test.
  fileprivate var panelFrame: CGRect = .zero

  public init() {}

  fileprivate func present(
    _ view: AnyView,
    dimsBackground: Bool = false,
    onClose: @escaping () -> Void
  ) {
    self.onClose = onClose
    self.dimsBackground = dimsBackground
    panel = view
  }

  fileprivate func dismiss() {
    guard panel != nil else { return }
    panel = nil
    dimsBackground = false
    let close = onClose
    onClose = nil
    close?()
  }
}

public extension EnvironmentValues {
  @Entry var infoPopupHost: InfoPopupHost? = nil
}

public extension View {
  /// Shows this page's info popups as the TV app's panel over it (see `InfoPopupHost`).
  func hostsInfoPopups() -> some View {
    modifier(InfoPopupHostOverlay())
  }
}

private struct InfoPopupHostOverlay: ViewModifier {
  @State private var host = InfoPopupHost()
  @State private var monitor: Any?

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: InfoPopupMetrics.cornerRadius, style: .continuous)
  }

  func body(content: Content) -> some View {
    content
      .environment(\.infoPopupHost, host)
      .overlay {
        if let panel = host.panel {
          ZStack {
            if host.dimsBackground {
              // Absorb clicks and scroll so the page behind cannot move (Sasha, 2026-11-21).
              Color.black.opacity(InfoPopupMetrics.scrimOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { host.dismiss() }
                .transition(.opacity)
            }
            hostedCard(panel)
              .transition(.opacity.combined(with: .scale(scale: 0.97)))
          }
        }
      }
      .animation(.easeOut(duration: 0.2), value: host.panel != nil)
      .onChange(of: host.panel != nil) { _, shown in
        shown ? startMonitoring() : stopMonitoring()
      }
      .onDisappear {
        stopMonitoring()
        host.dismiss()
      }
  }

  /// Content-sized card centred in the window — What's New and detail info both hug
  /// their text; a lone bullet must not stretch to a full-height Reminders card.
  private func hostedCard(_ panel: AnyView) -> some View {
    panel
      .background(Color(nsColor: .windowBackgroundColor), in: shape)
      .clipShape(shape)
      .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
      .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
      .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { host.panelFrame = $0 }
      .frame(maxWidth: 520)
      .padding(InfoPopupMetrics.padding * 2)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// A click outside the panel closes it and still goes where it was aimed; Escape closes
  /// it and goes nowhere. When the page is dimmed, scroll wheels *outside* the panel are
  /// swallowed so the page behind cannot move — events over the panel must reach the
  /// ScrollView (swallowing all wheels made What's New unscrollable; Sasha, 2026-11-26).
  private func startMonitoring() {
    stopMonitoring()
    let host = host
    monitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]
    ) { event in
      let height = event.window?.contentView?.bounds.height ?? 0
      let point = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
      if event.type == .scrollWheel {
        if host.dimsBackground, !host.panelFrame.contains(point) { return nil }
        return event
      }
      if event.type == .keyDown {
        guard event.keyCode == 53 else { return event }
        host.dismiss()
        return nil
      }
      if !host.panelFrame.contains(point) { host.dismiss() }
      return event
    }
  }

  private func stopMonitoring() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }
}
#endif
