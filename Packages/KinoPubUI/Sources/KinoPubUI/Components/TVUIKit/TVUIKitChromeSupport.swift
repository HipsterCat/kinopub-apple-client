#if os(tvOS)
//
//  TVUIKitChromeSupport.swift
//  KinoPubUI
//
//  Shared blur band + UIKit context-menu bridge for TVUIKit Home cells.
//

import UIKit
import SwiftUI
import TVUIKit
import OSLog

public enum TVUIKitChromeSupport {
  /// A drop shadow instead of a pill behind small white chrome over artwork. Used by
  /// every glyph and chip we draw on a tile, so they carry the same weight — a second
  /// copy of these numbers is how two tiles start looking subtly different.
  public static func applyLegibilityShadow(to layer: CALayer) {
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0
    layer.shadowRadius = 0
    layer.shadowOffset = .zero
  }
}

/// Bottom-quarter blur with a soft top fade (Rivulet / ATV+ legibility band).
@MainActor
public final class TVUIKitBottomInfoBlurView: UIView {
  private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
  private let fadeMask = CAGradientLayer()
  private let blurStrength: CGFloat = 0.85

  public override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    clipsToBounds = true
    layer.cornerRadius = TVUIKitPosterMetrics.cornerRadius
    layer.cornerCurve = .continuous
    layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]

    blurView.alpha = blurStrength
    blurView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(blurView)
    NSLayoutConstraint.activate([
      blurView.topAnchor.constraint(equalTo: topAnchor),
      blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
      blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
      blurView.trailingAnchor.constraint(equalTo: trailingAnchor)
    ])

    fadeMask.colors = [
      UIColor.clear.cgColor,
      UIColor.black.cgColor,
      UIColor.black.cgColor
    ]
    fadeMask.locations = [0, 0.45, 1]
    fadeMask.startPoint = CGPoint(x: 0.5, y: 0)
    fadeMask.endPoint = CGPoint(x: 0.5, y: 1)
    layer.mask = fadeMask
  }

  public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  public override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    fadeMask.frame = bounds
    CATransaction.commit()
  }
}

/// `[PCM]` console tracing for poster context menus. Compiled out of Release so
/// focus-chain strings are never built on a user's TV.
enum PosterContextMenuLog {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Kinopub Soda",
    category: "PCM"
  )

  static func log(_ message: @autoclosure () -> String) {
#if DEBUG
    let line = message()
    logger.info("[PCM] \(line, privacy: .public)")
#endif
  }

  /// Focused-view chain from the leaf up — class names + accessibility ids.
  /// Never use `UIScreen.main.focusedView` here: on Apple TV Simulator it asserts
  /// `_screenBasedFocusUnsupported` (crash in `didUpdateFocus`, 2026-10-01).
  @MainActor
  static func focusedChainDescription(startingFrom leaf: UIView? = nil) -> String {
    var view: UIView? = leaf ?? focusedView(in: nil)
    var parts: [String] = []
    var depth = 0
    while let current = view, depth < 12 {
      let id = current.accessibilityIdentifier.map { "#\($0)" } ?? ""
      let title = current.accessibilityLabel.map { "\"\($0)\"" } ?? ""
      parts.append("\(type(of: current))\(id)\(title.isEmpty ? "" : " \(title)")")
      view = current.superview
      depth += 1
    }
    return parts.isEmpty ? "(none)" : parts.joined(separator: " ← ")
  }

  /// Focus leaf via the window's focus system — safe on tvOS Simulator.
  @MainActor
  static func focusedView(in hint: UIView?) -> UIView? {
    if let hint,
       let item = UIFocusSystem.focusSystem(for: hint)?.focusedItem as? UIView {
      return item
    }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        if let item = UIFocusSystem.focusSystem(for: window)?.focusedItem as? UIView {
          return item
        }
      }
    }
    return nil
  }

  @MainActor
  static func pressTypeName(_ type: UIPress.PressType) -> String {
    switch type {
    case .upArrow: return "upArrow"
    case .downArrow: return "downArrow"
    case .leftArrow: return "leftArrow"
    case .rightArrow: return "rightArrow"
    case .select: return "select"
    case .menu: return "menu"
    case .playPause: return "playPause"
    default: return "other(\(type.rawValue))"
    }
  }
}

