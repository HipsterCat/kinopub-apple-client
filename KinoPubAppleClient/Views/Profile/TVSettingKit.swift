//
//  TVSettingKit.swift
//  KinoPubAppleClient
//
//  tvOS Settings on Apple's own Settings machinery, `TVSettingKit.framework`.
//
//  **Apple API limitation** (tvOS 27.2 simulator, 2026-10-01): the system Settings look —
//  a still preview column on the left, a list that shifts sideways while crossfading on
//  push and pop, the title crossfading in place, Apple's row cells and value pickers — has
//  no public API. SwiftUI's `NavigationStack` and `UINavigationController` both crossfade
//  the whole page, and a hand-built copy of the rest was not good enough. The private
//  framework is what the Settings app itself is built from, so it is used here directly,
//  following github.com/zhrispineda/Settings-tvOS (technique only).
//
//  Everything private stays in this file: classes are resolved by name once, every
//  selector is checked before use, and `TVSettingKit.isAvailable` is false if anything is
//  missing — the caller then shows the SwiftUI Settings instead. Distribution is personal
//  builds and TestFlight, where isolated private API is accepted (AGENTS.md). Re-probe on
//  every new tvOS.
//
//  What is used: `TSKSettingItem` / `TSKSettingGroup` (rows and sections, values bound by
//  KVC through `TSKValueStore`), `TSKViewController` (a page; one runtime subclass supplies
//  its groups and previews), `TSKPreviewViewController` + `TSKVibrantImageView` (the left
//  column), `_TSKSplitViewController` (the two columns and the slide animator).
//

#if os(tvOS)
import SwiftUI
import UIKit
import ObjectiveC

// MARK: - Availability

@MainActor
enum TVSettingKit {
  fileprivate static let itemClass: AnyClass? = resolvedClass("TSKSettingItem")
  fileprivate static let groupClass: AnyClass? = resolvedClass("TSKSettingGroup")
  fileprivate static let viewControllerClass: AnyClass? = resolvedClass("TSKViewController")
  fileprivate static let previewClass: AnyClass? = resolvedClass("TSKPreviewViewController")
  fileprivate static let vibrantImageClass: AnyClass? = resolvedClass("TSKVibrantImageView")
  fileprivate static let splitClass: AnyClass? = resolvedClass("_TSKSplitViewController")

  /// Every class and selector this file calls exists on this OS.
  static let isAvailable: Bool = {
    guard let itemClass, let groupClass, let viewControllerClass, let previewClass,
          let vibrantImageClass, let splitClass else { return false }
    let classSelectors: [(AnyClass, String)] = [
      (itemClass, "titleItemWithTitle:description:representedObject:keyPath:"),
      (itemClass, "toggleItemWithTitle:description:representedObject:keyPath:onTitle:offTitle:"),
      (itemClass, "multiValueItemWithTitle:description:representedObject:keyPath:availableValues:"),
      (itemClass, "textInputItemWithTitle:description:representedObject:keyPath:"),
      (itemClass, "actionItemWithTitle:description:representedObject:keyPath:target:action:"),
      (groupClass, "groupWithTitle:settingItems:"),
    ]
    let instanceSelectors: [(AnyClass, String)] = [
      (itemClass, "setAccessoryTypes:"),
      (itemClass, "setLocalizedValueFormatter:"),
      (itemClass, "setEnabled:"),
      (itemClass, "localizedDescription"),
      (viewControllerClass, "loadSettingGroups"),
      (viewControllerClass, "previewForItemAtIndexPath:"),
      (viewControllerClass, "settingItemAtIndexPath:"),
      (viewControllerClass, "reloadSettings"),
      (viewControllerClass, "defaultIndexPathForPreview"),
      (previewClass, "setContentView:"),
      (previewClass, "setAttributedDescriptionText:"),
      (vibrantImageClass, "initWithImage:identifier:"),
      (splitClass, "initWithNavigationController:"),
    ]
    return classSelectors.allSatisfy { cls, sel in
      (cls as AnyObject).responds(to: NSSelectorFromString(sel))
    } && instanceSelectors.allSatisfy { cls, sel in
      class_getInstanceMethod(cls, NSSelectorFromString(sel)) != nil
    } && TSKPageController.pageClass != nil
  }()

