//
//  TitleImagePickerSheet.swift
//  KinoPubAppleClient
//
//  "Change Images": which TMDB logo and backdrop the worker serves for a title.
//  The sheet, grid and toolbar policy are AniShelf's poster picker
//  (`PosterSelectionView` / `PosterGridView`, github.com/samuelhe52/AniShelf); the
//  per-language selection and the worker writes are ours.
//

import SwiftUI
import KinoPubUI
import KinoPubMetadata

/// The title a picker is opened for. A card knows no IMDb id; the worker then finds the
/// title from what it stored when the title was first opened.
struct TitleImagePickerTarget: Identifiable, Hashable {
  let kinopubID: Int
  let imdb: Int?
  let title: String

  var id: Int { kinopubID }
}

/// Opens on a Logo / Backdrop segment. Logos take one pick per language (ru, en, und), the
/// way the worker stores them; a backdrop is one picture per title in the worker, so its
/// grid takes one pick across all languages. With no pick stored, each language starts on
/// its most-voted file. Save drops what the worker had for that kind and pins exactly
/// what is selected, so no automatic choice is left behind next to a pick.
struct TitleImagePickerSheet: View {
  let target: TitleImagePickerTarget
  let images: TitleImageRoute
  /// After a save: drop the device's copies of this title's pictures.
  let onSaved: () async -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var model: TitleImagePickerModel
  @State private var kind: WorkerImageAdminKind = .logo

  init(target: TitleImagePickerTarget,
       images: TitleImageRoute,
       onSaved: @escaping () async -> Void,
       initialKind: WorkerImageAdminKind = .logo,
       model: TitleImagePickerModel? = nil) {
    self.target = target
    self.images = images
    self.onSaved = onSaved
    _kind = State(initialValue: initialKind)
    _model = State(initialValue: model ?? TitleImagePickerModel(
      target: target,
      client: WorkerImageAdminTokenStore.client(proxyBaseURL: images.baseURL),
      userLanguage: images.language == "en" ? .en : .ru
    ))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: TitleImagePickerMetrics.sectionSpacing) {
#if os(tvOS)
          tvHeader
#endif
          Picker("Image Kind", selection: $kind) {
            Text("Logo").tag(WorkerImageAdminKind.logo)
            Text("Backdrop").tag(WorkerImageAdminKind.backdrop)
          }
          .pickerStyle(.segmented)
          .labelsHidden()

          content
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, TitleImagePickerMetrics.horizontalPadding)
#if os(macOS)
        // iOS gets this gap from the navigation bar; the Mac sheet ends flush with it.
        .padding(.vertical, 16)
#endif
        .frame(maxWidth: TitleImagePickerMetrics.maxContentWidth)
        .frame(maxWidth: .infinity)
      }
      .animation(.default, value: model.phase(for: kind))
      .navigationTitle(target.title)
      .sheetInlineNavigationTitle()
#if os(iOS)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          closeButton
        }
        ToolbarItem(placement: .sheetTrailing) {
          saveButton
            .buttonStyle(.glassProminent)
        }
      }
#elseif os(macOS)
      // The sheet's own bottom bar showed one toolbar button only — the first
      // `.confirmationAction` item; `.cancellationAction` never appeared (macOS 27.2,
      // 2026-11-05, with or without a role or a group). So Close and Save are the
      // Mac dialog's push buttons, in a bar of their own.
      .safeAreaInset(edge: .bottom, spacing: 0) {
        VStack(spacing: 0) {
          Divider()
          HStack(spacing: 12) {
            Spacer()
            closeButton
              .keyboardShortcut(.cancelAction)
            saveButton
              .keyboardShortcut(.defaultAction)
          }
          .controlSize(.large)
          .padding(16)
        }
        .background(.bar)
      }
#endif
    }
    .task(id: kind) { await model.load(kind) }
#if os(iOS)
    .presentationDragIndicator(.visible)
#endif
    .presentationSizing(.page)
    .macSheetFrame(width: 900, height: 680)
  }

  /// DEBUG `-KINOPUBOpenImagePicker logo|backdrop`: the title page opens this sheet on load.
  static var launchKind: WorkerImageAdminKind? {
#if DEBUG
    UserDefaults.standard.string(forKey: "KINOPUBOpenImagePicker").flatMap(WorkerImageAdminKind.init(rawValue:))
#else
    nil
#endif
  }

  private var closeButton: some View {
    Button {
      dismiss()
    } label: {
      SheetCloseLabel()
    }
  }

  private var saveButton: some View {
    Button {
      Task {
        if await model.save() {
          await onSaved()
          dismiss()
        }
      }
    } label: {
      SheetConfirmLabel("Save Images")
    }
    .disabled(!model.hasChanges || model.isSaving)
  }

