//
//  DownloadsView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 22.07.2023.
//
//  The Library's «Downloaded»: what is downloading now, then what is on disk — both
//  engines, through `DownloadsCenter`. It used to read the mp4 manager only, so on an
//  iPhone (where films download as HLS) nothing ever appeared here.
//

import SwiftUI
import KinoPubBackend
import KinoPubKit
import KinoPubUI
import KinoPubMedia

struct DownloadsView: View {

  @Environment(NavigationState.self) var navigationState
  @ObservedObject private var center: DownloadsCenter

  init(center: DownloadsCenter = AppContext.shared.downloadsCenter) {
    self.center = center
  }

  var body: some View {
    RouteStack(tab: .downloads) {
      Group {
        if center.activities.isEmpty && center.downloaded.isEmpty {
          emptyView
        } else {
          list
        }
      }
      .platformNavigationTitle("Downloads")
#if !os(tvOS)
      .toolbar {
        if center.hasActivity {
          ToolbarItem(placement: .primaryAction) {
            DownloadsControlsMenu(center: center)
          }
        }
      }
#endif
      .onAppear { center.reloadDownloaded() }
    }
  }

  private var list: some View {
    List {
      if !center.activities.isEmpty {
        Section("Downloading") {
          ForEach(center.activities) { activity in
            DownloadActivityRow(activity: activity, center: center, showsArtwork: true)
#if !os(tvOS)
              .swipeActions(edge: .trailing) {
                Button(role: .destructive) { center.cancel(activity) } label: {
                  Label("Cancel Download", systemImage: "xmark")
                }
              }
#endif
              .contextMenu { DownloadActivityMenuItems(activity: activity, center: center) }
          }
        }
      }
      if !center.downloaded.isEmpty {
        Section("Downloaded") {
          ForEach(center.downloaded) { title in
            PlayerLink(route: DownloadsRoutes.player(title.meta, token: UUID()), item: title.meta, mode: .media) {
              DownloadedTitleRow(title: title)
            }
#if os(macOS)
            .buttonStyle(.plain)
#endif
#if !os(tvOS)
            .swipeActions(edge: .trailing) {
              Button(role: .destructive) { center.delete(title) } label: {
                Label("Delete Download", systemImage: "trash")
              }
            }
#endif
            .contextMenu {
              Button(role: .destructive) { center.delete(title) } label: {
                Label("Delete Download", systemImage: "trash")
              }
            }
          }
        }
      }
    }
#if os(iOS)
    .listStyle(.insetGrouped)
#elseif os(macOS)
    .listStyle(.inset)
#endif
  }

  /// Downloads is a local-only feature — nothing here can fail to "load", so this
  /// is always an empty state, never an error one.
  private var emptyView: some View {
    UnavailableView(title: "You don't have any downloads yet",
                    systemImage: "arrow.down.circle",
                    message: "Movies and shows you download will appear here.".localized,
                    retryTitle: "Continue Watching",
                    onRetry: {
      navigationState.selectedTab = .home
    })
  }
}

// MARK: - Rows

/// What a download is: the title, and the episode and quality when there are any.
private func downloadHeadline(_ meta: DownloadMeta) -> String {
  meta.localizedTitle
}

