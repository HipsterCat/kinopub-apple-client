//
//  TraktAccount.swift
//  KinoPubAppleClient
//
//  The viewer's Trakt account: sign-in with a device code, tokens in the Keychain.
//
//  Device code on every platform, not a browser redirect: it is the one flow an Apple TV
//  can do, and our Trakt app is PKCE-only with no client secret — Trakt made the secret
//  optional on the device token and refresh calls when it stopped issuing secrets
//  (trakt/trakt-api#974, 2026-10). The Client ID is public by design (`TraktClientID` in
//  Info.plist). The app is a Trakt "Development" app: only Sasha and the people he adds
//  can sign in until Trakt grants a production one.
//
//  Sync (scrobbling, history, watchlist) builds on `validAccessToken()`; it is not here yet.
//  Trakt's public data (ratings, reviews) needs no sign-in: `TraktMetadataAccess`.
//

import Foundation
import Observation
import KinoPubMetadata

/// Trakt as a metadata source (`TraktSource`): the Client ID while the viewer keeps
/// «Оценки и отзывы» on in Settings › Integrations › Trakt. On by default.
struct TraktMetadataAccess: TraktAccessProviding {
  static let enabledDefaultsKey = "traktMetadataEnabled"

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? true
  }

  func traktClientID() -> String? {
    Self.isEnabled ? TraktAccount.clientID : nil
  }
}

/// Douban's scores through our worker (`DoubanSource`), while the viewer keeps «Оценки»
/// on in Settings › Integrations › Douban. On by default; nothing to connect.
struct DoubanMetadataAccess: DoubanAccessProviding {
  static let enabledDefaultsKey = "doubanMetadataEnabled"

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? true
  }

  var isDoubanEnabled: Bool { Self.isEnabled }
}

/// Wikidata's ids, links, box office and award counts (`WikidataSource`), while the
/// viewer keeps it on in Settings › Integrations › Wikidata. On by default.
struct WikidataMetadataAccess: WikidataAccessProviding {
  static let enabledDefaultsKey = "wikidataMetadataEnabled"

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? true
  }

  var isWikidataEnabled: Bool { Self.isEnabled }
}

/// MyShows' score and audience for series (`MyShowsSource`), while the viewer keeps it on
/// in Settings › Integrations › MyShows. On by default; its public API needs no account.
struct MyShowsMetadataAccess: MyShowsAccessProviding {
  static let enabledDefaultsKey = "myShowsMetadataEnabled"

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? true
  }

  var isMyShowsEnabled: Bool { Self.isEnabled }
}

/// SkipDB's and TheIntroDB's skip times in the player, each while the viewer keeps it on
/// in Settings › Integrations. On by default; both read without a key.
struct SkipTimesMetadataAccess: SkipTimesAccessProviding {
  static let skipDBDefaultsKey = "skipDBMetadataEnabled"
  static let theIntroDBDefaultsKey = "theIntroDBMetadataEnabled"

  static func isEnabled(_ key: String) -> Bool {
    UserDefaults.standard.object(forKey: key) as? Bool ?? true
  }

  func isEnabled(_ source: MetadataSourceID) -> Bool {
    switch source {
    case .skipDB: Self.isEnabled(Self.skipDBDefaultsKey)
    case .introdb: Self.isEnabled(Self.theIntroDBDefaultsKey)
    default: false
    }
  }
}

struct TraktToken: Codable, Sendable {
  var accessToken: String
  var refreshToken: String
  var expiresAt: Date
}

extension Key where Value == TraktToken {
  static var traktToken: Key<TraktToken> { .init(rawValue: "token") }
}

@Observable
@MainActor
final class TraktAccount: AccountSigningIn {
  static let shared = TraktAccount()

  typealias SignIn = AccountSignIn

  private(set) var signIn: SignIn = .idle
  private(set) var username: String? = TraktAccount.storedUsername
  var isSignedIn: Bool { username != nil }

  // UserDefaults, not secrets: read by `Integration.status` and observed by Settings.
  nonisolated static let usernameDefaultsKey = "traktUsername"
  nonisolated static var storedUsername: String? {
    UserDefaults.standard.string(forKey: usernameDefaultsKey)
  }

  nonisolated static var clientID: String? {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: "TraktClientID") as? String else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private let storage = KeychainStorageImpl(service: "com.soda.kinopub.trakt")
  private let baseURL = URL(string: "https://api.trakt.tv")!
  /// Registered on the Trakt app; the refresh call repeats it though nothing redirects.
  private let redirectURI = "http://localhost/callback"
  private var signInTask: Task<Void, Never>?

  private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  // MARK: Sign in

  func startSignIn() {
    signInTask?.cancel()
    signInTask = Task { await runSignIn() }
  }