  private static func resolvedClass(_ name: String) -> AnyClass? {
    _ = loadFramework
    return NSClassFromString(name)
  }

  private static let loadFramework: Void = {
    dlopen("/System/Library/PrivateFrameworks/TVSettingKit.framework/TVSettingKit", RTLD_NOW)
  }()
}

// MARK: - Rows and pages, described in Swift

/// One row. The kinds are the system's own rows: each brings its cell, value text and —
/// for choices and text — the editing screen the Settings app uses.
struct TSKRow {
  enum Kind {
    /// Read-only; the value sits on the right.
    case info(value: String)
    /// On / Off, bound to `key` in the page's `TSKValueStore`.
    case toggle(key: String)
    /// Pushes the system's list of `values`, bound to `key`.
    case choice(key: String, values: [NSObject], label: (Any?) -> String?)
    /// Opens the system's text entry screen, bound to `key`.
    case text(key: String)
    /// Select runs it. `pushes` adds the chevron.
    case action(pushes: Bool, perform: () -> Void)
  }

  var title: String
  /// Shown under the preview on the left while the row has focus.
  var description: String?
  var kind: Kind
  var isEnabled = true
  /// The left column's picture for this row; the page's when nil.
  var previewSymbol: String?
}

struct TSKSection {
  var title: String? = nil
  var rows: [TSKRow]
}

/// A page. `sections` is called again on every `reload()`, so it reads current state.
struct TSKPage {
  var title: String?
  /// The left column's picture for rows that do not name their own.
  var previewSymbol: String?
  /// Replaces the picture-and-description preview entirely (About's app plate).
  var customPreview: (@MainActor (_ description: String?) -> UIViewController)?
  /// What the left column shows while no row has focus. Nil leaves TVSettingKit's default.
  var idlePreview: (@MainActor () -> UIViewController)?
  var sections: @MainActor () -> [TSKSection]
}

// MARK: - Values

/// What TVSettingKit reads and writes through KVC. Each key is a getter and a setter onto
/// our own storage (`@AppStorage` keys, models), so nothing is stored twice.
@MainActor
final class TSKValueStore: NSObject {
  private struct Binding {
    let get: () -> Any?
    let set: (Any?) -> Void
  }

  private var bindings: [String: Binding] = [:]
  /// Runs after any write, e.g. to reload pages whose rows depend on the value.
  var didWrite: ((String) -> Void)?

  /// Keys are plain identifiers — a dot would make KVC read it as a key path.
  func bind(_ key: String, get: @escaping () -> Any?, set: @escaping (Any?) -> Void) {
    precondition(!key.contains("."), "TSKValueStore keys cannot contain dots")
    bindings[key] = Binding(get: get, set: set)
  }

  func bindBool(_ key: String, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) {
    bind(key, get: { NSNumber(value: get()) }, set: { value in
      set((value as? NSNumber)?.boolValue ?? false)
    })
  }

  /// Tells TVSettingKit a value changed underneath it.
  func refresh(_ key: String) {
    willChangeValue(forKey: key)
    didChangeValue(forKey: key)
  }

  func refreshAll() {
    bindings.keys.forEach(refresh)
  }

  override nonisolated func value(forKey key: String) -> Any? {
    // TVSettingKit reads values on the main thread; KVC's signature just is not isolated.
    nonisolated(unsafe) var value: Any?
    MainActor.assumeIsolated { value = bindings[key]?.get() }
    return value
  }

  override nonisolated func setValue(_ value: Any?, forKey key: String) {
    nonisolated(unsafe) let value = value
    MainActor.assumeIsolated {
      guard let binding = bindings[key] else { return }
      willChangeValue(forKey: key)
      binding.set(value)
      didChangeValue(forKey: key)
      didWrite?(key)
    }
  }