private func downloadDetail(_ meta: DownloadMeta) -> String? {
  let parts = [meta.episode, meta.quality].compactMap { $0 }.filter { !$0.isEmpty }
  return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

/// Artwork beside a download row, at the row's own type size.
private struct DownloadArtwork: View {
  let url: String
  @ScaledMetric(relativeTo: .body) private var height: CGFloat = 54

  var body: some View {
    ArtworkImage(url: URL(string: url)) { phase in
      if let image = phase.image {
        image.resizable().aspectRatio(contentMode: .fill)
      } else {
        Color.secondary.opacity(0.15)
      }
    }
    .frame(width: height * 2 / 3, height: height)
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .accessibilityHidden(true)
  }
}

/// One download in flight: title, what it is and how far, and the ring that pauses it —
/// the TV app's Activity row. Used by the Downloads list and the Mac's Activity window.
struct DownloadActivityRow: View {
  let activity: DownloadActivity
  @ObservedObject var center: DownloadsCenter
  var showsArtwork = false

  var body: some View {
    HStack(spacing: 12) {
      if showsArtwork { DownloadArtwork(url: activity.meta.imageUrl) }
      VStack(alignment: .leading, spacing: 2) {
        Text(downloadHeadline(activity.meta))
          .lineLimit(1)
        Text(status)
          .font(.callout)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      DownloadActivityControl(activity: activity, center: center)
    }
    .accessibilityElement(children: .combine)
  }

  private var status: String {
    var parts: [String] = []
    if let detail = downloadDetail(activity.meta) { parts.append(detail) }
    switch activity.phase {
    case .downloading:
      parts.append(activity.progress.formatted(.percent.precision(.fractionLength(0))))
      if activity.totalBytes > 0 {
        parts.append(String(format: "%@ of %@".localized,
                            ByteCountFormatter.string(fromByteCount: activity.bytesWritten, countStyle: .file),
                            ByteCountFormatter.string(fromByteCount: activity.totalBytes, countStyle: .file)))
      }
      if let remaining = activity.remaining, remaining.isFinite, remaining > 0 {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = remaining >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.maximumUnitCount = 2
        if let text = formatter.string(from: remaining) {
          parts.append(String(format: "%@ left".localized, text))
        }
      }
    case .paused:
      parts.append(String(format: "Paused · %@".localized,
                          activity.progress.formatted(.percent.precision(.fractionLength(0)))))
    case .queued:
      parts.append("Waiting".localized)
    case .retrying:
      parts.append("Server is busy, retrying soon".localized)
    case .interrupted:
      parts.append("Interrupted".localized)
    }
    return parts.joined(separator: " · ")
  }
}

/// The ring with pause / continue in it, or Retry for an interrupted download.
struct DownloadActivityControl: View {
  let activity: DownloadActivity
  @ObservedObject var center: DownloadsCenter
  @ScaledMetric(relativeTo: .body) private var size: CGFloat = 26

  var body: some View {
    Button {
      if activity.isActive { center.pause(activity) } else { center.resume(activity) }
    } label: {
      ZStack {
        CircularProgressRing(progress: activity.phase == .interrupted ? 0 : activity.progress,
                             lineWidth: 2, color: .accentColor, track: .secondary.opacity(0.3))
        Image(systemName: glyph)
          .font(.system(size: size * 0.38, weight: .bold))
          .foregroundStyle(.secondary)
      }
      .frame(width: size, height: size)
      .contentShape(Circle())
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(Text(LocalizedStringKey(accessibilityTitle)))
    .help(Text(LocalizedStringKey(accessibilityTitle)))
  }

  private var glyph: String {
    switch activity.phase {
    case .downloading, .retrying: "pause.fill"
    case .paused, .queued: "arrow.down"
    case .interrupted: "arrow.clockwise"
    }
  }

  private var accessibilityTitle: String {
    switch activity.phase {
    case .downloading, .retrying: "Pause Download"
    case .paused, .queued: "Resume Download"
    case .interrupted: "Retry Download"
    }
  }
}

/// A row's context menu: the same actions as the ring, plus cancel.
struct DownloadActivityMenuItems: View {
  let activity: DownloadActivity
  @ObservedObject var center: DownloadsCenter

  var body: some View {
    if activity.isActive {
      Button { center.pause(activity) } label: { Label("Pause Download", systemImage: "pause") }
    } else if activity.phase == .interrupted {
      Button { center.retry(activity) } label: { Label("Retry Download", systemImage: "arrow.clockwise") }
    } else {
      Button { center.resume(activity) } label: { Label("Resume Download", systemImage: "arrow.down") }
    }
    Button(role: .destructive) { center.cancel(activity) } label: {
      Label("Cancel Download", systemImage: "xmark")
    }
  }
}

/// Pause / resume everything and Simultaneous Downloads — the Activity window's footer,
/// as a menu where a page has a toolbar.
struct DownloadsControlsMenu: View {
  @ObservedObject var center: DownloadsCenter

  var body: some View {
    Menu {
      if center.isAnyActive {
        Button { center.pauseAll() } label: { Label("Pause Downloads", systemImage: "pause") }
      } else {
        Button { center.resumeAll() } label: { Label("Resume Downloads", systemImage: "arrow.down") }
      }
      Toggle("Simultaneous Downloads", isOn: $center.simultaneous)
    } label: {
      Label("Download Options", systemImage: "ellipsis")
    }
  }
}

/// A finished download: plays offline on tap.
struct DownloadedTitleRow: View {
  let title: DownloadedTitle
  @State private var size: Int64?

  var body: some View {
    HStack(spacing: 12) {
      DownloadArtwork(url: title.meta.imageUrl)
      VStack(alignment: .leading, spacing: 2) {
        Text(downloadHeadline(title.meta))
          .lineLimit(1)
        Text(detail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .contentShape(Rectangle())
    .task(id: title.id) {
      let url = title.localURL
      size = await Task.detached(priority: .utility) { DownloadedTitle.diskSize(at: url) }.value
    }
  }

  private var detail: String {
    var parts: [String] = []
    if let detail = downloadDetail(title.meta) { parts.append(detail) }
    if let size, size > 0 { parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
    return parts.joined(separator: " · ")
  }
}
