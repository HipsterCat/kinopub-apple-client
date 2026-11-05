#if os(tvOS)
//
//  FocusDebugOverlay.swift
//  KinoPubUI
//
//  Borrowed from silo-apple (HipsterCat/silo-apple,
//  `iosApp/iosApp/tvOS/Debug/TVFocusDebugOverlay.swift`, 2026-11): the overlay that
//  marks where each arrow press would move focus from the focused control. Adapted:
//  a Settings › Diagnostics switch instead of a launch argument only, every build
//  (TestFlight is where Sasha tests), no top-menu hint (our tab bar is the system's),
//  and a corner readout that names the focused item and says **which arrows go
//  nowhere** — a dead end is a direction with no marker and "— nowhere" in the readout.
//
//  Read it this way:
//    dashed white      the focused item
//    green / orange /  where Up / Down / Left / Right lands, asked of the real focus
//    cyan / pink       engine (`FocusEngineQuery` below — private, runtime-resolved)
//    "· SCROLLS"       the engine answered with a scroll placeholder: the target is not
//                      built yet, the strip is where it will scroll in from
//    "?"               the engine said "nowhere"; the marker is a geometric guess, and
//                      a SwiftUI `.focusSection()` hop may still catch the press
//
//  Trust it on UIKit pages (cells, TVUIKit lockups). On SwiftUI controls — the title
//  page's hero — names read as `UIKitFocusableViewResponderItem`, boxes can sit on the
//  neighbouring control, and "nowhere" may be a move SwiftUI makes itself.
//
//  `UIFocusDebugger` itself is LLDB-only — calling it from app code throws (Plozz,
//  docs/performance-debugging.md). For "why can't this view take focus" pause in the
//  debugger and run `po UIFocusDebugger.checkFocusability(for: view)`.
//

import Combine
import SwiftUI
import UIKit

// MARK: - Switch

/// Installs or removes the overlay window. One call site, at the app root.
@MainActor
public enum FocusDebugOverlay {
  /// `-KINOPUBFocusDebug YES` turns it on regardless of the Settings switch — for the
  /// simulator, where reaching Settings with the remote is a chore.
  public static var forcedByLaunchArgument: Bool {
    UserDefaults.standard.bool(forKey: "KINOPUBFocusDebug")
  }

  public static func setEnabled(_ isEnabled: Bool) {
    if isEnabled || forcedByLaunchArgument {
      FocusDebugOverlayController.shared.enable()
    } else {
      FocusDebugOverlayController.shared.disable()
    }
  }
}

public extension View {
  /// Keeps the focus overlay window in step with a switch.
  func focusDebugOverlay(isEnabled: Bool) -> some View {
    onAppear { FocusDebugOverlay.setEnabled(isEnabled) }
      .onChange(of: isEnabled) { _, newValue in FocusDebugOverlay.setEnabled(newValue) }
  }
}

// MARK: - View

struct FocusDebugOverlayView: View {
  @State private var snapshot = FocusDebugSnapshot()

  /// Layout can settle after the focus notification fires (scroll animations, cells
  /// built late); a slow tick keeps the markers honest.
  private let settleTick = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()

  var body: some View {
    ZStack(alignment: .topTrailing) {
      if let focused = snapshot.focusedFrame {
        RoundedRectangle(cornerRadius: 12)
          .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
          .frame(width: focused.width, height: focused.height)
          .position(x: focused.midX, y: focused.midY)
      }

      ForEach(snapshot.targets) { target in
        marker(for: target)
      }

      // Top right: the hero's controls sit bottom left on the title page.
      readout
        .padding(.trailing, 24)
        .padding(.top, 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .onAppear { refresh() }
    .onReceive(NotificationCenter.default.publisher(for: UIFocusSystem.didUpdateNotification)) { _ in
      refresh()
    }
    .onReceive(settleTick) { _ in refresh() }
  }

  /// What is focused, and per arrow where it goes. "— nowhere" is the engine's own
  /// answer: a dead end, unless a SwiftUI `.focusSection()` catches the press.
  private var readout: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(snapshot.focusedDescription ?? "nothing focused")
      ForEach(FocusDebugSnapshot.Direction.allCases, id: \.self) { direction in
        let target = snapshot.targets.first { $0.direction == direction }
        HStack(spacing: 8) {
          Text(direction.badge).foregroundStyle(direction.color)
          Text(target.map(\.label) ?? "— nowhere")
            .foregroundStyle(target == nil ? Color.red : Color.white)
        }
      }
    }
    .font(.caption2.monospaced())
    .foregroundStyle(.white)
    .lineLimit(1)
    .padding(12)
    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .frame(maxWidth: 820, alignment: .leading)
  }