  override nonisolated class func automaticallyNotifiesObservers(forKey key: String) -> Bool {
    false
  }
}

/// Formats a bound value for the row's right-hand text.
private final class TSKLabelFormatter: Formatter {
  private let label: (Any?) -> String?

  init(label: @escaping (Any?) -> String?) {
    self.label = label
    super.init()
  }

  required init?(coder: NSCoder) { nil }

  override func string(for obj: Any?) -> String? {
    label(obj)
  }

  override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
                               for string: String,
                               errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
    obj?.pointee = string as NSString
    return true
  }
}

// MARK: - Items

/// Builds TVSettingKit items from `TSKRow`s.
@MainActor
private enum TSKItemFactory {
  static func group(_ section: TSKSection, store: TSKValueStore, actions: TSKActionTarget) -> NSObject? {
    let items = section.rows.compactMap { item($0, store: store, actions: actions) }
    let sel = NSSelectorFromString("groupWithTitle:settingItems:")
    return (TVSettingKit.groupClass as AnyObject?)?
      .perform(sel, with: (section.title ?? "") as NSString, with: items as NSArray)?
      .takeUnretainedValue() as? NSObject
  }

  static func item(_ row: TSKRow, store: TSKValueStore, actions: TSKActionTarget) -> NSObject? {
    guard let cls = TVSettingKit.itemClass else { return nil }
    let title = row.title as NSString
    let description = row.description as NSString?
    let item: NSObject?

    switch row.kind {
    case .info(let value):
      // TVSettingKit reads a row's value from `representedObject.keyPath`; a fixed value
      // is a one-key dictionary.
      typealias Make = @convention(c) (AnyClass, Selector, NSString, NSString?, AnyObject?, NSString?) -> NSObject?
      let sel = NSSelectorFromString("titleItemWithTitle:description:representedObject:keyPath:")
      item = call(cls, sel, as: Make.self)?(cls, sel, title, description,
                                             ["value": value] as NSDictionary, "value")
      item?.perform(NSSelectorFromString("setLocalizedValueFormatter:"),
                    with: TSKLabelFormatter { $0 as? String })

    case .toggle(let key):
      typealias Make = @convention(c) (AnyClass, Selector, NSString, NSString?, AnyObject?, NSString?, NSString?, NSString?) -> NSObject?
      let sel = NSSelectorFromString("toggleItemWithTitle:description:representedObject:keyPath:onTitle:offTitle:")
      item = call(cls, sel, as: Make.self)?(cls, sel, title, description, store, key as NSString,
                                             "On".localized as NSString, "Off".localized as NSString)

    case let .choice(key, values, label):
      typealias Make = @convention(c) (AnyClass, Selector, NSString, NSString?, AnyObject?, NSString?, NSArray?) -> NSObject?
      let sel = NSSelectorFromString("multiValueItemWithTitle:description:representedObject:keyPath:availableValues:")
      item = call(cls, sel, as: Make.self)?(cls, sel, title, description, store, key as NSString, values as NSArray)
      item?.perform(NSSelectorFromString("setLocalizedValueFormatter:"), with: TSKLabelFormatter(label: label))

    case .text(let key):
      typealias Make = @convention(c) (AnyClass, Selector, NSString, NSString?, AnyObject?, NSString?) -> NSObject?
      let sel = NSSelectorFromString("textInputItemWithTitle:description:representedObject:keyPath:")
      item = call(cls, sel, as: Make.self)?(cls, sel, title, description, store, key as NSString)

    case let .action(pushes, perform):
      typealias Make = @convention(c) (AnyClass, Selector, NSString, NSString?, AnyObject?, NSString?, AnyObject?, Selector) -> NSObject?
      let sel = NSSelectorFromString("actionItemWithTitle:description:representedObject:keyPath:target:action:")
      item = call(cls, sel, as: Make.self)?(cls, sel, title, description, nil, nil,
                                             actions, #selector(TSKActionTarget.handleAction(_:)))
      if let item {
        actions.register(item, perform: perform)
        // 1 = the disclosure chevron.
        item.setValue(pushes ? 1 : 0, forKey: "accessoryTypes")
      }
    }

    if let item {
      if !row.isEnabled { item.setValue(false, forKey: "enabled") }
      if let symbol = row.previewSymbol {
        objc_setAssociatedObject(item, &TSKKeys.previewSymbol, symbol, .OBJC_ASSOCIATION_COPY_NONATOMIC)
      }
    }
    return item
  }

  private static func call<T>(_ cls: AnyClass, _ sel: Selector, as type: T.Type) -> T? {
    guard let method = class_getClassMethod(cls, sel) else { return nil }
    return unsafeBitCast(method_getImplementation(method), to: type)
  }
}

/// Receives action-item selections and runs the matching closure.
@MainActor
final class TSKActionTarget: NSObject {
  private let actions = NSMapTable<NSObject, TSKClosureBox>.weakToStrongObjects()

