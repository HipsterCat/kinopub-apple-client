//
//  TVSidebarSandbox.swift
//  KinoPubAppleClient
//
//  DEBUG-only, tvOS-only. A sandbox for the Library sidebar: one plain list, flush with
//  the screen's leading edge, on mock data, and beside it every knob the system offers
//  for it — SwiftUI `List` and UIKit collection-view list, each with its own styles.
//  Flip a knob, look, walk it with the remote. The DEBUG SwiftUI / UIKit tabs that
//  used to sit after Library are gone from the bar (2026-10-07); this file stays as
//  the UILab prototype. `-KINOPUBSidebarSandbox` still seeds knobs if the sandbox
//  is presented from UILab.
//
//  Only knobs that exist on tvOS 26 are here — probed with `swiftc -typecheck` against
//  AppleTVOS27.2.sdk, 2026-09-26. Not on tvOS, so not offered: `listRowSeparator`,
//  `listSectionSeparator`, `listSectionSpacing`, `scrollContentBackground`,
//  `.inset` / `.insetGrouped` / `.sidebar` list styles, `systemFill` colours,
//  UIKit `showsSeparators`, `sidebarCell()`, the `.sidebar` list appearance, cell
//  `focusEffect`, `selectionFollowsFocus`. `listRowSpacing` is tvOS 27 only.
//
//  What was tried before this and dropped, with the reason: `ROADMAP.md`, Library.
//

#if os(tvOS) && DEBUG
import SwiftUI
import UIKit

// MARK: - Knobs

protocol SandboxOption: CaseIterable, Hashable, RawRepresentable
where RawValue == String, AllCases: RandomAccessCollection {}

enum SBSwitch: String, SandboxOption { case on, off }

enum SBEngine: String, SandboxOption {
  case swiftUI, uikit
  var tabTitle: String {
    switch self {
    case .swiftUI: "SwiftUI"
    case .uikit: "UIKit"
    }
  }
}

/// Share of the screen the sidebar takes — a fraction of the container, never points.
enum SBWidth: String, SandboxOption {
  case fifth, quarter, third
  var count: Int {
    switch self {
    case .fifth: 5
    case .quarter: 4
    case .third: 3
    }
  }
}

/// In-app stand-in for Settings › Accessibility › Display › Text Size.
enum SBTextSize: String, SandboxOption {
  case system, xLarge, xxLarge, xxxLarge, ax1, ax3
  var dynamicTypeSize: DynamicTypeSize? {
    switch self {
    case .system: nil
    case .xLarge: .xLarge
    case .xxLarge: .xxLarge
    case .xxxLarge: .xxxLarge
    case .ax1: .accessibility1
    case .ax3: .accessibility3
    }
  }
}

enum SBGrouping: String, SandboxOption { case sections, single }

/// Where the list's leading edge is: on the screen edge (only the list's own row padding
/// in between), or on the safe-area line.
enum SBLeading: String, SandboxOption { case flush, safeArea }
enum SBFolders: String, SandboxOption { case many, one, none }

/// Bookmark folders under Saved — anything but Saved's own `bookmark`.
enum SBFolderGlyph: String, SandboxOption {
  case empty, circle, circleFill, smallCircle, bullet
  var symbol: String? {
    switch self {
    case .empty: nil
    case .circle: "circle"
    case .circleFill: "circle.fill"
    case .smallCircle: "smallcircle.filled.circle"
    case .bullet: "list.bullet"
    }
  }
}

/// How the glyph gets its column: a callout-sized square, SwiftUI's reserved icon width,
/// or whatever the symbol's own width is.
enum SBGlyphBox: String, SandboxOption { case square, reservedWidth, natural }

/// The symbol's own size inside that square — the square stays callout-sized. `caption`
/// is caption1.
enum SBGlyphFont: String, SandboxOption {
  case callout, subheadline, footnote, caption
  var font: Font {
    switch self {
    case .callout: .callout
    case .subheadline: .subheadline
    case .footnote: .footnote
    case .caption: .caption
    }
  }
  var textStyle: UIFont.TextStyle {
    switch self {
    case .callout: .callout
    case .subheadline: .subheadline
    case .footnote: .footnote
    case .caption: .caption1
    }
  }
}

/// What a SwiftUI row is: a `Button`, or a `Menu` whose Select is the primary action (its
/// long-press menu is where per-row actions would go). Either way the control *is* the
/// row — the list's own row background is always cleared, so one layer draws every state.
enum SBRowKind: String, SandboxOption { case button, menu }

