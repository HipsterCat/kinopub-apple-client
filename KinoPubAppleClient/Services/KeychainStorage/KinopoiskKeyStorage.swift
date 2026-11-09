//
//  KinopoiskKeyStorage.swift
//  KinoPubAppleClient
//
//  The viewer's own API keys for Settings › Integrations (Kinopoisk Unofficial, TMDB).
//

import Foundation
import KinoPubMetadata

extension Key where Value == String {
  static var integrationAPIKey: Key<String> { .init(rawValue: "apiKey") }
}

/// One source's key: the Keychain item, whether it passed a check, and whether the
/// viewer has it switched on.
///
/// Each source has its own Keychain service, apart from `"com.soda.kinopub"` — these keys
/// are not kino.pub-session-scoped, so `KeychainStorageImpl.clear()` on logout must not
/// wipe them. The two flags are not secrets: plain UserDefaults, and "validated" is
/// cleared whenever the key text changes.
final class IntegrationKeyProvider: @unchecked Sendable {
  /// UserDefaults: the stored key passed a check.
  let validatedDefaultsKey: String
  /// UserDefaults: the viewer's switch beside the key. A key switched off stays stored.
  let enabledDefaultsKey: String
  private let storage: KeychainStorage

  init(service: String, validatedDefaultsKey: String, enabledDefaultsKey: String) {
    self.storage = KeychainStorageImpl(service: service)
    self.validatedDefaultsKey = validatedDefaultsKey
    self.enabledDefaultsKey = enabledDefaultsKey
  }

  /// Kinopoisk Unofficial (kinopoiskapiunofficial.tech). The defaults keys predate the
  /// other sources and keep their names.
  static let kinopoisk = IntegrationKeyProvider(
    service: "com.soda.kinopub.kinopoisk",
    validatedDefaultsKey: "kinopoiskAPIKeyValidated",
    enabledDefaultsKey: "kinopoiskAPIKeyEnabled"
  )

  /// The viewer's own TMDB key. Switched on, TMDB is asked directly with it instead of
  /// through KinoPub's server (the "KinoPub proxy" switch is its inverse).
  static let tmdb = IntegrationKeyProvider(
    service: "com.soda.kinopub.tmdb",
    validatedDefaultsKey: "tmdbAPIKeyValidated",
    enabledDefaultsKey: "tmdbAPIKeyEnabled"
  )

  var isValidated: Bool {
    get { UserDefaults.standard.bool(forKey: validatedDefaultsKey) }
    set { UserDefaults.standard.set(newValue, forKey: validatedDefaultsKey) }
  }

  /// On until switched off.
  var isEnabled: Bool {
    get { UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? true }
    set { UserDefaults.standard.set(newValue, forKey: enabledDefaultsKey) }
  }

  var isConnected: Bool { isValidated }

  /// The key the sources use: stored, checked, switched on.
  func activeKey() -> String? {
    guard isValidated, isEnabled else { return nil }
    let key: String? = storage.object(for: .integrationAPIKey)
    return (key?.isEmpty ?? true) ? nil : key
  }

  /// The stored key whether or not it passed — Settings needs it to know what to check.
  func rawKey() -> String? {
    storage.object(for: .integrationAPIKey)
  }

  func save(key: String?) {
    storage.setObject(key, for: .integrationAPIKey)
    isValidated = false
  }

  /// A key that just passed its check is switched on.
  func markValidated() {
    isValidated = true
    isEnabled = true
  }

  /// Settings' "Disconnect": the key leaves the Keychain.
  func removeKey() {
    storage.setObject(nil as String?, for: .integrationAPIKey)
    isValidated = false
  }
}

/// `KinopoiskSource` reads the key fresh on every request; nil means "not configured",
/// including a stored key that has not passed its check or is switched off.
extension IntegrationKeyProvider: KinopoiskKeyProviding {
  func currentAPIKey() -> String? { activeKey() }
}

/// `TMDBSource` goes to api.themoviedb.org itself while this returns a key.
extension IntegrationKeyProvider: TMDBDirectAccessProviding {
  func directAPIKey() -> String? { activeKey() }
}

/// Kept for the screens that only ever meant Kinopoisk's flags.
enum KinopoiskKeyValidation {
  static var defaultsKey: String { IntegrationKeyProvider.kinopoisk.validatedDefaultsKey }
  static var enabledKey: String { IntegrationKeyProvider.kinopoisk.enabledDefaultsKey }

  static var isValidated: Bool {
    get { IntegrationKeyProvider.kinopoisk.isValidated }
    set { IntegrationKeyProvider.kinopoisk.isValidated = newValue }
  }

  static var isEnabled: Bool {
    get { IntegrationKeyProvider.kinopoisk.isEnabled }
    set { IntegrationKeyProvider.kinopoisk.isEnabled = newValue }
  }
}