  private func marker(for target: FocusDebugSnapshot.Target) -> some View {
    let rect = target.frame
    let color = target.direction.color
    let suffix = target.isHeuristic ? " ?" : (target.isScrollRegion ? " · SCROLLS" : "")
    return RoundedRectangle(cornerRadius: 12)
      .stroke(color, style: target.isScrollRegion
              ? StrokeStyle(lineWidth: 4, dash: [12, 8])
              : StrokeStyle(lineWidth: 5))
      .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.14)))
      .overlay(alignment: .topLeading) {
        Text(target.direction.badge + suffix)
          .font(.caption2.monospaced().bold())
          .foregroundStyle(.black)
          .padding(.horizontal, 10)
          .padding(.vertical, 3)
          .background(color, in: Capsule())
          .offset(x: 8, y: -16)
      }
      .frame(width: rect.width, height: rect.height)
      .position(x: rect.midX, y: rect.midY)
  }

  private func refresh() {
    let next = FocusDebugSnapshot.capture()
    if next != snapshot { snapshot = next }
  }
}

// MARK: - Snapshot

struct FocusDebugSnapshot: Equatable {
  /// Frame of the focused item, in window coordinates.
  var focusedFrame: CGRect?
  var focusedDescription: String?
  /// Where each direction lands; a direction with no candidate is absent.
  var targets: [Target] = []

  struct Target: Equatable, Identifiable {
    let direction: Direction
    let frame: CGRect
    var label: String = ""
    /// The frame is the geometric fallback, not the engine's answer.
    var isHeuristic = false
    /// The engine answered with a scroll placeholder: the control is not built yet.
    var isScrollRegion = false
    var id: Direction { direction }
  }

  enum Direction: CaseIterable {
    case up, down, left, right

    var badge: String {
      switch self {
      case .up: "▲ UP"
      case .down: "▼ DOWN"
      case .left: "◀ LEFT"
      case .right: "▶ RIGHT"
      }
    }

    var focusHeading: UIFocusHeading {
      switch self {
      case .up: .up
      case .down: .down
      case .left: .left
      case .right: .right
      }
    }

    var color: Color {
      switch self {
      case .up: .green
      case .down: .orange
      case .left: .cyan
      case .right: .pink
      }
    }
  }

  // MARK: Capture

