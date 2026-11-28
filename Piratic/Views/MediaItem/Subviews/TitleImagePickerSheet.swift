//
//  TitleImagePickerSheet.swift
//  Piratic
//
//  "Change Images": which logo, poster, cover and backdrop the worker serves for a
//  title. Cover is a wide picture with lettering; backdrop stays textless. Files come
//  from TMDB, fanart.tv, TheTVDB, ThePosterDB, tvoe, Kinopoisk, Wikidata and the admin's own
//  uploads (workers/tmdb-proxy/src/sources.js); chips filter the grid by source, the
//  way Silo's Edit Metadata › Images does.
//  The sheet, grid and toolbar policy are AniShelf's poster picker
//  (`PosterSelectionView` / `PosterGridView`, github.com/samuelhe52/AniShelf); the
//  per-language selection and the worker writes are ours.
//

import SwiftUI
import ImageIO
import UniformTypeIdentifiers
#if !os(tvOS)
import PhotosUI
#endif
import PiraticUI
import PiraticMetadata

/// The title a picker is opened for. A card knows no IMDb id; the worker then finds the
/// title from what it stored when the title was first opened.
struct TitleImagePickerTarget: Identifiable, Hashable {
  let kinopubID: Int
  let imdb: Int?
  let title: String
  /// The segment the sheet opens on: a poster card's menu opens Poster (Sasha, 2026-11-26).
  var initialKind: WorkerImageAdminKind = .logo

  var id: Int { kinopubID }
}

extension WorkerImageAdminKind {
  /// Logos, covers and posters are pinned one per language; a backdrop is one per title.
  var picksPerLanguage: Bool { self != .backdrop }
}

/// Opens on a Logo / Cover / Backdrop segment. Logos and covers take one pick per
/// language (ru, en, and und for logos), the way the worker stores them; a backdrop is
/// one picture per title in the worker, so its grid takes one pick across all languages.
/// Cover lists language-tagged TMDB backdrops only. With no pick stored, each language
/// starts on its most-voted file. Save drops what the worker had for that kind and pins
/// exactly what is selected, so no automatic choice is left behind next to a pick.
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
  @State private var showsKeyEntry = false
  @State private var fanartKey = ""
  @State private var tvdbKey = ""
#if !os(tvOS)
  @State private var photoItem: PhotosPickerItem?
  @State private var showsFileImporter = false
  /// A picture read and ready to upload, waiting for its language.
  @State private var pendingUpload: TitleImageUpload?
#endif

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
              Text("Poster").tag(WorkerImageAdminKind.poster)
              Text("Cover").tag(WorkerImageAdminKind.cover)
              Text("Backdrop").tag(WorkerImageAdminKind.backdrop)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
#if !os(tvOS)
            .fixedSize()
#endif
            Spacer(minLength: 0)
#if !os(tvOS)
            uploadMenu
#endif
            Button {
              linkText = ""
              showsLinkEntry = true
            } label: {
              Label("Image Link", systemImage: "link")
            }
            .disabled(model.isSaving)
          }
#if os(iOS)
          // Four segments and two buttons: on a phone the buttons keep only their symbols.
          .labelStyle(TitleImagePickerToolbarLabelStyle())
#endif

          sourceChips

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
    .alert("Source Keys", isPresented: $showsKeyEntry) {
      SecureField("fanart.tv API Key", text: $fanartKey)
      SecureField("TheTVDB API Key", text: $tvdbKey)
      Button("Save") { saveKeys() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Saved in the worker, so every device sees these sources. A personal key is free at fanart.tv and thetvdb.com.")
    }
#if !os(tvOS)
    .onChange(of: photoItem) { _, item in
      guard let item else { return }
      photoItem = nil
      Task { await readUpload { try await item.loadTransferable(type: Data.self) } }
    }
    .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.image]) { result in
      guard case .success(let url) = result else { return }
      Task {
        await readUpload {
          let scoped = url.startAccessingSecurityScopedResource()
          defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          return try Data(contentsOf: url)
        }
      }
    }
    .confirmationDialog("Upload For", isPresented: uploadLanguageBinding, titleVisibility: .visible) {
      ForEach(model.languageOrder(for: kind), id: \.self) { language in
        Button(language.pickerTitle) { upload(language: language) }
      }
      Button("Cancel", role: .cancel) { pendingUpload = nil }
    }