  fileprivate func register(_ item: NSObject, perform: @escaping () -> Void) {
    actions.setObject(TSKClosureBox(perform), forKey: item)
  }

  // Not `perform(_:)`: that is NSObject's `performSelector:`, and `#selector` picks it.
  @objc(kinoPubHandleAction:) fileprivate func handleAction(_ sender: Any?) {
    guard let item = sender as? NSObject else { return }
    actions.object(forKey: item)?.run()
  }
}

private final class TSKClosureBox: NSObject {
  let run: () -> Void
  init(_ run: @escaping () -> Void) { self.run = run }
}

private enum TSKKeys {
  nonisolated(unsafe) static var page: UInt8 = 0
  nonisolated(unsafe) static var previewSymbol: UInt8 = 0
}

// MARK: - Previews

@MainActor
enum TSKPreview {
  /// TVSettingKit's own preview: a picture with the row's description under it.
  static func make(contentView: UIView?, description: NSAttributedString?) -> UIViewController? {
    guard let cls = TVSettingKit.previewClass as? UIViewController.Type else { return nil }
    let preview = cls.init(nibName: nil, bundle: nil)
    if let contentView {
      preview.perform(NSSelectorFromString("setContentView:"), with: contentView)
    }
    if let description {
      preview.perform(NSSelectorFromString("setAttributedDescriptionText:"), with: description)
    }
    return preview
  }

  /// The tinted, vibrant symbol the Settings app shows for its own panes.
  static func symbolView(_ symbol: String) -> UIView? {
    let configuration = UIImage.SymbolConfiguration(pointSize: 400, weight: .thin)
    guard let image = UIImage(systemName: symbol, withConfiguration: configuration),
          let cls = TVSettingKit.vibrantImageClass as? UIView.Type else { return nil }
    typealias Init = @convention(c) (AnyObject, Selector, UIImage, NSString) -> UIView?
    let sel = NSSelectorFromString("initWithImage:identifier:")
    guard let method = class_getInstanceMethod(cls, sel),
          let allocated = class_createInstance(cls, 0) as AnyObject? else { return nil }
    return unsafeBitCast(method_getImplementation(method), to: Init.self)(allocated, sel, image, symbol as NSString)
  }