enum SBListStyle: String, SandboxOption { case plain, grouped, automatic }

enum SBButtonStyle: String, SandboxOption {
  case automatic, plain, borderless, bordered, borderedProminent, card, glass
}

/// The selected row's system style. `same` = the rows' style, i.e. no selected look.
enum SBSelectedStyle: String, SandboxOption {
  case bordered, borderedProminent, glass, same
}

enum SBBorderShape: String, SandboxOption { case automatic, capsule, roundedRectangle }


enum SBHover: String, SandboxOption { case none, automatic, highlight, lift }

/// The list's padding around each row's content. `zero` makes the control the whole cell
/// — its platter is the row, not a smaller pill inside it.
enum SBRowInsets: String, SandboxOption { case zero, system }

enum SBUIKitAppearance: String, SandboxOption { case plain, grouped }

/// Where the count goes: the value cell's trailing text, a label accessory, or nowhere.
/// `cellDefault` is the cell's own `defaultContentConfiguration()`, count as accessory.
enum SBUIKitContent: String, SandboxOption { case valueCell, labelAccessory, cellDefault, cellNoCount }

/// `system` leaves the cell's background automatic (the system focus platter); `listCell` is
/// `UIBackgroundConfiguration.listCell()` and `clearAtRest` the default one cleared at
/// rest — both explicit, both paint a grey focus platter on tvOS.
enum SBUIKitBackground: String, SandboxOption { case system, listCell, clearAtRest, clear }

struct SidebarSandboxConfig: Equatable {
  // Shared
  var engine: SBEngine = .swiftUI
  var width: SBWidth = .quarter
  var textSize: SBTextSize = .system
  var grouping: SBGrouping = .sections
  var leading: SBLeading = .flush
  var folders: SBFolders = .many
  var folderGlyph: SBFolderGlyph = .circle
  var glyphBox: SBGlyphBox = .square
  var glyphFont: SBGlyphFont = .caption
  var followsFocus: SBSwitch = .on
  var hierarchical: SBSwitch = .on
  var longTitles: SBSwitch = .off
  /// Debug paint: sidebar column yellow, content red, knobs green; row cells outlined
  /// yellow, the control inside each row outlined orange.
  var paint: SBSwitch = .on
  /// Wrap the page in a `NavigationStack`, as the real Library is.
  var stack: SBSwitch = .on
  // SwiftUI
  var rowKind: SBRowKind = .button
  var listStyle: SBListStyle = .grouped
  var buttonStyle: SBButtonStyle = .automatic
  var borderShape: SBBorderShape = .automatic
  var flexibleSizing: SBSwitch = .on
  var selectedStyle: SBSelectedStyle = .bordered
  var hover: SBHover = .none
  var rowInsets: SBRowInsets = .zero
  // UIKit
  var appearance: SBUIKitAppearance = .plain
  var content: SBUIKitContent = .valueCell
  var background: SBUIKitBackground = .system
  var checkmark: SBSwitch = .off

  /// `-KINOPUBSidebarSandbox "key=value,key=value"`.
  static var launchValue: String? {
    UserDefaults.standard.string(forKey: "KINOPUBSidebarSandbox")
  }

  static func fromLaunchArguments() -> Self {
    var config = Self()
    for pair in (launchValue ?? "").split(separator: ",") {
      let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
      guard parts.count == 2 else { continue }
      setters[parts[0]]?(&config, parts[1])
    }
    return config
  }

  private static func set<T: SandboxOption>(_ keyPath: WritableKeyPath<Self, T>)
    -> (inout Self, String) -> Void {
    { config, raw in if let value = T(rawValue: raw) { config[keyPath: keyPath] = value } }
  }

  private static var setters: [String: (inout Self, String) -> Void] { [
    "engine": set(\.engine), "width": set(\.width), "textSize": set(\.textSize),
    "grouping": set(\.grouping), "leading": set(\.leading), "folders": set(\.folders), "folderGlyph": set(\.folderGlyph),
    "glyphBox": set(\.glyphBox), "glyphFont": set(\.glyphFont), "rowKind": set(\.rowKind), "followsFocus": set(\.followsFocus),
    "hierarchical": set(\.hierarchical), "longTitles": set(\.longTitles), "paint": set(\.paint), "stack": set(\.stack),
    "listStyle": set(\.listStyle), "buttonStyle": set(\.buttonStyle),
    "borderShape": set(\.borderShape), "flexibleSizing": set(\.flexibleSizing),
    "selectedStyle": set(\.selectedStyle), "rowInsets": set(\.rowInsets), "hover": set(\.hover),
    "appearance": set(\.appearance), "content": set(\.content),
    "background": set(\.background), "checkmark": set(\.checkmark),
  ] }
}

