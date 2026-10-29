//
//  MediaItemWorkerAdminView.swift
//

import SwiftUI
import KinoPubUI
import KinoPubMetadata
import KinoPubBackend
import KinoPubLogging

/// TMDB proxy admin: routes, KV picks, forget / refresh / catalog / pick.
struct MediaItemWorkerAdminView: View {
  let item: MediaItem
  let images: TitleImageRoute
  let overlayTMDBId: Int?
  /// Same partner line as the hero (`heroTitlePartnerLine`) for subtitle preview.
  let logoPartnerLine: String?
  let onArtworkChanged: () -> Void
  /// Drops this title's pictures and metadata on the device, then reloads them.
  let onResetLocalCache: () async -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var model = WorkerAdminPanelModel()
  @State private var catalogKind: WorkerImageAdminKind?
#if os(tvOS)
  @FocusState private var tvFocus: TVAdminFocus?
  @State private var catalogScrollPosition = ScrollPosition(edge: .top)
  @State private var catalogScrollGeometry = ScrollPage.Geometry()
#endif

  private var client: WorkerImageAdminClient? {
    WorkerImageAdminTokenStore.client(proxyBaseURL: images.baseURL)
  }

  private var imdbHint: String? {
    guard let imdb = item.imdb else { return nil }
    return TMDBIDFormatter.imdbString(from: imdb)
  }

  private var logoRequestURL: URL? {
    images.logo(kinopubID: item.id, imdb: item.imdb, width: ArtworkPixelWidth.logo)
  }

  private var backdropRequestURL: URL? {
    images.backdrop(kinopubID: item.id, imdb: item.imdb, width: ArtworkPixelWidth.backdrop)
  }

  var body: some View {
    Group {
#if os(tvOS)
      tvPanel
#else
      InfoPopupView(title: Text("Worker images"), subtitle: subtitle, confirmTitle: Text("Close")) {
        Group {
          if let kind = catalogKind {
            ScrollView(.vertical) {
              handheldCatalogContent(kind: kind)
                .padding(.vertical, 4)
            }
          } else {
            adminHomeBody
          }
        }
      }
#endif
    }
    .task {
      await model.verifyAdminAccess(using: client)
      await model.refreshStats(using: client)
      await model.probeRoutes(
        logo: logoRequestURL,
        backdrop: backdropRequestURL,
        acceptLanguage: workerHTTPAcceptLanguage
      )
    }
  }

  /// Same signal the worker contract expects; matches ``TitleImageRoute`` (ru default, not device locale).
  private var workerHTTPAcceptLanguage: String {
    images.language == "en" ? "en-US,en;q=0.9" : "ru"
  }

#if os(tvOS)
  /// `InfoPopupView` on tvOS is one scroll focus stop — buttons inside never focus.
  /// Interactive admin uses the same glass panel with real `.card` controls.
  private enum TVAdminFocus: Hashable {
    case firstAction
    case catalogBack
    case done
    case galleryPick(String)
  }

