#if os(tvOS)
//
//  FocusLog.swift
//  PiraticUI
//
//  Focus tracing for tvOS. Answers two questions that are otherwise unanswerable
//  from a screenshot:
//
//   1. What does the focus engine think is focused right now — which section, which
//      element. Printed on every move.
//   2. Which views still *look* focused while the engine says they are not. That is
//      the "fifteen posters lit at once" bug: `TVPosterView` owns its own focus scale
//      and remote-tilt motion effects, both torn down by its coordinated unfocus
//      animation — and when that animation never runs, the cell strands enlarged and
//      keeps parallaxing while the engine has long since moved on. No further event
//      will fix it, and nothing on screen says which cells are stuck.
//
//  Read it with either:
//    Console.app → filter subsystem `focus`
//    xcrun simctl spawn booted log stream --predicate 'category == "focus"'
//  or just watch Xcode's console while driving the remote.
//

import OSLog
import SwiftUI
import Synchronization
import UIKit

public enum FocusLog {

  /// Off by default, DEBUG included — flip to `true` while chasing a focus bug.
  /// The global trace walks the whole window hierarchy on *every* focus move, and
  /// with the system player up it sweeps AVKit's own collections too, flagging them
  /// as stranded — that sweep was the visible lag, not the logging itself.
  /// An atomic so a toggle and a focus callback cannot race on a plain global.
  private static let enabledFlag = Atomic<Bool>(false)

