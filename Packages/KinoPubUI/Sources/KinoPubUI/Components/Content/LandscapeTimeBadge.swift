//
//  LandscapeTimeBadge.swift
//  KinoPubUI
//
//  Apple-style landscape still time chip: play + duration, play + time left,
//  or checkmark + duration when finished.
//

import SwiftUI
import KinoPubBackend
import KinoPubMedia

/// Watch-state chip for landscape cards (Continue Watching, History, etc.).
public struct LandscapeTimeBadge: View {
  public enum Kind: Equatable {
    case unwatched(total: String)
    /// The whole phrase — «53m left», «Ещё 53м».
    case inProgress(remaining: String)
    case watched(total: String)
  }

  public let kind: Kind
  /// What VoiceOver reads: always the long, spelled-out time.
  private let spoken: String?

  public init(kind: Kind) {
    self.kind = kind
    self.spoken = nil
  }

  /// Builds a badge from a card that already classified through `WatchProgress`.
  ///
  /// `progress` is `resumeFraction` (nil unless in-progress). Do not pass a raw
  /// `time / duration` and expect this init to recover the credits window — 0.95
  /// of a two-hour title is six minutes left; `WatchProgress` finishes at three.
  public init?(durationSeconds: Int?, progress: Double?, isWatched: Bool) {
    guard let durationSeconds, durationSeconds >= 60 else { return nil }
    let runtime = RuntimeText(seconds: durationSeconds)
    guard let total = runtime.text(for: .timeBadge) else { return nil }
    let spokenTotal = runtime.accessibilityLabel() ?? total
    if isWatched {
      self.kind = .watched(total: total)
      self.spoken = "\(String(localized: "Watched")), \(spokenTotal)"
      return
    }
    if let fraction = progress {
      let left = RemainingText(progress: fraction, durationSeconds: durationSeconds)
      self.kind = .inProgress(remaining: left.formatted(MediaSurface.timeBadge.runtimeLength))
      self.spoken = left.accessibilityLabel()
      return
    }
    self.kind = .unwatched(total: total)
    self.spoken = spokenTotal
  }

  public var body: some View {
    HStack(spacing: 2) {
      if let iconName {
        Image(systemName: iconName)
              .font(.system(.caption2, weight: .bold))
      }
      Text(label)
        .font(.caption2.weight(.medium))
//        .monospacedDigit()
    }
    .foregroundStyle(isWatchedStyle ? Color.black : Color.white)
    .padding(.horizontal, 4)
    .padding(.vertical, 3)
    .background(pillFill, in: Capsule(style: .continuous))
    .accessibilityLabel(Text(accessibilityLabel))
  }

  private var isWatchedStyle: Bool {
    if case .watched = kind { return true }
    return false
  }

  /// Nil draws the chip as bare time. Focus and pointer platforms already put a play
  /// glyph in the middle of the still while the card is focused / hovered, so the chip
  /// repeating it there is one glyph too many; touch has no such state and keeps it.
  private var iconName: String? {
    switch kind {
    case .watched:
      return "checkmark"
    case .unwatched, .inProgress:
#if os(tvOS) || os(macOS)
      return nil
#else
      return "play.fill"
#endif
    }
  }

  private var label: String {
    switch kind {
    case .unwatched(let text), .watched(let text), .inProgress(let text):
      return text
    }
  }

  private var accessibilityLabel: String {
    if let spoken { return spoken }
    if case .watched(let total) = kind { return "\(String(localized: "Watched")), \(total)" }
    return label
  }

  private var pillFill: Color {
    isWatchedStyle
      ? Color.KinoPub.subtitle.opacity(0.8)
      : Color.black.opacity(0.55)
  }
}
