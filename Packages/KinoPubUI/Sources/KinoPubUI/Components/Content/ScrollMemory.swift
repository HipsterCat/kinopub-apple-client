//
//  ScrollMemory.swift
//  KinoPubUI
//
//  Where a page was scrolled to, kept by the page's long-lived model so that coming back
//  to a section finds it where it was left (Sasha, 2026-10-31). Not observable on
//  purpose: the offset is written on every scroll frame and nothing redraws for it.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

public final class ScrollMemory {
  /// The top of the visible area, in content points.
  public var y: CGFloat = 0
  public init() {}
}

public extension EnvironmentValues {
  /// The memory for the page's main vertical scroll. A section sets it on its root page;
  /// a page pushed over it gets its own, or none.
  @Entry var scrollMemory: ScrollMemory? = nil
  /// Bumped when the section's page is asked back to its top: the section chosen again
  /// while already at its root (Sasha, 2026-10-31).
  @Entry var scrollToTopRequest: Int = 0
  /// A keyboard scroll of the page's main vertical scroll (Mac), from whatever holds
  /// focus in the page.
  @Entry var pageScrollRequest: PageScrollRequest? = nil
}

/// Page Up / Down, Space, Home / End and the arrows on the page, as in any Mac scroll
/// view. Each request has its own id, so the same key twice scrolls twice.
public struct PageScrollRequest: Equatable, Sendable {
  public enum Kind: Sendable { case lineUp, lineDown, pageUp, pageDown, top, bottom }
  public let id: UUID
  public let kind: Kind

  public init(_ kind: Kind) {
    self.id = UUID()
    self.kind = kind
  }
}

public extension View {
  /// Remembers this scroll view's offset in `scrollMemory` and goes back to it when the
  /// page comes back, and goes to the top on `scrollToTopRequest`.
  func remembersScroll() -> some View {
    modifier(RememberedScroll())
  }
}

private struct RememberedScroll: ViewModifier {
  @Environment(\.scrollMemory) private var memory
  @Environment(\.scrollToTopRequest) private var scrollToTopRequest
  @State private var position = ScrollPosition(edge: .top)
#if os(macOS)
  @Environment(\.pageScrollRequest) private var pageScrollRequest
  @State private var scrollView = EnclosedScrollView()
#endif

  func body(content: Content) -> some View {
    content
      .scrollPosition($position)
#if os(macOS)
      // The offset straight from AppKit's clip view, outside SwiftUI: a scroll observer
      // on the page logged «OnScrollGeometryChange / OnScrollPhaseContextChange tried to
      // update multiple times per frame» on every trackpad scroll (Sasha, 2026-11-04).
      .background(EnclosedScrollViewProbe(box: scrollView, memory: memory))
      .onChange(of: pageScrollRequest) { _, request in
        if let request { scrollView.perform(request.kind) }
      }
#else
      .onScrollPhaseChange { _, phase, context in
        guard phase == .idle else { return }
        let geometry = context.geometry
        memory?.y = max(geometry.contentOffset.y + geometry.contentInsets.top, 0)
      }
#endif
      .task {
        // Once the lazy content has laid out down to where the page was.
        guard let memory, memory.y > 1 else { return }
        let y = memory.y
        for _ in 0..<3 {
          try? await Task.sleep(for: .milliseconds(80))
          position.scrollTo(y: y)
        }
      }
      .onChange(of: scrollToTopRequest) {
        withAnimation { position.scrollTo(edge: .top) }
      }
  }
}

#if os(macOS)
/// Adapter: the page's `NSScrollView`, found next to the SwiftUI `ScrollView` that hosts it.
///
/// Limitation (macOS 27.2 SDK): SwiftUI gives the page's scroll no keyboard scrolling while
/// focus sits on the page (the shell keeps it there for the hero's arrows) — Page Down,
/// Space and the arrows only beeped — and every SwiftUI way to read the offset is a
/// per-frame scroll observer, which logs «tried to update multiple times per frame» under a
/// trackpad. AppKit's clip view has both: its bounds are the offset, and scrolling it is
/// what the keys do in any Mac scroll view.
@MainActor
final class EnclosedScrollView {
  weak var view: NSScrollView?
  nonisolated(unsafe) private var observer: NSObjectProtocol?

  func attach(_ scrollView: NSScrollView, memory: ScrollMemory?) {
    guard scrollView !== view else { return }
    if let observer { NotificationCenter.default.removeObserver(observer) }
    view = scrollView
    let clip = scrollView.contentView
    clip.postsBoundsChangedNotifications = true
    observer = NotificationCenter.default.addObserver(
      forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
    ) { [weak memory, weak clip] _ in
      MainActor.assumeIsolated {
        guard let memory, let clip, let scroll = clip.enclosingScrollView else { return }
        memory.y = max(clip.bounds.origin.y + scroll.contentInsets.top, 0)
      }
    }
  }

  func perform(_ kind: PageScrollRequest.Kind) {
    guard let scrollView = view, let document = scrollView.documentView else { return }
    let clip = scrollView.contentView
    let top = -scrollView.contentInsets.top
    let visible = clip.bounds.height - scrollView.contentInsets.top - scrollView.contentInsets.bottom
    let bottom = max(document.frame.height - clip.bounds.height + scrollView.contentInsets.bottom, top)
    let line = max(scrollView.verticalLineScroll, 40)
    let page = max(visible - max(scrollView.verticalPageScroll, line), line)
    let y = clip.bounds.origin.y
    let target: CGFloat
    switch kind {
    case .lineUp: target = y - line
    case .lineDown: target = y + line
    case .pageUp: target = y - page
    case .pageDown: target = y + page
    case .top: target = top
    case .bottom: target = bottom
    }
    let clamped = min(max(target, top), bottom)
    guard abs(clamped - y) > 0.5 else { NSSound.beep(); return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = kind == .lineUp || kind == .lineDown ? 0.1 : 0.25
      context.allowsImplicitAnimation = true
      clip.animator().setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: clamped))
    }
    scrollView.reflectScrolledClipView(clip)
  }

  deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }
}

/// Sits behind the SwiftUI scroll view with the same frame and picks the `NSScrollView`
/// that fills it — the page's, not a rail's, which are shorter.
private struct EnclosedScrollViewProbe: NSViewRepresentable {
  let box: EnclosedScrollView
  let memory: ScrollMemory?

  func makeNSView(context: Context) -> Probe { Probe() }

  func updateNSView(_ probe: Probe, context: Context) {
    probe.onFound = { [box, memory] in box.attach($0, memory: memory) }
    probe.find()
  }

  final class Probe: NSView {
    var onFound: ((NSScrollView) -> Void)?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      find()
    }

    override func layout() {
      super.layout()
      find()
    }

    func find() {
      guard window != nil, let onFound else { return }
      let mine = convert(bounds, to: nil)
      guard mine.width > 1, mine.height > 1 else { return }
      var ancestor = superview
      while let current = ancestor {
        if let match = Self.scrollView(in: current, filling: mine) {
          onFound(match)
          return
        }
        ancestor = current.superview
      }
    }

    private static func scrollView(in view: NSView, filling rect: NSRect) -> NSScrollView? {
      for sub in view.subviews {
        if let scroll = sub as? NSScrollView {
          let frame = scroll.convert(scroll.bounds, to: nil)
          if abs(frame.width - rect.width) < 2, abs(frame.height - rect.height) < 2 {
            return scroll
          }
        }
      }
      return nil
    }
  }
}
#endif