#if os(tvOS)
  /// tvOS sheets have no toolbar; Menu closes, and Save sits above the grid.
  private var tvHeader: some View {
    HStack(spacing: 24) {
      Text(target.title)
        .font(.title2)
        .lineLimit(1)
      Spacer()
      saveButton
        .buttonStyle(.bordered)
    }
  }
#endif

  @ViewBuilder
  private var content: some View {
    switch model.phase(for: kind) {
    case .loading:
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    case .failed(let message):
      ContentUnavailableView {
        Label("Couldn't Load Images", systemImage: "exclamationmark.triangle")
      } description: {
        Text(verbatim: message)
      } actions: {
        Button("Try Again") { Task { await model.load(kind, force: true) } }
      }
    case .loaded:
      let sections = model.sections(for: kind)
      if sections.isEmpty {
        ContentUnavailableView(
          "No Images",
          systemImage: "photo.on.rectangle",
          description: Text("TMDB has no images of this kind for this title.")
        )
      } else {
        VStack(alignment: .leading, spacing: TitleImagePickerMetrics.sectionSpacing) {
          if let message = model.saveError {
            Text(verbatim: message)
              .font(.footnote)
              .foregroundStyle(.red)
          }
          ForEach(sections) { section in
            languageSection(section)
          }
        }
      }
    }
  }

  private func languageSection(_ section: TitleImagePickerSection) -> some View {
    VStack(alignment: .leading, spacing: TitleImagePickerMetrics.headerSpacing) {
      HStack(alignment: .firstTextBaseline) {
        Text(section.language.pickerTitle)
          .font(.headline)
        Text(verbatim: "\(section.files.count)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      TitleImageGrid(
        kind: section.kind,
        files: section.files,
        selectedURL: model.selectedURL(kind: section.kind, language: section.language),
        onSelect: { model.select($0, language: section.language, kind: section.kind) }
      )
    }
  }
}

// MARK: - Grid

/// AniShelf's `PosterGridView`: an adaptive grid of the files at their own aspect ratio,
/// a ring and a checkmark outside the clip for the selection, and here the votes and the
/// size underneath.
private struct TitleImageGrid: View {
  let kind: WorkerImageAdminKind
  let files: [WorkerImageAdminCandidate]
  let selectedURL: String?
  let onSelect: (WorkerImageAdminCandidate) -> Void

  var body: some View {
    LazyVGrid(
      columns: [GridItem(
        .adaptive(minimum: TitleImagePickerMetrics.minTileWidth(kind),
                  maximum: TitleImagePickerMetrics.maxTileWidth(kind)),
        spacing: TitleImagePickerMetrics.gridSpacing
      )],
      alignment: .leading,
      spacing: TitleImagePickerMetrics.gridSpacing
    ) {
      ForEach(files) { file in
        Button {
          onSelect(file)
        } label: {
          TitleImageTile(kind: kind, file: file, isSelected: file.url == selectedURL)
        }
#if os(tvOS)
        .buttonStyle(.card)
#else
        .buttonStyle(.plain)
#endif
        .accessibilityAddTraits(file.url == selectedURL ? .isSelected : [])
      }
    }
  }
}