  static func description(_ text: String?) -> NSAttributedString? {
    guard let text, !text.isEmpty else { return nil }
    return NSAttributedString(string: text)
  }
}

// MARK: - Pages

/// A `TSKViewController` whose groups and previews come from a `TSKPage`. TVSettingKit only
/// offers subclassing for that, so one subclass is made at runtime, once.
@MainActor
enum TSKPageController {
  /// The runtime subclass, or nil if TVSettingKit is missing.
  fileprivate static let pageClass: AnyClass? = {
    guard let base = TVSettingKit.viewControllerClass,
          let subclass = objc_allocateClassPair(base, "KinoPubTSKPageController", 0) else {
      return NSClassFromString("KinoPubTSKPageController")
    }

    // TVSettingKit calls both on the main thread.
    let load: @convention(block) (NSObject) -> NSArray = { controller in
      nonisolated(unsafe) let controller = controller
      nonisolated(unsafe) var groups: NSArray = []
      MainActor.assumeIsolated { groups = (box(of: controller)?.groups() ?? []) as NSArray }
      return groups
    }
    let preview: @convention(block) (NSObject, NSIndexPath?) -> UIViewController? = { controller, indexPath in
      nonisolated(unsafe) let controller = controller
      nonisolated(unsafe) let indexPath = indexPath
      nonisolated(unsafe) var preview: UIViewController?
      MainActor.assumeIsolated { preview = box(of: controller)?.preview(for: indexPath, in: controller) }
      return preview
    }
    // With nothing focused TVSettingKit previews its default row (the first). A page with
    // an idle preview answers nil instead, and `preview(for: nil)` shows that.
    let defaultSel = NSSelectorFromString("defaultIndexPathForPreview")
    typealias DefaultIndexPath = @convention(c) (AnyObject, Selector) -> NSIndexPath?
    let inherited = class_getMethodImplementation(base, defaultSel).map {
      unsafeBitCast($0, to: DefaultIndexPath.self)
    }
    let defaultIndexPath: @convention(block) (NSObject) -> NSIndexPath? = { controller in
      nonisolated(unsafe) let controller = controller
      nonisolated(unsafe) var hasIdlePreview = false
      MainActor.assumeIsolated { hasIdlePreview = box(of: controller)?.page.idlePreview != nil }
      return hasIdlePreview ? nil : inherited?(controller, defaultSel)
    }
    class_addMethod(subclass, defaultSel, imp_implementationWithBlock(defaultIndexPath), "@@:")
    class_addMethod(subclass, NSSelectorFromString("loadSettingGroups"),
                    imp_implementationWithBlock(load), "@@:")
    class_addMethod(subclass, NSSelectorFromString("previewForItemAtIndexPath:"),
                    imp_implementationWithBlock(preview), "@@:@")
    objc_registerClassPair(subclass)
    return subclass
  }()

  /// A page controller for `page`. Values bind to `store`; actions run through `actions`.
  static func make(_ page: TSKPage, store: TSKValueStore, actions: TSKActionTarget) -> UIViewController? {
    guard let cls = pageClass as? UIViewController.Type else { return nil }
    let box = TSKPageBox(page: page, store: store, actions: actions)
    // `init` runs `viewDidLoad`-free setup only; the groups are asked for later, so the
    // box has to be attached before the controller is first shown — it is, right here.
    let controller = cls.init()
    objc_setAssociatedObject(controller, &TSKKeys.page, box, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    controller.title = page.title
    return controller
  }

  /// Re-reads the page's sections, e.g. after a value another row depends on changed.
  static func reload(_ controller: UIViewController) {
    guard box(of: controller) != nil else { return }
    controller.perform(NSSelectorFromString("reloadSettings"))
  }

  fileprivate static func box(of controller: NSObject) -> TSKPageBox? {
    objc_getAssociatedObject(controller, &TSKKeys.page) as? TSKPageBox
  }
}

@MainActor
private final class TSKPageBox: NSObject {
  let page: TSKPage
  let store: TSKValueStore
  let actions: TSKActionTarget

  init(page: TSKPage, store: TSKValueStore, actions: TSKActionTarget) {
    self.page = page
    self.store = store
    self.actions = actions
  }

  func groups() -> [NSObject] {
    page.sections().compactMap { TSKItemFactory.group($0, store: store, actions: actions) }
  }

  func preview(for indexPath: NSIndexPath?, in controller: NSObject) -> UIViewController? {
    guard let indexPath else { return page.idlePreview?() }
    let item = controller.perform(NSSelectorFromString("settingItemAtIndexPath:"), with: indexPath)?
      .takeUnretainedValue() as? NSObject
    let description = item?.value(forKey: "localizedDescription") as? String
    if let custom = page.customPreview {
      return custom(description)
    }
    let symbol = item.flatMap { objc_getAssociatedObject($0, &TSKKeys.previewSymbol) as? String }
      ?? page.previewSymbol
    return TSKPreview.make(contentView: symbol.flatMap(TSKPreview.symbolView),
                           description: TSKPreview.description(description))
  }
}

// MARK: - Split container

/// TVSettingKit's two-column container around a navigation stack of pages.
@MainActor
final class TSKSplitHost: NSObject {
  let store = TSKValueStore()
  let actions = TSKActionTarget()
  /// Pages above the root; drives the tab bar.
  var onDepthChange: ((Int) -> Void)?

