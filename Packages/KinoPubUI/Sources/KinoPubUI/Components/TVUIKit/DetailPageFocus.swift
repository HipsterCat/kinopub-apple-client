#if os(tvOS)
//
//  DetailPageFocus.swift
//  KinoPubUI
//
//  Two focus policies for the detail page, both the engine's:
//
//  Menu below the hero scrolls back to it. A UIKit card never delivers Menu to
//  SwiftUI's `onExitCommand`, so the navigation controller pops. The page installs
//  a handler; the rails and the embedded page ask it, and only when the focused
//  item is inside that page. At the hero the handler declines and the stack pops.
//
//  Up into the button row from the right used to land on whichever circle is
//  nearest (the ellipsis). A full-width `UIFocusGuide` over that band redirects
//  to the entry control — Play, or Follow when it leads. The guide is disabled
//  while a button already has focus, so Left and Right stay between the buttons.
//  It does not become the focused item, and nothing writes `@FocusState`.
//

import SwiftUI
import UIKit

// MARK: - Menu

@MainActor
public enum DetailPageMenu {
  /// Every detail page's anchor still alive. A title opened from a title is a second
  /// page with a second anchor, and the page underneath keeps its own: one static
  /// "current" anchor was cleared when the page above left, so Menu on the page
  /// beneath popped it at once instead of going back up to its hero (Sasha, 2026-11-17).
  static let anchors = NSHashTable<DetailPageMenuAnchorView>.weakObjects()

  /// True when this press was eaten. False leaves Menu to the responder chain
  /// (the navigation stack, or a page that is not the detail page).
  public static func consumeIfFocusIsInPage() -> Bool {
    for anchor in anchors.allObjects {
      guard let window = anchor.window,
            let focused = focusedView(in: window),
            let scroll = anchor.enclosingScroll,
            focused.isDescendant(of: scroll) else { continue }
      return anchor.onMenu?() ?? false
    }
    return false
  }

  /// The scroll of the detail page that holds focus now, if any.
  static func focusedPageScroll() -> UIScrollView? {
    for anchor in anchors.allObjects {
      guard let window = anchor.window,
            let focused = focusedView(in: window),
            let scroll = anchor.enclosingScroll,
            focused.isDescendant(of: scroll) else { continue }
      return scroll
    }
    return nil
  }

  private static func focusedView(in window: UIWindow) -> UIView? {
    guard let item = UIFocusSystem.focusSystem(for: window)?.focusedItem else { return nil }
    if let view = item as? UIView { return view }
    return mirroredView(from: item, depth: 0)
  }

  private static func mirroredView(from subject: Any, depth: Int) -> UIView? {
    guard depth < 4 else { return nil }
    if let view = subject as? UIView { return view }
    for child in Mirror(reflecting: subject).children {
      if let found = mirroredView(from: child.value, depth: depth + 1) { return found }
    }
    return nil
  }
}

public struct DetailPageMenuAnchor: UIViewRepresentable {
  var onMenu: () -> Bool

  public init(onMenu: @escaping () -> Bool) {
    self.onMenu = onMenu
  }

  public func makeUIView(context: Context) -> DetailPageMenuAnchorView {
    let view = DetailPageMenuAnchorView()
    view.isUserInteractionEnabled = false
    view.isAccessibilityElement = false
    view.onMenu = onMenu
    return view
  }

  public func updateUIView(_ view: DetailPageMenuAnchorView, context: Context) {
    view.onMenu = onMenu
  }
}

public final class DetailPageMenuAnchorView: UIView {
  var onMenu: (() -> Bool)?

  public override var canBecomeFocused: Bool { false }

  var enclosingScroll: UIScrollView? {
    var view: UIView? = superview
    while let current = view {
      if let scroll = current as? UIScrollView { return scroll }
      view = current.superview
    }
    return nil
  }

  public override func didMoveToWindow() {
    super.didMoveToWindow()
    DetailPageMenu.anchors.add(self)
  }
}

// MARK: - Button-row guide

@MainActor
public enum HeroEntryFocus {
  /// Every page's button-row guide; `request` asks the one on the page with focus.
  static let guides = NSHashTable<HeroButtonRowGuideView>.weakObjects()

