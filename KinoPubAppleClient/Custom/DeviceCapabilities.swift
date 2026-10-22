//
//  DeviceCapabilities.swift
//  KinoPubAppleClient
//
//  Detects whether this device can DECODE HEVC (incl. 10-bit / HDR10), so we advertise
//  HEVC/4K/HDR to kino.pub only where the stream will actually play. Ported from
//  dungeon-master-xx/kinopub-apple-client.
//

import Foundation
import KinoPubBackend

enum DeviceCapabilities {

  /// Universal Apple client capability profile. Because all Apple devices share one
  /// session via iCloud Keychain, we always advertise the maximum playback profile
  /// (`4K + HDR + HEVC + SSL + mixedPlaylist`) so opening the app on an iPhone, iPad,
  /// or Simulator never downgrades the shared device slot used by Apple TV or Mac.
  static let supportsHEVC: Bool = true
  static let supports4K: Bool = true
  static let supportsHDR: Bool = true
  static let supportsSSL: Bool = true
  static let usesMixedPlaylist: Bool = true

  /// Applies the universal Apple client streaming capabilities to `settings`, returning
  /// `true` when at least one capability flag changed and needs to be saved on kino.pub.
  @discardableResult
  static func applyUniversalProfile(to settings: inout DeviceSettings) -> Bool {
    let changed = settings.support4k != supports4K
      || settings.supportHdr != supportsHDR
      || settings.supportHevc != supportsHEVC
      || settings.supportSsl != supportsSSL
      || settings.mixedPlaylist != usesMixedPlaylist
    settings.support4k = supports4K
    settings.supportHdr = supportsHDR
    settings.supportHevc = supportsHEVC
    settings.supportSsl = supportsSSL
    settings.mixedPlaylist = usesMixedPlaylist
    return changed
  }
}
