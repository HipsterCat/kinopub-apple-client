//
//  StorageSettingsView.swift
//  KinoPubAppleClient
//
//  What this device is holding, and the clears that only throw away something we
//  can fetch again. The bar is our bytes, split the way the network log's own
//  store screen splits a file: one colour per thing you can point at.
//
//  tvOS Settings does not present this form. The live page is a TVSettingKit
//  split (`TVSettingsCatalog.storagePage`): the same numbers, with the chart in
//  the left column and a Clear on each section. This form is iOS, macOS, and
//  the SwiftUI settings fallback.
//

import Charts
import Darwin
import SwiftUI
import Foundation
import KinoPubBackend
import KinoPubKit
import KinoPubMetadata
import KinoPubUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class StorageSettingsModel: ObservableObject {
  @Published private(set) var footprintBytes: Int64 = 0
  @Published private(set) var freeBytes: Int64 = 0
  @Published private(set) var volumeBytes: Int64 = 0
  @Published private(set) var rowSnapshotBytes: Int64 = 0
  @Published private(set) var recordBytes: Int64 = 0
  @Published private(set) var rowCount = 0
  @Published private(set) var recordCount = 0
  @Published private(set) var artworkGroups: [StorageCount] = []
  @Published private(set) var metadataGroups: [StorageCount] = []
  @Published private(set) var hlsTempBytes: Int64 = 0
  @Published private(set) var urlCacheDiskBytes: Int = 0
  @Published private(set) var urlCacheMemoryBytes: Int = 0
  @Published private(set) var artworkDiskBytes: Int = 0
  @Published private(set) var artworkMemoryBytes: Int = 0
  @Published private(set) var metadataBytes: Int64 = 0
  @Published private(set) var apiResponseBytes: Int64 = 0
  @Published private(set) var log = NetworkDiagnostics.StoreSnapshot(
    created: .distantPast,
    totalBytes: 0,
    blobsBytes: 0,
    blobsDecompressedBytes: 0,
    messageCount: 0,
    requestCount: 0
  )
  @Published private(set) var hasLog = false
  @Published private(set) var searchRecents = 0
  @Published private(set) var downloadsCount = 0
  @Published private(set) var downloadsBytes: Int64 = 0

  private let rowSnapshotStore = RowSnapshotStore()
  /// The titles those rows refer to — one snapshot, so one number and one Clear.
  private let recordDisk = MediaRecordDisk()

  var catalogBytes: Int64 { rowSnapshotBytes + recordBytes }

  /// Disk the bar is made of. Memory is a different number and is not mixed in.
  var diskSegments: [StorageSegment] {
    var segments: [StorageSegment] = [
      StorageSegment(id: "artwork", title: "Pictures", color: .blue, bytes: Int64(artworkDiskBytes)),
      StorageSegment(id: "catalog", title: "Catalog", color: .green, bytes: catalogBytes),
      StorageSegment(id: "metadata", title: "Metadata", color: .orange, bytes: metadataBytes),
      StorageSegment(id: "log", title: "Network log", color: .purple, bytes: log.totalBytes),
    ]
    let other = Int64(urlCacheDiskBytes) + apiResponseBytes + hlsTempBytes
    if other > 0 {
      segments.append(StorageSegment(id: "other", title: "Other", color: .gray, bytes: other))
    }
    if downloadsBytes > 0 {
      segments.append(StorageSegment(id: "downloads", title: "Downloads", color: .teal, bytes: downloadsBytes))
    }
    return segments.filter { $0.bytes > 0 }
  }

  var logSegments: [StorageSegment] {
    [
      StorageSegment(id: "logs", title: "Logs", color: .blue, bytes: log.logsBytes),
      StorageSegment(id: "blobs", title: "Blobs", color: .green, bytes: log.blobsBytes),
    ].filter { $0.bytes > 0 }
  }

  func refresh(appContext: AppContextProtocol) async {
    footprintBytes = ProcessFootprint.bytes
    freeBytes = VolumeSpace.freeBytes
    volumeBytes = VolumeSpace.totalBytes
    let loadedRows = rowSnapshotStore.loadAll()
    let rowBytes = rowSnapshotStore.diskUsage
    let loadedRecords = recordDisk.load()
    let records = recordDisk.diskUsage
    let hls = HLSAudioLabeler.legacyTemporaryDirectorySize
    let urlDisk = URLCache.shared.currentDiskUsage
    let urlMemory = URLCache.shared.currentMemoryUsage
    let artworkMemory = Artwork.memoryBytes
    let recents = SearchHistory.recent.count
    let snapshot = await NetworkDiagnostics.storeSnapshot()
    let (artworkDisk, metadata, api, pictures, answers) = await Task.detached {
      (
        Artwork.diskBytes,
        MetadataCache.diskBytes(),
        ResponseCache.diskBytes(),
        Artwork.sessionGroups(),
        MetadataCache.groups()
      )
    }.value

    rowSnapshotBytes = rowBytes
    recordBytes = records
    rowCount = loadedRows.count
    recordCount = loadedRecords.count
    artworkGroups = pictures.map { StorageCount(id: $0.id, count: $0.count, bytes: $0.bytes) }
    metadataGroups = answers.map { StorageCount(id: $0.id, count: $0.count, bytes: $0.bytes) }
    hlsTempBytes = hls
    urlCacheDiskBytes = urlDisk
    urlCacheMemoryBytes = urlMemory
    artworkDiskBytes = artworkDisk
    artworkMemoryBytes = artworkMemory
    metadataBytes = metadata
    apiResponseBytes = api
    searchRecents = recents
    if let snapshot {
      log = snapshot
      hasLog = true
    } else {
      hasLog = false
    }

    if FeatureFlags.downloadsEnabled {
      let files = appContext.downloadedFilesDatabase.readData() ?? []
      downloadsCount = files.count
      downloadsBytes = files.reduce(into: 0) { total, file in
        let size = try? file.localFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        total += Int64(size ?? 0)
      }
    }
  }

  func clearRowSnapshots() {
    rowSnapshotStore.clear()
    recordDisk.clear()
    rowSnapshotBytes = 0
    recordBytes = 0
    rowCount = 0
    recordCount = 0
  }

  func clearHLSTemp() {
    HLSAudioLabeler.removeLegacyTemporaryFiles()
    hlsTempBytes = 0
  }

  func clearURLCache() {
    URLCache.shared.removeAllCachedResponses()
    urlCacheDiskBytes = 0
    urlCacheMemoryBytes = 0
  }

  func clearAPIResponses() {
    ResponseCache.clearAll()
    apiResponseBytes = 0
  }

  func clearArtworkCache() {
    Artwork.clearCaches()
    artworkDiskBytes = 0
    artworkMemoryBytes = 0
    artworkGroups = []
  }

  func clearMetadata() async {
    await MetadataCache.clearAll()
    metadataBytes = 0
    metadataGroups = []
  }

  func clearNetworkLog() {
    NetworkDiagnostics.clear()
    log = NetworkDiagnostics.StoreSnapshot(
      created: log.created,
      totalBytes: 0,
      blobsBytes: 0,
      blobsDecompressedBytes: 0,
      messageCount: 0,
      requestCount: 0
    )
  }

  func clearSearchRecents() {
    SearchHistory.clear()
    searchRecents = 0
  }

  /// Every cache this screen can throw away. Downloads stay; they are removed
  /// from the Downloads tab.
  func clearEverything() async {
    clearArtworkCache()
    clearRowSnapshots()
    clearHLSTemp()
    clearURLCache()
    clearAPIResponses()
    clearNetworkLog()
    clearSearchRecents()
    await clearMetadata()
  }

  var appLine: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? "KinoPub"
    return "\(name) \(version) (\(build))"
  }

  var deviceLine: String {
#if os(macOS)
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return "Mac (\(version.majorVersion).\(version.minorVersion).\(version.patchVersion))"
#else
    let device = UIDevice.current
    return "\(device.model) (\(device.systemName) \(device.systemVersion))"
#endif
  }
}

