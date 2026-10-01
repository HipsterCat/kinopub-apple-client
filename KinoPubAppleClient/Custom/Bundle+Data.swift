//
//  Bundle+Data.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 10.08.2023.
//

import Foundation

extension Bundle {
  public var appBuild: String          { getInfo("CFBundleVersion") }
  public var appVersionLong: String    { getInfo("CFBundleShortVersionString") }
  /// What changed in this build. The TestFlight lane writes its "What to Test" text into
  /// `KPReleaseNotes` before archiving; a local build has none.
  public var releaseNotes: String? {
    let notes = (infoDictionary?["KPReleaseNotes"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return notes?.isEmpty == false ? notes : nil
  }
  fileprivate func getInfo(_ str: String) -> String { infoDictionary?[str] as? String ?? "⚠️" }
}
