//
//  PlayerTimeObserver.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 13.11.2023.
//

import Foundation
import AVFoundation

/// Calls back on the main actor every `period` seconds of playback.
///
/// On the main queue: AVFoundation asks for a serial one ("passing a concurrent queue to
/// this method will result in undefined behavior" — `AVPlayer.h`), and what the tick reads
/// — the player, its item, the pick state — is the main actor's.
@MainActor
final class PlayerTimeObserver {
  private weak var player: AVPlayer?
  private var timeObserverToken: Any?

  init(player: AVPlayer, period: TimeInterval, timeUpdateHandler: @escaping @MainActor (TimeInterval) -> Void) {
    self.player = player
    let interval = CMTime(seconds: period, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
      // Fire from the first period onwards — callers decide how often to hit the network.
      // (Previously gated at >60s, which delayed both local resume and server marktime.)
      let seconds = time.seconds
      guard seconds.isFinite, seconds > 0 else { return }
      MainActor.assumeIsolated { timeUpdateHandler(seconds) }
    }
  }

  isolated deinit {
    if let timeObserverToken, let player {
      player.removeTimeObserver(timeObserverToken)
    }
  }
}
