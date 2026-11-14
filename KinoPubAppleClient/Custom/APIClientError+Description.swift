//
//  APIClientError+Description.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 27.07.2023.
//

import Foundation
import KinoPubBackend
 
extension APIClientError: CustomStringConvertible { // Extension declares a conformance of imported type 'APIClientError' to imported protocol 'CustomStringConvertible'; this will not behave correctly if the owners of 'KinoPubBackend' introduce this conformance in the future
  public var description: String {
    switch self {
    case .urlError:
      return "Wrong URL"
    case .invalidUrlParams:
      return "Invalid URL params"
    case .decodingError(let error):
      return "Decoding issue: \(error)"
    case .networkError(let error):
      if let error = error as? BackendError {
        return error.errorDescription ?? error.localizedDescription
      }
      return "Networking issue: \(error)"
    case .httpStatus(let code, _):
      return "HTTP \(code)"
    }
  }

  var isAuthorizationPending: Bool {
    switch self {
    case .networkError(let error):
      if let backendError = error as? BackendError, backendError.errorCode == .authorizationPending {
        return true
      }
      break
    default: return false
    }
    return false
  }

  /// OAuth device-flow `slow_down` — caller must increase its poll interval.
  var isSlowDown: Bool {
    switch self {
    case .networkError(let error):
      if let backendError = error as? BackendError, backendError.errorCode == .slowDown {
        return true
      }
      return false
    default:
      return false
    }
  }

  /// True when the OAuth device-flow endpoint explicitly reports that the verification
  /// code has expired or been rejected (as opposed to `authorization_pending`,
  /// `slow_down`, or a transient transport/server error).
  var isDeviceCodeExpired: Bool {
    switch self {
    case .networkError(let error):
      guard let backendError = error as? BackendError else { return false }
      switch backendError.errorCode {
      case .invalidGrant:
        return true
      case .unknown(let raw):
        let normalized = raw.lowercased()
        return normalized == "expired_token"
          || normalized == "bad_verification_code"
          || normalized == "access_denied"
      case .authorizationPending, .slowDown, .invalidClient, .unauthorized, .userBanned:
        return false
      }
    default:
      return false
    }
  }

  /// True only when the backend explicitly rejected the credentials. Delegates to
  /// the backend's `isAuthRejection` so the app and the tests share one truth.
  var isFatalAuthError: Bool {
    isAuthRejection
  }

  /// Cancelled requests are superseded by newer ones, not failed — no error UI for them.
  var isCancellation: Bool {
    guard case .networkError(let error) = self else { return false }
    return (error as? URLError)?.code == .cancelled
  }

  /// Short text for the error toast and unavailable-content views. Tells the truth
  /// about the cause: an expired session is not "check your connection".
  var userFacingMessage: String {
    switch self {
    case .networkError(let error):
      if let backendError = error as? BackendError {
        switch backendError.errorCode {
        case .userBanned:
          return "This account can't sign in right now. Sign in again or use another account.".localized
        case .invalidGrant, .unauthorized, .invalidClient:
          return "Your session has expired. Sign in again.".localized
        case .authorizationPending, .slowDown:
          break
        case .unknown(let raw):
          if raw.lowercased() == "user_banned" {
            return "This account can't sign in right now. Sign in again or use another account.".localized
          }
          return backendError.errorDescription ?? raw
        }
        return backendError.errorDescription ?? backendError.errorCode.rawValue
      }
      if error is URLError {
        return "Check your connection and try again.".localized
      }
      return error.localizedDescription
    case .httpStatus(let code, _):
      if code == 401 {
        return "Your session has expired. Sign in again.".localized
      }
      return "Request failed (\(code))"
    case .urlError, .invalidUrlParams, .decodingError:
      return description
    }
  }

}

extension Error {
  /// `APIClientError.userFacingMessage` when possible, the system's text otherwise —
  /// so call sites don't have to unwrap the error type themselves.
  var userFacingMessage: String {
    (self as? APIClientError)?.userFacingMessage ?? localizedDescription
  }
}

// MARK: - Load failure text

/// What an unavailable view says about a failed load: a headline in plain words, a
/// sentence on what to do, and the technical kind on a line of its own (`HTTP 502 ·
/// bad gateway`, `URLError -1009`), so a screenshot tells what actually happened
/// (Sasha, 2026-11-08).
struct LoadFailureText: Equatable {
  /// Localized headline: "kino.pub Isn't Responding", "No Internet Connection".
  let title: String
  let systemImage: String
  /// Localized advice under the headline.
  let message: String
  /// The error kind as the network reported it. Not translated: it is for a bug report.
  let detail: String?
}

extension Error {

  /// `LoadFailureText` for any error a load can throw: the API client's own cases,
  /// a bare `URLError`, or anything else (its `localizedDescription`).
  var loadFailureText: LoadFailureText {
    if let apiError = self as? APIClientError {
      return apiError.failureText
    }
    if let urlError = self as? URLError {
      return LoadFailureText.transport(urlError)
    }
    return LoadFailureText(title: "Couldn't Load".localized,
                           systemImage: "exclamationmark.triangle",
                           message: localizedDescription,
                           detail: String(describing: type(of: self)))
  }
}

private extension APIClientError {

