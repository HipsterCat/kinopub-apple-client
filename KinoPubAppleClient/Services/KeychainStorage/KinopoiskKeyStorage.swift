//
//  KinopoiskKeyStorage.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubMetadata

/// Separate Keychain service from `"com.soda.kinopub"` — this key isn't
/// kino.pub-session-scoped, so `KeychainStorageImpl.clear()` on logout must not
/// wipe it. See the isolated-storage note in the Kinopoisk integration plan.
private let kinopoiskKeychainService = "com.soda.kinopub.kinopoisk"

extension Key where Value == String {
  static var kinopoiskAPIKey: Key<String> { .init(rawValue: "apiKey") }
}

/// Not a secret — just "has the currently stored key passed a validation call."
/// Plain UserDefaults, cleared whenever the key text changes.
enum KinopoiskKeyValidation {
  static let defaultsKey = "kinopoiskAPIKeyValidated"
  /// Settings › Integrations › Kinopoisk's switch: a connected key the viewer turned off
  /// stays stored but is not used. On until switched off.
  static let enabledKey = "kinopoiskAPIKeyEnabled"

  static var isValidated: Bool {
    get { UserDefaults.standard.bool(forKey: defaultsKey) }
    set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
  }

  static var isEnabled: Bool {
    get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
  }
}

/// Bridges the isolated Kinopoisk Keychain storage to `KinopoiskKeyProviding`.
/// `currentAPIKey()` (the protocol method `KinopoiskSource` calls) only returns a
/// key once it's validated, so a typo'd key doesn't get hit on every detail-page
/// load — Settings goes through `rawKey()`/`save(key:)`/`markValidated()` instead,
/// which need the unvalidated value too (to prefill the field, to know what to
/// validate).
final class KinopoiskKeyProvider: KinopoiskKeyProviding, @unchecked Sendable {
  private let storage: KeychainStorage

  init(storage: KeychainStorage = KeychainStorageImpl(service: kinopoiskKeychainService)) {
    self.storage = storage
  }

  func currentAPIKey() -> String? {
    guard KinopoiskKeyValidation.isValidated, KinopoiskKeyValidation.isEnabled else { return nil }
    let key: String? = storage.object(for: .kinopoiskAPIKey)
    return (key?.isEmpty ?? true) ? nil : key
  }

  func rawKey() -> String? {
    storage.object(for: .kinopoiskAPIKey)
  }

  func save(key: String?) {
    storage.setObject(key, for: .kinopoiskAPIKey)
    KinopoiskKeyValidation.isValidated = false
  }

  func markValidated() {
    KinopoiskKeyValidation.isValidated = true
    KinopoiskKeyValidation.isEnabled = true
  }

  /// Settings' "Disconnect": the key leaves the Keychain.
  func removeKey() {
    storage.setObject(nil as String?, for: .kinopoiskAPIKey)
    KinopoiskKeyValidation.isValidated = false
  }
}