  @MainActor
  static func capture() -> FocusDebugSnapshot {
    guard let window = appKeyWindow(),
          let focusedItem = UIFocusSystem.focusSystem(for: window)?.focusedItem
    else { return FocusDebugSnapshot() }

    var frames: [(item: UIFocusItem, frame: CGRect)] = []
    var visitedContainers = Set<ObjectIdentifier>()
    var seenItems = Set<ObjectIdentifier>()
    collectFocusItems(in: window, window: window, frames: &frames,
                      visitedContainers: &visitedContainers, seenItems: &seenItems, depth: 0)

    let focusedFrame = frames.first { $0.item === focusedItem }?.frame
      ?? (focusedItem as? UIView).map { $0.convert($0.bounds, to: window) }
      ?? frameByWalkingContainers(of: focusedItem, in: window)
    guard let focusedFrame else { return FocusDebugSnapshot() }

    // SwiftUI vends scroll-anchor items with region-sized frames; the plausibility
    // filter keeps the guess from repainting the giant box the engine filter rejected.
    let candidates = frames
      .filter { $0.item !== focusedItem }
      .filter { isPlausibleTargetFrame($0.frame, in: window) }

    let targets = Direction.allCases.compactMap { direction -> Target? in
      // Primary: ask the engine. Non-nil is exact. Nil means UIKit's search failed —
      // on a SwiftUI page a `.focusSection()` may still catch the press, which no
      // UIKit query can see, so the guess below is marked "?".
      if FocusEngineQuery.isAvailable,
         let item = FocusEngineQuery.nextFocusedItem(from: focusedItem,
                                                     heading: direction.focusHeading,
                                                     in: window),
         item !== focusedItem {
        let frame = frames.first { $0.item === item }?.frame
          ?? (item as? UIView).map { $0.convert($0.bounds, to: window) }
          ?? frameByWalkingContainers(of: item, in: window)
        if let frame {
          if isRealControl(item), isPlausibleTargetFrame(frame, in: window) {
            return Target(direction: direction, frame: frame, label: describe(item))
          }
          if let strip = scrollStrip(direction: direction, region: frame,
                                     focused: focusedFrame, in: window) {
            return Target(direction: direction, frame: strip,
                          label: "scrolls to unbuilt content (\(describe(item)))",
                          isScrollRegion: true)
          }
        }
      }

      return bestCandidate(from: focusedFrame, among: candidates, direction: direction)
        .map { Target(direction: direction, frame: $0.frame,
                      label: "? guess: \(describe($0.item))", isHeuristic: true) }
    }

    return FocusDebugSnapshot(focusedFrame: focusedFrame,
                              focusedDescription: "● " + describe(focusedItem),
                              targets: targets)
  }

  /// Class name plus whatever names the thing to a person: accessibility label, or the
  /// collection index path of the cell.
  @MainActor
  private static func describe(_ item: UIFocusItem) -> String {
    var parts = [String(describing: type(of: item))]
    if let view = item as? UIView {
      if let cell = view as? UICollectionViewCell,
         let collection = sequence(first: cell.superview, next: { $0?.superview })
           .compactMap({ $0 as? UICollectionView }).first,
         let path = collection.indexPath(for: cell) {
        parts.append("[\(path.section).\(path.item)]")
      }
      if let label = view.accessibilityLabel, !label.isEmpty {
        parts.append("“\(label.prefix(40))”")
      }
    } else if let object = item as? NSObject, let label = object.accessibilityLabel, !label.isEmpty {
      parts.append("“\(label.prefix(40))”")
    }
    return parts.joined(separator: " ")
  }

  /// The engine answers a move into unbuilt scrollable content with a placeholder
  /// item whose frame is the whole scroll region.
  private static func isRealControl(_ item: UIFocusItem) -> Bool {
    let className = String(describing: type(of: item)).lowercased()
    return !className.contains("dummy") && !className.contains("placeholder")
  }

  /// A focused-control-sized strip at the region edge the next row/column scrolls in from.
  private static func scrollStrip(direction: Direction, region: CGRect,
                                  focused: CGRect, in window: UIWindow) -> CGRect? {
    let visible = region.intersection(window.bounds)
    guard !visible.isEmpty else { return nil }
    let thickness: CGFloat = 72
    var strip: CGRect
    switch direction {
    case .up:
      strip = CGRect(x: focused.minX, y: visible.maxY - thickness, width: focused.width, height: thickness)
    case .down:
      strip = CGRect(x: focused.minX, y: visible.minY, width: focused.width, height: thickness)
    case .left:
      strip = CGRect(x: visible.maxX - thickness, y: focused.minY, width: thickness, height: focused.height)
    case .right:
      strip = CGRect(x: visible.minX, y: focused.minY, width: thickness, height: focused.height)
    }
    strip = strip.intersection(window.bounds)
    return strip.isEmpty ? nil : strip
  }

  private static func isPlausibleTargetFrame(_ frame: CGRect, in window: UIWindow) -> Bool {
    let bounds = window.bounds
    guard bounds.width > 0, bounds.height > 0 else { return false }
    let visible = frame.intersection(bounds)
    guard !visible.isEmpty else { return false }
    let areaShare = (visible.width * visible.height) / (bounds.width * bounds.height)
    return areaShare < 0.3 && visible.width < bounds.width * 0.85 && visible.height < bounds.height * 0.85
  }