  public static var isEnabled: Bool {
    get { enabledFlag.load(ordering: .acquiring) }
    set { enabledFlag.store(newValue, ordering: .releasing) }
  }

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Piratic",
    category: "focus"
  )

  /// SwiftUI side: a focusable view took or lost focus.
  public static func moved(section: String, element: String, focused: Bool) {
    guard isEnabled else { return }
    if focused {
      logger.info("▸ IN   \(section, privacy: .public) · \(element, privacy: .public)")
    } else {
      logger.debug("· out  \(section, privacy: .public) · \(element, privacy: .public)")
    }
  }

  /// UIKit side: the engine moved focus inside a collection.
  public static func engine(section: String, from: String?, to: String?) {
    guard isEnabled else { return }
    logger.info("▸ ENGINE \(section, privacy: .public): \(from ?? "—", privacy: .public) → \(to ?? "—", privacy: .public)")
  }

  /// The smoking gun: cells the engine does not consider focused that are still
  /// drawing themselves as if they were. `scaled` is the one that is visible to the
  /// user; `motionOnly` is listed separately so it can be ruled in or out rather than
  /// inflating the count.
  public static func stranded(section: String,
                              focused: String?,
                              scaled: [String],
                              motionOnly: [String]) {
    guard isEnabled, !scaled.isEmpty || !motionOnly.isEmpty else { return }
    if !scaled.isEmpty {
      logger.error(
        "✖ STRANDED-SCALE \(section, privacy: .public): engine focus = \(focused ?? "—", privacy: .public), \(scaled.count, privacy: .public) cell(s) still enlarged → \(scaled.joined(separator: ", "), privacy: .public)"
      )
    }
    if !motionOnly.isEmpty {
      logger.debug(
        "· motion-only \(section, privacy: .public): \(motionOnly.count, privacy: .public) cell(s) keep parallax → \(motionOnly.joined(separator: ", "), privacy: .public)"
      )
    }
  }

  /// What a rail actually occupies versus what it paints into.
  ///
  /// This exists for one specific unanswerable question: cells at the leading and
  /// trailing edge look clipped, and a sliver of the next card does not load until
  /// focus enters its rail. Both are what you see when a collection view's `bounds` are
  /// narrower than the area its content is painted into (`clipsToBounds` is off on all
  /// of ours) — UIKit only builds cells that intersect `bounds`, so anything drawn
  /// beyond them is real estate the data source never hears about. Printing bounds,
  /// insets and the visible index range says whether that is what is happening, instead
  /// of us reasoning about it from a screenshot.
  @MainActor
  public static func railGeometry(_ collection: UICollectionView, section: String) {
    guard isEnabled else { return }
    let visible = collection.indexPathsForVisibleItems.map(\.item).sorted()
    let range = visible.isEmpty ? "none" : "\(visible.first!)…\(visible.last!) (\(visible.count))"
    let window = collection.window?.bounds.width ?? -1
    logger.info(
      """
      ▦ RAIL \(section, privacy: .public): bounds \(Int(collection.bounds.width), privacy: .public)\
      ×\(Int(collection.bounds.height), privacy: .public), content \
      \(Int(collection.contentSize.width), privacy: .public), inset \
      \(Int(collection.adjustedContentInset.left), privacy: .public)/\
      \(Int(collection.adjustedContentInset.right), privacy: .public), safeArea \
      \(Int(collection.safeAreaInsets.left), privacy: .public)/\
      \(Int(collection.safeAreaInsets.right), privacy: .public), window \
      \(Int(window), privacy: .public), visible \(range, privacy: .public)
      """
    )
  }

  /// A rail moving itself, and whether it animated. The distinction is the whole point:
  /// an animated scroll on *arrival* is the "page draws, then visibly slides right"
  /// artefact — the rail should already be where it belongs when it appears, and only
  /// animate when the user asked it to move (picking another season tab).
  public static func railScroll(section: String, toIndex: Int, of count: Int, animated: Bool) {
    guard isEnabled else { return }
    logger.info(
      "→ SCROLL \(section, privacy: .public): item \(toIndex, privacy: .public)/\(count, privacy: .public) \(animated ? "animated" : "jump", privacy: .public)"
    )
  }

  /// A season tab taking focus or being picked, and what it asked the rail to do.
  public static func seasonTab(_ title: String, entryItem: Int?, animated: Bool) {
    guard isEnabled else { return }
    logger.info(
      "◧ SEASON \(title, privacy: .public) → entry \(entryItem.map(String.init) ?? "—", privacy: .public) \(animated ? "animated" : "jump", privacy: .public)"
    )
  }

  /// Where the episodes rail decided to open, and out of how many entries. The report
  /// this exists for: "a series I have never watched opened on episode 7, which has not
  /// even aired". One line says whether the *choice* was wrong or whether something
  /// moved the rail afterwards.
  public static func resumeTarget(episode: Int, number: Int, season: String, of count: Int) {
    guard isEnabled else { return }
    logger.info(
      "⤓ RESUME \(season, privacy: .public) · episode \(number, privacy: .public) (id \(episode, privacy: .public)) of \(count, privacy: .public) entries"
    )
  }

  /// A section reporting that focus entered it, for the coarse "where am I" trace.
  public static func enteredSection(_ section: String) {
    guard isEnabled else { return }
    logger.info("▸ SECTION \(section, privacy: .public)")
  }

  /// A move the engine refused, or a programmatic request that did not land on the
  /// environment it named. Always on: the census sweep stays behind `isEnabled`,
  /// but a rejected move used to leave the console empty.
  @MainActor
  public static func rejected(heading: String, preferred: String, chosen: String, reason: String) {
    logger.error(
      "✖ REJECTED \(heading, privacy: .public): preferred \(preferred, privacy: .public), chosen \(chosen, privacy: .public) — \(reason, privacy: .public)"
    )
  }

  /// A focus decision worth reading in any build (Menu at the hero, a redirect).
  public static func decision(_ text: String) {
    logger.notice("◆ \(text, privacy: .public)")
  }

  // MARK: - Rejection trace

  @MainActor private static var rejectionObserver: NSObjectProtocol?

  /// Logs every move the engine rejects: heading, where focus was, what the
  /// environments along that chain preferred, and that nothing was chosen.
  /// Cheap — it only runs when a move fails — so it is not behind `isEnabled`.
  @MainActor
  public static func startRejectionTrace() {
    guard rejectionObserver == nil else { return }
    rejectionObserver = NotificationCenter.default.addObserver(
      forName: UIFocusSystem.movementDidFailNotification,
      object: nil,
      queue: .main
    ) { note in
      nonisolated(unsafe) let note = note
      MainActor.assumeIsolated {
        guard let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey]
                as? UIFocusUpdateContext else { return }
        let heading = headingName(context.focusHeading)
        let previous = describe(context.previouslyFocusedItem)
        let chosen = context.nextFocusedItem == nil ? "— (move rejected)" : describe(context.nextFocusedItem)
        let preferred = preferredSummary(around: context.previouslyFocusedItem)
        rejected(heading: heading, preferred: preferred, chosen: chosen,
                 reason: "the engine rejected the move from \(previous)")
      }
    }
  }

  private static func headingName(_ heading: UIFocusHeading) -> String {
    var parts: [String] = []
    if heading.contains(.up) { parts.append("up") }
    if heading.contains(.down) { parts.append("down") }
    if heading.contains(.left) { parts.append("left") }
    if heading.contains(.right) { parts.append("right") }
    if heading.contains(.next) { parts.append("next") }
    if heading.contains(.previous) { parts.append("previous") }
    return parts.isEmpty ? "none" : parts.joined(separator: "+")
  }

  /// What the environments above the item that had focus asked the engine to prefer.
  @MainActor
  private static func preferredSummary(around item: UIFocusItem?) -> String {
    let start: UIFocusEnvironment?
    if let view = item as? UIView {
      start = view
    } else if let item, let view = mirroredView(from: item, depth: 0) {
      start = view
    } else {
      start = nil
    }
    guard var environment = start else { return "—" }
    var seen: [String] = []
    var steps = 0
    while steps < 6 {
      let preferred = environment.preferredFocusEnvironments
      if !preferred.isEmpty {
        seen.append(preferred.map(describeEnvironment).joined(separator: ", "))
      }
      guard let parent = environment.parentFocusEnvironment else { break }
      environment = parent
      steps += 1
    }
    return seen.isEmpty ? "—" : seen.joined(separator: " → ")
  }

  @MainActor
  private static func describeEnvironment(_ environment: UIFocusEnvironment) -> String {
    if let view = environment as? UIView { return describe(view: view) }
    return "\(type(of: environment))"
  }

  // MARK: - Global trace

  @MainActor private static var globalObserver: NSObjectProtocol?

  /// Traces **every** focus change in the app from one place.
  ///
  /// Per-view instrumentation cannot do this: `@Environment(\.isFocused)` is only true
  /// inside the focused view's own subtree, so a reporter attached *outside* a
  /// `Button` (which is where most of ours sit — after `.buttonStyle`) never fires at
  /// all. That is the blind spot where focus visibly moves and the log stays silent.
  /// `UIFocusSystem.didUpdateNotification` sits under both SwiftUI and UIKit, so
  /// nothing can move focus without showing up here.
  @MainActor
  public static func startGlobalTrace() {
    guard isEnabled, globalObserver == nil else { return }
    globalObserver = NotificationCenter.default.addObserver(
      forName: UIFocusSystem.didUpdateNotification,
      object: nil,
      queue: .main
    ) { note in
      // Queued on the main thread. The census has to run in this turn — a hop
      // would walk the window after focus had already moved on. `Notification`
      // is not `Sendable`; the queue is what makes the transfer safe.
      nonisolated(unsafe) let note = note
      MainActor.assumeIsolated {
        guard let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey]
                as? UIFocusUpdateContext else { return }
        let from = describe(context.previouslyFocusedItem)
        let to = describe(context.nextFocusedItem)
        logger.info("◆ \(from, privacy: .public)  →  \(to, privacy: .public)")
        sweepStrandedAcrossScreen()
      }
    }
  }

  /// Census of every collection on screen, not just the one focus happened to move
  /// inside. A rail only gets a `didUpdateFocus` when focus enters or leaves *it*, so
  /// a cell that stranded in rail A is never re-checked while the user is in rail B —
  /// which is exactly the "fifteen posters lit at once across the page" report. This
  /// runs on the whole window on every move.
  @MainActor
  private static func sweepStrandedAcrossScreen() {
    guard let window = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap(\.windows)
      .first(where: \.isKeyWindow) else { return }

    var collections: [UICollectionView] = []
    collect(from: window, into: &collections)

    var lit: [String] = []
    for collection in collections {
      let name = collection.accessibilityIdentifier?.nilIfEmpty ?? "collection"
      for cell in collection.visibleCells where !cell.isFocused {
        guard cell.focusAppearanceResidue.scaled else { continue }
        lit.append("\(name)/\(firstLabelText(in: cell) ?? "?")")
      }
    }
    guard !lit.isEmpty else { return }
    logger.error(
      "✖ SCREEN-STRANDED \(lit.count, privacy: .public) cell(s) enlarged while unfocused → \(lit.joined(separator: ", "), privacy: .public)"
    )
  }

  @MainActor
  private static func collect(from view: UIView, into result: inout [UICollectionView]) {
    if let collection = view as? UICollectionView { result.append(collection) }
    for subview in view.subviews { collect(from: subview, into: &result) }
  }

  /// "section · element" for a focus item, dug out of whatever it actually is:
  /// accessibility text first (SwiftUI fills it from the view's own labels), then the
  /// nearest meaningful ancestor as the section.
  @MainActor
  private static func describe(_ item: UIFocusItem?) -> String {
    guard let item else { return "—" }
    guard let view = item as? UIView else {
      // SwiftUI's focusables are NOT views — they are private responder items
      // (`UIKitFocusableViewResponderItem`), so the cast above fails and every
      // SwiftUI control used to print as a bare type name. That was the "I'm on the
      // ratings and it logs nothing useful" gap. Reflection is the only way in;
      // it is diagnostics-only and degrades to the type name if Apple renames things.
      if let backing = mirroredView(from: item, depth: 0) {
        return "SwiftUI/" + describe(view: backing)
      }
      return "\(type(of: item))"
    }
    return describe(view: view)
  }

  /// Digs a real `UIView` out of a private SwiftUI focus item.
  @MainActor
  private static func mirroredView(from subject: Any, depth: Int) -> UIView? {
    guard depth < 4 else { return nil }
    if let view = subject as? UIView { return view }
    for child in Mirror(reflecting: subject).children {
      if let found = mirroredView(from: child.value, depth: depth + 1) { return found }
    }
    return nil
  }

  @MainActor
  private static func describe(view: UIView) -> String {
    let element = view.accessibilityIdentifier?.nilIfEmpty
      ?? view.accessibilityLabel?.nilIfEmpty
      ?? firstLabelText(in: view)
      ?? "\(type(of: view))"

    var section = "?"
    var node: UIView? = view.superview
    while let current = node {
      if let cell = current as? UICollectionViewCell {
        section = "\(type(of: cell))"
        break
      }
      if current is UICollectionView || current is UIScrollView {
        section = current.accessibilityIdentifier?.nilIfEmpty ?? "\(type(of: current))"
        break
      }
      node = current.superview
    }
    return "\(section) · \(element)"
  }

  /// SwiftUI renders text into `UILabel`s under the hood; the nearest one is usually
  /// the human name of the control when no accessibility text was set explicitly.
  @MainActor
  private static func firstLabelText(in view: UIView) -> String? {
    if let label = view as? UILabel, let text = label.text?.nilIfEmpty { return text }
    for subview in view.subviews {
      if let found = firstLabelText(in: subview) { return found }
    }
    return nil
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - SwiftUI

private struct FocusLogModifier: ViewModifier {
  let section: String
  let element: String
  @Environment(\.isFocused) private var isFocused

  func body(content: Content) -> some View {
    content.onChange(of: isFocused) { _, focused in
      FocusLog.moved(section: section, element: element, focused: focused)
    }
  }
}

public extension View {
  /// Traces this view's focus as "section · element". Cheap enough to leave on every
  /// focusable control on the page — it only fires on change.
  func logsFocus(_ section: String, _ element: String) -> some View {
    modifier(FocusLogModifier(section: section, element: element))
  }
}

// MARK: - UIKit helpers

public extension UIView {
  /// What focus chrome this view (or anything under it) is still carrying.
  ///
  /// Scale and motion effects are reported separately on purpose. Only a leftover
  /// **scale** is the "poster is visibly still lit" bug; motion effects alone may
  /// simply be `TVPosterView`'s remote-tilt parallax, which it can legitimately keep
  /// installed while idle. Lumping them together turns every untouched cell into a
  /// false positive and buries the real ones.
  var focusAppearanceResidue: (scaled: Bool, motion: Bool) {
    var scaled = !transform.isIdentity || !CATransform3DIsIdentity(layer.transform)
    var motion = !motionEffects.isEmpty
    for subview in subviews {
      let child = subview.focusAppearanceResidue
      scaled = scaled || child.scaled
      motion = motion || child.motion
      if scaled && motion { break }
    }
    return (scaled, motion)
  }
}
#endif