// MARK: - Mock data

enum SBItem: Hashable {
  case series, movies, saved, folder(Int), history
}

struct SBRow: Hashable {
  let item: SBItem
  let title: String
  let symbol: String?
  let count: String?
}

private enum SBMock {
  static let folders: [(id: Int, title: String, count: Int)] = [
    (1, "хочу посмотреть", 546), (2, "kkk", 1), (3, "maybe", 64),
    (4, "lusya", 48), (5, "plan", 1), (6, "Gosha", 15),
  ]

  /// Series, Movies | Saved (+ its folders) | History. One folder is not a list of
  /// lists: it takes Saved's place under its own name.
  static func groups(for config: SidebarSandboxConfig) -> [[SBRow]] {
    let long = config.longTitles == .on
    let watching = [
      SBRow(item: .series, title: long ? "Сериалы, за которыми я слежу" : "Series",
            symbol: "bell", count: "12"),
      SBRow(item: .movies, title: long ? "Фильмы, которые не досмотрел" : "Movies",
            symbol: "film", count: "3"),
    ]
    let folders: [(id: Int, title: String, count: Int)] = switch config.folders {
    case .many: Self.folders
    case .one: Array(Self.folders.prefix(1))
    case .none: []
    }
    var saved: [SBRow]
    if folders.count == 1, let only = folders.first {
      saved = [SBRow(item: .folder(only.id), title: only.title, symbol: "bookmark",
                     count: "\(only.count)")]
    } else {
      saved = [SBRow(item: .saved, title: long ? "Все списки закладок" : "Saved",
                     symbol: "bookmark",
                     count: folders.isEmpty ? nil : "\(folders.reduce(0) { $0 + $1.count })")]
      saved += folders.map {
        SBRow(item: .folder($0.id), title: $0.title, symbol: config.folderGlyph.symbol,
              count: "\($0.count)")
      }
    }
    let history = [SBRow(item: .history, title: long ? "Недавно смотрели" : "History",
                         symbol: "clock", count: nil)]
    let groups = [watching, saved, history]
    return config.grouping == .sections ? groups : [groups.flatMap { $0 }]
  }
}

extension SBItem {
  var debugName: String {
    switch self {
    case .series: "series"
    case .movies: "movies"
    case .saved: "saved"
    case .folder(let id): "folder \(id)"
    case .history: "history"
    }
  }
}

// MARK: - Page

/// Where focus is on the page, as far as the navigation under test cares. The knobs
/// column is left out on purpose.
enum SBFocus: Hashable {
  case row(SBItem)
  /// The UIKit list as a whole — its rows are UIKit's, not SwiftUI focus targets.
  case uikitList
  case content(Int)
}

/// Three levels, the tab bar being the first: tabs → sidebar → content. Select goes one
/// level in (tab → selected row → content), Menu one level out (content → selected row →
/// tab bar); up/down in the sidebar switches the section, like left/right in the bar.
struct TVSidebarSandbox: View {
  @State private var config: SidebarSandboxConfig
  @State private var selection: SBItem = .series
  @State private var uikitFocused: SBItem?
  @FocusState private var focus: SBFocus?
  @Namespace private var pageScope
  @Environment(\.resetFocus) private var resetFocus

  init(engine: SBEngine) {
    var config = SidebarSandboxConfig.fromLaunchArguments()
    config.engine = engine
    _config = State(initialValue: config)
  }

  var body: some View {
    // In a stack, like the real Library (`RouteStack`). The stack insets its content by
    // the safe area and a child cannot opt out of that from inside — the sidebar column
    // stayed on the safe-area line whatever it ignored — so the stack itself does.
    Group {
      if config.stack == .on {
        NavigationStack { page }
      } else {
        page
      }
    }
    .modifier(SBLeadingModifier(leading: config.leading))
  }

  private var groups: [[SBRow]] { SBMock.groups(for: config) }

  private func paint(_ color: Color) -> Color {
    config.paint == .on ? color.opacity(0.35) : .clear
  }