enum StorageByteFormat {
  static func string(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}

struct StorageCount: Equatable, Identifiable {
  var id: String
  var count: Int
  var bytes: Int64
}

/// Where the watch library is meant to live. The file stays on this device:
/// the entitlement lists no CloudKit container, and opening the store with
/// `cloudKitDatabase: .automatic` fails, which recreates the file and then
/// falls back to memory. The choice is remembered for a build that has one.
enum LibraryPlace {
  static let defaultsKey = "storage.libraryPlace"
  static let device = "device"
  static let iCloud = "icloud"

  static var raw: String {
    UserDefaults.standard.string(forKey: defaultsKey) ?? device
  }
}

struct StorageSegment: Identifiable {
  var id: String
  var title: LocalizedStringKey
  var color: Color
  var bytes: Int64
}

struct StorageSettingsView: View {
  @Environment(\.appContext) private var appContext
  /// tvOS Settings presents this outside the stack Pulse's console can live in.
  /// When set, Open uses it. Otherwise the log is a push in the current stack.
  var onOpenNetworkLog: (() -> Void)? = nil

  @StateObject private var model = StorageSettingsModel()
  @State private var pendingClear: ClearTarget?

  private enum ClearTarget: Identifiable, Hashable {
    case rowSnapshots
    case hlsTemp
    case urlCache
    case apiResponses
    case artwork
    case metadata
    case networkLog
    case searchRecents

