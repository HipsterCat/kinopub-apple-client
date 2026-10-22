//
//  TokenResponse.swift
//  
//
//  Created by Kirill Kunst on 17.07.2023.
//

import Foundation

public struct AccessToken: Codable, Equatable, Sendable {
  public let accessToken: String
  public let refreshToken: String
  public let expiresIn: Int

  public init(accessToken: String, refreshToken: String, expiresIn: Int) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.expiresIn = expiresIn
  }

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case expiresIn = "expires_in"
    case refreshToken = "refresh_token"
  }
}
