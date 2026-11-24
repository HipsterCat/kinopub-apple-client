//
//  TrackMemorySections.swift
//  KinoPubAppleClient
//
//  What the app has learned about audio and subtitles, shown to everyone.
//
//  Deliberately not behind a debug flag: a preference that steers playback without ever
//  being visible is one the viewer cannot correct. The grouping is the same one the
//  resolver reads in — series, then season, then episode — so what is on screen explains
//  what actually happens.
//

import SwiftUI
import KinoPubBackend
import KinoPubMedia

#if !os(tvOS)
struct TrackMemorySections: View {

  let store: TrackPreferenceStore

  @Environment(\.appContext) private var appContext
  @State private var sections: [TrackPreferenceDigest.Section] = []
  @State private var showsResetAlert = false

  /// Enough to recognise what the app is doing without turning Settings into a database
  /// browser. The rest is still remembered; it is just not worth a screen.
  private static let maxSections = 12
  private static let maxEntriesPerScope = 3

  var body: some View {
    Group {
      if sections.isEmpty {
        Section {
          Text("Nothing remembered yet. Pick a dub or a subtitle track in the player and it will show up here.")
            .foregroundStyle(.secondary)
        } header: {
          Text("Remembered tracks")
        }
      } else {
        ForEach(Array(sections.prefix(Self.maxSections)), id: \.titleID) { section in
          Section {
            // One ForEach over the whole section: a grouped Form flattens nested ForEach
            // rows into one list of cells, so per-group offsets (0, 1, 2 for audio, again
            // for subtitles, again for the next scope) collided — «the ID 0 occurs
            // multiple times within the collection» on the Mac (Sasha's log 2026-11-24).
            ForEach(rows(for: section)) { row in
              LabeledContent {
                Text(row.detail)
              } label: {
                Text(row.label)
              }
            }
          } header: {
            Text(title(for: section))
          }
        }

        Section {
          Button("Forget remembered tracks", role: .destructive) {
            showsResetAlert = true
          }
        } footer: {
          if sections.count > Self.maxSections {
            Text("\(sections.count - Self.maxSections) more titles are remembered and not listed.")
          }
        }
      }
    }
    .onAppear(perform: reload)
    // Same key as the button above: Xcode's generated string symbols strip
    // punctuation, so "…tracks" and "…tracks?" collided on one symbol name.
    .alert("Forget remembered tracks", isPresented: $showsResetAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Forget", role: .destructive) {
        store.forgetEverything()
        reload()
      }
    } message: {
      Text("Playback goes back to the defaults above until new choices are made.")
    }
  }

  /// A Settings row, identified by where it comes from — scope, track kind and rank —
  /// which is unique across the section and stays put when the weights change.
  private struct Row: Identifiable {
    struct ID: Hashable {
      enum Kind: Hashable { case audio, subtitles }
      let scope: TrackMemoryScope
      let kind: Kind
      let rank: Int
    }

    let id: ID
    let label: String
    let detail: String
  }

  private func rows(for section: TrackPreferenceDigest.Section) -> [Row] {
    section.groups.flatMap { group -> [Row] in
      let scope = scopeLabel(for: group.scope)
      let audio = group.audio.prefix(Self.maxEntriesPerScope).enumerated().map { rank, entry in
        Row(id: .init(scope: group.scope, kind: .audio, rank: rank),
            label: entry.isLeader ? scope : "",
            detail: detail(entry))
      }
      let subtitles = group.subtitles.prefix(Self.maxEntriesPerScope).enumerated().map { rank, entry in
        Row(id: .init(scope: group.scope, kind: .subtitles, rank: rank),
            label: entry.isLeader ? "\(scope) · \("Subtitles".localized)" : "",
            detail: detail(entry))
      }
      return audio + subtitles
    }
  }

  /// The weight is the honest part: it is what decides ties, so showing it explains why
  /// one dub wins over another.
  private func detail(_ entry: TrackPreferenceDigest.Entry) -> String {
    "\(entry.label) · \(entry.weight)"
  }

  private func scopeLabel(for scope: TrackMemoryScope) -> String {
    scope.displayLabel
  }

  /// The title's own name when the app has seen it this session, and its id when it has
  /// not — inventing a name for a row that steers playback would be worse than a number.
  private func title(for section: TrackPreferenceDigest.Section) -> String {
    guard let titleID = section.titleID else { return "Anime".localized }
    if let snapshot = appContext.localProgressStore.snapshot(for: titleID) {
      return snapshot.localizedTitle
    }
    return "#\(titleID)"
  }

  private func reload() {
    sections = TrackPreferenceDigest.sections(from: store.storedScopes)
  }
}
#endif

extension TrackMemoryScope {
  /// How a remembered scope reads in Settings — one wording for every settings screen.
  /// Episodes and seasons through the media text vocabulary («S2, E5», «2 сезон, 5 серия»).
  var displayLabel: String {
    switch self {
    case .title:
      return "Whole title".localized
    case let .season(_, season):
      return SeasonText(season).formatted(MediaSurface.settingsRow.textLength)
    case let .episode(_, season, episode):
      return EpisodeText(season: season, number: episode).text(for: .settingsRow)
    case let .contentClass(name):
      return name.capitalized
    }
  }
}