  /// `item.frame` is in its container's coordinate space; the nearest ancestor that
  /// exposes a container is that space.
  @MainActor
  private static func frameByWalkingContainers(of item: UIFocusItem, in window: UIWindow) -> CGRect? {
    var environment = item.parentFocusEnvironment
    var hops = 0
    while let current = environment, hops < 30 {
      if let container = current.focusItemContainer {
        let frame = container.coordinateSpace.convert(item.frame, to: window.coordinateSpace)
        if frame.intersects(window.bounds) { return frame }
      }
      environment = current.parentFocusEnvironment
      hops += 1
    }
    return nil
  }

  /// The app's own key window — never the overlay's.
  @MainActor
  private static func appKeyWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let overlay = FocusDebugOverlayController.shared.window
    if let key = scene?.keyWindow, key !== overlay { return key }
    return scene?.windows.first { !$0.isHidden && $0 !== overlay }
  }

  /// Walks the view tree and nested `UIFocusItemContainer`s: UIKit items surface as
  /// subviews, SwiftUI vends non-view items through container queries.
  @MainActor
  private static func collectFocusItems(in view: UIView, window: UIWindow,
                                        frames: inout [(item: UIFocusItem, frame: CGRect)],
                                        visitedContainers: inout Set<ObjectIdentifier>,
                                        seenItems: inout Set<ObjectIdentifier>, depth: Int) {
    guard depth < 60, !view.isHidden, view.alpha > 0.01 else { return }
    collectFromContainer(view, window: window, frames: &frames,
                         visitedContainers: &visitedContainers, seenItems: &seenItems, depth: depth)
    for subview in view.subviews {
      collectFocusItems(in: subview, window: window, frames: &frames,
                        visitedContainers: &visitedContainers, seenItems: &seenItems, depth: depth + 1)
    }
  }

  @MainActor
  private static func collectFromContainer(_ container: UIFocusItemContainer, window: UIWindow,
                                           frames: inout [(item: UIFocusItem, frame: CGRect)],
                                           visitedContainers: inout Set<ObjectIdentifier>,
                                           seenItems: inout Set<ObjectIdentifier>, depth: Int) {
    guard depth < 60, visitedContainers.insert(ObjectIdentifier(container)).inserted else { return }
    let region = window.coordinateSpace.convert(window.bounds, to: container.coordinateSpace)
    for item in container.focusItems(in: region) {
      let frame = container.coordinateSpace.convert(item.frame, to: window.coordinateSpace)
      if item.canBecomeFocused, frame.intersects(window.bounds),
         seenItems.insert(ObjectIdentifier(item)).inserted {
        frames.append((item, frame))
      }
      if let nested = item as? UIFocusItemContainer, !(item is UIView) {
        collectFromContainer(nested, window: window, frames: &frames,
                             visitedContainers: &visitedContainers, seenItems: &seenItems, depth: depth + 1)
      }
    }
  }

  // MARK: Directional guess

  /// Beyond the focused frame in the direction; nearer edges win, overlap on the cross
  /// axis beats offset, centred candidates break ties.
  private static func bestCandidate(from focused: CGRect,
                                    among candidates: [(item: UIFocusItem, frame: CGRect)],
                                    direction: Direction) -> (item: UIFocusItem, frame: CGRect)? {
    var best: (item: UIFocusItem, frame: CGRect, score: CGFloat)?
    for (item, candidate) in candidates {
      let edgeDistance: CGFloat
      let axisGap: CGFloat
      let centerOffset: CGFloat
      switch direction {
      case .up:
        guard candidate.midY < focused.minY else { continue }
        edgeDistance = max(0, focused.minY - candidate.maxY)
        axisGap = max(0, max(candidate.minX, focused.minX) - min(candidate.maxX, focused.maxX))
        centerOffset = abs(candidate.midX - focused.midX)
      case .down:
        guard candidate.midY > focused.maxY else { continue }
        edgeDistance = max(0, candidate.minY - focused.maxY)
        axisGap = max(0, max(candidate.minX, focused.minX) - min(candidate.maxX, focused.maxX))
        centerOffset = abs(candidate.midX - focused.midX)
      case .left:
        guard candidate.midX < focused.minX else { continue }
        edgeDistance = max(0, focused.minX - candidate.maxX)
        axisGap = max(0, max(candidate.minY, focused.minY) - min(candidate.maxY, focused.maxY))
        centerOffset = abs(candidate.midY - focused.midY)
      case .right:
        guard candidate.midX > focused.maxX else { continue }
        edgeDistance = max(0, candidate.minX - focused.maxX)
        axisGap = max(0, max(candidate.minY, focused.minY) - min(candidate.maxY, focused.maxY))
        centerOffset = abs(candidate.midY - focused.midY)
      }
      let score = edgeDistance + axisGap * 3 + centerOffset * 0.25
      if best == nil || score < best!.score { best = (item, candidate, score) }
    }
    return best.map { ($0.item, $0.frame) }
  }
}

