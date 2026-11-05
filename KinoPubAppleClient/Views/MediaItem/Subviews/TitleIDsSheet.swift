//
//  TitleIDsSheet.swift
//  KinoPubAppleClient
//
//  "Title IDs": the external ids the worker stores for a title, as a form. Save pins
//  the changed ones through `POST /admin/kinopub/{id}/link`; a changed IMDb or TMDB id
//  then re-resolves the title so its pictures and facts come from the right one.
//

import SwiftUI
import KinoPubUI
import KinoPubMetadata

struct TitleIDsSheet: View {
  let target: TitleImagePickerTarget
  let images: TitleImageRoute
  /// After a save that re-resolved the title: drop the device's copies and reload.
  let onSaved: () async -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var phase: Phase = .loading
  @State private var loaded = WorkerTitleIDs(ids: [:], kind: nil)
  @State private var fields: [String: String] = [:]
  @State private var kind = "show"
  @State private var isSaving = false
  @State private var error: String?

  private enum Phase: Equatable { case loading, loaded, failed(String) }

  /// The namespaces the worker's link route accepts, in the form's order.
  private static let namespaces: [(key: String, title: LocalizedStringKey, prompt: String)] = [
    ("imdb", "IMDb", "tt1234567"),
    ("tmdb", "TMDB", "tv/1234 · movie/1234"),
    ("kinopoisk", "Kinopoisk", "1234567"),
    ("myshows", "MyShows", "12345"),
  ]

  private var client: WorkerImageAdminClient? {
    WorkerImageAdminTokenStore.client(proxyBaseURL: images.baseURL)
  }

  private var changes: [String: String] {
    var result: [String: String] = [:]
    for (key, _, _) in Self.namespaces {
      let value = (fields[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty, value != loaded.ids[key]?.value { result[key] = value }
    }
    return result
  }

  var body: some View {
    NavigationStack {
      Form {
        switch phase {
        case .loading:
          ProgressView()
            .frame(maxWidth: .infinity)
        case .failed(let message):
          Section {
            Text(verbatim: message)
              .foregroundStyle(.secondary)
            Button("Try Again") { Task { await load() } }
          }
        case .loaded:
          Section {
            ForEach(Self.namespaces, id: \.key) { namespace in
              idRow(namespace)
            }
            Picker("Type", selection: $kind) {
              Text("Series Kind").tag("show")
              Text("Movie Kind").tag("movie")
            }
          } header: {
            Text(verbatim: "kino.pub \(target.kinopubID)")
          } footer: {
            Text("A changed IMDb or TMDB id downloads the title again; its logo pins are dropped. An empty field keeps the stored id.")
          }
          if let error {
            Section {
              Text(verbatim: error)
                .foregroundStyle(.red)
            }
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Title IDs")
      .sheetInlineNavigationTitle()
#if !os(tvOS)
      .sheetCloseAndSave(close: { closeButton }, save: { saveButton })
#endif
    }
    .task { await load() }
#if os(iOS)
    .presentationDragIndicator(.visible)
#endif
    .macSheetFrame(width: 520, height: 460)
  }

  @ViewBuilder
  private func idRow(_ namespace: (key: String, title: LocalizedStringKey, prompt: String)) -> some View {
    let stored = loaded.ids[namespace.key]
    LabeledContent {
      TextField(namespace.title, text: Binding(
        get: { fields[namespace.key] ?? "" },
        set: { fields[namespace.key] = $0 }
      ), prompt: Text(verbatim: namespace.prompt))
      .labelsHidden()
      .multilineTextAlignment(.trailing)
      .autocorrectionDisabled()
#if os(iOS)
      .textInputAutocapitalization(.never)
#endif
      .monospacedDigit()
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(namespace.title)
        if let method = stored?.method {
          Text(verbatim: method == "manual" ? String(localized: "Set by hand") : method)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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
      Task { await save() }
    } label: {
      SheetConfirmLabel("Save Images")
    }
    .disabled(changes.isEmpty || isSaving || phase != .loaded)
  }

  private func load() async {
    guard let client else {
      phase = .failed(String(localized: "Add the worker admin token in Settings › Advanced."))
      return
    }
    phase = .loading
    do {
      let ids = try await client.titleIDs(kinopubID: target.kinopubID)
      loaded = ids
      fields = ids.ids.mapValues(\.value)
      if let kind = ids.kind, kind == "show" || kind == "movie" { self.kind = kind }
      phase = .loaded
    } catch {
      phase = .failed(error.localizedDescription)
    }
  }

  private func save() async {
    guard let client else { return }
    let changes = changes
    isSaving = true
    error = nil
    defer { isSaving = false }
    do {
      _ = try await client.link(kinopubID: target.kinopubID, ids: changes, kind: kind)
      // New ids only take effect once the worker resolves the title again.
      if changes["imdb"] != nil || changes["tmdb"] != nil {
        let imdb = changes["imdb"] ?? loaded.ids["imdb"]?.value
        _ = try await client.refresh(kinopubID: target.kinopubID, kind: .logo,
                                     imdb: imdb, kinopoisk: (changes["kinopoisk"] ?? loaded.ids["kinopoisk"]?.value).flatMap(Int.init))
        Artwork.clearCaches()
        await onSaved()
      }
      dismiss()
    } catch {
      self.error = error.localizedDescription
    }
  }
}
