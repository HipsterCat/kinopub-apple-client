//
//  PlexAccount.swift
//  KinoPubAppleClient
//
//  The viewer's Plex account, for Plex's cloud catalogue (`PlexSource`): Common Sense
//  Media, content ratings and the IMDb / Rotten Tomatoes figures Plex relays. No Plex
//  server is needed.
//
//  Plex registers no apps and issues no secrets: the app names itself (X-Plex-Product)
//  and keeps a random id per install (X-Plex-Client-Identifier). Sign-in is Plex's PIN
//  flow, the one Rivulet and Plozz use: `POST plex.tv/api/v2/pins` gives a short code,
//  the viewer enters it at plex.tv/link, and polling the pin returns the account token
//  (Sasha, 2026-11-09). The token goes to the Keychain.
//

import Foundation
import Observation
import KinoPubMetadata

/// The token and client id `PlexSource` sends, read on every request.
struct PlexMetadataAccess: PlexAccessProviding {
  func plexToken() -> String? { PlexAccount.storedToken }
  var plexClientIdentifier: String { PlexAccount.clientIdentifier }
}

private struct PlexToken: Codable, Sendable {
  var authToken: String
}

private extension Key where Value == PlexToken {
  static var plexToken: Key<PlexToken> { .init(rawValue: "token") }
}

@Observable
@MainActor
final class PlexAccount: AccountSigningIn {
  static let shared = PlexAccount()

  private(set) var signIn: AccountSignIn = .idle
  private(set) var username: String? = PlexAccount.storedUsername
  var isSignedIn: Bool { username != nil }

  nonisolated static let usernameDefaultsKey = "plexUsername"
  nonisolated static var storedUsername: String? {
    UserDefaults.standard.string(forKey: usernameDefaultsKey)
  }

  /// One per install, as Plex asks; it names this device in the viewer's Plex account.
  nonisolated static var clientIdentifier: String {
    let key = "plexClientIdentifier"
    if let id = UserDefaults.standard.string(forKey: key) { return id }
    let id = UUID().uuidString
    UserDefaults.standard.set(id, forKey: key)
    return id
  }

  nonisolated(unsafe) private static let storage = KeychainStorageImpl(service: "com.soda.kinopub.plex")

  nonisolated static var storedToken: String? {
    guard storedUsername != nil else { return nil }
    let token: PlexToken? = storage.object(for: .plexToken)
    return token?.authToken
  }

  private let baseURL = URL(string: "https://plex.tv/api/v2")!
  private var signInTask: Task<Void, Never>?

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
    Self.storage.setObject(nil as PlexToken?, for: .plexToken)
    UserDefaults.standard.removeObject(forKey: Self.usernameDefaultsKey)
    username = nil
  }

  private struct Pin: Decodable {
    let id: Int
    let code: String
    let expiresIn: Double?
    let authToken: String?
  }

  private func runSignIn() async {
    signIn = .requestingCode
    do {
      let (data, status) = try await send("pins", method: "POST")
      guard status == 200 || status == 201, let pin = try? JSONDecoder().decode(Pin.self, from: data) else {
        signIn = .failed(String(format: "Account_Error_HTTP".localized, "Plex", status))
        return
      }
      let expiresAt = Date().addingTimeInterval(pin.expiresIn ?? 900)
      signIn = .awaitingUser(code: pin.code, url: URL(string: "https://plex.tv/link")!, expiresAt: expiresAt)
      while Date() < expiresAt {
        try await Task.sleep(for: .seconds(2))
        let (data, status) = try await send("pins/\(pin.id)", method: "GET")
        switch status {
        case 200:
          guard let token = (try? JSONDecoder().decode(Pin.self, from: data))?.authToken, !token.isEmpty else {
            continue // Not entered yet.
          }
          Self.storage.setObject(PlexToken(authToken: token), for: .plexToken)
          await loadUsername(token: token)
          signIn = .idle
          return
        case 404:
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
      signIn = .failed(String(format: "Account_Error_Network".localized, "Plex"))
    }
  }

  private func loadUsername(token: String) async {
    struct User: Decodable { let username: String?; let title: String? }
    var name = "Plex"
    if let (data, status) = try? await send("user", method: "GET", token: token), status == 200,
       let user = try? JSONDecoder().decode(User.self, from: data),
       let found = [user.username, user.title].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
      name = found
    }
    UserDefaults.standard.set(name, forKey: Self.usernameDefaultsKey)
    username = name
  }

  // MARK: HTTP

  private func send(_ path: String, method: String, token: String? = nil) async throws -> (Data, Int) {
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("KinoPub", forHTTPHeaderField: "X-Plex-Product")
    request.setValue(Self.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
#if os(tvOS)
    request.setValue("tvOS", forHTTPHeaderField: "X-Plex-Platform")
#elseif os(macOS)
    request.setValue("macOS", forHTTPHeaderField: "X-Plex-Platform")
#else
    request.setValue("iOS", forHTTPHeaderField: "X-Plex-Platform")
#endif
    if let token { request.setValue(token, forHTTPHeaderField: "X-Plex-Token") }
    let (data, response) = try await URLSession.shared.data(for: request)
    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
  }
}
