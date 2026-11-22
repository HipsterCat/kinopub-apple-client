//
//  UserData.swift
//
//
//  Created by Kirill Kunst on 9.08.2023.
//

import Foundation

public struct UserData: Codable, Sendable {
  
  public struct Subscription: Codable, Sendable {
    public let active: Bool
    public let endTime: TimeInterval
    public let days: Double
    
    private enum CodingKeys: String, CodingKey {
      case active, days
      case endTime = "end_time"
    }
  }
  
  public struct Profile: Codable, Sendable {
    public let name: String?
    public let avatar: String?
  }
  
  public struct Settings: Codable, Sendable {
    public let showErotic: Bool
    public let showUncertain: Bool
    
    private enum CodingKeys: String, CodingKey {
      case showErotic = "show_erotic"
      case showUncertain = "show_uncertain"
    }
  }
  
  public let username: String
  public let registrationDate: TimeInterval
  public let settings: Settings
  public let subscription: Subscription
  public let profile: Profile
  
  private enum CodingKeys: String, CodingKey {
    case username, subscription, profile, settings
    case registrationDate = "reg_date"
  }
}

public extension UserData {
  var registrationDateFormatted: String {
    Date(timeIntervalSince1970: self.registrationDate).formatted()
  }
}

public extension UserData {
  /// Nothing known yet: an empty name and no subscription line, rather than a made-up one.
  static let placeholder = UserData(username: "",
                                    registrationDate: 0,
                                    settings: Settings(showErotic: false, showUncertain: false),
                                    subscription: Subscription(active: false, endTime: 0, days: 0),
                                    profile: Profile(name: nil, avatar: nil))

  static func mock() -> UserData {
    UserData(username: "Test User",
             registrationDate: 0,
             settings: Settings(showErotic: true, showUncertain: true),
             subscription: Subscription(active: true, endTime: 3333333, days: 20.5),
             profile: Profile(name: "Test User Full", avatar: ""))
  }
}
