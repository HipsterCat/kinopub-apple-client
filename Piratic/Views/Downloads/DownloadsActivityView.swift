//
//  DownloadsActivityView.swift
//  Piratic
//
//  The Mac's view of downloads in flight, as the Apple TV app on the Mac has it
//  (Sasha, 2026-11-16): Window › Activity (⌥⌘L) — a «Downloads» list with a ring and a
//  pause button per row, Simultaneous Downloads and Pause Downloads at the foot — and the
//  download button at the top of the sidebar, which shows the same list in a popover.
//  macOS has no Dynamic Island or ongoing notification for this; these are its places.
//

#if os(macOS)
import SwiftUI
import PiraticUI

enum ActivityWindow {
  static let id = "activity"
}

/// Window › Activity.
struct DownloadsActivityView: View {
  @ObservedObject var center: DownloadsCenter

  var body: some View {
    VStack(spacing: 0) {
      if center.activities.isEmpty {
        Text("There’s no activity to display")
          .font(.title3)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        DownloadsActivityList(center: center)
      }
      Divider()
      DownloadsActivityFooter(center: center)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    .frame(minWidth: 360, minHeight: 300)
  }
}

/// The «Downloads» section of rows — the window's body and the sidebar popover's.
struct DownloadsActivityList: View {
  @ObservedObject var center: DownloadsCenter

  var body: some View {
    List {
      Section("Downloads") {
        ForEach(center.activities) { activity in
          DownloadActivityRow(activity: activity, center: center)
            .contextMenu { DownloadActivityMenuItems(activity: activity, center: center) }
        }
      }
    }
    .listStyle(.inset)
  }
}

/// Simultaneous Downloads and Pause / Resume Downloads, as the TV app's window ends.
struct DownloadsActivityFooter: View {
  @ObservedObject var center: DownloadsCenter

  var body: some View {
    HStack {
      Toggle("Simultaneous Downloads", isOn: $center.simultaneous)
        .toggleStyle(.checkbox)
      Spacer()
      if center.isAnyActive || !center.hasActivity {
        Button("Pause Downloads") { center.pauseAll() }
          .disabled(!center.isAnyActive)
      } else {
        Button("Resume Downloads") { center.resumeAll() }
      }
    }
  }
}

/// The sidebar's toolbar item: the button while anything is downloading, nothing else.
struct MacSidebarDownloadsItem: View {
  @ObservedObject var center: DownloadsCenter

  var body: some View {
    if center.hasActivity {
      SidebarDownloadsButton(center: center)
    }
  }
}

/// The arrow at the top of the sidebar, beside the window's buttons, as in the TV app:
/// there while something downloads, its ring filling; a click shows what is downloading.
struct SidebarDownloadsButton: View {
  @ObservedObject var center: DownloadsCenter
  @State private var showsPopover = false

  var body: some View {
    Button {
      showsPopover.toggle()
    } label: {
      ZStack {
        CircularProgressRing(progress: center.overallProgress, lineWidth: 1.6,
                             color: .accentColor, track: .secondary.opacity(0.45))
        Image(systemName: "arrow.down")
          .font(.system(size: 9, weight: .bold))
      }
      .frame(width: 18, height: 18)
    }
    .help("Downloads")
    .accessibilityLabel(Text("Downloads"))
    .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
      VStack(spacing: 0) {
        DownloadsActivityList(center: center)
        Divider()
        DownloadsActivityFooter(center: center)
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
      }
      .frame(width: 360, height: 320)
    }
  }
}

#endif