// MARK: - Engine query

/// Asks the real tvOS focus engine what a d-pad move would focus, by rebuilding the
/// private request UIKit's press handling builds:
///
///   request  = _UIFocusMovementRequest(initWithFocusSystem:)
///   itemInfo = _UIFocusItemInfo(infoWithItem: focusedItem)
///   movement = _UIFocusMovementInfo(initWithHeading:velocity:isInitial:
///                shouldLoadScrollableContainer:groupFilter:inputType:)
///   context  = focusSystem._movementPerformer.contextForFocusMovement(request)
///   next     = context.nextFocusedItem
///
/// The performer runs the full candidate search (exhaustive search and focus-group
/// escalation included) without applying the move. Everything resolves through the
/// ObjC runtime and every step is guarded, so an OS that renames any of it flips
/// `isAvailable` and the overlay falls back to the geometric guess.
@MainActor
private enum FocusEngineQuery {
  private static let requestClass = NSClassFromString("_UIFocusMovementRequest") as? NSObject.Type
  private static let movementClass = NSClassFromString("_UIFocusMovementInfo") as? NSObject.Type
  private static let itemInfoClass = NSClassFromString("_UIFocusItemInfo") as? NSObject.Type
  private static let mapClass = NSClassFromString("_UIFocusMap") as? NSObject.Type

  private static let requestInitSel = NSSelectorFromString("initWithFocusSystem:")
  private static let itemInfoSel = NSSelectorFromString("infoWithItem:")
  private static let setItemInfoSel = NSSelectorFromString("setFocusedItemInfo:")
  private static let setMovementSel = NSSelectorFromString("setMovementInfo:")
  private static let movementInitSel = NSSelectorFromString(
    "initWithHeading:velocity:isInitial:shouldLoadScrollableContainer:groupFilter:inputType:"
  )
  private static let mapInitSel = NSSelectorFromString("initWithFocusSystem:rootEnvironment:")
  private static let nextItemSel = NSSelectorFromString("_nextFocusedItemForFocusMovementRequest:")
  private static let allocSel = NSSelectorFromString("alloc")
  private static let performerSel = NSSelectorFromString("_movementPerformer")
  private static let contextSel = NSSelectorFromString("contextForFocusMovement:")
  private static let nextFocusedItemSel = NSSelectorFromString("nextFocusedItem")

  static let isAvailable: Bool = {
    guard let requestClass, let movementClass, let itemInfoClass else { return false }
    let requestOK = requestClass.instancesRespond(to: requestInitSel)
      && requestClass.instancesRespond(to: setItemInfoSel)
      && requestClass.instancesRespond(to: setMovementSel)
      && movementClass.instancesRespond(to: movementInitSel)
      && (itemInfoClass as AnyObject).responds(to: itemInfoSel)
    let performerOK = UIFocusSystem.instancesRespond(to: performerSel)
    let mapOK = mapClass.map {
      $0.instancesRespond(to: mapInitSel) && $0.instancesRespond(to: nextItemSel)
    } ?? false
    return requestOK && (performerOK || mapOK)
  }()