    var id: Self { self }

    var title: LocalizedStringKey {
      switch self {
      case .rowSnapshots: "Clear catalog cache?"
      case .hlsTemp: "Clear HLS temp files?"
      case .urlCache: "Clear URL cache?"
      case .apiResponses: "Clear API responses?"
      case .artwork: "Clear pictures?"
      case .metadata: "Clear metadata cache?"
      case .networkLog: "Clear network log?"
      case .searchRecents: "Clear search recents?"
      }
    }
  }

  var body: some View {
    Form {
      deviceSection
      diskSection
      picturesSection
      catalogSection
      metadataSection
      networkSection
      logSection
      searchSection
      if model.hlsTempBytes > 0 {
        playbackSection
      }
      if FeatureFlags.downloadsEnabled {
        downloadsSection
      }
    }
    #if !os(tvOS)
    .formStyle(.grouped)
    #endif
    .platformNavigationTitle("Storage & Data")
    .task { await model.refresh(appContext: appContext) }
    .confirmationDialog(
      pendingClear?.title ?? "",
      isPresented: Binding(get: { pendingClear != nil }, set: { if !$0 { pendingClear = nil } }),
      presenting: pendingClear
    ) { target in
      Button("Clear", role: .destructive) {
        Task { await perform(target) }
        pendingClear = nil
      }
      Button("Cancel", role: .cancel) {}
    } message: { target in
      Text(target == .searchRecents
           ? "Recent searches on this device are removed."
           : "This only affects local caches — nothing on your account changes.")
    }
  }

  private var deviceSection: some View {
    Section {
      LabeledContent("App memory", value: formatted(model.footprintBytes))
      LabeledContent("Pictures in memory", value: formatted(Int64(model.artworkMemoryBytes)))
      LabeledContent("Free space", value: formatted(model.freeBytes))
      LabeledContent("App", value: model.appLine)
      LabeledContent("Device", value: model.deviceLine)
    } header: {
      Text("This device")
    } footer: {
      Text("App memory is what the process is using right now. Pictures in memory are the decoded posters and stills. Free space is the disk.")
    }
  }

  private var diskSection: some View {
    Section {
      StorageUsageBar(segments: model.diskSegments)
        .hideStorageRowSeparator()
      ForEach(model.diskSegments) { segment in
        LabeledContent(segment.title, value: formatted(segment.bytes))
      }
    } header: {
      Text("On disk")
    }
  }

  private var picturesSection: some View {
    Section {
      LabeledContent("Disk", value: formatted(Int64(model.artworkDiskBytes)))
      LabeledContent("Memory", value: formatted(Int64(model.artworkMemoryBytes)))
      Button("Clear pictures", role: .destructive) { pendingClear = .artwork }
        .disabled(model.artworkDiskBytes == 0 && model.artworkMemoryBytes == 0)
    } header: {
      Text("Pictures")
    } footer: {
      Text("Posters, stills and logos. Disk holds each image once; memory holds them decoded at the sizes on screen. Clearing means the next loads re-download.")
    }
  }