#endif
    .alert(linkAlertTitle, isPresented: $showsLinkEntry) {
      TextField("https://image.tmdb.org/t/p/original/…", text: $linkText)
#if os(iOS)
        .keyboardType(.URL)
        .textInputAutocapitalization(.never)
#endif
        .autocorrectionDisabled()
      if kind.picksPerLanguage {
        ForEach(model.languageOrder(for: kind), id: \.self) { language in
          Button(language.pickerTitle) { pinLink(language: language) }
        }
      } else {
        Button("Pin") { pinLink(language: .und) }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(linkAlertMessage)
    }
#if os(iOS)
    .presentationDragIndicator(.visible)
#endif
    .presentationSizing(.page)
    .macSheetFrame(width: 900, height: 680)
  }

  /// DEBUG `-PIRATICOpenImagePicker logo|cover|backdrop`: the title page opens this sheet on load.
  static var launchKind: WorkerImageAdminKind? {
#if DEBUG
    UserDefaults.standard.string(forKey: "PIRATICOpenImagePicker").flatMap(WorkerImageAdminKind.init(rawValue:))
#else
    nil
#endif
  }

  private var linkAlertTitle: LocalizedStringKey {
    switch kind {
    case .logo: "Logo by Link"
    case .cover: "Cover by Link"
    case .poster: "Poster by Link"
    case .backdrop: "Backdrop by Link"
    }
  }

  private var linkAlertMessage: LocalizedStringKey {
    switch kind {
    case .logo: "Replaces the logo of the language you choose."
    case .cover: "Replaces the cover of the language you choose."
    case .poster: "Replaces the poster of the language you choose."
    case .backdrop: "Replaces the title's backdrop."
    }
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

  /// Source chips over the grid: All, then each source with its count. Sources that
  /// need a key the worker lacks are offered under them.
  @ViewBuilder
  private var sourceChips: some View {
    let chips = model.sourceChips(for: kind)
    let missing = model.sourcesNeedingKey(for: kind)
    if chips.count > 1 || !missing.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        if chips.count > 1 {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              chip(title: String(localized: "All"), count: chips.reduce(0) { $0 + $1.count },
                   selected: model.sourceFilter(for: kind) == nil) {
                model.setSourceFilter(nil, for: kind)
              }
              ForEach(chips) { item in
                chip(title: TitleImageSource.name(item.source), count: item.count,
                     selected: model.sourceFilter(for: kind) == item.source) {
                  model.setSourceFilter(item.source, for: kind)
                }
              }
            }
#if os(tvOS)
            .padding(.vertical, 20)
#endif
          }
#if !os(tvOS)
          .scrollClipDisabled()
#endif
        }
        if !missing.isEmpty {
          Button {
            fanartKey = ""
            tvdbKey = ""
            showsKeyEntry = true
          } label: {
            Label {
              Text("Add keys for \(missing.map(TitleImageSource.name).formatted(.list(type: .and)))")
            } icon: {
              Image(systemName: "key")
            }
            .font(.footnote)
          }
#if !os(tvOS)
          .buttonStyle(.borderless)
#endif
        }
      }
    }
  }

  private func chip(title: String, count: Int, selected: Bool,
                    action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Text(verbatim: title)
        Text(verbatim: "\(count)")
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
#if !os(tvOS)
      .font(.subheadline)
#endif
    }
#if os(tvOS)
    .buttonStyle(.bordered)
#else
    .buttonStyle(.bordered)
    .buttonBorderShape(.capsule)
    .tint(selected ? .accentColor : nil)
#endif
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func saveKeys() {
    var keys: [String: String] = [:]
    let fanart = fanartKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let tvdb = tvdbKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if !fanart.isEmpty { keys["fanart"] = fanart }
    if !tvdb.isEmpty { keys["tvdb"] = tvdb }
    guard !keys.isEmpty else { return }
    Task { await model.saveKeys(keys) }
  }