/// Resolves which collection item a tvOS context-menu press belongs to.
/// Prefers `indexPaths` when UIKit fills it; otherwise walks from the focused view
/// (or the press point) up to the enclosing cell.
enum TVUIKitContextMenuIndexPath {
  @MainActor
  static func resolve(
    in collectionView: UICollectionView,
    indexPaths: [IndexPath],
    point: CGPoint
  ) -> IndexPath? {
    if let first = indexPaths.first { return first }
    // Do not use `UIScreen.main.focusedView` — asserts on Apple TV Simulator.
    var view: UIView? = PosterContextMenuLog.focusedView(in: collectionView)
    while let current = view {
      if let cell = current as? UICollectionViewCell,
         let path = collectionView.indexPath(for: cell) {
        return path
      }
      view = current.superview
    }
    return collectionView.indexPathForItem(at: point)
  }
}

/// `TVPosterView` is a `UIControl` / lockup whose **internals** stay focusable even when
/// the subclass returns `canBecomeFocused = false`. Focus then lands on
/// `_TVPosterContentView` (lift looks fine via ancestor rules) but
/// `collectionView(_:contextMenuConfigurationForItemsAt:)` never fires — the same
/// failure mode as 7a8bd62 on device.
///
/// `isUserInteractionEnabled = false` disables focus for the whole lockup subtree so
/// the **cell** is the focused leaf (Continue Watching / `TVPageWideCardCell` shape).
/// Deferred image assignment lives on `TVUIKitDeferredPosterView` in the Artwork facade.
@MainActor
final class TVUIKitNonFocusablePosterView: TVUIKitDeferredPosterView {
  override var canBecomeFocused: Bool { false }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    suppressFocusStealing()
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    suppressFocusStealing()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // TVPosterView may re-enable interaction while wiring chrome — keep it off.
    suppressFocusStealing()
  }

  private func suppressFocusStealing() {
    guard isUserInteractionEnabled else { return }
    isUserInteractionEnabled = false
    PosterContextMenuLog.log("NonFocusablePosterView cleared isUserInteractionEnabled")
  }
}

public enum TVUIKitContextMenuBuilder {
  public static func menu(from entries: [MediaCardContextEntry]) -> UIMenu {
    var children: [UIMenuElement] = []
    var pending: [UIMenuElement] = []

    func flush() {
      if !pending.isEmpty {
        children.append(contentsOf: pending)
        pending.removeAll()
      }
    }

    for entry in entries {
      switch entry {
      case .divider:
        flush()
        if !children.isEmpty {
          // UIMenu separators between groups via nested menus.
          let group = UIMenu(title: "", options: .displayInline, children: children)
          children = [group]
        }
      case .action(let action):
        let uiAction = UIAction(
          title: action.title,
          image: UIImage(systemName: action.systemImage),
          attributes: action.role == .destructive ? .destructive : [],
          state: action.isSelection ? (action.isOn ? .on : .off) : .off
        ) { _ in
          action.handler()
        }
        pending.append(uiAction)
      case .submenu(_, let title, let systemImage, let submenuChildren, let footer):
        flush()
        var nested: [UIMenuElement] = submenuChildren.map { child in
          UIAction(
            title: child.title,
            image: UIImage(systemName: child.systemImage),
            state: child.isSelection ? (child.isOn ? .on : .off) : .off
          ) { _ in child.handler() }
        }
        if !footer.isEmpty {
          nested.append(UIMenu(
            title: "",
            options: .displayInline,
            children: footer.map { foot in
              UIAction(
                title: foot.title,
                image: UIImage(systemName: foot.systemImage)
              ) { _ in foot.handler() }
            }
          ))
        }
        children.append(UIMenu(
          title: title,
          image: UIImage(systemName: systemImage),
          children: nested
        ))
      }
    }
    flush()
    return UIMenu(title: "", children: children)
  }
}
#endif
