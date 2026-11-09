//
//  ProviderMark.swift
//  KinoPubUI
//
//  Outside services' marks from `Media.xcassets/ratings` (Trakt, Simkl, AniList,
//  MyAnimeList, TMDB, Kinopoisk…), for screens outside this package that name a
//  service — Settings › Integrations first of all.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum ProviderMark {
  /// The mark named `name` in `ratings/`, or nil when the catalog has none.
  public static func image(named name: String) -> Image? {
    guard exists(name) else { return nil }
    return Image(name, bundle: .module)
  }

#if canImport(UIKit)
  public static func uiImage(named name: String) -> UIImage? {
    UIImage(named: name, in: .module, compatibleWith: nil)
  }
#endif

  private static func exists(_ name: String) -> Bool {
#if canImport(UIKit)
    UIImage(named: name, in: .module, compatibleWith: nil) != nil
#elseif canImport(AppKit)
    Bundle.module.image(forResource: name) != nil
#endif
  }
}
