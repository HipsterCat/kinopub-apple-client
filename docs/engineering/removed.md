# Removed approaches — do not revive

If you find a comment or a doc referencing these, it is stale. Each was tried here and taken out on purpose.


- `AuthPhase.resolving` / a root splash that waits on `refreshToken` before mounting Tabs — removed
  2026-10-01 for optimistic Keychain launch. Refresh still runs; it does not gate the shell.
- `washProgress` / `onScrollGeometryChange` scroll scrub, `MediaItemHeroScrollDriver`,
  `HeroMaterialBackdropView`, the `ZStack` hero-outside-scroll structure (the hero's *content*
  outside the scroll — the tvOS backdrop behind the tab view is not that), the overlay title logo,
  `MediaItemHeroBackdrop` (pinned still + fold material), `MediaItemFoldSnappingBehavior`, the
  per-section `onSectionFocused` / `reportMediaItemSectionFocus` reporters.
- `focusBridge`-style routing, `SiriRemoteTilt` / Game Controller fake parallax,
  `ExpandableButtonStyle`, `ExpandableLabel`, `RatingTileButtonStyle`, `DetailTileFocusChrome`.
- `MediaItemDetailSheet` / `MediaItemSheetLayout` — replaced by `InfoPopup`, where **the clipped
  content itself is the trigger**, never an `i` button beside it.
- `TVUIKitContinueWatchingCell` as a landscape grid tile — the grid dequeues the same media-item
  cell the rails use.
- Netflix-style Home focus-preview (`showsFeaturedPreview`) and the 560pt reserved spacer.
- Metal `ProgressiveBlur`, page-level `.background(.ultraThickMaterial)`, hand-rolled Button-row
  sidebars, custom `ultraThickMaterial` toolbars.
- The tvOS poster experiment: pinning `TVPosterView.contentSize` + `scaleAspectFill` +
  `clipsToBounds`. Aspect-fill crops 2:3 art, and **clipping the image view kills the parallax** —
  the lockup moves content inside its own frame. Not obvious from the API; do not retry blind.
- `PlexDataStore`-style optimistic Continue Watching mutation from a shelf.
- Home prefetch of `/v1/items/hot`, `/fresh` and `/popular`. Those rows painted only when
  every configured shelf was empty, and the fetch ran on every launch anyway (2026-10-25).
  The Catalog tab still opens a shortcut grid when the viewer asks for one.
- The hand-rolled artwork cache: `TVUIKitRemoteImage`'s private `NSCache`, the `ArtworkFetcher`
  coalescing actor, `preparingThumbnail` downsampling, and `AsyncImage` in `CachedRemoteImage`.
  All four behaviours survive — `Artwork` provides them, on four platforms instead of one.

Known bad, still present, do not polish: `HudToast` (rewrite, don't patch).