  /// Asks the engine to land on the entry control the guide names. Logs when the
  /// focused item afterwards is not that control.
  public static func request() {
    let inWindow = guides.allObjects.filter { $0.window != nil }
    let scroll = DetailPageMenu.focusedPageScroll()
    let guide = inWindow.first { guide in scroll.map { guide.isDescendant(of: $0) } ?? false }
      ?? (inWindow.count == 1 ? inWindow.first : nil)
    guard let guide else {
      FocusLog.rejected(heading: "menu", preferred: "hero entry", chosen: "—",
                        reason: "the button-row focus guide is not in the window")
      return
    }
    guide.requestEntry()
  }
}

public struct HeroButtonRowGuide: UIViewRepresentable {
  /// For the log only: which control the marker stands on.
  var entryIdentifier: String
  /// Focus is already on a hero button: the guide must not sit on top of Left/Right.
  var suspended: Bool

  public init(entryIdentifier: String, suspended: Bool) {
    self.entryIdentifier = entryIdentifier
    self.suspended = suspended
  }

  public func makeUIView(context: Context) -> HeroButtonRowGuideView {
    let view = HeroButtonRowGuideView()
    view.isUserInteractionEnabled = false
    view.isAccessibilityElement = false
    view.entryIdentifier = entryIdentifier
    view.suspended = suspended
    return view
  }

  public func updateUIView(_ view: HeroButtonRowGuideView, context: Context) {
    view.entryIdentifier = entryIdentifier
    view.suspended = suspended
    view.retarget()
  }
}

/// Put behind the entry control (Play, or Follow when it leads). The guide finds the
/// control's focus item under it.
///
/// Why a marker: a SwiftUI button is not a `UIView` with an `accessibilityIdentifier`.
/// The identifier lives in the accessibility tree only, so the guide that looked the
/// control up by identifier among UIKit views never found it, stayed disabled, and Up
/// from the right of the row went to «…» or flew over the row onto the synopsis
/// (Sasha, 2026-11-17). The focus item itself is what the hosting view hands out
/// through `UIFocusItemContainer`, at the marker's place.
public struct HeroEntryMarker: UIViewRepresentable {
  public init() {}

  public func makeUIView(context: Context) -> HeroEntryMarkerView {
    let view = HeroEntryMarkerView()
    view.isUserInteractionEnabled = false
    view.isAccessibilityElement = false
    return view
  }

  public func updateUIView(_ view: HeroEntryMarkerView, context: Context) {}
}

public final class HeroEntryMarkerView: UIView {
  public override var canBecomeFocused: Bool { false }
}

public final class HeroButtonRowGuideView: UIView {
  let guide = UIFocusGuide()
  var entryIdentifier = "kinopub.hero.play"
  var suspended = false
  private var reportedMissingEntry = false

  public override var canBecomeFocused: Bool { false }

  /// The guide prefers this view, and this view answers with the entry control's focus
  /// item at the moment the engine asks — SwiftUI rebuilds its items, so a stored one
  /// goes stale. Menu asks this view the same way.
  public override var preferredFocusEnvironments: [UIFocusEnvironment] {
    if let target = resolveEntry() { return [target] }
    return []
  }

