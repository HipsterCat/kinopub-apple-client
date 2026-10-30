//
//  PageKeyboardFocus.swift
//  KinoPubUI
//
//  Arrow-key travel through a page's cards on a Mac. SwiftUI moves focus between
//  views with Tab only; arrows are ours to route, as the App Store and the TV app route
//  them: Left / Right along a rail or a grid row, Up / Down between rails or grid rows,
//  Up from the top back to the page (the Home hero). The page's shell asks the content
//  to take the keyboard (`pageKeyboardEntry`) and hears when it gives it back.
//

#if os(macOS)
import Foundation
import SwiftUI

/// «Take the keyboard»: each request has its own id, so asking twice is two requests.
public struct PageKeyboardEntry: Equatable, Sendable {
  public let id = UUID()
  public init() {}
}

public extension EnvironmentValues {
  /// Set by the page's shell when Down leaves the page itself (the hero) for its cards.
  @Entry var pageKeyboardEntry: PageKeyboardEntry? = nil
  /// Called when Up leaves the top rail or grid row: the shell takes focus back.
  @Entry var pageKeyboardExit: (() -> Void)? = nil
}

/// The arrow keys as move directions.
public extension KeyPress {
  var moveDirection: MoveCommandDirection? {
    switch key {
    case .leftArrow: .left
    case .rightArrow: .right
    case .upArrow: .up
    case .downArrow: .down
    default: nil
    }
  }
}

public extension Set where Element == KeyEquivalent {
  static let arrows: Set<KeyEquivalent> = [.leftArrow, .rightArrow, .upArrow, .downArrow]
}

/// Where an arrow takes the keyboard in rows of cards (rails, or a grid's rows).
public enum PageKeyboardTravel {
  /// `rows` are the card ids of each row in order; nil when the move leaves the top.
  public static func next<ID: Hashable>(from current: ID, rows: [[ID]],
                                        direction: MoveCommandDirection) -> ID?? {
    guard let r = rows.firstIndex(where: { $0.contains(current) }),
          let c = rows[r].firstIndex(of: current) else { return .none }
    switch direction {
    case .left:
      return c > 0 ? .some(rows[r][c - 1]) : .none
    case .right:
      return c + 1 < rows[r].count ? .some(rows[r][c + 1]) : .none
    case .up:
      guard r > 0 else { return .some(nil) }
      let above = rows[r - 1]
      return above.isEmpty ? .none : .some(above[min(c, above.count - 1)])
    case .down:
      guard r + 1 < rows.count else { return .none }
      let below = rows[r + 1]
      return below.isEmpty ? .none : .some(below[min(c, below.count - 1)])
    @unknown default:
      return .none
    }
  }
}
#endif