private struct TitleImageTile: View {
  let kind: WorkerImageAdminKind
  let file: WorkerImageAdminCandidate
  let isSelected: Bool

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: TitleImagePickerMetrics.cornerRadius, style: .continuous)
  }

  /// Logos keep their own proportions inside a 16:9 box; backdrops are 16:9 already.
  private var boxAspectRatio: CGFloat { 16 / 9 }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Color.clear
        .aspectRatio(boxAspectRatio, contentMode: .fit)
        .overlay {
          if kind == .logo {
            // Logos are drawn over the hero's forced-dark picture, so they are judged
            // on dark here as well.
            Color(white: 0.16)
              .overlay {
                CachedRemoteImage(url: file.previewURL(kind: kind), contentMode: .fit) {
                  ProgressView()
                } failure: {
                  Image(systemName: "photo").foregroundStyle(.secondary)
                }
                .padding(TitleImagePickerMetrics.logoInset)
              }
          } else {
            CachedRemoteImage(url: file.previewURL(kind: kind), contentMode: .fill) {
              Color.secondary.opacity(0.15)
            } failure: {
              Color.secondary.opacity(0.15)
                .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
          }
        }
        .overlay { shape.stroke(.white.opacity(0.18), lineWidth: 1) }
        .clipShape(shape)
        // Outside the clip, so the marks leave the picture uncovered; the inset ring
        // stays concentric with the corners.
        .overlay {
          ZStack {
            if isSelected {
              shape
                .inset(by: -TitleImagePickerMetrics.selectionRingGap)
                .stroke(Color.accentColor, lineWidth: TitleImagePickerMetrics.selectionRingWidth)
                .transition(.asymmetric(
                  insertion: .opacity.combined(with: .scale(scale: 1.04)),
                  removal: .opacity
                ))
            }
          }
        }
        .overlay(alignment: .topTrailing) {
          ZStack {
            if isSelected {
              Image(systemName: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.accentColor)
                .background(Circle().fill(.background).padding(-1.5))
                .transition(.scale(scale: 0.4).combined(with: .opacity))
                .accessibilityHidden(true)
            }
          }
          .offset(x: TitleImagePickerMetrics.badgeOffset, y: -TitleImagePickerMetrics.badgeOffset)
        }
        .animation(.snappy(duration: 0.2), value: isSelected)

      HStack(spacing: 8) {
        Label {
          Text(file.voteLabel)
        } icon: {
          Image(systemName: "star.fill")
        }
        .labelStyle(TitleImageCaptionLabelStyle())
        Text(verbatim: file.sizeLabel)
        if file.isVector {
          Text(verbatim: "SVG")
        }
      }
      .font(.caption)
      .monospacedDigit()
      .foregroundStyle(.secondary)
      .lineLimit(1)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

/// Icon and text a hair apart, the way a caption reads.
private struct TitleImageCaptionLabelStyle: LabelStyle {
  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    HStack(spacing: 3) {
      configuration.icon.imageScale(.small)
      configuration.title
    }
  }
}

private enum TitleImagePickerMetrics {
#if os(tvOS)
  static let horizontalPadding: CGFloat = 80
  static let maxContentWidth: CGFloat = .infinity
  static let sectionSpacing: CGFloat = 40
  static let headerSpacing: CGFloat = 20
  static let gridSpacing: CGFloat = 40
  static let cornerRadius: CGFloat = 12
  static let logoInset: CGFloat = 24
  static func minTileWidth(_ kind: WorkerImageAdminKind) -> CGFloat { 360 }
  static func maxTileWidth(_ kind: WorkerImageAdminKind) -> CGFloat { 460 }
#else
  static let horizontalPadding: CGFloat = 16
  static let maxContentWidth: CGFloat = 1_100
  static let sectionSpacing: CGFloat = 24
  static let headerSpacing: CGFloat = 10
  static let gridSpacing: CGFloat = 14
  static let cornerRadius: CGFloat = 10
  static let logoInset: CGFloat = 14
  static func minTileWidth(_ kind: WorkerImageAdminKind) -> CGFloat { kind == .logo ? 150 : 200 }
  static func maxTileWidth(_ kind: WorkerImageAdminKind) -> CGFloat { kind == .logo ? 260 : 320 }
#endif
  static let selectionRingGap: CGFloat = 3.5
  static let selectionRingWidth: CGFloat = 3
  static let badgeOffset: CGFloat = 6
}

// MARK: - Model

struct TitleImagePickerSection: Identifiable {
  let kind: WorkerImageAdminKind
  let language: WorkerArtworkLanguageTag
  let files: [WorkerImageAdminCandidate]

  var id: String { "\(kind.rawValue)-\(language.rawValue)" }
}

@Observable
@MainActor
final class TitleImagePickerModel {
  enum Phase: Equatable {
    case loading
    case loaded
    case failed(String)
  }

  private let target: TitleImagePickerTarget
  private let client: WorkerImageAdminClient?
  private let userLanguage: WorkerArtworkLanguageTag

  private var phases: [WorkerImageAdminKind: Phase] = [:]
  private var catalogs: [WorkerImageAdminKind: WorkerImageAdminCatalog] = [:]
  /// What is selected now, per kind and language.
  private var selection: [WorkerImageAdminKind: [WorkerArtworkLanguageTag: String]] = [:]
  /// What the worker has pinned, as the catalog reported it.
  private var pinned: [WorkerImageAdminKind: [WorkerArtworkLanguageTag: String]] = [:]

  private(set) var isSaving = false
  private(set) var saveError: String?

