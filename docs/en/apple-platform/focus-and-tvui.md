# Focus and TVUIKit

## Evergreen

- True layered parallax needs **layered images** (HIG). Flat posters get lift, scale, specular, and
  tilt toward the touch surface — not multi-layer parallax.
- System focus highlight attaches to the first `Image` in a button label by default. `AsyncImage`
  alone often **does not** get it — add explicit `.hoverEffect(.highlight)` (and usually
  `.buttonStyle(.borderless)` for poster lockups).
- **For a focusable *container* on tvOS, reach for `.buttonStyle(.card)` first and write no focus
  code at all.** Apple's own `DestinationVideo` sample does exactly
  `var buttonStyle: some PrimitiveButtonStyle { #if os(tvOS) .card #else .plain #endif }` on every
  card in the app, applies it once to the enclosing stack, and fences `.hoverEffect()` to
  iOS/visionOS. Focus scale, highlight, lift and parallax are system-owned. Everything focusable
  there is a `Button` or `NavigationLink` — including things that are really just focus stops.
- **Corollary, learned the hard way 2026-08-09 (twice): `.hoverEffect(.highlight)` is for controls
  whose label *is* the image.** On a control labelled `icon + text` (rating tiles, vote pills) it
  does the literal thing — scales and shadows the icon alone while the container sits still. The
  hand-rolled `scaleEffect` + `brightness` replacement that followed was functionally right but read
  as non-native; `.card` is the answer, and it makes both the custom style and the row's manual
  focus padding unnecessary. Do not stack `hoverEffect` / `scaleEffect` / `isFocused` branches on
  top of `.card`.
- One focus owner per interactive zone. Prefer layout-driven focus (`focusSection`, `defaultFocus`)
  over hybrid bridges. Avoid `.defaultFocus(..., .userInitiated)` unless you understand the reset.
- **Never bind two sibling views to the same `@FocusState` equals-value.** `.focused($x, equals:
  .same)` on multiple views is ambiguous — the engine can't resolve which one is actually focused.
  Found on-device 2026-08-09 costing a real regression: six `MediaItemHeroView` buttons shared one
  case (`heroOther`), and focus froze dead on Play — not just "couldn't reach that group," genuinely
  stuck, Right and Down both no-ops, on movies with full metadata as much as sparse ones. Menu even
  closed the app instead of popping, because the confused focus state broke the NavigationStack's
  back-context too. One case per focusable view. If it's flagged as a "someday" cleanup item
  somewhere, fix it on sight instead — this one sat in a checklist and cost a misdiagnosed detour
  before anyone traced it. See [detail-page-choreography](../plans/detail-page-choreography.md).
- Simulator focus/remote is provisional; Device Hub hosts the window — there is no separate
  Simulator.app on current Xcode. Escape ≠ Menu.

## TVUIKit inventory

Public tvOS-only framework. "Lockup" in our SwiftUI code still means
`.buttonStyle(.borderless)` + `.hoverEffect` — that is a different thing from `TVLockupView`.
Verified against `AppleTVOS27.0.sdk/System/Library/Frameworks/TVUIKit.framework/Headers`.

**In use (shelves + grids, gated):** `TVPosterView` / `TVCardView` inside one shared
`TVUIKitMediaCollection` (horizontal shelf or vertical grid — same cell, same
`ShelfMetrics` sizing) under `FeatureFlags.tvUIKitPosters` /
`EnvironmentValues.usesTVUIKitPosters`
([`KinoPubUI/Components/TVUIKit/`](../../../Packages/KinoPubUI/Sources/KinoPubUI/Components/TVUIKit/)).
Rivulet pattern: caption nil on `TVPosterView`, overlays as a sibling of the image view with
focus-scale sync + stale-appearance reset. Flag stays **off** until Device Hub focus validation.
A Home shelf is the same poster grid scrolled sideways — not a second card component.

| Type | Availability | What it gives |
| --- | --- | --- |
| `TVPosterView` | tvOS 12 | Image + title + subtitle. Computes the **optimal `focusSizeIncrease` from the image**; overriding it has no visible effect |
| `TVLockupView` (+ `TVLockupViewComponent`) | tvOS 12 | Header / footer that move on focus; `updateAppearanceForLockupViewState:` pushes `.focused` / `.highlighted` into subviews |
| `TVCardView` | tvOS 12 | Floating card lockup; contents respond to focus as one unit |
| `TVCaptionButtonView` | tvOS 12 | Button + caption, knock-out effect, `motionDirection` |
| `TVMediaItemContentConfiguration` | tvOS 15 | The TV-app media cell: image, text, secondaryText, **`playbackProgress`**, **`badgeText` / `badgeProperties`** (incl. `liveContentBadgeProperties`), `overlayView`, `focusedFrameGuide`, `textProperties` / `secondaryTextProperties` (font, color, `transform`). **`+wideCellConfiguration` is the only factory — 16:9, no poster variant exists.** |
| `NSCollectionLayoutSection.orthogonalLayoutSectionForMediaItems` | tvOS 15 | The system's own rail for those cells — item size, gutters, insets, focus room. Use it instead of tuning a flow layout by hand. |
| `TVMonogramContentConfiguration` | tvOS 15 | Person cell: circle, focus motion, localized initials from `personNameComponents` **when `image` is nil**. `+cellConfiguration` is the only factory; `textProperties` / `secondaryTextProperties` (font, color) are the only styling knobs. |
| `TVCollectionViewFullScreenLayout` | tvOS 13 | Full-screen paging layout: `parallaxFactor`, `maskAmount`, `contentBleed`, `cornerRadius`, and `willCenterCellAtIndexPath:` / `didCenterCellAtIndexPath:` delegate callbacks |
| `TVMonogramView`, `TVDigitEntryViewController` | tvOS 12 | Older person monogram view; PIN entry |