  private var catalogSection: some View {
    Section {
      LabeledContent("Home & Library", value: formatted(model.catalogBytes))
      Button("Clear catalog cache", role: .destructive) { pendingClear = .rowSnapshots }
        .disabled(model.catalogBytes == 0)
    } header: {
      Text("Catalog")
    } footer: {
      Text("Cached rows paint Home and Library instantly on a cold start. Clearing forces the next launch to refetch from the network.")
    }
  }

  private var metadataSection: some View {
    Section {
      LabeledContent("TMDB & Kinopoisk", value: formatted(model.metadataBytes))
      Button("Clear metadata cache", role: .destructive) { pendingClear = .metadata }
        .disabled(model.metadataBytes == 0)
    } header: {
      Text("Metadata")
    } footer: {
      Text("Facts, cast and stills fetched for title pages. They load again the next time a title opens.")
    }
  }

  private var networkSection: some View {
    Section {
      LabeledContent("URL cache, disk", value: formatted(Int64(model.urlCacheDiskBytes)))
      LabeledContent("URL cache, memory", value: formatted(Int64(model.urlCacheMemoryBytes)))
      Button("Clear URL cache", role: .destructive) { pendingClear = .urlCache }
        .disabled(model.urlCacheDiskBytes == 0 && model.urlCacheMemoryBytes == 0)
      LabeledContent("API responses", value: formatted(model.apiResponseBytes))
      Button("Clear API responses", role: .destructive) { pendingClear = .apiResponses }
        .disabled(model.apiResponseBytes == 0)
    } header: {
      Text("Network cache")
    } footer: {
      Text("URL cache is the system's. API responses are genres and countries. Pictures are not in either.")
    }
  }

  private var logSection: some View {
    Section {
      StorageUsageBar(segments: model.logSegments)
        .hideStorageRowSeparator()
      LabeledContent("Logs", value: formatted(model.log.logsBytes))
      LabeledContent("Blobs", value: formatted(model.log.blobsBytes))
      LabeledContent("Blobs decompressed", value: formatted(model.log.blobsDecompressedBytes))
      LabeledContent("Requests", value: "\(model.log.requestCount)")
      LabeledContent("Messages", value: "\(model.log.messageCount)")
      if model.hasLog {
        LabeledContent("Created", value: model.log.created.formatted(date: .abbreviated, time: .standard))
      }
      openLogControl
      Button("Clear network log", role: .destructive) { pendingClear = .networkLog }
        .disabled(model.log.totalBytes == 0)
    } header: {
      Text("Network log")
    } footer: {
      Text("Requests with headers, body and timing. Pictures and video are not recorded. Bodies are capped, and the store drops the oldest entries past 32 MB.")
    }
  }

  @ViewBuilder
  private var openLogControl: some View {
    if let onOpenNetworkLog {
      Button("Open network log", action: onOpenNetworkLog)
    } else {
      NavigationLink("Open network log") {
        NetworkConsoleView()
          .navigationTitle("Network log")
      }
    }
  }

  private var searchSection: some View {
    Section {
      LabeledContent("Recent searches", value: "\(model.searchRecents)")
      Button("Clear search recents", role: .destructive) { pendingClear = .searchRecents }
        .disabled(model.searchRecents == 0)
    } header: {
      Text("Search")
    }
  }

  private var playbackSection: some View {
    Section {
      LabeledContent("HLS temp files", value: formatted(model.hlsTempBytes))
      Button("Clear HLS temp files", role: .destructive) { pendingClear = .hlsTemp }
    } header: {
      Text("Playback")
    } footer: {
      Text("Scratch files from relabeling audio tracks in older builds. These are already swept on every launch.")
    }
  }

  private var downloadsSection: some View {
    Section {
      LabeledContent("Downloaded files", value: "\(model.downloadsCount)")
      LabeledContent("Downloads size", value: formatted(model.downloadsBytes))
    } header: {
      Text("Downloads")
    } footer: {
      Text("Manage individual downloads from the Downloads tab — remove titles you're done with from there.")
    }
  }

  private func perform(_ target: ClearTarget) async {
    switch target {
    case .rowSnapshots: model.clearRowSnapshots()
    case .hlsTemp: model.clearHLSTemp()
    case .urlCache: model.clearURLCache()
    case .apiResponses: model.clearAPIResponses()
    case .artwork: model.clearArtworkCache()
    case .metadata: await model.clearMetadata()
    case .networkLog: model.clearNetworkLog()
    case .searchRecents: model.clearSearchRecents()
    }
  }