  private var page: some View {
    HStack(alignment: .top, spacing: 0) {
      sidebar
        .containerRelativeFrame(.horizontal, count: config.width.count, span: 1, spacing: 0)
        .background(paint(.yellow))
        .focusSection()
        // The UIKit list's rows are not SwiftUI focus targets; the list as a whole is
        // the page's default, and resetting focus hands it to UIKit, which picks the
        // selected row (`remembersLastFocusedIndexPath`).
        .prefersDefaultFocus(config.engine == .uikit, in: pageScope)
      SBContent(row: groups.flatMap { $0 }.first { $0.item == selection }, focus: $focus)
        // Takes the rest. Without it the three columns came out narrower than the
        // screen and SwiftUI centred them — 117 pt either side, the sidebar nowhere near
        // the edge whatever safe area it ignored.
        .frame(maxWidth: .infinity)
        .background(paint(.red))
        .focusSection()
        .onExitCommand { returnToSidebar() }
      knobs
        .containerRelativeFrame(.horizontal, count: 3, span: 1, spacing: 0)
        .background(paint(.green))
        .focusSection()
        .onExitCommand { returnToSidebar() }
    }
    .focusScope(pageScope)
    // Down (or Select) from the tab bar lands on the selected row, not on whatever sits
    // under the tab.
    .defaultFocus($focus, .row(selection), priority: .userInitiated)
    .onChange(of: focus) { _, newValue in
      guard case .row(let item)? = newValue, config.followsFocus == .on else { return }
      selection = item
    }
  }

  @ViewBuilder
  private var sidebar: some View {
    Group {
      switch config.engine {
      case .swiftUI:
        SBSwiftUIList(config: config, groups: groups, selection: selection, focus: $focus,
                      onActivate: activate)
      case .uikit:
        SBUIKitList(config: config, groups: groups, selection: $selection,
                    focused: $uikitFocused, onActivate: activate)
          .focused($focus, equals: .uikitList)
      }
    }
    .modifier(SBTextSizeModifier(size: config.textSize))
  }

  /// Select on a row: that section, and focus one level in.
  private func activate(_ item: SBItem) {
    selection = item
    focus = .content(0)
  }

  /// Menu in the content: back to the selected row.
  private func returnToSidebar() {
    switch config.engine {
    case .swiftUI: focus = .row(selection)
    case .uikit:
      focus = .uikitList
      resetFocus(in: pageScope)
    }
  }

  private var focusName: String {
    switch focus {
    case .row(let item)?: item.debugName
    case .content(let index)?: "content \(index + 1)"
    case .uikitList?: uikitFocused?.debugName ?? "uikit list"
    case nil: uikitFocused?.debugName ?? "—"
    }
  }

  /// Settings-shaped: a `Form`, one system `Picker` row per knob.
  private var knobs: some View {
    Form {
      Section {
        Text("selected: \(selection.debugName) · focused: \(focusName)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Section("Shared") {
        picker("Width (of screen)", \.width)
        picker("Text size", \.textSize)
        picker("Grouping", \.grouping)
        picker("Leading edge", \.leading)
        picker("Folders", \.folders)
        picker("Folder glyph", \.folderGlyph)
        picker("Glyph box", \.glyphBox)
        picker("Glyph size", \.glyphFont)
        picker("Selection follows focus", \.followsFocus)
        picker("Primary / secondary / tertiary", \.hierarchical)
        picker("Long titles", \.longTitles)
        picker("Paint containers", \.paint)
        picker("In a NavigationStack", \.stack)
      }
      switch config.engine {
      case .swiftUI:
        Section("SwiftUI List") {
          picker("Row", \.rowKind)
          picker("List style", \.listStyle)
          picker("Button style (rows)", \.buttonStyle)
          picker("Button style (selected row)", \.selectedStyle)
          picker("Border shape", \.borderShape)
          picker("buttonSizing(.flexible)", \.flexibleSizing)
          picker("hoverEffect", \.hover)
          picker("Row insets", \.rowInsets)
        }
      case .uikit:
        Section("UIKit list") {
          picker("Appearance", \.appearance)
          picker("Content", \.content)
          picker("Background", \.background)
          picker("Checkmark on selected", \.checkmark)
        }
      }
    }
  }

  private func picker<T: SandboxOption>(_ title: String,
                                        _ keyPath: WritableKeyPath<SidebarSandboxConfig, T>)
    -> some View {
    Picker(title, selection: Binding(get: { config[keyPath: keyPath] },
                                     set: { config[keyPath: keyPath] = $0 })) {
      ForEach(Array(T.allCases), id: \.self) { option in
        Text(option.rawValue).tag(option)
      }
    }
    // Same as the sidebar: the row's control is the row.
    .modifier(SBRowInsetsModifier(insets: config.rowInsets))
  }
}

/// Stand-in for the section's grid: enough focusable cards to go into and back out of.
private struct SBContent: View {
  let row: SBRow?
  let focus: FocusState<SBFocus?>.Binding

