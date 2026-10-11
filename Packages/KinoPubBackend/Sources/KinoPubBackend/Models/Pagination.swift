//
//  Pagination.swift
//
//
//  Created by Kirill Kunst on 21.07.2023.
//

import Foundation

public struct Pagination: Codable {
  public let total: Int
  public let current: Int
  public let perpage: Int

  public init(total: Int, current: Int, perpage: Int) {
    self.total = total
    self.current = current
    self.perpage = perpage
  }
}
