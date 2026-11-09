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
  @State private var showsLinkEntry = false
  @State private var linkText = ""

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
          HStack(spacing: 12) {
            Picker("Image Kind", selection: $kind) {
              Text("Logo").tag(WorkerImageAdminKind.logo)
              Text("Backdrop").tag(WorkerImageAdminKind.backdrop)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
#if !os(tvOS)
            .fixedSize()
#endif
            Spacer(minLength: 0)
            Button {
              linkText = ""
              showsLinkEntry = true
            } label: {
              Label("Image Link", systemImage: "link")
            }
            .disabled(model.isSaving)
          }

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
#if !os(tvOS)
      .sheetCloseAndSave(close: { closeButton }, save: { saveButton })
#endif
    }
    .task(id: kind) { await model.load(kind) }
    .alert(kind == .logo ? "Logo by Link" : "Backdrop by Link", isPresented: $showsLinkEntry) {
      TextField("https://image.tmdb.org/t/p/original/…", text: $linkText)
#if os(iOS)
        .keyboardType(.URL)
        .textInputAutocapitalization(.never)
#endif
        .autocorrectionDisabled()
      if kind == .logo {
        ForEach(model.languageOrder(for: .logo), id: \.self) { language in
          Button(language.pickerTitle) { pinLink(language: language) }
        }
      } else {
        Button("Pin") { pinLink(language: .und) }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(kind == .logo
           ? "Replaces the logo of the language you choose."
           : "Replaces the title's backdrop.")
    }
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

  private func pinLink(language: WorkerArtworkLanguageTag) {
    let link = linkText
    let kind = kind
    Task {
      if await model.pinLink(link, kind: kind, language: language) {
        await onSaved()
      }
    }
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
          let current = model.currentImages(for: kind)
          if !current.isEmpty {
            currentSection(current)
          }
          ForEach(sections) { section in
            languageSection(section)
          }
        }
      }
    }
  }

  /// What the worker has for this title now: a pin, or its own automatic choice.
  private func currentSection(_ images: [TitleImagePickerCurrent]) -> some View {
    VStack(alignment: .leading, spacing: TitleImagePickerMetrics.headerSpacing) {
      Text("On the Title Now")
        .font(.headline)
      LazyVGrid(
        columns: [GridItem(
          .adaptive(minimum: TitleImagePickerMetrics.minTileWidth(kind),
                    maximum: TitleImagePickerMetrics.maxTileWidth(kind)),
          spacing: TitleImagePickerMetrics.gridSpacing
        )],
        alignment: .leading,
        spacing: TitleImagePickerMetrics.gridSpacing
      ) {
        ForEach(images) { image in
          TitleImageTile(kind: image.kind, previewURL: image.previewURL, isSelected: false) {
            HStack(spacing: 6) {
              Text(verbatim: image.language.pickerTitle)
              Text(verbatim: "·")
              if image.isPinned {
                Label("Pinned", systemImage: "pin.fill")
                  .labelStyle(TitleImageCaptionLabelStyle())
              } else {
                Text("Automatic")
              }
            }
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
          TitleImageTile(kind: kind, previewURL: file.previewURL(kind: kind),
                         isSelected: file.url == selectedURL) {
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
          }
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

private struct TitleImageTile<Caption: View>: View {
  let kind: WorkerImageAdminKind
  let previewURL: URL?
  let isSelected: Bool
  /// The box the picture fills or fits; a season's poster is 2:3.
  var boxAspectRatio: CGFloat = 16 / 9
  @ViewBuilder let caption: () -> Caption

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: TitleImagePickerMetrics.cornerRadius, style: .continuous)
  }

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
                CachedRemoteImage(url: previewURL, contentMode: .fit) {
                  ProgressView()
                } failure: {
                  Image(systemName: "photo").foregroundStyle(.secondary)
                }
                .padding(TitleImagePickerMetrics.logoInset)
              }
          } else {
            CachedRemoteImage(url: previewURL, contentMode: .fill) {
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

      caption()
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
  /// A season poster's tile in `SeasonImageBrowserSheet`.
  static let minPosterWidth: CGFloat = 120
  static let maxPosterWidth: CGFloat = 180
  static let selectionRingGap: CGFloat = 3.5
  static let selectionRingWidth: CGFloat = 3
  static let badgeOffset: CGFloat = 6
}

// MARK: - Season posters

#if !os(tvOS)
/// «Изменить изображение» on a season card: every TMDB poster of the season in the picker's
/// grid, to look through and pick from. Nothing is saved yet — the worker keeps no season
/// pick (Sasha, 2026-11-09: «пока что без сохранить»).
struct SeasonImageBrowserSheet: View {
  let title: String
  let load: () async -> [URL]

  @Environment(\.dismiss) private var dismiss
  @State private var posters: [URL]?
  @State private var selected: URL?

  var body: some View {
    NavigationStack {
      ScrollView {
        content
          .frame(maxWidth: .infinity)
          .padding(.horizontal, TitleImagePickerMetrics.horizontalPadding)
#if os(macOS)
          .padding(.vertical, 16)
#endif
          .frame(maxWidth: TitleImagePickerMetrics.maxContentWidth)
          .frame(maxWidth: .infinity)
      }
      .navigationTitle(Text("Season Images"))
      .navigationSubtitleIfAvailable(title)
      .sheetInlineNavigationTitle()
      .sheetCloseAndSave(close: {
        Button { dismiss() } label: { SheetCloseLabel() }
      }, save: { EmptyView() })
    }
    .task {
      let found = await load()
      posters = found
      if selected == nil { selected = found.first }
    }
#if os(iOS)
    .presentationDragIndicator(.visible)
#endif
    .presentationSizing(.page)
    .macSheetFrame(width: 900, height: 680)
  }

  @ViewBuilder
  private var content: some View {
    if let posters {
      if posters.isEmpty {
        ContentUnavailableView("No Images",
                               systemImage: "photo.on.rectangle",
                               description: Text("TMDB has no posters for this season."))
      } else {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: TitleImagePickerMetrics.minPosterWidth,
                                       maximum: TitleImagePickerMetrics.maxPosterWidth),
                             spacing: TitleImagePickerMetrics.gridSpacing)],
          alignment: .leading,
          spacing: TitleImagePickerMetrics.gridSpacing
        ) {
          ForEach(posters, id: \.self) { url in
            Button {
              selected = url
            } label: {
              TitleImageTile(kind: .backdrop, previewURL: url, isSelected: url == selected,
                             boxAspectRatio: CardAspect.poster.ratio) {
                EmptyView()
              }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(url == selected ? .isSelected : [])
          }
        }
      }
    } else {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
  }
}

private extension View {
  /// The season's name under «Изображения сезона» on a Mac; iOS keeps the bar's one line.
  @ViewBuilder
  func navigationSubtitleIfAvailable(_ subtitle: String) -> some View {
#if os(macOS)
    navigationSubtitle(subtitle)
#else
    self
#endif
  }
}
#endif

// MARK: - Model

/// A file the worker stores for the title and serves for one language.
struct TitleImagePickerCurrent: Identifiable {
  let kind: WorkerImageAdminKind
  let language: WorkerArtworkLanguageTag
  let url: String
  let isPinned: Bool

  var id: String { "\(kind.rawValue)-\(language.rawValue)" }

  var previewURL: URL? {
    let width = kind == .logo ? "w500" : "w780"
    return URL(string: url.replacingOccurrences(of: "/t/p/original/", with: "/t/p/\(width)/"))
  }
}

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
  /// What the worker serves now, per language: a pin, else its stored automatic file.
  private var current: [WorkerImageAdminKind: [TitleImagePickerCurrent]] = [:]

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

  func currentImages(for kind: WorkerImageAdminKind) -> [TitleImagePickerCurrent] {
    current[kind] ?? []
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

  /// Pins the selection. Each pick replaces every file of its language in the worker
  /// (a backdrop pick all backdrops), so nothing automatic stays beside a pin.
  func save() async -> Bool {
    guard let client else { return false }
    isSaving = true
    saveError = nil
    defer { isSaving = false }
    do {
      for kind in [WorkerImageAdminKind.logo, .backdrop] {
        let selected = selection[kind] ?? [:]
        guard !selected.isEmpty, selected != (pinned[kind] ?? [:]) else { continue }
        for language in languageOrder(for: kind) {
          guard let url = selected[language], url != pinned[kind]?[language] else { continue }
          let file = catalogs[kind].flatMap { catalog in
            languageOrder(for: kind).lazy.flatMap { catalog.bucket($0) }.first { $0.url == url }
          }
          _ = try await client.pick(kinopubID: target.kinopubID, kind: kind, url: url,
                                    language: kind == .logo ? language : nil,
                                    width: file?.width, height: file?.height)
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

  /// Pins a file by its address, for when TMDB's list has nothing usable. An
  /// image.tmdb.org address is stored at its original size whatever size it names.
  func pinLink(_ raw: String, kind: WorkerImageAdminKind, language: WorkerArtworkLanguageTag) async -> Bool {
    guard let client else { return false }
    guard let url = Self.normalizedLink(raw) else {
      saveError = String(localized: "Paste an https link to an image.")
      return false
    }
    isSaving = true
    saveError = nil
    defer { isSaving = false }
    do {
      _ = try await client.pick(kinopubID: target.kinopubID, kind: kind, url: url,
                                language: kind == .logo ? language : nil)
      Artwork.clearCaches()
      await load(kind, force: true)
      return true
    } catch {
      saveError = error.localizedDescription
      return false
    }
  }

  static func normalizedLink(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var components = URLComponents(string: trimmed),
          components.scheme?.lowercased() == "https",
          let host = components.host, !host.isEmpty else { return nil }
    if host.lowercased() == "image.tmdb.org" {
      // /t/p/w500/abc.png → /t/p/original/abc.png
      var parts = components.path.split(separator: "/", omittingEmptySubsequences: false)
      if parts.count >= 5, parts[1] == "t", parts[2] == "p" {
        parts[3] = "original"
        components.path = parts.joined(separator: "/")
      }
    }
    return components.url?.absoluteString
  }

  private func apply(_ catalog: WorkerImageAdminCatalog, kind: WorkerImageAdminKind) {
    catalogs[kind] = catalog
    let order = languageOrder(for: kind)
    // TMDB files by file name: the worker may hold a file as .png that TMDB lists as .svg.
    var fileFor: [String: (language: WorkerArtworkLanguageTag, url: String)] = [:]
    for language in order {
      for file in catalog.bucket(language) {
        fileFor[Self.fileKey(file.url)] = (language, file.url)
      }
    }
    let stored = (catalog.stored ?? []).filter { !Self.isKinopubArt($0.url) }
    func tag(_ lang: String?) -> WorkerArtworkLanguageTag? {
      guard let lang else { return .und }
      return WorkerArtworkLanguageTag(rawValue: lang)
    }

    // What the worker serves: per language a pin, else the first stored file — its list
    // keeps pins first, then its own ranking. Backdrops: the one pin, else a textless one.
    var now: [TitleImagePickerCurrent] = []
    if kind == .logo {
      for language in order {
        let mine = stored.filter { tag($0.lang) == language }
        if let asset = mine.first(where: { $0.pinned == true }) ?? mine.first {
          now.append(TitleImagePickerCurrent(kind: kind, language: language, url: asset.url,
                                             isPinned: asset.pinned == true))
        }
      }
    } else if let asset = stored.first(where: { $0.pinned == true })
                ?? stored.first(where: { $0.lang == nil }) {
      now.append(TitleImagePickerCurrent(kind: kind, language: tag(asset.lang) ?? .und,
                                         url: asset.url, isPinned: asset.pinned == true))
    }
    current[kind] = now

    // Pins and the served files, as TMDB files in the grid.
    var pins: [WorkerArtworkLanguageTag: String] = [:]
    var served: [WorkerArtworkLanguageTag: String] = [:]
    for item in now {
      guard let match = fileFor[Self.fileKey(item.url)] else { continue }
      let language = kind == .logo ? item.language : match.language
      if item.isPinned { pins[language] = match.url }
      served[language] = match.url
    }
    pinned[kind] = pins

    // Start on what is on the title now; a language with nothing stored starts on its
    // most-voted file.
    var chosen = served
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

  /// `…/t/p/original/abc.svg` and `…/abc.png` are one TMDB file.
  static func fileKey(_ url: String) -> String {
    let name = URL(string: url)?.lastPathComponent ?? url
    return (name as NSString).deletingPathExtension
  }

  private static func isKinopubArt(_ url: String) -> Bool {
    guard let host = URL(string: url)?.host?.lowercased() else { return false }
    return host.contains("kinopub") || host.contains("kino.pub") || host.contains("staticpop")
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
  /// The Title IDs form.
  let onEditIDs: () -> Void
  /// After the worker changed what it serves: drop the device's copies and reload.
  let onArtworkChanged: () async -> Void
  let report: (HudToast) -> Void

  /// `nil` without an admin token or a worker — the menus then show nothing.
  static func make(target: TitleImagePickerTarget,
                   kinopoisk: Int?,
                   images: TitleImageRoute,
                   onChangeImages: @escaping () -> Void,
                   onEditIDs: @escaping () -> Void,
                   onArtworkChanged: @escaping () async -> Void,
                   report: @escaping (HudToast) -> Void) -> TitleImageAdminActions? {
    guard WorkerImageAdminTokenStore.isConfigured, images.isConfigured else { return nil }
    return TitleImageAdminActions(target: target, kinopoisk: kinopoisk, images: images,
                                  onChangeImages: onChangeImages, onEditIDs: onEditIDs,
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
    Button(action: actions.onEditIDs) {
      Label("Title IDs", systemImage: "number")
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