  init(target: TitleImagePickerTarget,
       client: WorkerImageAdminClient?,
       userLanguage: WorkerArtworkLanguageTag) {
    self.target = target
    self.client = client
    self.userLanguage = userLanguage
  }

  /// Preview / fixture: a catalog already in hand.
  init(target: TitleImagePickerTarget,
       userLanguage: WorkerArtworkLanguageTag,
       catalogs: [WorkerImageAdminKind: WorkerImageAdminCatalog]) {
    self.target = target
    self.client = nil
    self.userLanguage = userLanguage
    for (kind, catalog) in catalogs { apply(catalog, kind: kind) }
  }

  func phase(for kind: WorkerImageAdminKind) -> Phase {
    phases[kind] ?? .loading
  }

  /// Backdrops: no language first, then English, then Russian — text-free art leads.
  /// Logos: the app's language first.
  func languageOrder(for kind: WorkerImageAdminKind) -> [WorkerArtworkLanguageTag] {
    switch kind {
    case .logo: userLanguage == .en ? [.en, .ru, .und] : [.ru, .en, .und]
    default: [.und, .en, .ru]
    }
  }

  func sections(for kind: WorkerImageAdminKind) -> [TitleImagePickerSection] {
    guard let catalog = catalogs[kind] else { return [] }
    return languageOrder(for: kind).compactMap { language in
      let files = Self.ranked(catalog.bucket(language))
      return files.isEmpty ? nil : TitleImagePickerSection(kind: kind, language: language, files: files)
    }
  }

  func selectedURL(kind: WorkerImageAdminKind, language: WorkerArtworkLanguageTag) -> String? {
    selection[kind]?[language]
  }

  var hasChanges: Bool {
    catalogs.keys.contains { kind in
      let selected = selection[kind] ?? [:]
      return !selected.isEmpty && selected != (pinned[kind] ?? [:])
    }
  }

  func select(_ file: WorkerImageAdminCandidate,
              language: WorkerArtworkLanguageTag,
              kind: WorkerImageAdminKind) {
    saveError = nil
    if kind == .logo {
      selection[kind, default: [:]][language] = file.url
    } else {
      // One backdrop per title in the worker: a pick anywhere replaces the last one.
      selection[kind] = [language: file.url]
    }
  }

  func load(_ kind: WorkerImageAdminKind, force: Bool = false) async {
    if !force, catalogs[kind] != nil { return }
    guard let client else {
      phases[kind] = .failed(String(localized: "Add the worker admin token in Settings › Advanced."))
      return
    }
    phases[kind] = .loading
    do {
      let imdb = target.imdb.map { TMDBIDFormatter.imdbString(from: $0) }
      let catalog = try await client.catalog(kinopubID: target.kinopubID, kind: kind, imdb: imdb)
      apply(catalog, kind: kind)
    } catch is CancellationError {
      return
    } catch {
      phases[kind] = .failed(error.localizedDescription)
    }
  }

  /// Forget, then pin: the worker's `pick` keeps a kind's unpinned files beside a new
  /// pin, so the kind is cleared first and only the selection is written back.
  func save() async -> Bool {
    guard let client else { return false }
    isSaving = true
    saveError = nil
    defer { isSaving = false }
    do {
      for kind in [WorkerImageAdminKind.logo, .backdrop] {
        let selected = selection[kind] ?? [:]
        guard !selected.isEmpty, selected != (pinned[kind] ?? [:]) else { continue }
        _ = try await client.forget(kinopubID: target.kinopubID, kind: kind)
        for language in languageOrder(for: kind) {
          guard let url = selected[language] else { continue }
          if kind == .logo {
            _ = try await client.pickLogo(kinopubID: target.kinopubID, url: url, language: language)
          } else {
            _ = try await client.pickBackdrop(kinopubID: target.kinopubID, url: url)
          }
        }
        pinned[kind] = selected
      }
      Artwork.clearCaches()
      return true
    } catch {
      saveError = error.localizedDescription
      return false
    }
  }