  private var tvPanel: some View {
    ZStack {
      Color.black.opacity(InfoPopupMetrics.scrimOpacity)
        .ignoresSafeArea()
      VStack(spacing: 0) {
        Group {
          if let kind = catalogKind {
            tvCatalogScreen(kind: kind)
          } else {
            ScrollView(.vertical) {
              tvHomeBody
                .padding(WorkerAdminTVMetrics.panelPadding)
            }
          }
        }
        .frame(
          maxWidth: catalogKind == nil ? InfoPopupMetrics.maxWidth : .infinity,
          maxHeight: .infinity,
          alignment: .top
        )
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(catalogKind == nil ? WorkerAdminTVMetrics.outerPadding : WorkerAdminTVMetrics.catalogOuterPadding)
      .glassEffect(
        .regular,
        in: RoundedRectangle(cornerRadius: InfoPopupMetrics.cornerRadius, style: .continuous)
      )
    }
    .onExitCommand {
      if catalogKind != nil {
        catalogKind = nil
        tvFocus = .firstAction
      } else {
        dismiss()
      }
    }
    .defaultFocus($tvFocus, .firstAction, priority: .userInitiated)
  }

  private var tvHomeBody: some View {
    VStack(alignment: .leading, spacing: WorkerAdminTVMetrics.sectionSpacing) {
      tvAdminAccessBanner
      tvRouteSummary
      tvActionsSection
      if let message = model.statusMessage {
        Text(message)
          .font(WorkerAdminTVMetrics.secondaryFont)
          .foregroundStyle(.secondary)
      }
      Button("Done") { dismiss() }
        .buttonStyle(.card)
        .focused($tvFocus, equals: .done)
        .workerAdminTVButtonLabel()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func tvCatalogScreen(kind: WorkerImageAdminKind) -> some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: WorkerAdminTVMetrics.catalogSectionSpacing) {
        Button("Back") {
          catalogKind = nil
          tvFocus = .firstAction
        }
        .buttonStyle(.card)
        .focused($tvFocus, equals: .catalogBack)
        .workerAdminTVButtonLabel(fullWidth: false)
        .focusSection()
        tvCatalogHeader(kind: kind)
        if model.isLoadingCatalog {
          ProgressView()
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
        } else {
          Text("WorkerAdmin_CatalogGridHint")
            .font(WorkerAdminTVMetrics.secondaryFont)
            .foregroundStyle(.secondary)
          catalogRows(kind: kind)
            .focusSection()
          catalogServingStrip(kind: kind)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, WorkerAdminTVMetrics.catalogHorizontalPadding)
      .padding(.vertical, WorkerAdminTVMetrics.catalogVerticalPadding)
    }
    .scrollPosition($catalogScrollPosition)
    .onScrollGeometryChange(for: ScrollPage.Geometry.self) {
      ScrollPage.Geometry(
        offset: $0.contentOffset.y,
        viewport: $0.containerSize.height,
        content: $0.contentSize.height
      )
    } action: { _, geometry in
      catalogScrollGeometry = geometry
    }
    .onMoveCommand { direction in
      guard let target = ScrollPage.target(of: catalogScrollGeometry, direction: direction) else { return }
      withAnimation(.easeOut(duration: 0.28)) {
        catalogScrollPosition.scrollTo(y: target)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder
  private func tvCatalogHeader(kind: WorkerImageAdminKind) -> some View {
    catalogScreenHeader(kind: kind)
  }

  private func firstGalleryPickID(kind: WorkerImageAdminKind) -> String? {
    let catalog = kind == .logo ? model.logoCatalog : model.backdropCatalog
    guard let catalog else { return nil }
    for tag in [WorkerArtworkLanguageTag.ru, .en, .und] {
      if let file = catalog.bucket(tag).first { return file.id }
    }
    return nil
  }

  private func focusFirstGalleryItem(kind: WorkerImageAdminKind) {
    if let id = firstGalleryPickID(kind: kind) {
      tvFocus = .galleryPick(id)
      catalogScrollPosition.scrollTo(edge: .top)
    } else {
      tvFocus = .catalogBack
    }
  }

  @ViewBuilder
  private var tvAdminAccessBanner: some View {
    switch model.tokenStatus {
    case .unknown:
      HStack(spacing: 12) {
        ProgressView()
        Text("WorkerAdmin_TokenChecking")
          .font(WorkerAdminTVMetrics.secondaryFont)
          .foregroundStyle(.secondary)
      }
    case .ok:
      Label("WorkerAdmin_TokenOK", systemImage: "checkmark.seal.fill")
        .font(.headline)
        .foregroundStyle(.green)
    case .failed(let message):
      VStack(alignment: .leading, spacing: 8) {
        Label("WorkerAdmin_TokenFailedTitle", systemImage: "xmark.octagon.fill")
          .font(.headline)
          .foregroundStyle(.red)
        Text(message)
          .font(WorkerAdminTVMetrics.secondaryFont)
          .foregroundStyle(.red)
        Text("WorkerAdmin_TokenFailedHint")
          .font(InfoPopupMetrics.captionFont)
          .foregroundStyle(.secondary)
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
  }

  /// Pinned readout — final URLs stay visible without scrolling past six buttons.
  private var tvRouteSummary: some View {
    VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Worker images")
          .font(InfoPopupMetrics.titleFont)
          .foregroundStyle(Color.KinoPub.text)
        subtitle
          .font(InfoPopupMetrics.subtitleFont)
          .foregroundStyle(.secondary)
      }
      Text("Final image URLs")
        .font(InfoPopupMetrics.sectionFont)
        .foregroundStyle(Color.KinoPub.text)
      Text(verbatim: "Accept-Language: \(workerHTTPAcceptLanguage) · route \(images.language ?? "ru-first")")
        .font(InfoPopupMetrics.captionFont)
        .foregroundStyle(.secondary)
      tvFinalURLRow(kind: .logo, probe: model.logoProbe, request: logoRequestURL)
      tvFinalURLRow(kind: .backdrop, probe: model.backdropProbe, request: backdropRequestURL)
      tvAdminButton("Re-probe redirects", focus: .firstAction) {
        await model.probeRoutes(
          logo: logoRequestURL,
          backdrop: backdropRequestURL,
          acceptLanguage: workerHTTPAcceptLanguage
        )
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private enum TVFinalURLKind {
    case logo
    case backdrop

    var label: String {
      switch self {
      case .logo: "Logo"
      case .backdrop: "Backdrop"
      }
    }
  }

  @ViewBuilder
  private func tvFinalURLRow(kind: TVFinalURLKind, probe: WorkerRouteProbe?, request: URL?) -> some View {
    let label = kind.label
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(label)
          .font(InfoPopupMetrics.sectionFont)
        if let lang = probe?.language {
          Text(lang.rawValue.uppercased())
            .font(InfoPopupMetrics.captionFont.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.fill.tertiary, in: Capsule())
        }
        if let code = probe?.statusCode {
          Text("HTTP \(code)")
            .font(InfoPopupMetrics.captionFont)
            .foregroundStyle(.secondary)
        }
      }
      if probe?.isLoading == true {
        ProgressView()
      } else if let error = probe?.error {
        Text(error)
          .font(InfoPopupMetrics.bodyFont)
          .foregroundStyle(.red)
      } else if let final = probe?.servedURL {
        Text(verbatim: final.absoluteString)
          .font(InfoPopupMetrics.bodyFont.monospaced())
          .foregroundStyle(Color.KinoPub.text)
          .fixedSize(horizontal: false, vertical: true)
        if probe?.didRedirect == false {
          Text("Same as request — worker did not redirect (missing art or error).")
            .font(InfoPopupMetrics.captionFont)
            .foregroundStyle(.orange)
        }
        switch kind {
        case .logo:
          if let lang = probe?.language {
            logoDeliveryNotes(lang)
          }
        case .backdrop:
          Text("WorkerAdmin_BackdropUndNote")
            .font(InfoPopupMetrics.captionFont)
            .foregroundStyle(.secondary)
        }
      } else if let request {
        Text(verbatim: request.absoluteString)
          .font(InfoPopupMetrics.captionFont.monospaced())
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private func logoDeliveryNotes(_ lang: WorkerArtworkLanguageTag) -> some View {
    let kind = TitleLogoRequestKind(deliveredLanguage: lang)
    if let line = kind.supplementaryUnderLogo(
      localized: item.localizedTitle,
      original: item.originalTitle,
      partner: logoPartnerLine
    ) {
      Text(String(format: String(localized: "WorkerAdmin_HeroSubtitle"), line))
        .font(InfoPopupMetrics.captionFont)
        .foregroundStyle(.secondary)
    } else {
      Text("WorkerAdmin_HeroSubtitleNone")
        .font(InfoPopupMetrics.captionFont)
        .foregroundStyle(.secondary)
    }
  }

  private var tvActionsSection: some View {
    InfoPopupSection(Text("Actions")) {
      VStack(alignment: .leading, spacing: WorkerAdminTVMetrics.buttonSpacing) {
        if client == nil {
          Text("WorkerAdmin_NoToken")
            .font(WorkerAdminTVMetrics.secondaryFont)
            .foregroundStyle(.secondary)
        }
        tvAdminButton("Forget logo") {
          await run { try await $0.forget(kinopubID: item.id, kind: .logo) }
        }
        tvAdminButton("Forget backdrop") {
          await run { try await $0.forget(kinopubID: item.id, kind: .backdrop) }
        }
        tvAdminButton("Refresh logo") {
          await run {
            try await $0.refresh(kinopubID: item.id, kind: .logo, imdb: imdbHint, kinopoisk: item.kinopoisk)
          }
        }
        tvAdminButton("Refresh backdrop") {
          await run {
            try await $0.refresh(kinopubID: item.id, kind: .backdrop, imdb: imdbHint, kinopoisk: item.kinopoisk)
          }
        }
        tvAdminButton("All logos") {
          await openCatalog(.logo)
        }
        tvAdminButton("All backdrops") {
          await openCatalog(.backdrop)
        }
        resetLocalCacheButton
      }
    }
  }

  @ViewBuilder
  private func tvAdminButton(
    _ title: String,
    focus: TVAdminFocus? = nil,
    action: @escaping () async -> Void
  ) -> some View {
    let button = Button(title) {
      Task { await action() }
    }
    .buttonStyle(.card)
    .workerAdminTVButtonLabel()
    .disabled(model.isBusy || client == nil)
    if let focus {
      button.focused($tvFocus, equals: focus)
    } else {
      button
    }
  }
#endif

  private func openCatalog(_ kind: WorkerImageAdminKind) async {
    catalogKind = kind
#if os(tvOS)
    tvFocus = .catalogBack
#endif
    await model.probeRoutes(
      logo: logoRequestURL,
      backdrop: backdropRequestURL,
      acceptLanguage: workerHTTPAcceptLanguage
    )
    await loadCatalog(kind)
#if os(tvOS)
    focusFirstGalleryItem(kind: kind)
#endif
  }

  private var adminHomeBody: some View {
    VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing) {
      adminAccessBanner
      idsSection
      routesSection
      if let message = model.statusMessage {
        Text(message)
          .font(InfoPopupMetrics.captionFont)
          .foregroundStyle(.secondary)
      }
      actionsSection
      statsSection
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func handheldCatalogContent(kind: WorkerImageAdminKind) -> some View {
    VStack(alignment: .leading, spacing: InfoPopupMetrics.contentSpacing) {
      Button("Back") {
        catalogKind = nil
      }
      catalogScreenHeader(kind: kind)
      if model.isLoadingCatalog {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
      } else {
        Text("WorkerAdmin_CatalogGridHint")
          .font(InfoPopupMetrics.captionFont)
          .foregroundStyle(.secondary)
        catalogRows(kind: kind)
        catalogServingStrip(kind: kind)
      }
      if let message = model.statusMessage {
        Text(message)
          .font(InfoPopupMetrics.captionFont)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func catalogScreenHeader(kind: WorkerImageAdminKind) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      switch model.tokenStatus {
      case .ok:
        Label("WorkerAdmin_TokenOK", systemImage: "checkmark.seal.fill")
          .font(InfoPopupMetrics.captionFont)
          .foregroundStyle(.green)
      case .failed(let message):
        Text(message)
          .font(InfoPopupMetrics.captionFont)
          .foregroundStyle(.red)
      case .unknown:
        EmptyView()
      }
      Text("TMDB \(kind.rawValue) catalog")
        .font(InfoPopupMetrics.sectionFont)
        .foregroundStyle(Color.KinoPub.text)
      subtitle
        .font(InfoPopupMetrics.captionFont)
        .foregroundStyle(.secondary)
      if kind == .backdrop {
        Text("WorkerAdmin_BackdropTmdbNote")
          .font(InfoPopupMetrics.captionFont)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var subtitle: Text {
    Text(verbatim: "kino.pub \(item.id)")
  }

  @ViewBuilder
  private var adminAccessBanner: some View {
    switch model.tokenStatus {
    case .unknown:
      EmptyView()
    case .ok:
      Label("WorkerAdmin_TokenOK", systemImage: "checkmark.seal.fill")
        .font(InfoPopupMetrics.captionFont)
        .foregroundStyle(.green)
    case .failed(let message):
      VStack(alignment: .leading, spacing: 6) {
        Label("WorkerAdmin_TokenFailedTitle", systemImage: "xmark.octagon.fill")
          .font(InfoPopupMetrics.sectionFont)
          .foregroundStyle(.red)
        Text(message)
          .font(InfoPopupMetrics.captionFont)
          .foregroundStyle(.red)
        Text("WorkerAdmin_TokenFailedHint")
          .font(InfoPopupMetrics.captionFont)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var idsSection: some View {
    InfoPopupSection(Text("IDs")) {
      adminFact("Kinopub", String(item.id))
      if let imdbHint { adminFact("IMDb", imdbHint) }
      if let kp = item.kinopoisk { adminFact("Kinopoisk", String(kp)) }
      if let overlayTMDBId { adminFact("TMDB (overlay)", String(overlayTMDBId)) }
      if let tmdb = model.catalogTMDB {
        adminFact("TMDB (worker)", tmdb)
      }
      if let rev = model.lastArtRev {
        adminFact("art_rev", String(rev))
      }
    }
  }

  private var routesSection: some View {
    InfoPopupSection(Text("Image routes")) {
      routeProbeBlock(label: "Logo", probe: model.logoProbe, request: logoRequestURL)
      routeProbeBlock(label: "Backdrop", probe: model.backdropProbe, request: backdropRequestURL)
      adminButton("Re-probe redirects") {
        await model.probeRoutes(
          logo: logoRequestURL,
          backdrop: backdropRequestURL,
          acceptLanguage: workerHTTPAcceptLanguage
        )
      }
    }
  }

  private var actionsSection: some View {
    InfoPopupSection(Text("Actions")) {
#if os(tvOS)
      VStack(alignment: .leading, spacing: 12) {
        adminButton("Forget logo") {
          await run { try await $0.forget(kinopubID: item.id, kind: .logo) }
        }
        adminButton("Forget backdrop") { await run { try await $0.forget(kinopubID: item.id, kind: .backdrop) } }
        adminButton("Refresh logo") {
          await run {
            try await $0.refresh(kinopubID: item.id, kind: .logo, imdb: imdbHint, kinopoisk: item.kinopoisk)
          }
        }
        adminButton("Refresh backdrop") {
          await run {
            try await $0.refresh(kinopubID: item.id, kind: .backdrop, imdb: imdbHint, kinopoisk: item.kinopoisk)
          }
        }
        adminButton("All logos") {
          await openCatalog(.logo)
        }
        adminButton("All backdrops") {
          await openCatalog(.backdrop)
        }
      }
      .focusSection()
#else
      HStack(spacing: 12) {
        adminButton("Forget logo") { await run { try await $0.forget(kinopubID: item.id, kind: .logo) } }
        adminButton("Forget backdrop") { await run { try await $0.forget(kinopubID: item.id, kind: .backdrop) } }
      }
      HStack(spacing: 12) {
        adminButton("Refresh logo") {
          await run {
            try await $0.refresh(kinopubID: item.id, kind: .logo, imdb: imdbHint, kinopoisk: item.kinopoisk)
          }
        }
        adminButton("Refresh backdrop") {
          await run {
            try await $0.refresh(kinopubID: item.id, kind: .backdrop, imdb: imdbHint, kinopoisk: item.kinopoisk)
          }
        }
      }
      HStack(spacing: 12) {
        adminButton("All logos") {
          await openCatalog(.logo)
        }
        adminButton("All backdrops") {
          await openCatalog(.backdrop)
        }
      }
      resetLocalCacheButton
#endif
    }
  }

  private var resetLocalCacheButton: some View {
    Button("Reset local cache") {
      Task { await resetLocalCache() }
    }
#if os(tvOS)
    .buttonStyle(.card)
    .workerAdminTVButtonLabel()
#endif
    .disabled(model.isBusy)
  }

  private func resetLocalCache() async {
    model.isBusy = true
    defer { model.isBusy = false }
    await onResetLocalCache()
    model.statusMessage = String(localized: "Local cache cleared for this title.")
  }

  private var statsSection: some View {
    InfoPopupSection(Text("Image stats (worker)")) {
      if model.stats.isEmpty {
        Text("timeout / missing / waited — POST /admin/stats")
          .font(InfoPopupMetrics.captionFont)
          .foregroundStyle(.secondary)
      } else {
        ForEach(model.stats.keys.sorted(), id: \.self) { key in
          adminFact(key, String(model.stats[key] ?? 0))
        }
      }
      adminButton("Refresh stats") { await model.refreshStats(using: client) }
    }
  }

  @ViewBuilder
  private func catalogRows(kind: WorkerImageAdminKind) -> some View {
#if os(tvOS)
    tvCatalogRows(kind: kind)
#else
    iosCatalogRows(kind: kind)
#endif
  }

  @ViewBuilder
  private func iosCatalogRows(kind: WorkerImageAdminKind) -> some View {
    let catalog = kind == .logo ? model.logoCatalog : model.backdropCatalog
    if model.isLoadingCatalog {
      ProgressView()
    } else if let catalog {
      catalogGallery(kind: kind, catalog: catalog, columns: WorkerAdminGalleryMetrics.iosColumns)
    } else {
      Text("No catalog loaded")
        .font(InfoPopupMetrics.bodyFont)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func catalogGallery(
    kind: WorkerImageAdminKind,
    catalog: WorkerImageAdminCatalog,
    columns: [GridItem]
  ) -> some View {
    VStack(alignment: .leading, spacing: WorkerAdminGalleryMetrics.sectionSpacing) {
      ForEach([WorkerArtworkLanguageTag.ru, .en, .und], id: \.self) { tag in
        catalogLanguageSection(
          title: tag.rawValue.uppercased(),
          files: catalog.bucket(tag),
          columns: columns,
          kind: kind,
          language: tag,
          catalog: catalog
        )
      }
      ForEach(catalog.extraLanguageSections, id: \.code) { section in
        catalogLanguageSection(
          title: section.code.uppercased(),
          files: section.files,
          columns: columns,
          kind: kind,
          language: workerArtworkTag(forISO: section.code),
          catalog: catalog
        )
      }
    }
  }

  @ViewBuilder
  private func catalogLanguageSection(
    title: String,
    files: [WorkerImageAdminCandidate],
    columns: [GridItem],
    kind: WorkerImageAdminKind,
    language: WorkerArtworkLanguageTag,
    catalog: WorkerImageAdminCatalog
  ) -> some View {
    Text(title)
      .font(WorkerAdminGalleryMetrics.sectionFont)
      .foregroundStyle(Color.KinoPub.text)
    if files.isEmpty {
      Text(String(format: String(localized: "WorkerAdmin_EmptyLanguageBucket"), title))
        .font(WorkerAdminGalleryMetrics.footerFont)
        .foregroundStyle(.secondary)
    } else {
      catalogGridRows(
        files: files,
        columns: columns,
        kind: kind,
        language: language,
        catalog: catalog
      )
    }
  }

  private func workerArtworkTag(forISO code: String) -> WorkerArtworkLanguageTag {
    switch code.lowercased() {
    case "ru": .ru
    case "en": .en
    default: .und
    }
  }

  @ViewBuilder
  private func catalogGridRows(
    files: [WorkerImageAdminCandidate],
    columns: [GridItem],
    kind: WorkerImageAdminKind,
    language: WorkerArtworkLanguageTag,
    catalog: WorkerImageAdminCatalog
  ) -> some View {
#if os(tvOS)
    let columnCount = max(1, columns.count)
    let rows = stride(from: 0, to: files.count, by: columnCount).map { start in
      Array(files[start..<min(start + columnCount, files.count)])
    }
    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
      HStack(alignment: .top, spacing: WorkerAdminGalleryMetrics.gridSpacing) {
        ForEach(row) { file in
          catalogGalleryTile(file, kind: kind, language: language, catalog: catalog)
            .frame(maxWidth: .infinity)
        }
        if row.count < columnCount {
          Spacer(minLength: 0)
            .frame(maxWidth: .infinity)
        }
      }
    }
#else
    LazyVGrid(columns: columns, spacing: WorkerAdminGalleryMetrics.gridSpacing) {
      ForEach(files) { file in
        catalogGalleryTile(file, kind: kind, language: language, catalog: catalog)
      }
    }
#endif
  }

  @ViewBuilder
  private func catalogServingStrip(kind: WorkerImageAdminKind) -> some View {
    let probe = kind == .logo ? model.logoProbe : model.backdropProbe
    VStack(alignment: .leading, spacing: 10) {
      Text("WorkerAdmin_CurrentOnTitle")
        .font(WorkerAdminGalleryMetrics.sectionFont)
        .foregroundStyle(Color.KinoPub.text)
      if probe?.isLoading == true {
        ProgressView()
      } else if let probe, let url = probe.servedURL {
        catalogServingPreview(url: url, kind: kind)
        HStack(spacing: 12) {
          if let lang = probe.language {
            Text(lang.rawValue.uppercased())
              .font(WorkerAdminGalleryMetrics.badgeFont)
              .foregroundStyle(.secondary)
          }
          if let code = probe.statusCode {
            Text(verbatim: "HTTP \(code)")
              .font(WorkerAdminGalleryMetrics.badgeFont)
              .foregroundStyle(.secondary)
          }
        }
      } else {
        Text("WorkerAdmin_NoServingURL")
          .font(WorkerAdminGalleryMetrics.footerFont)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.top, 8)
  }

  @ViewBuilder
  private func catalogServingPreview(url: URL, kind: WorkerImageAdminKind) -> some View {
    Group {
      if kind == .backdrop {
        Color.black.opacity(0.2)
          .aspectRatio(16 / 9, contentMode: .fit)
          .overlay {
            CachedRemoteImage(url: url, contentMode: .fill) {
              Color.white.opacity(0.08)
            } failure: {
              Color.white.opacity(0.05)
            }
          }
          .clipped()
      } else {
        CachedRemoteImage(url: url, contentMode: .fit) {
          Color.white.opacity(0.08)
        } failure: {
          Color.white.opacity(0.05)
        }
        .frame(maxWidth: .infinity)
        .frame(height: WorkerAdminGalleryMetrics.servingLogoHeight)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: WorkerAdminGalleryMetrics.tileCorner, style: .continuous))
  }

  @ViewBuilder
  private func catalogGalleryTile(
    _ file: WorkerImageAdminCandidate,
    kind: WorkerImageAdminKind,
    language: WorkerArtworkLanguageTag,
    catalog: WorkerImageAdminCatalog
  ) -> some View {
    let highlight = catalogHighlight(file: file, kind: kind, catalog: catalog)
    let previewURL = URL(string: file.url)
    Button {
      Task { await pick(file, kind: kind, language: language) }
    } label: {
      VStack(alignment: .leading, spacing: 0) {
        catalogPreview(url: previewURL, kind: kind)
        catalogTileFooter(file: file, language: language, highlight: highlight)
      }
      .frame(height: WorkerAdminGalleryMetrics.tileHeight(kind: kind))
      .clipShape(RoundedRectangle(cornerRadius: WorkerAdminGalleryMetrics.tileCorner, style: .continuous))
    }
#if os(tvOS)
    .buttonStyle(.card)
    .focused($tvFocus, equals: .galleryPick(file.id))
#endif
    .disabled(model.isBusy || client == nil)
  }

  @ViewBuilder
  private func catalogPreview(url: URL?, kind: WorkerImageAdminKind) -> some View {
    Group {
      if kind == .backdrop {
        Color.black.opacity(0.2)
          .aspectRatio(16 / 9, contentMode: .fit)
          .overlay {
            CachedRemoteImage(url: url, contentMode: .fill) {
              Color.white.opacity(0.08)
            } failure: {
              Color.white.opacity(0.05)
            }
          }
          .clipped()
      } else {
        CachedRemoteImage(url: url, contentMode: .fit) {
          Color.white.opacity(0.08)
        } failure: {
          Color.white.opacity(0.05)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .padding(.vertical, WorkerAdminGalleryMetrics.previewVerticalPadding)
    .padding(.horizontal, WorkerAdminGalleryMetrics.previewHorizontalPadding)
    .frame(maxHeight: .infinity)
  }

  @ViewBuilder
  private func catalogTileFooter(
    file: WorkerImageAdminCandidate,
    language: WorkerArtworkLanguageTag,
    highlight: WorkerAdminCatalogHighlight?
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      if let highlight {
        Text(highlight.label)
          .font(WorkerAdminGalleryMetrics.badgeFont)
          .foregroundStyle(.yellow)
      }
      Text(catalogFooterLine(file: file, language: language))
        .font(WorkerAdminGalleryMetrics.footerFont)
        .foregroundStyle(Color.KinoPub.text)
        .lineLimit(3)
        .multilineTextAlignment(.leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(minHeight: WorkerAdminGalleryMetrics.footerMinHeight, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.vertical, 14)
    .background(Color.black.opacity(0.35))
  }

  private func catalogFooterLine(
    file: WorkerImageAdminCandidate,
    language: WorkerArtworkLanguageTag
  ) -> String {
    var parts = [language.rawValue.uppercased(), file.sizeLabel]
    if let vote = file.vote {
      parts.append(String(format: String(localized: "WorkerAdmin_VoteFormat"), vote))
    }
    if let from = file.from, !from.isEmpty {
      parts.append(from)
    }
    return parts.joined(separator: " · ")
  }

  private func catalogHighlight(
    file: WorkerImageAdminCandidate,
    kind: WorkerImageAdminKind,
    catalog: WorkerImageAdminCatalog
  ) -> WorkerAdminCatalogHighlight? {
    if catalog.stored?.contains(where: { $0.url == file.url }) == true {
      return .pinnedKV
    }
    let served = (kind == .logo ? model.logoProbe?.servedURL : model.backdropProbe?.servedURL)
    if let served,
       let tail = URL(string: file.url)?.lastPathComponent,
       !tail.isEmpty,
       served.absoluteString.contains(tail) {
      return .liveRoute
    }
    return nil
  }

#if os(tvOS)
  @ViewBuilder
  private func tvCatalogRows(kind: WorkerImageAdminKind) -> some View {
    let catalog = kind == .logo ? model.logoCatalog : model.backdropCatalog
    if model.isLoadingCatalog {
      ProgressView()
    } else if let catalog {
      catalogGallery(kind: kind, catalog: catalog, columns: WorkerAdminTVMetrics.catalogColumns)
    } else {
      Text("No catalog loaded")
        .font(WorkerAdminTVMetrics.secondaryFont)
        .foregroundStyle(.secondary)
    }
  }
#endif

  private func routeProbeBlock(label: String, probe: WorkerRouteProbe?, request: URL?) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(InfoPopupMetrics.sectionFont)
      if let request {
        adminFact("Request", request.absoluteString)
      } else {
        adminFact("Request", "—")
      }
      if probe?.isLoading == true {
        ProgressView()
      } else if let probe {
        if let served = probe.servedURL {
          adminFact("Final URL", served.absoluteString)
          if let lang = probe.language {
            adminFact("Served lang", lang.rawValue)
          }
          if let code = probe.statusCode {
            adminFact("HTTP", String(code))
          }
          if probe.didRedirect == false {
            adminFact("Note", "No redirect — same URL as request.")
          }
        } else if let error = probe.error {
          adminFact("Probe", error)
        }
      }
    }
  }

  private func adminFact(_ label: String, _ value: String) -> some View {
    InfoPopupFact(Text(verbatim: label), value: value)
  }

  private func adminButton(_ title: String, action: @escaping () async -> Void) -> some View {
    Button(title) {
      Task { await action() }
    }
#if os(tvOS)
    .buttonStyle(.card)
#endif
    .disabled(model.isBusy || client == nil)
  }

  @discardableResult
  private func run(_ work: (WorkerImageAdminClient) async throws -> WorkerImageAdminActionResponse) async -> Bool {
    guard let client else {
      model.statusMessage = WorkerImageAdminError.unauthorizedOrMissing.localizedDescription
      return false
    }
    model.isBusy = true
    defer { model.isBusy = false }
    do {
      let response = try await work(client)
      model.lastArtRev = response.art_rev
      model.statusMessage = responseMessage(response)
      onArtworkChanged()
      Artwork.clearCaches()
      await model.probeRoutes(
        logo: logoRequestURL,
        backdrop: backdropRequestURL,
        acceptLanguage: workerHTTPAcceptLanguage
      )
      return true
    } catch {
      model.statusMessage = error.localizedDescription
      return false
    }
  }

  private func loadCatalog(_ kind: WorkerImageAdminKind) async {
    guard let client else {
      model.statusMessage = WorkerImageAdminError.unauthorizedOrMissing.localizedDescription
      return
    }
    model.isLoadingCatalog = true
    defer { model.isLoadingCatalog = false }
    do {
      let catalog = try await client.catalog(kinopubID: item.id, kind: kind, imdb: imdbHint)
      model.catalogTMDB = catalog.tmdb
      switch kind {
      case .logo: model.logoCatalog = catalog
      case .backdrop: model.backdropCatalog = catalog
      case .poster: break
      }
      model.statusMessage = "Loaded \(kind.rawValue) from \(catalog.tmdb ?? "TMDB")"
    } catch {
      model.statusMessage = error.localizedDescription
      switch kind {
      case .logo: model.logoCatalog = nil
      case .backdrop: model.backdropCatalog = nil
      case .poster: break
      }
    }
  }

  private func pick(
    _ file: WorkerImageAdminCandidate,
    kind: WorkerImageAdminKind,
    language: WorkerArtworkLanguageTag
  ) async {
    let ok = await run { client in
      switch kind {
      case .logo:
        return try await client.pickLogo(kinopubID: item.id, url: file.url, language: language)
      case .backdrop:
        return try await client.pickBackdrop(kinopubID: item.id, url: file.url)
      case .poster:
        throw WorkerImageAdminError.server("poster pick not wired in UI")
      }
    }
#if os(tvOS)
    if ok {
      await loadCatalog(kind)
      if kind == .logo {
        model.statusMessage = String(localized: "WorkerAdmin_PickLogoSaved")
      } else {
        catalogKind = nil
        tvFocus = .firstAction
      }
    } else {
      await loadCatalog(kind)
    }
#else
    if ok {
      await loadCatalog(kind)
      if kind == .logo {
        model.statusMessage = String(localized: "WorkerAdmin_PickLogoSaved")
      } else {
        catalogKind = nil
      }
    }
#endif
  }

  private func responseMessage(_ response: WorkerImageAdminActionResponse) -> String {
    if let picked = response.picked, !picked.isEmpty {
      return "Pinned: " + picked.values.joined(separator: ", ")
    }
    if let count = response.count {
      return "OK · \(response.kind ?? "kind") count \(count)"
    }
    if let rev = response.art_rev {
      return "OK · art_rev \(rev)"
    }
    return "OK"
  }
}

struct WorkerRouteProbe: Sendable {
  var requestURL: URL
  var servedURL: URL?
  var language: WorkerArtworkLanguageTag?
  var statusCode: Int?
  var didRedirect = false
  var error: String?
  var isLoading = false

  static func loading(_ request: URL) -> WorkerRouteProbe {
    WorkerRouteProbe(requestURL: request, isLoading: true)
  }
}

enum WorkerRouteProber {
  /// Fresh network fetch (no Nuke cache) so the URL after the worker's 302 is visible.
  static func probe(_ requestURL: URL, acceptLanguage: String) async -> WorkerRouteProbe {
    var result = WorkerRouteProbe(requestURL: requestURL)
    do {
      var request = URLRequest(url: requestURL)
      request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
      request.timeoutInterval = 30
      request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
      let activity = NetworkActivity.begin(request)
      defer { NetworkActivity.end(activity) }
      let (_, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        result.error = "No HTTP response"
        return result
      }
      let final = http.url ?? requestURL
      result.servedURL = final
      result.statusCode = http.statusCode
      result.didRedirect = final.absoluteString != requestURL.absoluteString
      let header = http.value(forHTTPHeaderField: "Content-Language")
      result.language = WorkerArtworkLanguageTag.resolved(
        answeredURL: final,
        contentLanguageHeader: header
      )
    } catch {
      result.error = error.localizedDescription
    }
    return result
  }
}

private enum WorkerAdminTokenStatus: Equatable {
  case unknown
  case ok
  case failed(String)
}

private enum WorkerAdminCatalogHighlight {
  case liveRoute
  case workerPick
  case pinnedKV

  var label: LocalizedStringKey {
    switch self {
    case .liveRoute: "WorkerAdmin_HighlightLive"
    case .workerPick: "WorkerAdmin_WorkerPick"
    case .pinnedKV: "WorkerAdmin_HighlightPinned"
    }
  }
}

private enum WorkerAdminGalleryMetrics {
#if os(tvOS)
  static let sectionSpacing: CGFloat = 32
  static let gridSpacing: CGFloat = 24
  static let tileCorner: CGFloat = 16
  static let sectionFont: Font = .title2
  static let footerFont: Font = .subheadline
  static let badgeFont: Font = .caption
  static let previewVerticalPadding: CGFloat = 20
  static let previewHorizontalPadding: CGFloat = 16
  static let footerMinHeight: CGFloat = 76
  static let iosColumns: [GridItem] = []
#else
  static let sectionSpacing: CGFloat = 20
  static let gridSpacing: CGFloat = 16
  static let tileCorner: CGFloat = 12
  static let sectionFont: Font = .headline
  static let footerFont: Font = .caption
  static let badgeFont: Font = .caption2
  static let previewVerticalPadding: CGFloat = 10
  static let previewHorizontalPadding: CGFloat = 8
  static let footerMinHeight: CGFloat = 56
  static let iosColumns: [GridItem] = [
    GridItem(.flexible(), spacing: 16),
    GridItem(.flexible(), spacing: 16),
  ]
#endif

  static func tileHeight(kind: WorkerImageAdminKind) -> CGFloat {
#if os(tvOS)
    kind == .logo ? 300 : 340
#else
    kind == .logo ? 200 : 220
#endif
  }

  static let servingLogoHeight: CGFloat = {
#if os(tvOS)
    96
#else
    72
#endif
  }()
}

@Observable
@MainActor
private final class WorkerAdminPanelModel {
  var statusMessage: String?
  var tokenStatus: WorkerAdminTokenStatus = .unknown
  var isBusy = false
  var isLoadingCatalog = false
  var lastArtRev: Int?
  var catalogTMDB: String?
  var stats: [String: Int] = [:]
  var logoCatalog: WorkerImageAdminCatalog?
  var backdropCatalog: WorkerImageAdminCatalog?
  var logoProbe: WorkerRouteProbe?
  var backdropProbe: WorkerRouteProbe?

  func verifyAdminAccess(using client: WorkerImageAdminClient?) async {
    guard let client else {
      tokenStatus = .failed(String(localized: "WorkerAdmin_NoToken"))
      return
    }
    do {
      _ = try await client.imageStats()
      tokenStatus = .ok
    } catch {
      tokenStatus = .failed(error.localizedDescription)
      statusMessage = error.localizedDescription
    }
  }

  func refreshStats(using client: WorkerImageAdminClient?) async {
    guard let client else {
      tokenStatus = .failed(String(localized: "WorkerAdmin_NoToken"))
      return
    }
    do {
      stats = try await client.imageStats()
      if tokenStatus == .unknown { tokenStatus = .ok }
    } catch {
      tokenStatus = .failed(error.localizedDescription)
      statusMessage = error.localizedDescription
    }
  }

  func probeRoutes(logo: URL?, backdrop: URL?, acceptLanguage: String) async {
    if let logo {
      logoProbe = .loading(logo)
      logoProbe = await WorkerRouteProber.probe(logo, acceptLanguage: acceptLanguage)
    }
    if let backdrop {
      backdropProbe = .loading(backdrop)
      backdropProbe = await WorkerRouteProber.probe(backdrop, acceptLanguage: acceptLanguage)
    }
  }
}

private extension View {
  @ViewBuilder
  func workerAdminURLSelection() -> some View {
#if os(tvOS)
    self
#else
    textSelection(.enabled)
#endif
  }
}

#if os(tvOS)
private enum WorkerAdminTVMetrics {
  static let outerPadding: CGFloat = 40
  static let catalogOuterPadding: CGFloat = 28
  static let panelPadding: CGFloat = 48
  static let catalogHorizontalPadding: CGFloat = 36
  static let catalogVerticalPadding: CGFloat = 32
  static let sectionSpacing: CGFloat = 36
  static let catalogSectionSpacing: CGFloat = 32
  static let buttonSpacing: CGFloat = 20
  static let secondaryFont: Font = .subheadline
  static let catalogColumns: [GridItem] = [
    GridItem(.flexible(), spacing: 24),
    GridItem(.flexible(), spacing: 24),
  ]
}

private struct WorkerAdminTVButtonLabel: ViewModifier {
  var fullWidth: Bool

  func body(content: Content) -> some View {
    content
      .font(.title3)
      .padding(.vertical, 24)
      .padding(.horizontal, 48)
      .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
  }
}

private extension View {
  func workerAdminTVButtonLabel(fullWidth: Bool = true) -> some View {
    modifier(WorkerAdminTVButtonLabel(fullWidth: fullWidth))
  }
}
#endif
