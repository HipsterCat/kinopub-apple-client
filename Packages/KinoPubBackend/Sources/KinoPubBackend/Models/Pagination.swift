//
//  Pagination.swift
//
//
//  Created by Kirill Kunst on 21.07.2023.
//

import Foundation

public struct Pagination: Codable {
  /// Total number of pages.
  public let total: Int
  public let current: Int
  public let perpage: Int
  /// Total number of matching items when the host sends `total_items`.
  public let totalItems: Int?

  public init(total: Int, current: Int, perpage: Int, totalItems: Int? = nil) {
    self.total = total
    self.current = current
    self.perpage = perpage
    self.totalItems = totalItems
  }

  enum CodingKeys: String, CodingKey {
    case total
    case current
    case perpage
    case totalItems = "total_items"
  }

  /// Best-known result count for catalog chrome. Prefers `total_items`; otherwise
  /// estimates from pages × page size while more pages remain.
  public func resultCount(loadedItemCount: Int) -> Int {
    if let totalItems { return totalItems }
    if current >= total { return loadedItemCount }
    return max(loadedItemCount, total * perpage)
  }
}