  private func formatted(_ bytes: Int64) -> String {
    StorageByteFormat.string(bytes)
  }
}

private struct StorageUsageBar: View {
  let segments: [StorageSegment]

  var body: some View {
    let total = segments.reduce(Int64(0)) { $0 + $1.bytes }
    VStack(alignment: .leading, spacing: 8) {
      Color.clear
        .frame(height: 14)
        .overlay {
          GeometryReader { geo in
            HStack(spacing: 3) {
              if total == 0 {
                Color.secondary.opacity(0.25)
              } else {
                ForEach(segments) { segment in
                  segment.color
                    .frame(width: width(of: segment, total: total, available: geo.size.width))
                }
              }
            }
          }
        }
        .clipShape(Capsule())

      ViewThatFits(in: .horizontal) {
        legend
        VStack(alignment: .leading, spacing: 4) { legend }
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }

  private var legend: some View {
    HStack(spacing: 12) {
      ForEach(segments) { segment in
        HStack(spacing: 6) {
          Circle().fill(segment.color).frame(width: 8, height: 8)
          Text(segment.title)
        }
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  /// A slice keeps a few points so a small cache is still visible. The last slice
  /// takes whatever is left, so the gaps between slices don't push the bar past the row.
  private func width(of segment: StorageSegment, total: Int64, available: CGFloat) -> CGFloat {
    let gaps = CGFloat(max(0, segments.count - 1)) * 3
    let usable = max(0, available - gaps)
    let share = usable * CGFloat(segment.bytes) / CGFloat(total)
    let minimum: CGFloat = segments.count > 1 ? 6 : 0
    guard segment.id == segments.last?.id else { return max(minimum, share) }
    let others = segments.dropLast().reduce(CGFloat(0)) { partial, earlier in
      partial + max(minimum, usable * CGFloat(earlier.bytes) / CGFloat(total))
    }
    return max(minimum, usable - others)
  }
}

private enum ProcessFootprint {
  static var bytes: Int64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return 0 }
    return Int64(info.phys_footprint)
  }
}

private enum VolumeSpace {
  static var freeBytes: Int64 {
    let values = try? URL.cachesDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
    return Int64(values?.volumeAvailableCapacity ?? 0)
  }

  static var totalBytes: Int64 {
    let values = try? URL.cachesDirectory.resourceValues(forKeys: [.volumeTotalCapacityKey])
    return Int64(values?.volumeTotalCapacity ?? 0)
  }
}

private extension View {
  @ViewBuilder
  func hideStorageRowSeparator() -> some View {
#if os(tvOS)
    self
#else
    listRowSeparator(.hidden)
#endif
  }
}

#if os(tvOS)
/// Swift Charts donut. Each slice carries its share, the hole carries a size.
/// Focusing a row isolates that slice and the hole shows its size; otherwise
/// the hole is the total. The bar under it is the budget: what is held now,
/// the cap (a store's own limit, or the disk), and free space.
struct StorageChartSlice: Identifiable, Equatable {
  var id: String
  var title: String
  var color: Color
  var bytes: Int64
}

struct StorageCapacity: Equatable {
  var used: Int64 = 0
  /// A store cap when `capped`, otherwise the volume the cache sits on.
  var limit: Int64 = 1
  var free: Int64 = 0
  var capped = false

  var statusKey: String {
    if capped { return used >= limit ? "At the limit" : "Within the limit" }
    return free < 1_000_000_000 ? "At the limit" : "Within disk space"
  }
}

@MainActor
final class StorageChartModel: ObservableObject {
  @Published var slices: [StorageChartSlice] = []
  @Published var highlightedID: String?
  @Published var capacity = StorageCapacity()

  func apply(slices: [StorageChartSlice], highlightedID: String?, capacity: StorageCapacity) {
    if self.slices != slices { self.slices = slices }
    if self.highlightedID != highlightedID { self.highlightedID = highlightedID }
    if self.capacity != capacity { self.capacity = capacity }
  }
}

struct StorageDonutChart: View {
  @ObservedObject var model: StorageChartModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var drawn: [StorageChartSlice] { model.slices.filter { $0.bytes > 0 } }

  private var total: Int64 { drawn.reduce(0) { $0 + $1.bytes } }

  private var isolating: StorageChartSlice? {
    drawn.first { $0.id == model.highlightedID }
  }

  private var center: String {
    StorageByteFormat.string(isolating?.bytes ?? total)
  }

  var body: some View {
    VStack(spacing: 28) {
      chart
        .frame(width: 660, height: 620)
      capacityBar
        .frame(width: 660)
    }
  }

  private var chart: some View {
    let slices = drawn
    return Group {
      if slices.isEmpty {
        Chart {
          SectorMark(angle: .value("Bytes", 1), innerRadius: .ratio(0.62), angularInset: 2)
            .foregroundStyle(Color.secondary.opacity(0.35))
        }
        .chartLegend(.hidden)
        .chartBackground { proxy in centerLabel(in: proxy) }
      } else {
        Chart(slices) { slice in
          let hot = isolating == nil || slice.id == isolating?.id
          let pulled = isolating?.id == slice.id
          SectorMark(
            angle: .value("Bytes", slice.bytes),
            innerRadius: .ratio(0.62),
            outerRadius: .ratio(pulled || isolating == nil ? 1 : 0.9),
            angularInset: pulled ? 6 : 1.5
          )
          .foregroundStyle(slice.color)
          .opacity(hot ? 1 : 0.35)
          .cornerRadius(8)
          .annotation(position: .overlay) {
            percentLabel(for: slice)
          }
        }
        .chartLegend(.hidden)
        .chartBackground { proxy in centerLabel(in: proxy) }
      }
    }
    .animation(reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.28), value: model.highlightedID)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(isolating.map { "\($0.title), \(center)" } ?? center)
  }

  private func centerLabel(in proxy: ChartProxy) -> some View {
    GeometryReader { geo in
      if let anchor = proxy.plotFrame {
        let frame = geo[anchor]
        Text(center)
          .font(.title)
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.4)
          .frame(width: frame.width * 0.42)
          .position(x: frame.midX, y: frame.midY)
      }
    }
  }

  @ViewBuilder
  private func percentLabel(for slice: StorageChartSlice) -> some View {
    let fraction = total > 0 ? Double(slice.bytes) / Double(total) : 0
    if fraction >= 0.07 {
      Text(Self.percent(fraction))
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.45), radius: 3)
    }
  }

