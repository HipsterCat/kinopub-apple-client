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

  var totalFormatted: String {
    let formatter = DateComponentsFormatter()
    #if os(iOS)
    formatter.allowedUnits = [.hour, .minute, .second, .nanosecond]
    #endif
    formatter.unitsStyle = .positional
    return formatter.string(from: self.total) ?? ""
  }
}
