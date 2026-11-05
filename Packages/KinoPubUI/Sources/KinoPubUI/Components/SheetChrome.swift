//
//  SheetChrome.swift
//  KinoPubUI
//
//  Sheet toolbar policy borrowed from AniShelf (`PlatformViewModifiers.swift`,
//  github.com/samuelhe52/AniShelf): the dismiss button sits at `.cancellationAction`
//  with `SheetCloseLabel`, every other button at `.sheetLeading` / `.sheetTrailing`,
//  never at raw `.topBar*` placements. A macOS sheet only shows toolbar items in its
//  cancel and confirm slots, so those two placements become exactly those slots there.
//

import SwiftUI

public extension ToolbarItemPlacement {
  /// A sheet's trailing button: the confirm slot of the Mac sheet's bottom bar.
  static var sheetTrailing: Self {
#if os(macOS)
    .confirmationAction
#elseif os(tvOS)
    .automatic
#else
    .topBarTrailing
#endif
  }

  /// A sheet's leading button, such as Back: the cancel slot on macOS.
  static var sheetLeading: Self {
#if os(macOS)
    .cancellationAction
#elseif os(tvOS)
    .automatic
#else
    .topBarLeading
#endif
  }
}

/// Label for a sheet's dismiss button: a glyph on iOS, the text button macOS sheets use.
public struct SheetCloseLabel: View {
  private let title: LocalizedStringKey

  public init(_ title: LocalizedStringKey = "Close") {
    self.title = title
  }

  public var body: some View {
#if os(iOS)
    Image(systemName: "xmark")
      .accessibilityLabel(Text(title))
#else
    Text(title)
#endif
  }
}

/// Label for a sheet's confirm button: the checkmark iOS 26 sheets use, text on the Mac.
public struct SheetConfirmLabel: View {
  private let title: LocalizedStringKey

  public init(_ title: LocalizedStringKey = "Save") {
    self.title = title
  }

  public var body: some View {
#if os(iOS)
    Image(systemName: "checkmark")
      .accessibilityLabel(Text(title))
#else
    Text(title)
#endif
  }
}

public extension View {
  /// Gives a sheet its desktop size. A macOS sheet opens at its content's ideal size, and
  /// grids and geometry-driven layouts have almost none, so state it. Minimum and maximum
  /// sizes are left to the content and `presentationSizing`.
  @ViewBuilder
  func macSheetFrame(width: CGFloat, height: CGFloat) -> some View {
#if os(macOS)
    frame(idealWidth: width, idealHeight: height)
#else
    self
#endif
  }

  /// Inline title on iOS; the Mac sheet and tvOS have no navigation bar title modes.
  @ViewBuilder
  func sheetInlineNavigationTitle() -> some View {
#if os(iOS)
    navigationBarTitleDisplayMode(.inline)
#else
    self
#endif
  }
}
