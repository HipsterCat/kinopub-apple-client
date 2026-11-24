//
//  TrackPreferenceStore.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend
import Synchronization

/// **Owns what every scope has learned about dubs and subtitles.** One store, keyed by
/// `TrackMemoryScope.storageKey`; `TrackResolver` reads it and never writes.
///
/// This is the fifth thing that persists per item, and deliberately not part of
/// `MediaLibraryStore`: that one owns optimistic library state the server also knows
/// about (watchlist, watched, votes), and this is local-only knowledge the server has
/// no concept of.
///
/// Rules: docs/product/playback-tracks.md
final class TrackPreferenceStore: Sendable {

  static let shared = TrackPreferenceStore()

  private static let storageKey = "trackPreferenceLedgers.v1"

  private let suite: DefaultsSuite

  private struct State {
    var ledgers: [String: TrackPreferenceLedger]
    var revision = 0
  }

  private let state: Mutex<State>

  /// Bumped on every write. A cached `PlaybackPlan` was decided from this history, so a
  /// change here is what makes it stale — cheaper and more honest than a time-based cache,
  /// which would go stale exactly when the viewer switched dub and expected it to stick.
  var revision: Int { state.withLock { $0.revision } }

  init(defaults suite: DefaultsSuite = .standard) {
    self.suite = suite
    state = Mutex(State(ledgers: Self.load(from: suite.defaults)))
    migrateLegacySubtitleChoicesIfNeeded()
  }

  // MARK: - Reading

  /// One entry per step of the chain, empty where nothing was learned, so the resolver
  /// walks the same shape every time.
  func ledgers(for chain: [TrackMemoryScope]) -> [ScopedLedger] {
    let ledgers = all
    return chain.map { scope in
      ScopedLedger(scope: scope, ledger: ledgers[scope.storageKey] ?? TrackPreferenceLedger())
    }
  }

  func ledger(for scope: TrackMemoryScope) -> TrackPreferenceLedger? {
    state.withLock { $0.ledgers[scope.storageKey] }
  }

  /// Everything stored, keyed by its raw storage key.
  var all: [String: TrackPreferenceLedger] {
    state.withLock { $0.ledgers }
  }

  /// Everything stored, back as scopes — what Settings shows the viewer. A key that no
  /// longer parses is skipped rather than guessed at; it belongs to a scope shape this
  /// build does not have.
  var storedScopes: [TrackMemoryScope: TrackPreferenceLedger] {
    var parsed: [TrackMemoryScope: TrackPreferenceLedger] = [:]
    for (key, ledger) in all {
      guard let scope = TrackMemoryScope(storageKey: key) else { continue }
      parsed[scope] = ledger
    }
    return parsed
  }

  // MARK: - Writing

  /// What this episode offered. Recorded whether or not anything was chosen — "seen" is
  /// about the menu, and it is what lets a dub that arrives later be told apart from one
  /// the viewer has been declining all along.
  func noteMenu(_ tracks: [AudioTrackInfo], in chain: [TrackMemoryScope]) {
    guard !tracks.isEmpty else { return }
    mutate(chain) { $0.noteMenu(tracks) }
  }

  /// One play, worth one unit of weight in every scope that applies — once the episode has
  /// been watched far enough to count. `picked` is the viewer choosing it in the player's
  /// menu: recorded the moment it happens, and from then on what every scope opens with
  /// until they pick something else.
  func recordAudio(_ signature: AudioTrackSignature,
                   in chain: [TrackMemoryScope],
                   picked: Bool = false,
                   at date: Date = Date()) {
    mutate(chain) { $0.recordAudio(signature, at: date, picked: picked) }
  }

  func recordSubtitle(_ signature: SubtitleChoiceSignature,
                      in chain: [TrackMemoryScope],
                      picked: Bool = false,
                      at date: Date = Date()) {
    mutate(chain) { $0.recordSubtitle(signature, at: date, picked: picked) }
  }

  func forget(scope: TrackMemoryScope) {
    update { $0.removeValue(forKey: scope.storageKey) }
  }

  func forgetEverything() {
    update { $0 = [:] }
  }

  // MARK: - Private

  private func mutate(_ chain: [TrackMemoryScope],
                      _ body: (inout TrackPreferenceLedger) -> Void) {
    guard !chain.isEmpty else { return }
    update { ledgers in
      for scope in chain {
        body(&ledgers[scope.storageKey, default: TrackPreferenceLedger()])
      }
    }
  }

  /// One change, persisted before the lock is let go: the disk sees them in order.
  private func update(_ change: (inout [String: TrackPreferenceLedger]) -> Void) {
    state.withLock { state in
      change(&state.ledgers)
      state.revision &+= 1
      guard let data = try? JSONEncoder().encode(state.ledgers) else { return }
      suite.defaults.set(data, forKey: Self.storageKey)
    }
  }

  private static func load(from defaults: UserDefaults) -> [String: TrackPreferenceLedger] {
    guard let data = defaults.data(forKey: storageKey),
          let stored = try? JSONDecoder().decode([String: TrackPreferenceLedger].self, from: data)
    else { return [:] }
    return stored
  }

  /// `SubtitleTrackMemory` stored a real language code, so it converts cleanly and is
  /// worth keeping. The old audio memory stored a **rendition display name**, which is
  /// exactly the handle this design replaced — reversing a localized label back into a
  /// language code guesses, so those choices are dropped and re-learned on the next pick.
  private func migrateLegacySubtitleChoicesIfNeeded() {
    let defaults = suite.defaults
    let legacyKey = "subtitleTrackChoices"
    guard let data = defaults.data(forKey: legacyKey),
          let choices = try? JSONDecoder().decode([String: SubtitleChoice].self, from: data)
    else { return }

    let migratedAt = Date()
    update { ledgers in
      for (rawID, choice) in choices {
        guard let itemID = Int(rawID) else { continue }
        let scope = TrackMemoryScope.title(id: itemID)
        guard ledgers[scope.storageKey] == nil else { continue }
        let signature: SubtitleChoiceSignature
        if let primary = choice.primary {
          signature = SubtitleChoiceSignature(languageKey: primary.lang, isCC: primary.isCC)
        } else if choice.isEmpty {
          signature = .off
        } else {
          continue
        }
        var ledger = TrackPreferenceLedger()
        // They were made in the old picker, so they are picks.
        ledger.recordSubtitle(signature, at: migratedAt, picked: true)
        ledgers[scope.storageKey] = ledger
      }
    }
    defaults.removeObject(forKey: legacyKey)
  }
}