  var failureText: LoadFailureText {
    switch self {
    case .httpStatus(let code, _):
      return LoadFailureText.http(code)
    case .networkError(let error):
      if let urlError = error as? URLError {
        return LoadFailureText.transport(urlError)
      }
      if let backendError = error as? BackendError {
        let detail = backendError.status > 0
          ? "HTTP \(backendError.status) · \(backendError.errorCode.rawValue)"
          : "API · \(backendError.errorCode.rawValue)"
        if isUserBanned {
          return LoadFailureText(title: "Account Unavailable".localized,
                                 systemImage: "person.crop.circle.badge.exclamationmark",
                                 message: "This account can't sign in right now. Sign in again or use another account.".localized,
                                 detail: detail)
        }
        if requiresInteractiveReauthentication || isAuthRejection {
          return LoadFailureText(title: "Session Expired".localized,
                                 systemImage: "person.crop.circle.badge.exclamationmark",
                                 message: "Your session has expired. Sign in again.".localized,
                                 detail: detail)
        }
        return LoadFailureText(title: "Couldn't Load".localized,
                               systemImage: "exclamationmark.triangle",
                               message: backendError.errorDescription
                                 ?? "The server answered with an error.".localized,
                               detail: detail)
      }
      return LoadFailureText(title: "Network Error".localized,
                             systemImage: "wifi.exclamationmark",
                             message: "Something went wrong while loading.".localized,
                             detail: String(describing: error))
    case .decodingError(let error):
      return LoadFailureText(title: "Unexpected Response".localized,
                             systemImage: "doc.questionmark",
                             message: "The app couldn't read the server's answer. An update may fix it.".localized,
                             detail: LoadFailureText.decodingDetail(error))
    case .urlError, .invalidUrlParams:
      return LoadFailureText(title: "Couldn't Load".localized,
                             systemImage: "exclamationmark.triangle",
                             message: "Something went wrong while loading.".localized,
                             detail: description)
    }
  }
}

extension LoadFailureText {

  /// A non-2xx answer whose body was not kino.pub's JSON envelope — nginx's 502 page,
  /// a Cloudflare 5xx, a bare 404.
  static func http(_ code: Int) -> LoadFailureText {
    let reason = HTTPURLResponse.localizedString(forStatusCode: code)
    let detail = reason.isEmpty ? "HTTP \(code)" : "HTTP \(code) · \(reason)"
    switch code {
    case 401:
      return LoadFailureText(title: "Session Expired".localized,
                             systemImage: "person.crop.circle.badge.exclamationmark",
                             message: "Your session has expired. Sign in again.".localized,
                             detail: detail)
    case 403:
      return LoadFailureText(title: "Access Denied".localized,
                             systemImage: "lock",
                             message: "kino.pub refused this request.".localized,
                             detail: detail)
    case 404, 410:
      return LoadFailureText(title: "Not Found".localized,
                             systemImage: "questionmark.folder",
                             message: "kino.pub doesn't have this, or it was removed.".localized,
                             detail: detail)
    case 429:
      return LoadFailureText(title: "Too Many Requests".localized,
                             systemImage: "hourglass",
                             message: "kino.pub asks to slow down. Try again in a minute.".localized,
                             detail: detail)
    case 500...599:
      return LoadFailureText(title: "kino.pub Isn't Responding".localized,
                             systemImage: "exclamationmark.icloud",
                             message: "The server is having trouble. It usually passes quickly — try again in a minute.".localized,
                             detail: detail)
    default:
      return LoadFailureText(title: "Couldn't Load".localized,
                             systemImage: "exclamationmark.triangle",
                             message: "The server answered with an error.".localized,
                             detail: detail)
    }
  }

  /// The request never got an answer: offline, timed out, host not reachable, TLS.
  static func transport(_ error: URLError) -> LoadFailureText {
    let detail = "URLError \(error.code.rawValue)"
    switch error.code {
    case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
         .internationalRoamingOff:
      return LoadFailureText(title: "No Internet Connection".localized,
                             systemImage: "wifi.slash",
                             message: "Check your connection and try again.".localized,
                             detail: detail)
    case .timedOut:
      return LoadFailureText(title: "kino.pub Isn't Responding".localized,
                             systemImage: "clock.badge.exclamationmark",
                             message: "The server didn't answer in time.".localized,
                             detail: detail)
    case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
      return LoadFailureText(title: "Can't Reach kino.pub".localized,
                             systemImage: "network.slash",
                             message: "The server can't be reached right now.".localized,
                             detail: detail)
    case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
         .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
      return LoadFailureText(title: "Secure Connection Failed".localized,
                             systemImage: "lock.trianglebadge.exclamationmark",
                             message: "The connection to the server isn't secure. Check the date and time, VPN or proxy.".localized,
                             detail: detail)
    default:
      return LoadFailureText(title: "Network Error".localized,
                             systemImage: "wifi.exclamationmark",
                             message: error.localizedDescription,
                             detail: detail)
    }
  }

  /// Which field broke the decode, in the payload's own key path.
  static func decodingDetail(_ error: Error) -> String {
    func path(_ context: DecodingError.Context) -> String {
      let keys = context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }
      return keys.isEmpty ? "root" : keys.joined(separator: ".")
    }
    guard let decoding = error as? DecodingError else {
      return "Decoding · \(error)"
    }
    switch decoding {
    case .keyNotFound(let key, let context):
      return "Decoding · missing «\(key.stringValue)» at \(path(context))"
    case .typeMismatch(let type, let context):
      return "Decoding · \(type) expected at \(path(context))"
    case .valueNotFound(let type, let context):
      return "Decoding · \(type) is null at \(path(context))"
    case .dataCorrupted(let context):
      return "Decoding · corrupted at \(path(context))"
    @unknown default:
      return "Decoding · \(decoding)"
    }
  }
}