Cost, stated honestly: all of it is UIKit. `TVMediaItemContentConfiguration` implies a
`UICollectionView` rail rather than a SwiftUI `LazyHStack`, and every extra bridge is another
focus owner — which is the argument for **one** collection with several sections per page region,
not for staying in SwiftUI.

**Superseding the earlier "do not port every rail" line (user decision, 2026-08-10):** on tvOS,
person / wide-16:9 / poster tiles come from the three system cells, and rails come from
`orthogonalLayoutSectionForMediaItems`. The standard, the rules that follow from it, and the
list of places still deviating live in
[component-catalogue → the tvOS cell standard](../policies/component-catalogue.md#the-tvos-cell-standard).

Still open on top of that standard:

- **`TVCollectionViewFullScreenLayout` for an autoplay hero.** `didCenterCellAtIndexPath:` is a
  system-provided "this card settled in the centre" hook — exactly the trigger a Netflix-style
  autoplaying hero needs, without hand-rolling centre detection, debounce, and fast-scroll
  cancellation. **Needs validation** before committing.
- SwiftUI `.borderless` + `.hoverEffect(.highlight)` remains the path on iOS/macOS, and the
  fallback for tvOS surfaces that are not one of the three cells (buttons, tabs, chrome).

## Project decisions

- **tvOS posters:** one atom — `TVPosterView` cell in `TVUIKitMediaCollection` — for Home shelves
  and Movies/Series/Search/History/Watchlist grids when `FeatureFlags.tvUIKitPosters` is on.
  Same `ShelfMetrics` sizing either orientation. SwiftUI `MediaCardView` is the fallback / other
  platforms.
- Rows screens hand focus to the first banner or shelf card, not the tab bar.
- No inert reserved space above rows (old 560pt featured-preview spacer is gone).
- Detail ambient muted trailer is **off on tvOS** (still + scrims + blurred poster wash). Trailer
  button / real player unchanged. Ambient trailer may return with a dedicated hero pass.
- **Every tvOS state keeps a focus escape path.** This is a platform invariant about the user, not
  a workaround — a dead end on tvOS is unrecoverable, the remote has nowhere else to go. Observed as
  a one-way trap in the reference app (empty below-fold + hero already made non-focusable = no Up,
  no exit):
  1. Do not enter a "scrolled past the hero" state until at least one focusable row exists below.
  2. Do not drop the hero's focusability until focus has actually landed below it. Fading chrome is
     not the same as removing it — `MediaItemHeroView.chromeAlpha` keeps a 0.35 floor precisely so
     Play/More stay in the focus graph.
  3. Empty and error states are **focusable sections with a Retry control**, never an empty list.
     An empty list is a focus dead end, not just a blank area.
- **A detail page leads with what you can play.** The cheapest path on a remote is
  `hero button → playable rail → everything else`, and Apple's own detail pages are ordered that
  way. Episodes / parts / versions / trailers sit directly under the hero as one rail (see
  [component-catalogue](../policies/component-catalogue.md#one-playable-rail-not-one-section-per-content-type));
  related titles, ratings, cast and info follow. Ordering is by what the user can do now, not by
  entity type — a movie is not "the layout with the rail missing".
- **We do not build a focus layer on top of the focus engine.** No focus bridge, no shared
  `@FocusState` case across siblings, no `asyncAfter` focus delays, no hand-rolled focus scale.
  Full list and reasoning: [constraints-and-requirements](../policies/constraints-and-requirements.md).

### Detail page

> Corrected 2026-08-13. The earlier entries here ("hero chrome belongs outside the scrolling
> container", "scroll offset scrubs the material") described one broken SwiftUI attempt and one
> per-frame number, not product rules. Both are void.

- **The artwork layer is behind the scroll; the hero's content is in it.** One connected focus and
  view graph — hero content and the sections below are siblings inside the same scroll. Splitting
  them into independent scroll/focus worlds broke directional continuity *and* the `NavigationStack`
  back-context on 2026-08-09. Parallax, blur and crop belong to the artwork layer, which nothing
  focuses.
- **Two discrete states, not a scrub.** The hero either owns focus or it does not; that flag has
  exactly **one writer** and is derived from focus, never from scroll offset. There is no
  intermediate rest position, and no `washProgress`-style number driving several layers per frame —
  that mechanism keyed the blur to incidental content geometry (it "only worked for series") and
  re-ran the whole page body, shelves included, on every scroll frame.
- **No compact title, no floating header logo** unless navigation chrome requires one.
- No vertical `.viewAligned` on the detail `ScrollView` (it fought section focus).
- Top Shelf is a **later platform-completeness** item — before advanced subtitles, after core catalog
  / shell work. **Needs validation** on entitlement / extension packaging when implemented.

## Superseded

- Hand-rolled `SiriRemoteTilt` / Game Controller joystick fake parallax.

**Reopened:** the passive focus-marquee / autoplaying Home hero was listed here as superseded. The
user has since said the product is heading that way. Treat it as an open design direction, not a
rejected one — see `TVCollectionViewFullScreenLayout` above.

## Pitfalls

- `.buttonStyle(.plain)` commonly kills visible focus.
- Claiming focus bugs fixed from previews or headless simulator alone.
