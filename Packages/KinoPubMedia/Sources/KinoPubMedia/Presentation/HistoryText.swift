import Foundation

/// **When a history play happened** — «27 января в 20:54», «27 January at 20:54».
public struct HistoryEventText: Hashable, Sendable {
  public let date: Date

  public init?(_ date: Date?) {
    guard let date else { return nil }
    self.date = date
  }

  public func formatted(language: MediaLanguage = .current,
                        timeZone: TimeZone = .current) -> String {
    let day = Self.string(from: date, template: "d MMMM", language: language, timeZone: timeZone)
    let time = Self.clock(from: date, language: language, timeZone: timeZone)
    switch language {
    case .ru: return "\(day) в \(time)"
    case .en: return "\(day) at \(time)"
    }
  }

  private static func clock(from date: Date, language: MediaLanguage, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = language.locale
    formatter.timeZone = timeZone
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }

  static func string(from date: Date,
                     template: String,
                     language: MediaLanguage,
                     timeZone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = language.locale
    formatter.timeZone = timeZone
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
  }
}

/// **The day a history play belongs to** — «Сегодня», «Вчера», «15 сентября 2026».
public struct HistoryDayText: Hashable, Sendable {
  public let day: Date

  public init(_ day: Date) {
    self.day = day
  }

  public func formatted(language: MediaLanguage = .current,
                        calendar: Calendar = .current,
                        now: Date = Date()) -> String {
    if calendar.isDate(day, inSameDayAs: now) {
      return language == .ru ? "Сегодня" : "Today"
    }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
       calendar.isDate(day, inSameDayAs: yesterday) {
      return language == .ru ? "Вчера" : "Yesterday"
    }
    return HistoryEventText.string(from: day,
                                   template: "d MMMM yyyy",
                                   language: language,
                                   timeZone: calendar.timeZone)
  }
}
