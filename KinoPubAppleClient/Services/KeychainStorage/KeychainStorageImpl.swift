//
//  KeychainStorageImpl.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 27.07.2023.
//

import Foundation
import KeychainAccess
import KinoPubLogging
import OSLog

/// Underlying Keychain store abstraction so `KeychainStorageImpl` can pair an iCloud-synced
/// (`kSecAttrSynchronizable = kCFBooleanTrue`) store with a local fallback store and be
/// deterministically unit-tested.
protocol KeychainDataStore {
  func getData(_ key: String) throws -> Data?
  func set(_ value: Data, key: String) throws
  func remove(_ key: String) throws
  func removeAll() throws
}

private struct KeychainAccessStore: KeychainDataStore {
  let keychain: Keychain

  func getData(_ key: String) throws -> Data? {
    try keychain.getData(key, ignoringAttributeSynchronizable: false)
  }

  func set(_ value: Data, key: String) throws {
    try keychain.set(value, key: key, ignoringAttributeSynchronizable: false)
  }

  func remove(_ key: String) throws {
    try keychain.remove(key, ignoringAttributeSynchronizable: false)
  }

  func removeAll() throws {
    try keychain.removeAll()
  }
}

final class KeychainStorageImpl: KeychainStorage {

  private let synchronizableStore: KeychainDataStore
  private let localStore: KeychainDataStore

  init(service: String = "com.soda.kinopub") {
    self.synchronizableStore = KeychainAccessStore(
      keychain: Keychain(service: service)
        .synchronizable(true)
        .accessibility(.afterFirstUnlock)
    )
    self.localStore = KeychainAccessStore(
      keychain: Keychain(service: service)
        .synchronizable(false)
        .accessibility(.afterFirstUnlock)
    )
  }

  init(synchronizableStore: KeychainDataStore, localStore: KeychainDataStore) {
    self.synchronizableStore = synchronizableStore
    self.localStore = localStore
  }

  public func object<Value>(for key: Key<Value>) -> Value? where Value: Decodable, Value: Encodable {
    let decoder = JSONDecoder()

    // 1. Prefer the iCloud-synchronizable Keychain item so signing in or refreshing on
    //    any Apple device propagates across iPhone, iPad, Mac, Apple TV, and Vision Pro.
    if let syncedData = try? synchronizableStore.getData(key.rawValue),
       let decoded = try? decoder.decode(Value.self, from: syncedData) {
      return decoded
    }

    // 2. Fall back to the local-only Keychain item and automatically migrate it into
    //    the synchronizable Keychain so pre-existing local sessions are preserved and
    //    promoted to iCloud Keychain without asking the user to re-authenticate.
    do {
      guard let localData = try localStore.getData(key.rawValue) else { return nil }
      let decoded = try decoder.decode(Value.self, from: localData)
      if (try? synchronizableStore.set(localData, key: key.rawValue)) != nil {
        try? localStore.remove(key.rawValue)
      }
      return decoded
    } catch {
      Logger.app.debug("Keychain read failed for \(key.rawValue): \(String(describing: error))")
      return nil
    }
  }

  public func setObject<Value>(_ object: Value?, for key: Key<Value>) where Value: Decodable, Value: Encodable {
    guard let object else {
      try? synchronizableStore.remove(key.rawValue)
      try? localStore.remove(key.rawValue)
      return
    }

    do {
      let data = try JSONEncoder().encode(object)
      do {
        try synchronizableStore.set(data, key: key.rawValue)
        // Remove any legacy local-only duplicate once the synchronizable write succeeds
        // so an older local entry can never shadow future iCloud Keychain updates.
        try? localStore.remove(key.rawValue)
      } catch {
        // Unsigned simulator/test environments without keychain-sync entitlements fall
        // back to the local store transparently.
        try localStore.set(data, key: key.rawValue)
      }
    } catch {
      Logger.app.debug("Keychain write failed for \(key.rawValue): \(String(describing: error))")
    }
  }
  
  func clear() {
    try? synchronizableStore.removeAll()
    try? localStore.removeAll()
  }
}
