import Foundation

/// Resolves the MyAnimeList Client ID without ever hard-coding a value.
///
/// Order: process environment `MAL_CLIENT_ID`, then Info.plist `MALClientID`
/// (typically `$(MAL_CLIENT_ID)` from the build). Unsubstituted `$(…)` placeholders
/// and empty strings are treated as missing.
public enum MyAnimeListCredentials: Sendable {
  public static let infoKey = "MALClientID"
  public static let envName = "MAL_CLIENT_ID"
  /// OAuth redirect registered for the Piratic MAL application (account linking later).
  public static let redirectURI = "piratic://myanimelist"

  public static func clientID(bundle: Bundle = .main,
                              environment: [String: String] = ProcessInfo.processInfo.environment)
    -> String? {
    sanitize(environment[envName])
      ?? sanitize(bundle.object(forInfoDictionaryKey: infoKey) as? String)
  }

  public static func sanitize(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty,
          !trimmed.contains("$(")
    else { return nil }
    return trimmed
  }
}