  private var count: Int { min(max(Int(row?.count ?? "") ?? 6, 3), 9) }

  var body: some View {
    ScrollView {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) {
        ForEach(0..<count, id: \.self) { index in
          VStack {
            Button {} label: {
              Rectangle()
                .fill(.fill.tertiary)
                .aspectRatio(2 / 3, contentMode: .fit)
            }
            .buttonStyle(.card)
            .focused(focus, equals: .content(index))
            Text("\(row?.title ?? "") \(index + 1)")
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
               Text((row?.count) ?? "\(row?.count) episodes")
                 .font(.caption2)
                 .foregroundStyle(.tertiary)
                 .lineLimit(1)
          }
        }
      }
      .padding(.horizontal)
    }
//    .scrollClipDisabled()
  }
}

private struct SBLeadingModifier: ViewModifier {
  let leading: SBLeading
  func body(content: Content) -> some View {
    switch leading {
    case .flush: content.ignoresSafeArea(.container, edges: .leading)
    case .safeArea: content
    }
  }
}

private struct SBTextSizeModifier: ViewModifier {
  let size: SBTextSize
  func body(content: Content) -> some View {
    if let dynamicTypeSize = size.dynamicTypeSize {
      content.dynamicTypeSize(dynamicTypeSize)
    } else {
      content
    }
  }
}

/// The callout point size at the current Dynamic Type size — the glyph square's side.
@MainActor
private func calloutPointSize(for traits: UITraitCollection) -> CGFloat {
  UIFont.preferredFont(forTextStyle: .callout, compatibleWith: traits).pointSize
}

// MARK: - SwiftUI engine

private struct SBSwiftUIList: View {
  let config: SidebarSandboxConfig
  let groups: [[SBRow]]
  let selection: SBItem
  let focus: FocusState<SBFocus?>.Binding
  let onActivate: (SBItem) -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var glyphSide: CGFloat {
    calloutPointSize(for: UITraitCollection(
      preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize)))
  }

  var body: some View {
    List {
      ForEach(groups.indices, id: \.self) { index in
        Section {
          ForEach(groups[index], id: \.item) { row in
            rowButton(row)
          }
        }
      }
    }
    .modifier(SBListStyleModifier(style: config.listStyle))
    // A focused row scales past the list's frame; the list must not crop it.
    .scrollClipDisabled()
    // Back in from the content (Left) lands on the selected row, not the nearest one.
    .defaultFocus(focus, .row(selection), priority: .userInitiated)
  }

  private func rowButton(_ row: SBRow) -> some View {
    let isSelected = selection == row.item
    let isFocused = focus.wrappedValue == .row(row.item)
    let label = SBSwiftUILabel(row: row, config: config, glyphSide: glyphSide,
                               isEmphasized: isSelected || isFocused)
    return Group {
      switch config.rowKind {
      case .menu:
        Menu {
          Button("Row actions go here") {}
        } label: {
          label
        } primaryAction: {
          onActivate(row.item)
        }
      case .button:
        Button {
          onActivate(row.item)
        } label: {
          label
        }
      }
    }
    // One style type for every row, so a row changes look without being swapped out
    // from under the focus engine. Focused counts as selected: a row that takes focus
    // is drawn in the selected style from its first frame — before, it arrived in the
    // rows' style (the list's full-width platter) and then switched to the smaller
    // bordered one, which read as the row shrinking.
    .buttonStyle(SBRowButtonStyle(rest: config.buttonStyle, selected: config.selectedStyle,
                                  isSelected: isSelected || isFocused))
    .modifier(SBBorderShapeModifier(shape: config.borderShape))
    .modifier(SBHoverModifier(hover: config.hover))
    .modifier(SBSizingModifier(flexible: config.flexibleSizing == .on))
    .focused(focus, equals: .row(row.item))
    // The control is the row: the list adds no background of its own under it. With
    // paint on, the row cell is outlined (yellow) and the control (orange) — debug only.
    .overlay { if config.paint == .on { Rectangle().stroke(Color.orange, lineWidth: 2) } }
    .listRowBackground(config.paint == .on ? Rectangle().stroke(Color.yellow, lineWidth: 2) : nil)
    .modifier(SBRowInsetsModifier(insets: config.rowInsets))
  }
}