#if !os(tvOS)
  private var uploadMenu: some View {
    Menu {
      PhotosPicker(selection: $photoItem, matching: .images) {
        Label("Photo Library", systemImage: "photo.on.rectangle")
      }
      Button {
        showsFileImporter = true
      } label: {
        Label("Choose File…", systemImage: "folder")
      }
    } label: {
      Label("Upload", systemImage: "square.and.arrow.up")
    }
    .fixedSize()
    .disabled(model.isSaving)
  }

  private var uploadLanguageBinding: Binding<Bool> {
    Binding(get: { pendingUpload != nil && kind.picksPerLanguage },
            set: { if !$0 { pendingUpload = nil } })
  }

  /// Reads the picture, then asks for its language (a backdrop has none) and uploads.
  private func readUpload(_ read: @escaping () async throws -> Data?) async {
    do {
      guard let data = try await read(), let prepared = TitleImageUpload(data: data) else {
        model.reportUploadError(String(localized: "This file is not a picture."))
        return
      }
      pendingUpload = prepared
      // A backdrop has no language: no question, straight up.
      if !kind.picksPerLanguage { upload(language: .und) }
    } catch {
      model.reportUploadError(error.localizedDescription)
    }
  }

  private func upload(language: WorkerArtworkLanguageTag) {
    guard let prepared = pendingUpload else { return }
    pendingUpload = nil
    let kind = kind
    Task {
      if await model.upload(prepared, kind: kind, language: language) {
        await onSaved()
      }
    }
  }
#endif

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
          description: Text("No source has images of this kind for this title.")
        )
        if let message = model.saveError {
          Text(verbatim: message)
            .font(.footnote)
            .foregroundStyle(.red)
        }
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
          TitleImageTile(kind: image.kind, previewURL: image.previewURL, isSelected: false,
                         badge: image.source.map(TitleImageSource.badge)) {
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
                         isSelected: file.url == selectedURL,
                         badge: TitleImageSource.badge(file.source ?? "tmdb")) {
            HStack(spacing: 8) {
              if let vote = file.vote {
                Label {
                  Text(vote.formatted(.number.precision(.fractionLength(1))))
                } icon: {
                  Image(systemName: "star.fill")
                }
                .labelStyle(TitleImageCaptionLabelStyle())
              } else if let votes = file.votes, votes > 0 {
                Label {
                  Text(Int(votes).formatted())
                } icon: {
                  Image(systemName: "hand.thumbsup.fill")
                }
                .labelStyle(TitleImageCaptionLabelStyle())
              }
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
  /// The box the picture fills or fits; posters (title and season) are 2:3.
  var boxAspectRatio: CGFloat? = nil
  /// Where the file comes from, on the picture's corner (TMDB, FANART, TVDB, …).
  var badge: String? = nil
  @ViewBuilder let caption: () -> Caption

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: TitleImagePickerMetrics.cornerRadius, style: .continuous)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Color.clear
        .aspectRatio(boxAspectRatio ?? (kind == .poster ? CardAspect.poster.ratio : 16 / 9),
                     contentMode: .fit)
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
        .overlay(alignment: .bottomTrailing) {
          if let badge {
            Text(verbatim: badge)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(.black.opacity(0.55), in: Capsule())
              .padding(TitleImagePickerMetrics.sourceBadgeInset)
              .accessibilityLabel(Text(verbatim: badge))
          }
        }
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

#if os(iOS)
/// Symbol only in a compact width, title and symbol otherwise.
private struct TitleImagePickerToolbarLabelStyle: LabelStyle {
  @Environment(\.horizontalSizeClass) private var sizeClass

  @ViewBuilder
  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    if sizeClass == .compact {
      Label(configuration).labelStyle(.iconOnly)
    } else {
      Label(configuration)
    }
  }
}
#endif

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
  static func minTileWidth(_ kind: WorkerImageAdminKind) -> CGFloat { kind == .poster ? 220 : 360 }
  static func maxTileWidth(_ kind: WorkerImageAdminKind) -> CGFloat { kind == .poster ? 300 : 460 }
#else
  static let horizontalPadding: CGFloat = 16
  static let maxContentWidth: CGFloat = 1_100
  static let sectionSpacing: CGFloat = 24
  static let headerSpacing: CGFloat = 10
  static let gridSpacing: CGFloat = 14
  static let cornerRadius: CGFloat = 10
  static let logoInset: CGFloat = 14
  static func minTileWidth(_ kind: WorkerImageAdminKind) -> CGFloat { kind == .logo || kind == .poster ? 150 : 200 }
  static func maxTileWidth(_ kind: WorkerImageAdminKind) -> CGFloat { kind == .logo || kind == .poster ? 220 : 320 }
