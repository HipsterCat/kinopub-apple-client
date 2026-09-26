//
//  PaginatedItemsResponse.swift
//
//
//  Created by Kirill Kunst on 26.07.2023.
//

import Foundation

public struct PaginatedData<T: Codable>: Codable {

  public var items: [T]
  public var pagination: Pagination

  /// Several answers to the same page number as one: items in the given order, the
  /// furthest `total` (so paging goes on while any answer has more). Search "everywhere"
  /// is three requests — without `field` the server matches titles only (2026-09-26).
  public static func merging(_ pages: [PaginatedData]) -> PaginatedData {
    PaginatedData(items: pages.flatMap(\.items),
                  pagination: Pagination(total: pages.map(\.pagination.total).max() ?? 0,
                                         current: pages.map(\.pagination.current).max() ?? 0,
                                         perpage: pages.map(\.pagination.perpage).reduce(0, +)))
  }

  public static func mock(data: [T]) -> PaginatedData {
    return PaginatedData(items: data, pagination: Pagination(total: 0, current: 0, perpage: 0))
  }

}