private struct SBSwiftUILabel: View {
  let row: SBRow
  let config: SidebarSandboxConfig
  let glyphSide: CGFloat
  let isEmphasized: Bool

  var body: some View {
    HStack {
      label
      if config.flexibleSizing == .on {
        Spacer(minLength: 0)
      }
      if let count = row.count {
        Text(count)
          .font(.caption)
          .monospacedDigit()
          .modifier(SBForeground(on: config.hierarchical == .on, style: .tertiary))
      }
    }
    .modifier(SBForeground(on: config.hierarchical == .on,
                           style: isEmphasized ? .primary : .secondary))
  }

  @ViewBuilder
  private var label: some View {
    let base = Label {
      Text(row.title)
        .font(.callout)
        .lineLimit(1)
    } icon: {
      glyph
    }
    switch config.glyphBox {
    case .reservedWidth: base.labelReservedIconWidth(glyphSide)
    case .square, .natural: base
    }
  }

  @ViewBuilder
  private var glyph: some View {
    let image = Group {
      if let symbol = row.symbol {
        Image(systemName: symbol).font(config.glyphFont.font)
      } else {
        Color.clear
      }
    }
    switch config.glyphBox {
    case .square: image.frame(width: glyphSide, height: glyphSide)
    case .reservedWidth, .natural: image
    }
  }
}

private struct SBRowInsetsModifier: ViewModifier {
  let insets: SBRowInsets
  func body(content: Content) -> some View {
    switch insets {
    case .zero: content.listRowInsets(EdgeInsets())
    case .system: content
    }
  }
}

private struct SBForeground: ViewModifier {
  let on: Bool
  let style: HierarchicalShapeStyle
  func body(content: Content) -> some View {
    if on { content.foregroundStyle(style) } else { content }
  }
}

private struct SBListStyleModifier: ViewModifier {
  let style: SBListStyle
  func body(content: Content) -> some View {
    switch style {
    case .plain: content.listStyle(.plain)
    case .grouped: content.listStyle(.grouped)
    case .automatic: content.listStyle(.automatic)
    }
  }
}

/// Only system styles, picked per row: the selected row gets `selected`, the rest `rest`.
private struct SBRowButtonStyle: PrimitiveButtonStyle {
  let rest: SBButtonStyle
  let selected: SBSelectedStyle
  let isSelected: Bool

  @ViewBuilder
  func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
    switch (isSelected, selected) {
    case (true, .bordered): BorderedButtonStyle().makeBody(configuration: configuration)
    case (true, .borderedProminent): BorderedProminentButtonStyle().makeBody(configuration: configuration)
    case (true, .glass): GlassButtonStyle().makeBody(configuration: configuration)
    default: restBody(configuration)
    }
  }

  @ViewBuilder
  private func restBody(_ configuration: PrimitiveButtonStyleConfiguration) -> some View {
    switch rest {
    case .automatic: DefaultButtonStyle().makeBody(configuration: configuration)
    case .plain: PlainButtonStyle().makeBody(configuration: configuration)
    case .borderless: BorderlessButtonStyle().makeBody(configuration: configuration)
    case .bordered: BorderedButtonStyle().makeBody(configuration: configuration)
    case .borderedProminent: BorderedProminentButtonStyle().makeBody(configuration: configuration)
    case .card: CardButtonStyle().makeBody(configuration: configuration)
    case .glass: GlassButtonStyle().makeBody(configuration: configuration)
    }
  }
}

private struct SBBorderShapeModifier: ViewModifier {
  let shape: SBBorderShape
  func body(content: Content) -> some View {
    switch shape {
    case .automatic: content.buttonBorderShape(.automatic)
    case .capsule: content.buttonBorderShape(.capsule)
    case .roundedRectangle: content.buttonBorderShape(.roundedRectangle)
    }
  }
}

private struct SBHoverModifier: ViewModifier {
  let hover: SBHover
  func body(content: Content) -> some View {
    switch hover {
    case .none: content
    case .automatic: content.hoverEffect(.automatic)
    case .highlight: content.hoverEffect(.highlight)
    case .lift: content.hoverEffect(.lift)
    }
  }
}

private struct SBSizingModifier: ViewModifier {
  let flexible: Bool
  func body(content: Content) -> some View {
    if flexible { content.buttonSizing(.flexible) } else { content }
  }
}

// MARK: - UIKit engine