  private(set) var split: UIViewController?
  private var navigation: UINavigationController?
  private var delegateProxy: TSKNavigationDelegateProxy?

  func makeSplit(root page: TSKPage) -> UIViewController? {
    guard TVSettingKit.isAvailable,
          let root = TSKPageController.make(page, store: store, actions: actions),
          let splitClass = TVSettingKit.splitClass as? UIViewController.Type else { return nil }
    let navigation = UINavigationController(rootViewController: root)
    // alloc + the one designated initializer; an `init` would initialise it twice.
    typealias Init = @convention(c) (AnyObject, Selector, UINavigationController) -> UIViewController?
    let sel = NSSelectorFromString("initWithNavigationController:")
    guard let method = class_getInstanceMethod(splitClass, sel),
          let allocated = class_createInstance(splitClass, 0) as AnyObject?,
          let split = unsafeBitCast(method_getImplementation(method), to: Init.self)(allocated, sel, navigation)
    else { return nil }
    split.loadViewIfNeeded()
    // The split is the navigation delegate (it supplies the slide animator); the proxy
    // forwards everything to it and also reports depth.
    let proxy = TSKNavigationDelegateProxy(target: navigation.delegate as? NSObject) { [weak self] depth in
      self?.onDepthChange?(depth)
    }
    navigation.delegate = proxy
    self.delegateProxy = proxy
    self.navigation = navigation
    self.split = split
    return split
  }

  func push(_ page: TSKPage) {
    guard let controller = TSKPageController.make(page, store: store, actions: actions) else { return }
    navigation?.pushViewController(controller, animated: true)
  }

  /// Full-screen tools (labs, the network log) are presented over the split rather than
  /// pushed into its list column.
  func present(_ controller: UIViewController) {
    controller.modalPresentationStyle = .fullScreen
    split?.present(controller, animated: true)
  }

  func popToRoot() {
    navigation?.popToRootViewController(animated: true)
  }

  /// Rebuilds every page in the stack from current state.
  func reloadPages() {
    navigation?.viewControllers.forEach(TSKPageController.reload)
  }
}

private final class TSKNavigationDelegateProxy: NSObject, UINavigationControllerDelegate {
  // Read by UIKit's message forwarding, which is not isolated; only ever on the main thread.
  nonisolated(unsafe) private weak var target: NSObject?
  private let onDepthChange: (Int) -> Void

  init(target: NSObject?, onDepthChange: @escaping (Int) -> Void) {
    self.target = target
    self.onDepthChange = onDepthChange
  }

  // `willShow`, so the tab bar leaves and returns with the transition, not after it.
  func navigationController(_ navigationController: UINavigationController,
                            willShow viewController: UIViewController,
                            animated: Bool) {
    onDepthChange(navigationController.viewControllers.count - 1)
    (target as? UINavigationControllerDelegate)?
      .navigationController?(navigationController, willShow: viewController, animated: animated)
  }

  override func responds(to aSelector: Selector!) -> Bool {
    super.responds(to: aSelector) || (target?.responds(to: aSelector) ?? false)
  }

  override func forwardingTarget(for aSelector: Selector!) -> Any? {
    target?.responds(to: aSelector) == true ? target : nil
  }
}

/// Puts a `TSKSplitHost` in SwiftUI.
struct TSKSplitView: UIViewControllerRepresentable {
  let host: TSKSplitHost
  let root: TSKPage

  func makeUIViewController(context: Context) -> UIViewController {
    host.makeSplit(root: root) ?? UIViewController()
  }

  func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
#endif
