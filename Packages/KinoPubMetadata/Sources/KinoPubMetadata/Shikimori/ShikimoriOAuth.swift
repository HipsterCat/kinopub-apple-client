import Foundation

/// Shikimori OAuth + GraphQL preparation for Piratic (`user_rates`).
///
/// Read paths should prefer GraphQL (`https://shikimori.one/api/graphql`) over REST
/// v1/v2 when possible. Writes to `user_rates` still use OAuth + REST/GraphQL mutations
/// once the Piratic app is registered on Shikimori.
///
/// **Credentials never live in source.** Only the Info.plist / env **names** are stored
/// here. `SHIKIMORI_CLIENT_SECRET` must not appear in Info.plist or any committed
/// xcconfig — Keychain, CI env, or a worker secret only.
public enum ShikimoriOAuth: Sendable {
  /// Required on every Shikimori request, including token exchange.
  public static let userAgent = "Piratic"

  public static let authorizeURL = URL(string: "https://shikimori.one/oauth/authorize")!
  public static let tokenURL = URL(string: "https://shikimori.one/oauth/token")!
  public static let graphqlURL = URL(string: "https://shikimori.one/api/graphql")!
  public static let apiBaseURL = URL(string: "https://shikimori.one/api")!

  /// Registered redirect for the Piratic Shikimori OAuth application.
  public static let redirectURI = "piratic://shikimori"

  /// Info.plist key for the Client ID placeholder (`$(SHIKIMORI_CLIENT_ID)`).
  public static let clientIDInfoKey = "ShikimoriClientID"
  /// Process / CI environment name for the Client ID value.
  public static let clientIDEnvName = "SHIKIMORI_CLIENT_ID"
  /// Process / CI / worker secret name for the Client Secret value — never commit the value.
  public static let clientSecretEnvName = "SHIKIMORI_CLIENT_SECRET"

  /// Scope needed to create / update / delete the viewer's rates.
  public static let userRatesScope = "user_rates"

  public static func clientID(bundle: Bundle = .main,
                              environment: [String: String] = ProcessInfo.processInfo.environment)
    -> String? {
    sanitize(environment[clientIDEnvName])
      ?? sanitize(bundle.object(forInfoDictionaryKey: clientIDInfoKey) as? String)
  }

  /// Client Secret from the environment only — never from Info.plist.
  public static func clientSecret(environment: [String: String] = ProcessInfo.processInfo.environment)
    -> String? {
    sanitize(environment[clientSecretEnvName])
  }

  public static var isClientConfigured: Bool { clientID() != nil }

  /// Authorization URL for the Piratic app. Callers supply PKCE / state when the
  /// sign-in UI is wired; this builds the base query Shikimori expects.
  public static func authorizationURL(clientID: String,
                                      redirectURI: String = redirectURI,
                                      scope: String = userRatesScope) -> URL? {
    var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "scope", value: scope),
    ]
    return components?.url
  }

  /// Default headers for GraphQL / API reads once a Bearer token is available.
  public static func headers(accessToken: String?) -> [String: String] {
    var headers = [
      "User-Agent": userAgent,
      "Accept": "application/json",
      "Content-Type": "application/json",
    ]
    if let accessToken, !accessToken.isEmpty {
      headers["Authorization"] = "Bearer \(accessToken)"
    }
    return headers
  }

  /// GraphQL query body for the current user's rates (prefer over REST `GET /api/v2/user_rates`).
  public static let userRatesGraphQLQuery = """
    query UserRates($page: Int, $limit: Int) {
      userRates(page: $page, limit: $limit) {
        id
        score
        status
        episodes
        rewatches
        targetId
        targetType
      }
    }
    """

  private static func sanitize(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty,
          !trimmed.contains("$(")
    else { return nil }
    return trimmed
  }
}

/// Deep-link redirects registered for Piratic OAuth apps.
public enum PiraticOAuthRedirect: Sendable, Equatable {
  /// MAL app redirect (`piratic://myanimelist…`).
  case myAnimeList(URL)
  /// Shikimori app redirect (`piratic://shikimori…`).
  case shikimori(URL)

  public init?(url: URL) {
    guard url.scheme?.lowercased() == "piratic" else { return nil }
    switch url.host?.lowercased() {
    case "myanimelist": self = .myAnimeList(url)
    case "shikimori": self = .shikimori(url)
    default: return nil
    }
  }
}
