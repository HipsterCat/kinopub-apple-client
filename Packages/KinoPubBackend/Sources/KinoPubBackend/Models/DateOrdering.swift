//
//  DateOrdering.swift
//

import Foundation

extension Date {
  /// `>=` and `<=` on `Date` are weak-linked to a Foundation overlay the compiler
  /// calls on any OS that reports 27.2. iPad OS 27.2 seed 24B5089g has no such
  /// symbol: the stub is null and the call lands at address 0 (`EXC_BAD_ACCESS`).
  /// Order by the reference interval, which is the compiler's own fallback.
  public func isOnOrAfter(_ other: Date) -> Bool {
    timeIntervalSinceReferenceDate >= other.timeIntervalSinceReferenceDate
  }

  /// See ``isOnOrAfter(_:)``.
  public func isOnOrBefore(_ other: Date) -> Bool {
    timeIntervalSinceReferenceDate <= other.timeIntervalSinceReferenceDate
  }
}
