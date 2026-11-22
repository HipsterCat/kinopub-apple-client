//
//  SkipChip.swift
//  KinoPubAppleClient
//
//  The skip control on iOS and the Mac, where AVKit has no `contextualActions`.
//  Ordinary glass, so it sits with the player chrome instead of shouting over it.
//  It fades out on its own, a short dissolve, as the chrome starts to leave.
//

import SwiftUI
import KinoPubBackend
import KinoPubMedia
import KinoPubUI

#if !os(tvOS)

struct SkipChipOverlay: View {
  @ObservedObject var manager: PlayerManager
  @ObservedObject var chrome: PlayerChromeMonitor
  /// Where the buttons are, for the pass-through host. Not observed: nothing redraws from it.
  var hitRegions: SkipHitRegions

  @AppStorage(SkipChipPreferences.styleKey) private var styleRaw = SkipAutoStyle.apple.rawValue
  @AppStorage(SkipChipPreferences.cancelKey) private var cancelRaw = SkipCancelStyle.dismiss.rawValue
  @AppStorage(SkipChipPreferences.delayKey) private var delaySeconds = SkipChipPreferences.defaultDelay

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var style: SkipAutoStyle { SkipAutoStyle(rawValue: styleRaw) ?? .apple }
  private var cancel: SkipCancelStyle { SkipCancelStyle(rawValue: cancelRaw) ?? .dismiss }
  private var delay: Double { Double(delaySeconds) }

  private var shown: Bool {
    SkipChipVisibility.shown(hasOffer: manager.skipOffer != nil,
                             controlsVisible: chrome.controlsVisible,
                             menuActive: chrome.menuActive)
  }

  private var ahead: SkipAheadContent { manager.skipAheadContent() }

  private var pipWanted: Bool { shown && style == .pictureInPicture }

  private var dissolve: Animation {
    reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.22)
  }

  var body: some View {
    ZStack {
      if style == .pictureInPicture {
        pictureInPictureCaption
      }
      VStack(spacing: 0) {
        if style == .banner {
          banner
            .padding(.top, 28)
            .padding(.horizontal, 24)
        }
        Spacer(minLength: 0)
          .allowsHitTesting(false)
        if style != .banner {
          HStack {
            Spacer(minLength: 0)
              .allowsHitTesting(false)
            chipRow
          }
          .padding(.trailing, 24)
          .padding(.bottom, 88)
        }
      }
    }
    .coordinateSpace(.named(SkipHitRegions.space))
    .opacity(shown ? 1 : 0)
    .animation(dissolve, value: shown)
    .allowsHitTesting(shown)
    .onChange(of: shown, initial: true) { _, shown in
      hitRegions.enabled = shown
    }
    .environment(\.colorScheme, .dark)
    .onChange(of: pipWanted, initial: true) { _, wanted in
      chrome.setPictureInPicture(active: wanted, artworkURL: ahead.artworkURL)
    }
    .onChange(of: ahead.artworkURL) { _, url in
      guard pipWanted else { return }
      chrome.setPictureInPicture(active: true, artworkURL: url)
    }
  }

  private var chipRow: some View {
    HStack(spacing: 10) {
      if cancel == .watchCredits {
        watchCreditsButton
      }
      skipButton
      if cancel == .dismiss {
        dismissButton
      }
    }
  }

  private var skipButton: some View {
    Button(action: { manager.performSkip() }) {
      skipLabel
        .font(.headline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .modifier(SkipProgressDecoration(style: style, fractionLeft: manager.skipCountdownLeft))
    }
    .modifier(SkipGlassProminence(prominent: cancel.skipIsProminent))
    .accessibilityLabel(accessibilityTitle)
    .accessibilityIdentifier("player.skip")
    .skipHitRegion("skip", in: hitRegions)
  }

  private var dismissButton: some View {
    Button(action: { manager.dismissSkip() }) {
      Image(systemName: "xmark")
        .font(.headline)
        .padding(8)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.white)
    .accessibilityLabel("Player_SkipDismiss".localized)
    .accessibilityIdentifier("player.skip.cancel")
    .skipHitRegion("dismiss", in: hitRegions)
  }

  private var watchCreditsButton: some View {
    Button(action: { manager.dismissSkip() }) {
      Text("Player_WatchCredits".localized)
        .font(.headline)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.white)
    .accessibilityIdentifier("player.skip.cancel")
    .skipHitRegion("watchCredits", in: hitRegions)
  }

  @ViewBuilder
  private var skipLabel: some View {
    switch style {
    case .countdown:
      Label(PlaybackSkip.countdownLabel(countdownLeft: manager.skipCountdownLeft, delay: delay),
            systemImage: skipSymbolName)
    case .ring:
      HStack(spacing: 8) {
        CircularProgressRing(progress: manager.skipCountdownLeft, color: .white, track: .white.opacity(0.28))
          .frame(width: 18, height: 18)
        Label(PlaybackSkip.title, systemImage: skipSymbolName)
      }
    default:
      Label(PlaybackSkip.title, systemImage: skipSymbolName)
    }
  }

  private var skipSymbolName: String {
    guard let offer = manager.skipOffer else { return "forward.fill" }
    return PlaybackSkip.symbolName(for: offer, durationSeconds: manager.skipDurationSeconds)
  }

  private var banner: some View {
    HStack(alignment: .center, spacing: 12) {
      Button(action: { manager.performSkip() }) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Player_SkipNext".localized)
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(ahead.title)
            .font(.headline)
            .lineLimit(2)
          SkipProgressBar(fractionElapsed: 1 - manager.skipCountdownLeft)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 420, alignment: .leading)
      }
      .modifier(SkipGlassProminence(prominent: cancel.skipIsProminent))
      .accessibilityLabel(accessibilityTitle)
      .accessibilityIdentifier("player.skip")
      .skipHitRegion("banner", in: hitRegions)
      if cancel == .watchCredits {
        watchCreditsButton
      } else {
        dismissButton
      }
    }
  }

  /// Leading caption over the artwork. The shrunk video sits trailing, under this overlay.
  private var pictureInPictureCaption: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Player_SkipNext".localized)
        .font(.caption)
        .foregroundStyle(.white.opacity(0.8))
      Text(ahead.title)
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white)
        .lineLimit(3)
      SkipProgressBar(fractionElapsed: 1 - manager.skipCountdownLeft)
        .frame(maxWidth: 280)
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .allowsHitTesting(false)
  }

  private var accessibilityTitle: String {
    guard let offer = manager.skipOffer else { return PlaybackSkip.title }
    return PlaybackSkip.accessibilityTitle(for: offer.kind)
  }
}