  private func apply(_ catalog: WorkerImageAdminCatalog, kind: WorkerImageAdminKind) {
    catalogs[kind] = catalog
    let order = languageOrder(for: kind)
    // Where each pinned file sits in the TMDB list, by its url.
    var bucketOf: [String: WorkerArtworkLanguageTag] = [:]
    for language in order {
      for file in catalog.bucket(language) { bucketOf[file.url] = language }
    }
    var pins: [WorkerArtworkLanguageTag: String] = [:]
    for stored in catalog.stored ?? [] where stored.pinned == true {
      guard let language = bucketOf[stored.url] else { continue }
      pins[language] = stored.url
    }
    if kind != .logo, let first = order.first(where: { pins[$0] != nil }) {
      pins = [first: pins[first]!]
    }
    pinned[kind] = pins

    var chosen = pins
    if kind == .logo {
      for language in order where chosen[language] == nil {
        chosen[language] = Self.ranked(catalog.bucket(language)).first?.url
      }
    } else if chosen.isEmpty,
              let language = order.first(where: { !catalog.bucket($0).isEmpty }) {
      chosen[language] = Self.ranked(catalog.bucket(language)).first?.url
    }
    selection[kind] = chosen
    phases[kind] = .loaded
  }

  /// Most votes first (usually the right one), then the larger file.
  static func ranked(_ files: [WorkerImageAdminCandidate]) -> [WorkerImageAdminCandidate] {
    files.sorted { lhs, rhs in
      let lv = lhs.vote ?? 0, rv = rhs.vote ?? 0
      if lv != rv { return lv > rv }
      return (lhs.width ?? 0) > (rhs.width ?? 0)
    }
  }
}

// MARK: - Presentation helpers

extension WorkerArtworkLanguageTag {
  /// "Russian" / "English" in the app's language; "No Language" for textless files.
  var pickerTitle: String {
    switch self {
    case .und:
      return String(localized: "No Language")
    case .ru, .en:
      let name = Locale.current.localizedString(forLanguageCode: rawValue) ?? rawValue
      return name.prefix(1).uppercased() + name.dropFirst()
    }
  }
}

extension WorkerImageAdminCandidate {
  /// TMDB serves every width for every kind; the grid asks for a small one, not `original`.
  func previewURL(kind: WorkerImageAdminKind) -> URL? {
    let width = kind == .logo ? "w500" : "w780"
    return URL(string: url.replacingOccurrences(of: "/t/p/original/", with: "/t/p/\(width)/"))
  }

  var voteLabel: String {
    (vote ?? 0).formatted(.number.precision(.fractionLength(1)))
  }

  var isVector: Bool { from?.lowercased() == "svg" }
}

// MARK: - Menu items

/// What the title page's More menus offer an admin: Change Images, and the worker's
/// rarely used maintenance actions one level down, in More.
@MainActor
struct TitleImageAdminActions {
  let target: TitleImagePickerTarget
  let kinopoisk: Int?
  let images: TitleImageRoute
  let onChangeImages: () -> Void
  /// After the worker changed what it serves: drop the device's copies and reload.
  let onArtworkChanged: () async -> Void
  let report: (HudToast) -> Void

  /// `nil` without an admin token or a worker — the menus then show nothing.
  static func make(target: TitleImagePickerTarget,
                   kinopoisk: Int?,
                   images: TitleImageRoute,
                   onChangeImages: @escaping () -> Void,
                   onArtworkChanged: @escaping () async -> Void,
                   report: @escaping (HudToast) -> Void) -> TitleImageAdminActions? {
    guard WorkerImageAdminTokenStore.isConfigured, images.isConfigured else { return nil }
    return TitleImageAdminActions(target: target, kinopoisk: kinopoisk, images: images,
                                  onChangeImages: onChangeImages,
                                  onArtworkChanged: onArtworkChanged, report: report)
  }

  private var client: WorkerImageAdminClient? {
    WorkerImageAdminTokenStore.client(proxyBaseURL: images.baseURL)
  }

  func refresh(_ kind: WorkerImageAdminKind) {
    perform(done: "Asked TMDB again") { client in
      let imdb = target.imdb.map { TMDBIDFormatter.imdbString(from: $0) }
      _ = try await client.refresh(kinopubID: target.kinopubID, kind: kind,
                                   imdb: imdb, kinopoisk: kinopoisk)
    }
  }

  func forget(_ kind: WorkerImageAdminKind) {
    perform(done: "Forgotten") { client in
      _ = try await client.forget(kinopubID: target.kinopubID, kind: kind)
    }
  }

  func resetLocalCache() {
    Task {
      await onArtworkChanged()
      report(HudToast(systemImage: "checkmark", title: String(localized: "Local cache cleared")))
    }
  }

  func showStats() {
    Task {
      guard let client else { return }
      do {
        let stats = try await client.imageStats()
        let line = stats.keys.sorted().map { "\($0) \(stats[$0] ?? 0)" }.joined(separator: " · ")
        report(HudToast(systemImage: "chart.bar", title: line.isEmpty ? "—" : line))
      } catch {
        report(HudToast(systemImage: "exclamationmark.triangle", title: error.localizedDescription))
      }
    }
  }

