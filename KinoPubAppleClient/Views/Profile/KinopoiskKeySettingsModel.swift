//
//  IntegrationKeySettingsModel.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubMetadata

/// Drives the "enter your own API key" flow of Settings › Integrations (Kinopoisk
/// Unofficial, TMDB, OMDb) on every platform. Saving and validating
/// happen together, on the explicit "Validate" action — typing alone doesn't
/// touch Keychain on every keystroke.
@MainActor
final class IntegrationKeySettingsModel: ObservableObject {
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

  let integration: Integration
  private let keyProvider: IntegrationKeyProvider
  private let client = MetadataHTTPClient()

  init(keyProvider: IntegrationKeyProvider = .kinopoisk, integration: Integration = .kinopoisk) {
    self.integration = integration
    self.keyProvider = keyProvider
    let existing = keyProvider.rawKey() ?? ""
    self.keyText = existing
    self.validationState = (!existing.isEmpty && keyProvider.isValidated) ? .valid : .idle
  }

  /// One cheap, content-agnostic call that only a working key answers.
  private static func validationRequest(for integration: Integration, key: String) -> (URL, [String: String]) {
    switch integration {
    case .tmdb:
      // A v4 read access token is a JWT and goes in the header; a v3 key is a query item.
      if key.hasPrefix("eyJ") {
        return (URL(string: "https://api.themoviedb.org/3/configuration")!, ["Authorization": "Bearer \(key)"])
      }
      var components = URLComponents(string: "https://api.themoviedb.org/3/configuration")!
      components.queryItems = [URLQueryItem(name: "api_key", value: key)]
      return (components.url!, [:])
    case .omdb:
      // The Shawshank Redemption again. A bad key answers 401 "Invalid API key!".
      return (OMDbSource.requestURL(imdb: "tt0111161", key: key)!, [:])
    default:
      // A permanently-stable kinopoisk id (The Shawshank Redemption).
      return (URL(string: "https://kinopoiskapiunofficial.tech/api/v2.2/films/326")!, ["X-API-KEY": key])
    }
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
      let (url, headers) = Self.validationRequest(for: integration, key: trimmed)
      _ = try await client.getData(url: url, headers: headers)
      keyProvider.markValidated()
      validationState = .valid
    } catch MetadataError.httpStatus(402) where integration == .kinopoisk {
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
    case .invalid, .networkError: statusText.localized
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
      return String(format: "Couldn't reach %@ right now — try again.".localized, integration.name)
    }
  }
}