  func cancelSignIn() {
    signInTask?.cancel()
    signInTask = nil
    signIn = .idle
  }

  func signOut() {
    cancelSignIn()
    if let token: TraktToken = storage.object(for: .traktToken), let clientID = Self.clientID {
      // Best effort: the token is forgotten here either way.
      let body = ["token": token.accessToken, "client_id": clientID]
      Task { _ = try? await post("oauth/revoke", body: body) }
    }
    storage.setObject(nil as TraktToken?, for: .traktToken)
    UserDefaults.standard.removeObject(forKey: Self.usernameDefaultsKey)
    username = nil
  }

  private struct DeviceCode: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationUrl: String
    let expiresIn: Double
    let interval: Double
  }

  private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Double
    let createdAt: Double
  }

  private func runSignIn() async {
    guard let clientID = Self.clientID else {
      signIn = .failed("Trakt_Error_NoClientID".localized)
      return
    }
    signIn = .requestingCode
    do {
      let (data, status) = try await post("oauth/device/code", body: ["client_id": clientID])
      guard status == 200 else {
        signIn = .failed(String(format: "Trakt_Error_HTTP".localized, status))
        return
      }
      let code = try decoder.decode(DeviceCode.self, from: data)
      let expiresAt = Date().addingTimeInterval(code.expiresIn)
      let url = URL(string: code.verificationUrl) ?? URL(string: "https://trakt.tv/activate")!
      signIn = .awaitingUser(code: code.userCode, url: url, expiresAt: expiresAt)

      var interval = max(code.interval, 1)
      while Date() < expiresAt {
        try await Task.sleep(for: .seconds(interval))
        let (data, status) = try await post("oauth/device/token",
                                            body: ["code": code.deviceCode, "client_id": clientID])
        switch status {
        case 200:
          let token = try decoder.decode(TokenResponse.self, from: data)
          store(token)
          await loadUsername()
          signIn = .idle
          return
        case 400:
          continue // Not entered yet.
        case 429:
          interval += 1 // Polling too fast.
        case 418:
          signIn = .failed("Trakt_Error_Denied".localized)
          return
        case 404, 409, 410:
          signIn = .failed("Trakt_Error_CodeExpired".localized)
          return
        default:
          continue
        }
      }
      signIn = .failed("Trakt_Error_CodeExpired".localized)
    } catch is CancellationError {
      // Cancelled by the viewer; `cancelSignIn` already reset the state.
    } catch {
      signIn = .failed("Trakt_Error_Network".localized)
    }
  }

  private func store(_ response: TokenResponse) {
    let token = TraktToken(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      expiresAt: Date(timeIntervalSince1970: response.createdAt + response.expiresIn)
    )
    storage.setObject(token, for: .traktToken)
  }

  private func loadUsername() async {
    guard let access = await validAccessToken() else { return }
    var request = URLRequest(url: baseURL.appending(path: "users/settings"))
    applyHeaders(to: &request)
    request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
    struct Settings: Decodable {
      struct User: Decodable { let username: String?; let name: String? }
      let user: User?
    }
    let name: String
    if let result = try? await URLSession.shared.data(for: request),
       let settings = try? decoder.decode(Settings.self, from: result.0),
       let username = settings.user?.username, !username.isEmpty {
      name = username
    } else {
      // Signed in all the same; the name comes on the next look.
      name = "Trakt"
    }
    UserDefaults.standard.set(name, forKey: Self.usernameDefaultsKey)
    username = name
  }

  // MARK: Tokens

  /// The access token, refreshed first when it ends within a day. Nil when signed out
  /// or the refresh was refused (the viewer then signs in again).
  func validAccessToken() async -> String? {
    guard let token: TraktToken = storage.object(for: .traktToken) else { return nil }
    if token.expiresAt.timeIntervalSinceNow > 24 * 60 * 60 { return token.accessToken }
    guard let clientID = Self.clientID else { return nil }
    let body = [
      "refresh_token": token.refreshToken,
      "client_id": clientID,
      "redirect_uri": redirectURI,
      "grant_type": "refresh_token",
    ]
    guard let result = try? await post("oauth/token", body: body), result.1 == 200,
          let response = try? decoder.decode(TokenResponse.self, from: result.0) else {
      return token.expiresAt > Date() ? token.accessToken : nil
    }
    // Trakt rotates the refresh token on every refresh.
    store(response)
    return response.accessToken
  }

  // MARK: HTTP

  private func applyHeaders(to request: inout URLRequest) {
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("2", forHTTPHeaderField: "trakt-api-version")
    if let clientID = Self.clientID {
      request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
    }
  }

  private func post(_ path: String, body: [String: String]) async throws -> (Data, Int) {
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = "POST"
    applyHeaders(to: &request)
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
  }
}