  public override init(frame: CGRect) {
    super.init(frame: frame)
    addLayoutGuide(guide)
    guide.preferredFocusEnvironments = [self]
    NSLayoutConstraint.activate([
      guide.leadingAnchor.constraint(equalTo: leadingAnchor),
      guide.trailingAnchor.constraint(equalTo: trailingAnchor),
      guide.topAnchor.constraint(equalTo: topAnchor),
      guide.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  public override func didMoveToWindow() {
    super.didMoveToWindow()
    HeroEntryFocus.guides.add(self)
    if window != nil { retarget() }
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    retarget()
  }

  func retarget() {
    let found = window != nil && marker != nil
    guide.isEnabled = !suspended && found
    if window != nil, !found, !reportedMissingEntry {
      reportedMissingEntry = true
      FocusLog.rejected(heading: "up", preferred: entryIdentifier, chosen: "—",
                        reason: "the button-row guide found no entry marker on its page; the guide is off")
    }
  }

  func requestEntry() {
    retarget()
    guard let system = window.flatMap({ UIFocusSystem.focusSystem(for: $0) }) else {
      FocusLog.rejected(heading: "menu", preferred: entryIdentifier, chosen: "—",
                        reason: "no focus system for the hero")
      return
    }
    let before = Self.describe(system.focusedItem)
    guard let target = resolveEntry() else {
      FocusLog.rejected(heading: "menu", preferred: entryIdentifier, chosen: before,
                        reason: "no focus item under the entry marker")
      return
    }
    system.requestFocusUpdate(to: target)
    system.updateFocusIfNeeded()
    if !isEntry(system.focusedItem) {
      FocusLog.rejected(heading: "menu", preferred: entryIdentifier,
                        chosen: Self.describe(system.focusedItem),
                        reason: "requestFocusUpdate did not land on the entry control (was \(before))")
    }
  }

  // MARK: Finding the entry control

  private var marker: HeroEntryMarkerView? {
    guard let root = enclosingScroll ?? window else { return nil }
    return Self.firstMarker(in: root)
  }

  private static func firstMarker(in view: UIView) -> HeroEntryMarkerView? {
    if let marker = view as? HeroEntryMarkerView, marker.window != nil { return marker }
    for subview in view.subviews {
      if let found = firstMarker(in: subview) { return found }
    }
    return nil
  }

  /// The smallest focusable item that covers the marker's centre, asked of the focus item
  /// containers above the marker, nearest first.
  private func resolveEntry() -> UIFocusItem? {
    guard let marker else { return nil }
    let center = CGPoint(x: marker.bounds.midX, y: marker.bounds.midY)
    var container: UIView? = marker.superview
    while let view = container {
      if let itemContainer = view.focusItemContainer {
        let space = itemContainer.coordinateSpace
        let point = marker.convert(center, to: space)
        // The marker's own rectangle, wherever the page is scrolled: Menu asks while the
        // scroll back to the hero is still running.
        let items = itemContainer.focusItems(in: marker.convert(marker.bounds, to: space))
        if let best = Self.smallestFocusable(in: items, covering: point, space: space, depth: 0) {
          return best
        }
      }
      container = view.superview
    }
    return nil
  }

  private static func smallestFocusable(in items: [UIFocusItem], covering point: CGPoint,
                                        space: UICoordinateSpace, depth: Int) -> UIFocusItem? {
    var best: (item: UIFocusItem, area: CGFloat)?
    for item in items {
      guard !(item is HeroEntryMarkerView), !(item is HeroButtonRowGuideView) else { continue }
      let frame = frameOf(item, in: space)
      guard frame.contains(point) else { continue }
      if item.canBecomeFocused {
        let area = frame.width * frame.height
        if best == nil || area < best!.area { best = (item, area) }
      } else if depth < 4, let nested = item.focusItemContainer {
        let probe = CGRect(origin: point, size: .zero).insetBy(dx: -1, dy: -1)
        let children = nested.focusItems(in: space.convert(probe, to: nested.coordinateSpace))
        if let found = smallestFocusable(in: children, covering: point, space: space, depth: depth + 1) {
          let area = frameOf(found, in: space).width * frameOf(found, in: space).height
          if best == nil || area < best!.area { best = (found, area) }
        }
      }
    }
    return best?.item
  }

  /// A focus item's frame is in its parent container's coordinate space.
  private static func frameOf(_ item: UIFocusItem, in space: UICoordinateSpace) -> CGRect {
    if let view = item as? UIView, let superview = view.superview {
      return superview.convert(view.frame, to: space)
    }
    guard let parentSpace = item.parentFocusEnvironment?.focusItemContainer?.coordinateSpace else {
      return item.frame
    }
    return parentSpace.convert(item.frame, to: space)
  }

  private func isEntry(_ item: UIFocusItem?) -> Bool {
    guard let item, let marker else { return false }
    let space = marker.coordinateSpace
    let center = CGPoint(x: marker.bounds.midX, y: marker.bounds.midY)
    return Self.frameOf(item, in: space).contains(center)
  }

  private var enclosingScroll: UIScrollView? {
    var view: UIView? = superview
    while let current = view {
      if let scroll = current as? UIScrollView { return scroll }
      view = current.superview
    }
    return nil
  }

  private static func describe(_ item: UIFocusItem?) -> String {
    guard let view = item as? UIView else { return item.map { "\(type(of: $0))" } ?? "—" }
    return view.accessibilityIdentifier ?? view.accessibilityLabel ?? "\(type(of: view))"
  }
}
#endif