  /// `alloc` goes through `perform` because Swift hides `NSObject.alloc`. Its +1 is
  /// left for the init to consume; the init's +1 result is what `takeRetainedValue`
  /// balances.
  private static func allocInstance(of cls: NSObject.Type) -> NSObject? {
    (cls as AnyObject).perform(allocSel)?.takeUnretainedValue() as? NSObject
  }

  static func nextFocusedItem(from focusedItem: UIFocusItem, heading: UIFocusHeading,
                              in window: UIWindow) -> UIFocusItem? {
    guard isAvailable, let movementClass, let itemInfoClass, let requestClass,
          let focusSystem = UIFocusSystem.focusSystem(for: window)
    else { return nil }

    guard let requestAlloc = allocInstance(of: requestClass),
          let request = requestAlloc.perform(requestInitSel, with: focusSystem)?
            .takeRetainedValue() as? NSObject
    else { return nil }

    guard let itemInfo = (itemInfoClass as AnyObject).perform(itemInfoSel, with: focusedItem)?
      .takeUnretainedValue()
    else { return nil }
    _ = request.perform(setItemInfoSel, with: itemInfo)

    // (heading: NSUInteger, velocity: CGFloat, isInitial: BOOL,
    //  shouldLoadScrollableContainer: BOOL, groupFilter: id, inputType: NSInteger)
    typealias MovementInit = @convention(c) (
      AnyObject, Selector, UInt, CGFloat, ObjCBool, ObjCBool, AnyObject?, Int
    ) -> Unmanaged<AnyObject>?
    guard let movementAlloc = allocInstance(of: movementClass),
          let movementImp = movementAlloc.method(for: movementInitSel)
    else { return nil }
    let movementInit = unsafeBitCast(movementImp, to: MovementInit.self)
    guard let movement = movementInit(movementAlloc, movementInitSel,
                                      UInt(heading.rawValue), 0, false, true, nil, 0)?
      .takeRetainedValue()
    else { return nil }
    _ = request.perform(setMovementSel, with: movement)

    if UIFocusSystem.instancesRespond(to: performerSel),
       let performer = focusSystem.perform(performerSel)?.takeUnretainedValue() as? NSObject,
       performer.responds(to: contextSel) {
      let context = performer.perform(contextSel, with: request)?.takeUnretainedValue()
      if let context = context as? UIFocusUpdateContext { return context.nextFocusedItem }
      if let context = context as? NSObject, context.responds(to: nextFocusedItemSel) {
        return context.perform(nextFocusedItemSel)?.takeUnretainedValue() as? UIFocusItem
      }
      return nil
    }

    // Lesser fallback: a bare focus-map query (first pass only).
    guard let mapClass else { return nil }
    typealias MapInit = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?) -> Unmanaged<AnyObject>?
    guard let mapAlloc = allocInstance(of: mapClass),
          let mapImp = mapAlloc.method(for: mapInitSel)
    else { return nil }
    let mapInit = unsafeBitCast(mapImp, to: MapInit.self)
    guard let map = mapInit(mapAlloc, mapInitSel, focusSystem, window)?.takeRetainedValue() as? NSObject
    else { return nil }
    return map.perform(nextItemSel, with: request)?.takeUnretainedValue() as? UIFocusItem
  }
}

// MARK: - Window

/// Hosts the overlay in its own passthrough window above everything (player and
/// sheets included); it never takes touches or focus.
@MainActor
final class FocusDebugOverlayController {
  static let shared = FocusDebugOverlayController()

  private(set) var window: UIWindow?

  func enable() {
    guard window == nil else { return }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    else { return }

    let host = UIHostingController(rootView: FocusDebugOverlayView())
    host.view.backgroundColor = .clear

    let overlay = UIWindow(windowScene: scene)
    overlay.windowLevel = .alert + 100
    overlay.isUserInteractionEnabled = false
    overlay.backgroundColor = .clear
    overlay.rootViewController = host
    overlay.isHidden = false
    window = overlay
  }

  func disable() {
    window?.isHidden = true
    window?.rootViewController = nil
    window = nil
  }
}
#endif
