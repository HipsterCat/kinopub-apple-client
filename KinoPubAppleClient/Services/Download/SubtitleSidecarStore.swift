//
//  SubtitleSidecarStore.swift
//  KinoPubAppleClient
//
//  While a title downloads and the device is online, fetch every sidecar SRT the API
//  listed and rewrite `DownloadMeta.subtitles` to local `file://` URLs so offline
//  playback still has EN/RU (and the rest). HLS embeds renditions in the `.movpkg`;
//  this path is for the mp4 engine and for meta that must round-trip through the player.
//

import Foundation
import KinoPubBackend
import KinoPubLogging
import OSLog

enum SubtitleSidecarStore {

  /// Downloads each remote sidecar next to Documents/Subtitles/<key>/ and returns meta
  /// with those URLs rewritten. Already-local URLs are left alone. Failures keep the
  /// remote URL so a later online play can still load them.
  static func localize(_ meta: DownloadMeta) async -> DownloadMeta {
    guard !meta.subtitles.isEmpty else { return meta }
    let folder = directory(for: meta)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    } catch {
      Logger.app.error("[SUBS] could not create \(folder.path): \(error)")
      return meta
    }
    var updated: [Subtitle] = []
    for (index, sub) in meta.subtitles.enumerated() {
      guard let remote = URL(string: sub.url), remote.scheme == "http" || remote.scheme == "https" else {
        updated.append(sub)
        continue
      }
      let name = filename(for: sub, index: index)
      let local = folder.appendingPathComponent(name)
      if !FileManager.default.fileExists(atPath: local.path) {
        do {
          let (data, _) = try await URLSession.shared.data(from: remote)
          try data.write(to: local, options: .atomic)
        } catch {
          Logger.app.error("[SUBS] failed \(remote.absoluteString): \(error)")
          updated.append(sub)
          continue
        }
      }
      updated.append(Subtitle(lang: sub.lang, shift: sub.shift, embed: sub.embed,
                              url: local.absoluteString))
    }
    var next = meta
    next.subtitles = updated
    return next
  }

  private static func directory(for meta: DownloadMeta) -> URL {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let key = HLSDownloadKey.make(for: meta)
      .replacingOccurrences(of: "|", with: "_")
    return documents.appendingPathComponent("Subtitles/\(key)", isDirectory: true)
  }

  private static func filename(for sub: Subtitle, index: Int) -> String {
    let lang = sub.lang.isEmpty ? "und" : sub.lang
    return String(format: "%02d-%@.srt", index + 1, lang)
  }
}