  private func perform(done: String.LocalizationValue,
                       _ work: @escaping (WorkerImageAdminClient) async throws -> Void) {
    Task {
      guard let client else { return }
      do {
        try await work(client)
        Artwork.clearCaches()
        await onArtworkChanged()
        report(HudToast(systemImage: "checkmark", title: String(localized: done)))
      } catch {
        report(HudToast(systemImage: "exclamationmark.triangle", title: error.localizedDescription))
      }
    }
  }
}

/// Change Images, then More › the maintenance actions. One list for the toolbar's More
/// (iOS, macOS) and the hero's More (tvOS, iOS).
struct TitleImageAdminMenuItems: View {
  let actions: TitleImageAdminActions

  var body: some View {
    Button(action: actions.onChangeImages) {
      Label("Change Images", systemImage: "photo.on.rectangle")
    }
    Menu {
      Button { actions.refresh(.logo) } label: {
        Label("Refresh Logo", systemImage: "arrow.clockwise")
      }
      Button { actions.refresh(.backdrop) } label: {
        Label("Refresh Backdrop", systemImage: "arrow.clockwise")
      }
      Divider()
      Button(role: .destructive) { actions.forget(.logo) } label: {
        Label("Forget Logo", systemImage: "trash")
      }
      Button(role: .destructive) { actions.forget(.backdrop) } label: {
        Label("Forget Backdrop", systemImage: "trash")
      }
      Divider()
      Button { actions.resetLocalCache() } label: {
        Label("Reset Local Cache", systemImage: "externaldrive.badge.xmark")
      }
      Button { actions.showStats() } label: {
        Label("Worker Stats", systemImage: "chart.bar")
      }
    } label: {
      Label("More Image Actions", systemImage: "ellipsis.circle")
    }
  }
}

// MARK: - Preview

#if DEBUG
@MainActor
private enum TitleImagePickerPreviewData {
  static let target = TitleImagePickerTarget(kinopubID: 1, imdb: nil, title: "Дюна")

  static func candidate(_ path: String, lang: String, w: Int, h: Int, vote: Double) -> WorkerImageAdminCandidate {
    let json = """
    {"url":"https://image.tmdb.org/t/p/original\(path)","lang":"\(lang)","from":"png",\
    "width":\(w),"height":\(h),"vote":\(vote)}
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(WorkerImageAdminCandidate.self, from: Data(json.utf8))
  }

  static var model: TitleImagePickerModel {
    let logos = WorkerImageAdminCatalog(
      ok: true, id: "1", kind: "logo", tmdb: "movie/438631",
      ru: [candidate("/zEqyD0SBt6HL7W9JQoWwtd5Do1T.png", lang: "ru", w: 1200, h: 400, vote: 5.3)],
      en: [candidate("/zEqyD0SBt6HL7W9JQoWwtd5Do1T.png", lang: "en", w: 1500, h: 500, vote: 5.6),
           candidate("/kZvNqMS6xRDN2c4WbbspXyb1SXW.png", lang: "en", w: 800, h: 200, vote: 5.1)],
      und: [],
      stored: nil
    )
    let backdrops = WorkerImageAdminCatalog(
      ok: true, id: "1", kind: "backdrop", tmdb: "movie/438631",
      ru: [],
      en: [candidate("/jYEW5xZkZk2WTrdbMGAPFuBqbDc.jpg", lang: "en", w: 3840, h: 2160, vote: 5.4)],
      und: [candidate("/iopYFB1b6Bh7FWZh3onQhph1sih.jpg", lang: "und", w: 3840, h: 2160, vote: 5.7),
            candidate("/lzWHmYdfeFiMIY4JaMmtR7GEli3.jpg", lang: "und", w: 1920, h: 1080, vote: 5.2)],
      stored: nil
    )
    return TitleImagePickerModel(target: target, userLanguage: .ru,
                                 catalogs: [.logo: logos, .backdrop: backdrops])
  }
}

#Preview("Change Images") {
  Color.clear
    .sheet(isPresented: .constant(true)) {
      TitleImagePickerSheet(target: TitleImagePickerPreviewData.target,
                            images: TitleImageRoute(baseURL: nil),
                            onSaved: {},
                            model: TitleImagePickerPreviewData.model)
    }
}
#endif
