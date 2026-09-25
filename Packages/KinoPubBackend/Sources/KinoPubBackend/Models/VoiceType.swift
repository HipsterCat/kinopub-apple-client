//
//  VoiceType.swift
//  KinoPubBackend
//
//  How a track is voiced — kino.pub's own ids, the same everywhere they appear: an audio
//  track's `type.id`, `GET /v1/references/voiceover-type`, and kino.watch's `voiceType`
//  filter (verified 2026-09-26). One enum for the player's track ladder, the catalog of
//  voiceover authors, and future "preferred voiceover" settings.
//

import Foundation

public enum VoiceType: Int, CaseIterable, Codable, Hashable, Sendable, Identifiable {
  /// kino.watch's "Неопределён".
  case undetermined = -1
  case dub = 1
  /// Многоголосый.
  case multiVoice = 2
  /// Двухголосый.
  case twoVoice = 3
  /// Одноголосый.
  case singleVoice = 4
  /// Авторский.
  case author = 5
  case original = 6
  /// Нейросеть.
  case neural = 7

  public var id: Int { rawValue }

  /// The API's `short_title`.
  public var shortTitle: String {
    switch self {
    case .undetermined: "—"
    case .dub: "DUB"
    case .multiVoice: "MVO"
    case .twoVoice: "DVO"
    case .singleVoice: "VO"
    case .author: "AVO"
    case .original: "Orig"
    case .neural: "Ai"
    }
  }

  /// Localization key.
  public var titleKey: String {
    switch self {
    case .undetermined: "VoiceType_Undetermined"
    case .dub: "VoiceType_Dub"
    case .multiVoice: "VoiceType_MultiVoice"
    case .twoVoice: "VoiceType_TwoVoice"
    case .singleVoice: "VoiceType_SingleVoice"
    case .author: "VoiceType_Author"
    case .original: "VoiceType_Original"
    case .neural: "VoiceType_Neural"
    }
  }

  /// The player's default ladder: DUB → MVO → DVO → VO → AVO → Orig, the rest after.
  /// `AudioTracks.kindRank` reads this, so the order lives in one place.
  public var preferenceRank: Int {
    switch self {
    case .dub: 0
    case .multiVoice: 1
    case .twoVoice: 2
    case .singleVoice: 3
    case .author: 4
    case .original: 5
    case .neural, .undetermined: AudioTracks.kindRankUnknown
    }
  }
}
