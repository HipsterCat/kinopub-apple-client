import Foundation

/// Which `UserDefaults` a store writes to, for stores used from any thread.
///
/// `UserDefaults` is documented thread safe and not `Sendable`, so a `Sendable` store keeps
/// the name and opens the suite where it uses it. Instances over one name share storage.
public struct DefaultsSuite: Sendable, Hashable {
  private let name: String?

  /// The app's own defaults.
  public static let standard = DefaultsSuite(name: nil)

  /// A suite of its own — what the tests give their stores.
  public static func suite(_ name: String) -> DefaultsSuite { DefaultsSuite(name: name) }

  public var defaults: UserDefaults {
    guard let name, let suite = UserDefaults(suiteName: name) else { return .standard }
    return suite
  }
}