#endif
  /// A season poster's tile in `SeasonImageBrowserSheet`.
  static let minPosterWidth: CGFloat = 120
  static let maxPosterWidth: CGFloat = 180
  static let selectionRingGap: CGFloat = 3.5
  static let selectionRingWidth: CGFloat = 3
  static let badgeOffset: CGFloat = 6
#if os(tvOS)
  static let sourceBadgeInset: CGFloat = 12
#else
  static let sourceBadgeInset: CGFloat = 6
#endif
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
  /// The source of the matching file in the lists, when it is one of them.
  var source: String? = nil

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

  /// The source chip picked per kind; none = All.
  private var sourceFilters: [WorkerImageAdminKind: String] = [:]

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
  /// Logos and covers: the app's language first. Cover has no textless bucket.
  func languageOrder(for kind: WorkerImageAdminKind) -> [WorkerArtworkLanguageTag] {
    switch kind {
    case .logo: userLanguage == .en ? [.en, .ru, .und] : [.ru, .en, .und]
    case .cover, .poster: userLanguage == .en ? [.en, .ru] : [.ru, .en]
    case .backdrop: [.und, .en, .ru]
    }
  }

  func currentImages(for kind: WorkerImageAdminKind) -> [TitleImagePickerCurrent] {
    current[kind] ?? []
  }

  func sections(for kind: WorkerImageAdminKind) -> [TitleImagePickerSection] {
    guard let catalog = catalogs[kind] else { return [] }
    let filter = sourceFilter(for: kind)
    return languageOrder(for: kind).compactMap { language in
      let files = Self.ranked(catalog.bucket(language))
        .filter { filter == nil || ($0.source ?? "tmdb") == filter }
      return files.isEmpty ? nil : TitleImagePickerSection(kind: kind, language: language, files: files)
    }
  }

  func sourceFilter(for kind: WorkerImageAdminKind) -> String? {
    sourceFilters[kind]
  }

  func setSourceFilter(_ source: String?, for kind: WorkerImageAdminKind) {
    sourceFilters[kind] = source
  }

  /// The sources with files in this kind's lists, in the worker's order, with counts.
  func sourceChips(for kind: WorkerImageAdminKind) -> [TitleImageSourceChip] {
    guard let catalog = catalogs[kind] else { return [] }
    var counts: [String: Int] = [:]
    for language in languageOrder(for: kind) {
      for file in catalog.bucket(language) { counts[file.source ?? "tmdb", default: 0] += 1 }
    }
    let order = catalog.sources.map(\.id)
    let ranked = counts.keys.sorted { lhs, rhs in
      let l = order.firstIndex(of: lhs) ?? .max, r = order.firstIndex(of: rhs) ?? .max
      return l != r ? l < r : lhs < rhs
    }
    return ranked.map { TitleImageSourceChip(source: $0, count: counts[$0] ?? 0) }
  }

  /// Sources the worker could ask with a key it does not have.
  func sourcesNeedingKey(for kind: WorkerImageAdminKind) -> [String] {
    catalogs[kind]?.sources.filter(\.needsKey).map(\.id) ?? []
  }

  func saveKeys(_ keys: [String: String]) async {
    guard let client else { return }
    saveError = nil
    do {
      _ = try await client.saveSourceKeys(keys)
      for kind in Array(catalogs.keys) { await load(kind, force: true) }
    } catch {
      saveError = error.localizedDescription
    }
  }

  func reportUploadError(_ message: String) {
    saveError = message
  }

  /// Uploads the picture to the worker and pins it for `language`, like a link.
  func upload(_ image: TitleImageUpload,
              kind: WorkerImageAdminKind,
              language: WorkerArtworkLanguageTag) async -> Bool {
    guard let client else { return false }
    isSaving = true
    saveError = nil
    defer { isSaving = false }
    do {
      let pinLanguage: WorkerArtworkLanguageTag? = kind.picksPerLanguage ? language : nil
      _ = try await client.upload(kinopubID: target.kinopubID, kind: kind, data: image.data,
                                  contentType: image.contentType, language: pinLanguage,
                                  width: image.width, height: image.height)
      CoverArtwork.refreshTitle(target.kinopubID)
      await load(kind, force: true)
      return true
    } catch {
      saveError = error.localizedDescription
      return false
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
    if kind.picksPerLanguage {
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
      let catalog = try await client.catalog(kinopubID: target.kinopubID, kind: kind, imdb: imdb,
                                             sources: true)
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
    var changed = false
    defer {
      isSaving = false
      if changed { CoverArtwork.refreshTitle(target.kinopubID) }
    }
    do {
      for kind in [WorkerImageAdminKind.logo, .poster, .cover, .backdrop] {
        let selected = selection[kind] ?? [:]
        guard !selected.isEmpty, selected != (pinned[kind] ?? [:]) else { continue }
        for language in languageOrder(for: kind) {
          guard let url = selected[language], url != pinned[kind]?[language] else { continue }
          let file = catalogs[kind].flatMap { catalog in
            languageOrder(for: kind).lazy.flatMap { catalog.bucket($0) }.first { $0.url == url }
          }
          let pinLanguage: WorkerArtworkLanguageTag? = (kind.picksPerLanguage) ? language : nil
          _ = try await client.pick(kinopubID: target.kinopubID, kind: kind, url: url,
                                    language: pinLanguage,
                                    width: file?.width, height: file?.height)
          changed = true
        }
        pinned[kind] = selected
      }
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
      let pinLanguage: WorkerArtworkLanguageTag? = (kind.picksPerLanguage) ? language : nil
      _ = try await client.pick(kinopubID: target.kinopubID, kind: kind, url: url,
                                language: pinLanguage)
      CoverArtwork.refreshTitle(target.kinopubID)
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
    var fileFor: [String: (language: WorkerArtworkLanguageTag, url: String, source: String)] = [:]
    for language in order {
      for file in catalog.bucket(language) {
        fileFor[Self.fileKey(file.url)] = (language, file.url, file.source ?? "tmdb")
      }
    }
    let stored = (catalog.stored ?? []).filter { !Self.isKinopubArt($0.url) }
    func tag(_ lang: String?) -> WorkerArtworkLanguageTag? {
      guard let lang else { return .und }
      return WorkerArtworkLanguageTag(rawValue: lang)
    }

    // What the worker serves: per language a pin, else the first stored file — its list
    // keeps pins first, then its own ranking. Backdrops: the one pin, else a textless one.
    // Covers: per-language pins in artwork.cover; automatic files still come from the
    // catalog buckets (lang-tagged TMDB backdrops).
    var now: [TitleImagePickerCurrent] = []
    if kind.picksPerLanguage {
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
    now = now.map { item in
      var item = item
      item.source = fileFor[Self.fileKey(item.url)]?.source
      return item
    }
    current[kind] = now

    // Pins and the served files, as TMDB files in the grid.
    var pins: [WorkerArtworkLanguageTag: String] = [:]
    var served: [WorkerArtworkLanguageTag: String] = [:]
    for item in now {
      guard let match = fileFor[Self.fileKey(item.url)] else { continue }
      let language = (kind.picksPerLanguage) ? item.language : match.language
      if item.isPinned { pins[language] = match.url }
      served[language] = match.url
    }
    pinned[kind] = pins

    // Start on what is on the title now; a language with nothing stored starts on its
    // most-voted file.
    var chosen = served
    if kind.picksPerLanguage {
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

  /// `…/t/p/original/abc.svg` and `…/abc.png` are one TMDB file. Other sources keep
  /// the whole address: Kinopoisk's files all end in `/orig`.
  static func fileKey(_ url: String) -> String {
    guard let parsed = URL(string: url), parsed.host?.lowercased() == "image.tmdb.org" else { return url }
    return (parsed.lastPathComponent as NSString).deletingPathExtension
  }

  private static func isKinopubArt(_ url: String) -> Bool {
    guard let host = URL(string: url)?.host?.lowercased() else { return false }
    return host.contains("kinopub") || host.contains("kino.pub") || host.contains("staticpop") || host.contains("kino.watch") || host.contains("pushbr") || host.contains("boramoraboom")
  }

  /// Most votes first (usually the right one), then likes, then the larger file.
  static func ranked(_ files: [WorkerImageAdminCandidate]) -> [WorkerImageAdminCandidate] {
    files.sorted { lhs, rhs in
      let lv = lhs.vote ?? 0, rv = rhs.vote ?? 0
      if lv != rv { return lv > rv }
      let lc = lhs.votes ?? 0, rc = rhs.votes ?? 0
      if lc != rc { return lc > rc }
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
  /// Other sources send their own small copy.
  func previewURL(kind: WorkerImageAdminKind) -> URL? {
    if let preview, let url = URL(string: preview) { return url }
    let width = kind == .logo ? "w500" : "w780"
    return URL(string: url.replacingOccurrences(of: "/t/p/original/", with: "/t/p/\(width)/"))
  }

  var voteLabel: String {
    (vote ?? 0).formatted(.number.precision(.fractionLength(1)))
  }

  var isVector: Bool { from?.lowercased() == "svg" }
}

struct TitleImageSourceChip: Identifiable {
  let source: String
  let count: Int

  var id: String { source }
}

/// What the picker calls each worker source.
enum TitleImageSource {
  static func name(_ source: String) -> String {
    switch source {
    case "tmdb": "TMDB"
    case "fanart": "fanart.tv"
    case "tvdb": "TheTVDB"
    case "tvoe": "TVOE"
    case "kinopoisk": String(localized: "Kinopoisk")
    case "wikidata": "Wikidata"
    case "tpdb": "ThePosterDB"
    case "upload": String(localized: "Uploaded")
    case "admin": String(localized: "By Link")
    default: source
    }
  }

  /// The short mark on a tile's corner.
  static func badge(_ source: String) -> String {
    switch source {
    case "fanart": "FANART"
    case "tvdb": "TVDB"
    case "tpdb": "TPDB"
    default: name(source).uppercased()
    }
  }
}

/// A picture read for upload: PNG, JPEG and WebP go as they are, anything else
/// (HEIC from Photos, TIFF, …) is re-encoded as JPEG, the formats the worker takes.
struct TitleImageUpload {
  let data: Data
  let contentType: String
  let width: Int?
  let height: Int?

  init?(data: Data) {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          CGImageSourceGetCount(source) > 0 else { return nil }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    width = properties?[kCGImagePropertyPixelWidth] as? Int
    height = properties?[kCGImagePropertyPixelHeight] as? Int
    let type = (CGImageSourceGetType(source) as String?).flatMap(UTType.init)
    if let type, let mime = type.preferredMIMEType,
       [UTType.png, .jpeg, .webP].contains(type) {
      self.data = data
      self.contentType = mime
      return
    }
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    self.data = output as Data
    self.contentType = "image/jpeg"
  }
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
        CoverArtwork.refreshTitle(target.kinopubID)
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
      Button { actions.refresh(.poster) } label: {
        Label("Refresh Poster", systemImage: "arrow.clockwise")
      }
      Button { actions.refresh(.cover) } label: {
        Label("Refresh Cover", systemImage: "arrow.clockwise")
      }
      Button { actions.refresh(.backdrop) } label: {
        Label("Refresh Backdrop", systemImage: "arrow.clockwise")
      }
      Divider()
      Button(role: .destructive) { actions.forget(.logo) } label: {
        Label("Forget Logo", systemImage: "trash")
      }
      Button(role: .destructive) { actions.forget(.poster) } label: {
        Label("Forget Poster", systemImage: "trash")
      }
      Button(role: .destructive) { actions.forget(.cover) } label: {
        Label("Forget Cover", systemImage: "trash")
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
    let covers = WorkerImageAdminCatalog(
      ok: true, id: "1", kind: "cover", tmdb: "movie/438631",
      ru: [candidate("/ru-cover.jpg", lang: "ru", w: 1920, h: 1080, vote: 4.8)],
      en: [candidate("/jYEW5xZkZk2WTrdbMGAPFuBqbDc.jpg", lang: "en", w: 3840, h: 2160, vote: 5.4)],
      und: [],
      stored: nil
    )
    return TitleImagePickerModel(target: target, userLanguage: .ru,
                                 catalogs: [.logo: logos, .cover: covers, .backdrop: backdrops])
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
