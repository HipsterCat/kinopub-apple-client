//
//  CollectionsView.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubUI
import KinoPubBackend

/// The full collections browser, pushed from Home's collections row — a paginated
/// list of the curated collections as **rows without covers** (title + size + views),
/// each opening that collection's item grid. `MediaListRowView.backgroundArtURL` is
/// the hook for the planned look where a collection's own art sits behind the row.
struct CollectionsView: View {
  @Environment(ErrorHandler.self) var errorHandler
  @Environment(\.mediaNavigation) private var mediaNavigation
  @StateObject private var model: CollectionsModel

  init(model: @autoclosure @escaping () -> CollectionsModel) {
    _model = StateObject(wrappedValue: model())
  }

  var body: some View {
    @Bindable var errorHandler = errorHandler
    content
      .platformNavigationTitle("Collections")
      .background(Color.KinoPub.background)
      .task { await model.fetch() }
      .refreshable { await model.refresh() }
      .handleError(state: $errorHandler.state)
  }

  @ViewBuilder
  private var content: some View {
    if model.collections.isEmpty && !model.isLoaded {
      LoadingIndicatorView()
    } else if model.collections.isEmpty && model.loadFailed {
      UnavailableView(title: "Couldn't Load",
                      systemImage: "wifi.exclamationmark",
                      message: model.loadError?.userFacingMessage ?? "Check your connection and try again.".localized,
                      retryTitle: "Try Again",
                      onRetry: {
        Task { await model.refresh() }
      })
    } else if model.collections.isEmpty {
      UnavailableView(title: "No Results", systemImage: "rectangle.stack")
    } else {
      list
    }
  }

  private var list: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: Self.rowSpacing) {
        ForEach(model.collections) { collection in
          row(for: collection)
            .onAppear { model.loadMoreIfNeeded(after: collection) }
        }
        PaginationFooter(state: model.paginationState, onRetry: { model.retryPagination() })
      }
      .padding(.horizontal, Self.horizontalInset)
      .padding(.vertical, Self.verticalInset)
    }
#if os(tvOS)
    // A focused row's lift draws outside its frame; the page's edges must not cut it.
    .scrollClipDisabled()
#endif
  }

  @ViewBuilder
  private func row(for collection: Collection) -> some View {
    let label = MediaListRowView(
      title: collection.title,
      meta: meta(for: collection)
      // `backgroundArtURL:` stays nil on purpose — the hook for the collection's own
      // cover (`posters.big`) behind the row, when that design lands.
    )
#if os(tvOS)
    Button {
      mediaNavigation?(Route.collection(collection))
    } label: {
      label
    }
    .buttonStyle(.card)
#else
    NavigationLink(value: Route.collection(collection)) {
      label
    }
    .buttonStyle(.plain)
    .pointingHandCursorOnHover()
#endif
  }

  /// "250 titles · 5.1K views" — whichever of the two the collection carries.
  private func meta(for collection: Collection) -> String? {
    var parts: [String] = []
    if let count = collection.itemsCount, count > 0 {
      parts.append("\(count) \(titlesUnit(count))")
    }
    if let views = collection.views, views > 0 {
      parts.append("\(views.formatted(.number.notation(.compactName))) \("MediaItem_CatalogViews".localized)")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  /// "250 тайтлов" / "250 titles" — the declined unit, per `localizedPluralForm`.
  private func titlesUnit(_ count: Int) -> String {
    switch localizedPluralForm(count) {
    case 0: return "MediaItem_UnitTitleOne".localized
    case 1: return "MediaItem_UnitTitleFew".localized
    default: return "MediaItem_UnitTitleMany".localized
    }
  }

#if os(tvOS)
  private static let rowSpacing: CGFloat = 16
  private static let horizontalInset: CGFloat = 80
  private static let verticalInset: CGFloat = 24
#elseif os(macOS)
  private static let rowSpacing: CGFloat = 8
  private static let horizontalInset: CGFloat = 32
  private static let verticalInset: CGFloat = 12
#else
  private static let rowSpacing: CGFloat = 8
  private static let horizontalInset: CGFloat = 20
  private static let verticalInset: CGFloat = 12
#endif

  static func make(context: AppContextProtocol,
                   authState: AuthState,
                   errorHandler: ErrorHandler) -> CollectionsView {
    CollectionsView(model: CollectionsModel(collectionsService: context.collectionsService,
                                            authState: authState,
                                            errorHandler: errorHandler))
  }
}

struct CollectionsView_Previews: PreviewProvider {
  static var previews: some View {
    NavigationStack {
      CollectionsView(model: CollectionsModel(collectionsService: CollectionsServiceMock(),
                                              authState: AuthState(authService: AuthorizationServiceMock(),
                                                                   accessTokenService: AccessTokenServiceMock()),
                                              errorHandler: ErrorHandler()))
    }
  }
}