/// The chip's host covers the whole player and passes every touch through to AVKit
/// except those on a button. A hosting view answers `hitTest` with itself for any
/// point over SwiftUI content, buttons or not, so the host cannot tell a button from
/// empty space on its own: the buttons report their frames here instead.
@MainActor
final class SkipHitRegions {
  static let space = "skip.chip"

  var enabled = false
  private var rects: [String: CGRect] = [:]

  func set(_ rect: CGRect, for id: String) {
    rects[id] = rect
  }

  func remove(_ id: String) {
    rects[id] = nil
  }

  /// `point` in the hosting view's coordinates, which is the overlay's root space.
  func contains(_ point: CGPoint) -> Bool {
    enabled && rects.values.contains { $0.insetBy(dx: -6, dy: -6).contains(point) }
  }
}

private extension View {
  func skipHitRegion(_ id: String, in regions: SkipHitRegions) -> some View {
    onGeometryChange(for: CGRect.self) { proxy in
      proxy.frame(in: .named(SkipHitRegions.space))
    } action: { rect in
      regions.set(rect, for: id)
    }
    .onDisappear { regions.remove(id) }
  }
}

/// `.glass` and `.glassProminent` are different style types, so a ternary cannot
/// pick one. Watch Credits is the case that makes Skip prominent.
private struct SkipGlassProminence: ViewModifier {
  var prominent: Bool

  func body(content: Content) -> some View {
    if prominent {
      content.buttonStyle(.glassProminent)
    } else {
      content.buttonStyle(.glass)
    }
  }
}
private struct SkipProgressDecoration: ViewModifier {
  let style: SkipAutoStyle
  /// 1 is a full countdown still to run, 0 is the moment it skips.
  let fractionLeft: Double

  func body(content: Content) -> some View {
    content
      .background(alignment: .leading) {
        if style == .fill {
          GeometryReader { geo in
            Color.white.opacity(0.5)
              .frame(width: max(0, geo.size.width * fractionLeft))
          }
        }
      }
      .overlay(alignment: .bottom) {
        if style == .stroke {
          GeometryReader { geo in
            VStack(spacing: 0) {
              Spacer(minLength: 0)
              Color.white
                .frame(width: max(0, geo.size.width * (1 - fractionLeft)), height: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
      }
      .clipShape(Capsule())
      .animation(.linear(duration: 0.25), value: fractionLeft)
  }
}

private struct SkipProgressBar: View {
  let fractionElapsed: Double

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(.white.opacity(0.28))
        Capsule()
          .fill(.white)
          .frame(width: max(0, geo.size.width * min(max(fractionElapsed, 0), 1)))
      }
    }
    .frame(height: 3)
    .accessibilityHidden(true)
    .animation(.linear(duration: 0.25), value: fractionElapsed)
  }
}

struct SkipAheadContent: Equatable {
  var title: String
  var artworkURL: URL?
}

extension PlayerManager {

  /// What an automatic skip is heading toward: the next episode when the credits
  /// close this one, otherwise the film still playing (the part after the intro).
  func skipAheadContent() -> SkipAheadContent {
    let series = AppContext.shared.localProgressStore.snapshot(for: playItem.metadata.id)
    if skipOffer?.kind == .credits,
       case .playNext(let next) = PlaybackEnd.action(playing: playItem,
                                                    series: series,
                                                    policy: PlaybackPreferences.policy) {
      let title = EpisodeText(season: next.seasonNumber, number: next.number, name: next.title)
        .text(for: .continueWatchingCard)
      let still = next.thumbnail.isEmpty ? nil : URL(string: next.thumbnail)
      return SkipAheadContent(title: title, artworkURL: still ?? series?.skipPosterURL)
    }
    let title = displayTitle ?? PlaybackSkip.title
    if let episode = playItem as? Episode, !episode.thumbnail.isEmpty, let url = URL(string: episode.thumbnail) {
      return SkipAheadContent(title: title, artworkURL: url)
    }
    let poster = (playItem as? MediaItem)?.skipPosterURL ?? series?.skipPosterURL
    return SkipAheadContent(title: title, artworkURL: poster)
  }
}

private extension MediaItem {
  var skipPosterURL: URL? {
    guard let raw = posters.wideURL, !raw.isEmpty else { return nil }
    return URL(string: raw)
  }
}

/// Full-bleed still drawn behind the shrunk player.
struct SkipArtworkFill: View {
  let url: URL?

  var body: some View {
    CachedRemoteImage(url: url, contentMode: .fill) {
      Color.black
    } failure: {
      Color.black
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
  }
}

#endif