private struct SBUIKitList: UIViewControllerRepresentable {
  let config: SidebarSandboxConfig
  let groups: [[SBRow]]
  @Binding var selection: SBItem
  @Binding var focused: SBItem?
  let onActivate: (SBItem) -> Void

  func makeUIViewController(context: Context) -> SBUIKitListController {
    SBUIKitListController()
  }

  func updateUIViewController(_ controller: SBUIKitListController, context: Context) {
    controller.onSelect = { selection = $0 }
    controller.onFocus = { focused = $0 }
    controller.onActivate = onActivate
    controller.update(config: config, groups: groups, selection: selection)
  }
}

private final class SBUIKitListController: UIViewController, UICollectionViewDelegate {
  var onSelect: (SBItem) -> Void = { _ in }
  var onFocus: (SBItem?) -> Void = { _ in }
  var onActivate: (SBItem) -> Void = { _ in }

  private var collectionView: UICollectionView!
  private var dataSource: UICollectionViewDiffableDataSource<Int, SBRow>!
  private var config = SidebarSandboxConfig()
  private var groups: [[SBRow]] = []
  private var selection: SBItem?

  override func loadView() {
    collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    collectionView.backgroundColor = .clear
    collectionView.delegate = self
    // Like the tab bar: coming back in lands on the last focused row, which — selection
    // following focus — is the selected one.
    collectionView.remembersLastFocusedIndexPath = true
    // A focused cell scales past the list's frame; do not crop it.
    collectionView.clipsToBounds = false
    view = collectionView

    let registration = UICollectionView.CellRegistration<UICollectionViewListCell, SBRow> {
      [weak self] cell, _, row in
      guard let self else { return }
      let config = self.config
      cell.configurationUpdateHandler = { cell, state in
        guard let cell = cell as? UICollectionViewListCell else { return }
        cell.contentConfiguration = Self.content(for: row, config: config, state: state,
                                                 base: cell.defaultContentConfiguration())
        // `nil` leaves the cell on its automatic background — the only path that paints
        // tvOS's white focus platter; any explicit configuration, even the default one
        // `updated(for:)`, comes out grey.
        cell.backgroundConfiguration = config.background == .system
          ? nil
          : Self.background(config: config, state: state, base: cell.defaultBackgroundConfiguration())
        cell.accessories = Self.accessories(for: row, config: config, state: state)
        // Debug paint: the cell's frame, outlined.
        cell.layer.borderColor = UIColor.systemYellow.cgColor
        cell.layer.borderWidth = config.paint == .on ? 2 : 0
      }
    }
    dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) {
      collectionView, indexPath, row in
      collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: row)
    }
    let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
      elementKind: UICollectionView.elementKindSectionHeader
    ) { header, _, _ in
      header.contentConfiguration = UIListContentConfiguration.header()
    }
    dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
      collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
    }
  }

  private func makeLayout() -> UICollectionViewCompositionalLayout {
    let appearance: UICollectionLayoutListConfiguration.Appearance =
      config.appearance == .grouped ? .grouped : .plain
    let separated = config.grouping == .sections
    return UICollectionViewCompositionalLayout { index, environment in
      var list = UICollectionLayoutListConfiguration(appearance: appearance)
      list.backgroundColor = .clear
      // Without headers a tvOS list runs its sections together, `.grouped` included; an
      // empty system header is the system's own gap between them.
      list.headerMode = separated && index > 0 ? .supplementary : .none
      return NSCollectionLayoutSection.list(using: list, layoutEnvironment: environment)
    }
  }


  func update(config: SidebarSandboxConfig, groups: [[SBRow]], selection: SBItem) {
    let configChanged = config != self.config
    self.config = config
    self.selection = selection
    // The collection re-applies the window's safe area as content inset even when
    // SwiftUI lays it out under the margin; `.never` leaves only the cells' own margins.
    collectionView.contentInsetAdjustmentBehavior = config.leading == .flush ? .never : .automatic
    if let size = config.textSize.dynamicTypeSize {
      view.traitOverrides.preferredContentSizeCategory = UIContentSizeCategory(size)
    } else if view.traitOverrides.contains(UITraitPreferredContentSizeCategory.self) {
      view.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
    }
    if configChanged {
      collectionView.setCollectionViewLayout(makeLayout(), animated: false)
    }
    if groups != self.groups || configChanged {
      self.groups = groups
      var snapshot = NSDiffableDataSourceSnapshot<Int, SBRow>()
      for (index, group) in groups.enumerated() {
        snapshot.appendSections([index])
        snapshot.appendItems(group, toSection: index)
      }
      // Cells capture the configuration they were registered with; re-dequeue them.
      dataSource.applySnapshotUsingReloadData(snapshot)
    }
    syncSelection()
  }

  private func indexPath(for item: SBItem) -> IndexPath? {
    groups.lazy.flatMap { $0 }.first { $0.item == item }.flatMap { dataSource.indexPath(for: $0) }
  }

  private func syncSelection() {
    guard let selection, let indexPath = indexPath(for: selection) else { return }
    if collectionView.indexPathsForSelectedItems != [indexPath] {
      collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
    }
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard let row = dataSource.itemIdentifier(for: indexPath) else { return }
    onSelect(row.item)
    onActivate(row.item)
  }

  /// `selectionFollowsFocus` does not exist on tvOS; this is the same thing by hand.
  func collectionView(_ collectionView: UICollectionView,
                      didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                      with coordinator: UIFocusAnimationCoordinator) {
    let row = context.nextFocusedIndexPath.flatMap { dataSource.itemIdentifier(for: $0) }
    onFocus(row?.item)
    guard config.followsFocus == .on, let row, let indexPath = context.nextFocusedIndexPath else { return }
    collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
    onSelect(row.item)
  }

  func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
    collectionView.indexPathsForSelectedItems?.first
  }

  // MARK: Cell configuration

  private static func content(for row: SBRow, config: SidebarSandboxConfig,
                              state: UICellConfigurationState,
                              base: UIListContentConfiguration) -> UIListContentConfiguration {
    var content: UIListContentConfiguration = switch config.content {
    case .valueCell: .valueCell()
    case .cellDefault: base
    case .labelAccessory, .cellNoCount: .cell()
    }
    content = content.updated(for: state)
    let traits = state.traitCollection
    let callout = UIFont.preferredFont(forTextStyle: .callout, compatibleWith: traits)

    content.text = row.title
    content.textProperties.font = callout
    content.textProperties.adjustsFontForContentSizeCategory = true
    content.textProperties.numberOfLines = 1
    if config.content == .valueCell {
      content.secondaryText = row.count
      content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1, compatibleWith: traits)
      content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
      content.prefersSideBySideTextAndSecondaryText = true
    }

    // An empty glyph still holds its square, so the titles stay on one line.
    content.image = row.symbol.flatMap { UIImage(systemName: $0) }
      ?? UIImage(systemName: "circle")?.withTintColor(.clear, renderingMode: .alwaysOriginal)
    content.imageProperties.preferredSymbolConfiguration = .init(
      font: .preferredFont(forTextStyle: config.glyphFont.textStyle, compatibleWith: traits))
    if config.glyphBox != .natural {
      content.imageProperties.reservedLayoutSize = CGSize(width: callout.pointSize, height: callout.pointSize)
    }

    // Focused rows keep the system's inverted colours.
    if config.hierarchical == .on, !state.isFocused {
      let color: UIColor = state.isSelected ? .label : .secondaryLabel
      content.textProperties.color = color
      if row.symbol != nil { content.imageProperties.tintColor = color }
      content.secondaryTextProperties.color = .tertiaryLabel
    }
    return content
  }

  private static func background(config: SidebarSandboxConfig,
                                 state: UICellConfigurationState,
                                 base: UIBackgroundConfiguration) -> UIBackgroundConfiguration {
    switch config.background {
    case .system:
      return base.updated(for: state)
    case .listCell:
      return UIBackgroundConfiguration.listCell().updated(for: state)
    case .clearAtRest:
      var background = base.updated(for: state)
      if !state.isSelected, !state.isFocused { background.backgroundColor = .clear }
      return background
    case .clear:
      return UIBackgroundConfiguration.clear()
    }
  }

  private static func accessories(for row: SBRow, config: SidebarSandboxConfig,
                                  state: UICellConfigurationState) -> [UICellAccessory] {
    var accessories: [UICellAccessory] = []
    if config.content == .labelAccessory || config.content == .cellDefault, let count = row.count {
      let font = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: state.traitCollection)
      accessories.append(.label(text: count, options: .init(font: font, adjustsFontForContentSizeCategory: true)))
    }
    if config.checkmark == .on, state.isSelected {
      accessories.append(.checkmark())
    }
    return accessories
  }
}

#Preview("Sidebar sandbox — SwiftUI") {
  TVSidebarSandbox(engine: .swiftUI)
}
#endif
