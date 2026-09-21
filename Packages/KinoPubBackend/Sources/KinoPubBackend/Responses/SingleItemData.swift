
import Foundation

public struct SingleItemData<T: Codable>: Codable {

  public var item: T

  public static func mock(data: T) -> SingleItemData {
    return SingleItemData(item: data)
  }

}