  private static func percent(_ fraction: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .percent
    formatter.maximumFractionDigits = fraction < 0.1 ? 1 : 0
    formatter.minimumFractionDigits = 0
    return formatter.string(from: NSNumber(value: fraction)) ?? ""
  }

  private var capacityBar: some View {
    let cap = model.capacity
    let span = Double(max(cap.limit, cap.used, 1))
    let tint = isolating?.color ?? Color.primary
    return VStack(alignment: .leading, spacing: 12) {
      ProgressView(value: Double(max(cap.used, 0)), total: span)
        .tint(tint)
      HStack {
        Text(StorageByteFormat.string(cap.used))
        Spacer(minLength: 12)
        Text("\("Limit".localized) \(StorageByteFormat.string(cap.limit))")
        Spacer(minLength: 12)
        Text("\("Free space".localized) \(StorageByteFormat.string(cap.free))")
      }
      .font(.callout)
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      Text(cap.statusKey.localized)
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(StorageByteFormat.string(cap.used)), \(cap.statusKey.localized), \("Limit".localized) \(StorageByteFormat.string(cap.limit)), \("Free space".localized) \(StorageByteFormat.string(cap.free))"
    )
  }
}

@MainActor
final class StorageChartController: UIHostingController<StorageDonutChart> {
  let model: StorageChartModel

  init() {
    let model = StorageChartModel()
    self.model = model
    super.init(rootView: StorageDonutChart(model: model))
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = false
    view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      view.widthAnchor.constraint(equalToConstant: 700),
      view.heightAnchor.constraint(equalToConstant: 780),
    ])
  }

  @MainActor required dynamic init?(coder: NSCoder) { nil }
}

#endif

#Preview {
  NavigationStack {
    StorageSettingsView()
  }
}
