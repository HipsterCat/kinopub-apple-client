//
//  Duration.swift
//
//
//  Created by Kirill Kunst on 21.07.2023.
//

import Foundation
import KinoPubMedia

public struct Duration: Codable, Hashable {
  public let average: Double
  public let total: TimeInterval
}

public extension Duration {
  /// Legacy long form used by older chrome — prefer `compact` for new UI.
  @available(*, deprecated, message: "Use RuntimeText(seconds:).formatted(.medium).")
  var hoursMinutesFormatted: String {
    Self.hoursMinutes(seconds: Int(total))
  }

  /// «1ч 48 мин» — `RuntimeText`, medium.
  @available(*, deprecated, message: "Use RuntimeText(seconds:).formatted(.medium).")
  static func hoursMinutes(seconds: Int) -> String {
    RuntimeText(seconds: seconds).formatted(.medium) ?? ""
  }

  /// «2ч 35м», «39м», past a day «1д 12ч 4м» — `RuntimeText`, short.
  @available(*, deprecated, message: "Use RuntimeText(seconds:).formatted(.short), or .text(for: MediaSurface).")
  static func compact(seconds: Int) -> String {
    RuntimeText(seconds: seconds).formatted(.short) ?? ""
  }

  /// Short, with the minutes total once it is an hour or more — «1ч 45м (105 мин)».
  @available(*, deprecated, message: "Use RuntimeText: formatted(.short) and minutesOnly().")
  static func compactWithMinutes(seconds: Int) -> String {
    let runtime = RuntimeText(seconds: seconds)
    guard let short = runtime.formatted(.short) else { return "" }
    guard runtime.minutes >= 60, let minutes = runtime.minutesOnly() else { return short }
    return "\(short) (\(minutes))"
  }

  /// Alias kept for call sites that still say "hoursMinutes".
  @available(*, deprecated, message: "Use RuntimeText(seconds:).formatted(.short).")
  static func compactHoursMinutes(seconds: Int) -> String {
    compact(seconds: seconds)
  }

  var totalFormatted: String {
    let formatter = DateComponentsFormatter()
    #if os(iOS)
    formatter.allowedUnits = [.hour, .minute, .second, .nanosecond]
    #endif
    formatter.unitsStyle = .positional
    return formatter.string(from: self.total) ?? ""
  }
}
