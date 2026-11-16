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
  static weak var anchor: DetailPageMenuAnchorView?

  /// True when this press was eaten. False leaves Menu to the responder chain
  /// (the navigation stack, or a page that is not the detail page).
  public static func consumeIfFocusIsInPage() -> Bool {
    guard let anchor, let window = anchor.window,
          let focused = focusedView(in: window),
          let scroll = anchor.enclosingScroll,
          focused.isDescendant(of: scroll) else { return false }
    return anchor.onMenu?() ?? false
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
    if window != nil {
      DetailPageMenu.anchor = self
    } else if DetailPageMenu.anchor === self {
      DetailPageMenu.anchor = nil
    }
  }
}

// MARK: - Button-row guide

@MainActor
public enum HeroEntryFocus {
  static weak var guide: HeroButtonRowGuideView?

  /// Asks the engine to land on the entry control the guide names. Logs when the
  /// focused item afterwards is not that control.
  public static func request() {
    guard let guide else {
      FocusLog.rejected(heading: "menu", preferred: "hero entry", chosen: "—",
                        reason: "the button-row focus guide is not in the window")
      return
    }
    guide.requestEntry()
  }
}

public struct HeroButtonRowGuide: UIViewRepresentable {
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

public final class HeroButtonRowGuideView: UIView {
  let guide = UIFocusGuide()
  var entryIdentifier = "kinopub.hero.play"
  var suspended = false

  public override var canBecomeFocused: Bool { false }

  /// Menu asks this view for focus. The engine then follows the environments
  /// below — the entry control — the same way a directional move follows the guide.
  /// A `UIFocusGuide` is not itself a focus environment `requestFocusUpdate` accepts.
  public override var preferredFocusEnvironments: [UIFocusEnvironment] {
    if let target = resolveEntry() { return [target] }
    return super.preferredFocusEnvironments
  }

  public override init(frame: CGRect) {
    super.init(frame: frame)
    addLayoutGuide(guide)
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
    if window != nil {
      HeroEntryFocus.guide = self
      retarget()
    } else if HeroEntryFocus.guide === self {
      HeroEntryFocus.guide = nil
    }
  }

  private var reportedMissingEntry = false

  func retarget() {
    let target = resolveEntry()
    guide.preferredFocusEnvironments = target.map { [$0] } ?? []
    guide.isEnabled = !suspended && target != nil
    if target == nil, window != nil, !reportedMissingEntry {
      reportedMissingEntry = true
      FocusLog.rejected(heading: "up", preferred: entryIdentifier, chosen: "—",
                        reason: "the button-row guide found no view named \(entryIdentifier); the guide is off")
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
                        reason: "entry control is not in the window")
      return
    }
    system.requestFocusUpdate(to: target)
    system.updateFocusIfNeeded()
    if !Self.matches(system.focusedItem, identifier: entryIdentifier) {
      system.requestFocusUpdate(to: self)
      system.updateFocusIfNeeded()
    }
    let chosen = Self.describe(system.focusedItem)
    if !Self.matches(system.focusedItem, identifier: entryIdentifier) {
      FocusLog.rejected(heading: "menu", preferred: entryIdentifier, chosen: chosen,
                        reason: "requestFocusUpdate did not land on the preferred control (was \(before))")
    }
  }

  private func resolveEntry() -> UIFocusEnvironment? {
    let root = enclosingScroll ?? window
    guard let root else { return nil }
    if let view = focusableView(identifier: entryIdentifier, in: root) { return view }
    if entryIdentifier != "kinopub.hero.play",
       let view = focusableView(identifier: "kinopub.hero.play", in: root) {
      return view
    }
    return nil
  }

  private var enclosingScroll: UIScrollView? {
    var view: UIView? = superview
    while let current = view {
      if let scroll = current as? UIScrollView { return scroll }
      view = current.superview
    }
    return nil
  }

  private func focusableView(identifier: String, in root: UIView) -> UIView? {
    if root.accessibilityIdentifier == identifier {
      if root.canBecomeFocused { return root }
      if let child = firstFocusable(in: root) { return child }
      return root
    }
    for subview in root.subviews {
      if let found = focusableView(identifier: identifier, in: subview) { return found }
    }
    return nil
  }

  private func firstFocusable(in view: UIView) -> UIView? {
    if view.canBecomeFocused { return view }
    for subview in view.subviews {
      if let found = firstFocusable(in: subview) { return found }
    }
    return nil
  }

  private static func matches(_ item: UIFocusItem?, identifier: String) -> Bool {
    guard let view = item as? UIView else { return false }
    var current: UIView? = view
    while let node = current {
      if node.accessibilityIdentifier == identifier { return true }
      current = node.superview
    }
    return false
  }

  private static func describe(_ item: UIFocusItem?) -> String {
    guard let view = item as? UIView else { return item.map { "\(type(of: $0))" } ?? "—" }
    return view.accessibilityIdentifier ?? view.accessibilityLabel ?? "\(type(of: view))"
  }
}
#endif
