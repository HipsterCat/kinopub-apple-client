//
//  ViewerStateReader.swift
//  KinoPubAppleClient
//
//  The one read of what the viewer has done with a thing. The stores keep owning their
//  pieces; this gathers them into a `ViewerOverlay` and lets `ViewerState.overlaid` apply
//  the rules. A surface asks here — it does not read four stores.
//

import Foundation
import KinoPubBackend
import KinoPubMedia

protocol ViewerStateReading {
  /// `reported` is what the payload in hand says (`ViewerState(reportedBy:)`), or
  /// `.unknown` when there is none.
  func state(for ref: MediaRef, reported: ViewerState) -> ViewerState
}

protocol ViewerStateProvider {
  var viewerState: ViewerStateReading { get }
}

final class ViewerStateReader: ViewerStateReading {

  private let library: MediaLibraryStore
  private let progress: LocalWatchProgressStore
  private let bookmarks: BookmarkMembershipStore

  init(library: MediaLibraryStore,
       progress: LocalWatchProgressStore,
       bookmarks: BookmarkMembershipStore = .shared) {
    self.library = library
    self.progress = progress
    self.bookmarks = bookmarks
  }

  func state(for ref: MediaRef, reported: ViewerState) -> ViewerState {
    reported.overlaid(overlay(for: ref))
  }

  /// Title-level facts — follow, folders, vote — are the title's whatever `ref` is: an
  /// episode is followed when its series is.
  func overlay(for ref: MediaRef) -> ViewerOverlay {
    let watch = ref.watchRef
    let record = progress.records(forItem: ref.itemID).first {
      WatchRecord.key(itemID: $0.itemID, season: $0.season, episode: $0.episode)
        == WatchRecord.key(itemID: watch.itemID, season: watch.season, episode: watch.number)
    }
    return ViewerOverlay(
      progress: record?.watch,
      progressUpdatedAt: record?.updatedAt,
      isWatched: library.watched(watch),
      isFollowing: library.inWatchlist(itemId: ref.itemID),
      bookmarkFolderIDs: bookmarks.knownFolderIDs(for: ref.itemID),
      download: download(for: ref),
      vote: library.userVote(itemId: ref.itemID).map { $0 ? ViewerState.Vote.up : .down })
  }

  /// A series, or one of its seasons, from its episodes — the ring for watched and for
  /// downloaded (`ViewerState.aggregating`). `season` nil: every season.
  func state(forSeries item: MediaItem, season: Int? = nil) -> ViewerState {
    let episodes = (item.seasons ?? [])
      .filter { season == nil || $0.number == season }
      .flatMap { block in
        block.episodes.map { episode in
          state(for: .episode(item.id, season: block.number, number: episode.number),
                reported: ViewerState(reportedBy: episode))
        }
      }
    return state(for: item.titleRef, reported: ViewerState(reportedBy: item))
      .aggregating(episodes: episodes)
  }

  /// A file is one episode or one version. TODO(decision): what "downloaded" means for a
  /// whole title — a film's only version, every episode of a series, any of them? Until
  /// decided a title ref reports nothing and the payload's (none) stands.
  private func download(for ref: MediaRef) -> ViewerState.Download? {
    guard ref.kind != .title else { return nil }
    return library.downloadStatus(itemId: ref.itemID, video: ref.number, season: ref.season)
  }
}

/// Answers from fixed values — previews and tests.
final class ViewerStateReaderMock: ViewerStateReading {
  var overlays: [MediaRef: ViewerOverlay] = [:]

  func state(for ref: MediaRef, reported: ViewerState) -> ViewerState {
    reported.overlaid(overlays[ref] ?? ViewerOverlay())
  }
}
