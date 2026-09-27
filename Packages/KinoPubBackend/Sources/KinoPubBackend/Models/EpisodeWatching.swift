//
//  EpisodeWatching.swift
//
//
//  Created by Kirill Kunst on 21.07.2023.
//

import Foundation

public struct EpisodeWatching: Codable, Hashable {
  public let status: Int
  public let time: Int

  public init(status: Int, time: Int) {
    self.status = status
    self.time = time
  }
}
