import Foundation

/// Staged Menu ("back") on a catalog page: below the top row, Menu returns there;
/// at the top row it passes through to the tab bar.
///
/// Policy from Rivulet `StagedMenuBack` (`6c5355f`), which itself matches the
/// Apple TV app. Extended so a wrapping grid (Library) counts rows inside one
/// section, not only section index — a rail is one row even when scrolled
/// sideways; a grid's first row is `columns` items.
///
/// This is the decision only. Delivery of the press is the page's
/// `.onExitCommand` / `pressesBegan`, never a window-level interceptor.
public enum StagedMenuBack {
  /// - Parameters:
  ///   - focusedSection: the page section that currently holds focus.
  ///   - focusedItem: item index in that section. `nil` when focus is inside a
  ///     nested row (the Home banner) — treated as that section's first row.
  ///   - topSection: first section that can take focus.
  ///   - firstRowItemCount: how many items make up that section's first row
  ///     (the whole rail, or one grid row of `columns` items).
  public static func shouldReturnToTop(
    focusedSection: Int?,
    focusedItem: Int?,
    topSection: Int,
    firstRowItemCount: Int
  ) -> Bool {
    guard let focusedSection else { return false }
    if focusedSection > topSection { return true }
    if focusedSection < topSection { return false }
    guard let focusedItem else { return false }
    return focusedItem >= max(firstRowItemCount, 1)
  }

  public static func firstRowItemCount(flowIsGrid: Bool, columns: Int, itemCount: Int) -> Int {
    if flowIsGrid {
      return min(max(columns, 1), max(itemCount, 0))
    }
    return max(itemCount, 0)
  }
}
