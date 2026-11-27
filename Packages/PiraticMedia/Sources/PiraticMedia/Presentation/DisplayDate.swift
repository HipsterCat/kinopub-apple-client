import Foundation

public extension Date {
  /// Keep the locale's date and time layout with a bare year in Russian.
  func formattedForDisplay(_ style: Date.FormatStyle) -> String {
    let value = formatted(style)
    guard style.locale.language.languageCode?.identifier == "ru" else { return value }
    return value.replacingOccurrences(of: #"(?<=\p{Nd})\h+г\."#, with: "", options: .regularExpression)
  }
}
