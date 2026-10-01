#if os(tvOS)
//
//  TVUIKitChromeSupport.swift
//  KinoPubUI
//
//  Shared blur band + UIKit context-menu bridge for TVUIKit Home cells.
//

import OSLog
import UIKit
import SwiftUI
import TVUIKit

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

/// DEBUG poster context-menu trace. Filter Console / `log stream` for `[PCM]`.
/// Always on in DEBUG — this is the on-device diagnosis path for vertical shelves.
enum PCMLog {
  static var isEnabled: Bool {
#if DEBUG
    true
#else
    false
#endif
  }

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Kinopub Soda",
    category: "pcm"
  )

  static func focus(cell: String, focusedView: String, posterCanFocus: Bool, hostFocused: Bool) {
    guard isEnabled else { return }
    logger.info("[PCM] focus cell=\(cell, privacy: .public) focusedView=\(focusedView, privacy: .public) posterCanFocus=\(posterCanFocus, privacy: .public) hostFocused=\(hostFocused, privacy: .public)")
  }

  static func attach(view: String, cell: String) {
    guard isEnabled else { return }
    logger.info("[PCM] attach interaction view=\(view, privacy: .public) cell=\(cell, privacy: .public)")
  }

  static func configurationRequested(source: String, detail: String) {
    guard isEnabled else { return }
    logger.info("[PCM] configuration requested source=\(source, privacy: .public) \(detail, privacy: .public)")
  }

  static func configurationReturned(source: String, entryCount: Int) {
    guard isEnabled else { return }
    logger.info("[PCM] configuration returned source=\(source, privacy: .public) entries=\(entryCount, privacy: .public)")
  }

  static func configurationNil(source: String, reason: String) {
    guard isEnabled else { return }
    logger.info("[PCM] configuration nil source=\(source, privacy: .public) reason=\(reason, privacy: .public)")
  }

  static func describe(_ view: UIView?) -> String {
    guard let view else { return "nil" }
    let type = String(describing: type(of: view))
    let id = view.accessibilityIdentifier.map { " id=\($0)" } ?? ""
    return "\(type)\(id)"
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

/// Resolves which collection item a tvOS context-menu press belongs to.
///
/// Continue Watching stills focus the **cell**, so `indexPaths` is filled.
/// Vertical posters focus a plain host *inside* the lockup — UIKit then often
/// hands an empty `indexPaths` array; walk from the focused view (or press point).
enum TVUIKitContextMenuIndexPath {
  static func resolve(
    in collectionView: UICollectionView,
    indexPaths: [IndexPath],
    point: CGPoint
  ) -> IndexPath? {
    if let first = indexPaths.first { return first }
    var view: UIView? = UIScreen.main.focusedView
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

/// Plain focusable host that lives *inside* a `TVPosterView` content view so:
/// 1. the lockup still lifts (Apple animates when a lockup **subview** is focused), and
/// 2. `UIContextMenuInteraction` sits on the focused view itself — installing it on
///    `TVPosterView` (a `UIControl`) does not receive long-press / Play-Pause on tvOS.
///
/// Cell-only focus (`canBecomeFocused` on the cell, lockup non-focusable) matched
/// Continue Watching in theory but did **not** open vertical poster menus on device
/// (PR #36 tip `7a8bd62`). The host is the path that can own the interaction.
@MainActor
final class TVUIKitLockupMenuHost: UIView {
  override var canBecomeFocused: Bool { true }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isUserInteractionEnabled = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// `TVPosterView` is a `UIControl` and steals focus from an inner menu host unless
/// focusability is turned off on the lockup itself. Lift/parallax still run when the
/// inner host (a lockup subview) is focused.
@MainActor
final class TVUIKitNonFocusablePosterView: TVPosterView {
  override var canBecomeFocused: Bool { false }
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
