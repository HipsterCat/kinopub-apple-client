//
//  KinopoiskKeySettingsModel.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubMetadata

/// Drives the "enter your Kinopoisk Unofficial API key" flow shared by the
/// iOS/macOS Settings form and the tvOS push destination. Saving and validating
/// happen together, on the explicit "Validate" action — typing alone doesn't
/// touch Keychain on every keystroke.
@MainActor
final class KinopoiskKeySettingsModel: ObservableObject {
  enum ValidationState: Equatable {
    case idle
    case checking
    case valid
    case validButQuotaExceeded
    case invalid
    case networkError
  }

  @Published var keyText: String
  @Published private(set) var validationState: ValidationState

  private let keyProvider: KinopoiskKeyProvider
  private let client = MetadataHTTPClient()

  /// A permanently-stable kinopoisk id (The Shawshank Redemption) — cheap,
  /// content-agnostic call just to check the key itself.
  private static let validationURL = URL(string: "https://kinopoiskapiunofficial.tech/api/v2.2/films/326")!

  init(keyProvider: KinopoiskKeyProvider) {
    self.keyProvider = keyProvider
    let existing = keyProvider.rawKey() ?? ""
    self.keyText = existing
    self.validationState = (!existing.isEmpty && KinopoiskKeyValidation.isValidated) ? .valid : .idle
  }

  var isValidateEnabled: Bool {
    !keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validationState != .checking
  }

  func validate() async {
    await check(key: keyText)
  }

  /// Saves `key` and asks Kinopoisk Unofficial whether it works. The Integrations
  /// page calls this from its key alert; the field there is its own draft.
  @discardableResult
  func check(key: String) async -> ValidationState {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return validationState }
    keyText = trimmed
    validationState = .checking
    keyProvider.save(key: trimmed)
    do {
      _ = try await client.getData(url: Self.validationURL, headers: ["X-API-KEY": trimmed])
      keyProvider.markValidated()
      validationState = .valid
    } catch MetadataError.httpStatus(402) {
      // Real key, today's free-tier quota is just used up.
      keyProvider.markValidated()
      validationState = .validButQuotaExceeded
    } catch MetadataError.httpStatus(let code) where code == 401 || code == 403 {
      validationState = .invalid
    } catch {
      validationState = .networkError
    }
    return validationState
  }

  /// Forgets the key: Keychain and the validated flag.
  func disconnect() {
    keyProvider.removeKey()
    keyText = ""
    validationState = .idle
  }

  /// Why the key alert comes back after Verify, or nil when the key was kept.
  var failureText: String? {
    switch validationState {
    case .invalid, .networkError: statusText
    default: nil
    }
  }

  var statusText: String {
    switch validationState {
    case .idle:
      return "Optional — adds photos, facts and awards to detail pages, from Kinopoisk Unofficial (a third-party service, not an official Kinopoisk product)."
    case .checking:
      return "Checking…"
    case .valid:
      return "Key saved and working."
    case .validButQuotaExceeded:
      return "Key is valid, but today's quota is used up — it'll work again once it resets."
    case .invalid:
      return "That key was rejected — check it and try again."
    case .networkError:
      return "Couldn't reach Kinopoisk right now — try again."
    }
  }
}
