//
//  Bundle+Data.swift
//  Piratic
//
//  Created by Kirill Kunst on 10.08.2023.
//

import Foundation

extension Bundle {
  public var appBuild: String          { getInfo("CFBundleVersion") }
  public var appVersionLong: String    { getInfo("CFBundleShortVersionString") }
  /// Home-screen / About title (`CFBundleDisplayName`), not the Swift module (`PRODUCT_NAME`).
  public var appDisplayName: String {
    object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? "Piratic"
  }
  fileprivate func getInfo(_ str: String) -> String { infoDictionary?[str] as? String ?? "⚠️" }
}
