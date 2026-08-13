# Apple-native design

Durable UI policy for this multiplatform client. How-tos and API tables live in
[`docs/en/apple-platform/`](../apple-platform/).

## Goal

Look and feel like a stock Apple media app, with a wider feature set. Extend capability, not the
visual vocabulary. Match Apple TV / TV / Music / Journal patterns; steal features from microiptv and
the community fork's backend, not their chrome.

## Platform stance

- Ship a real app on **tvOS, iOS, iPadOS, and macOS**.
- tvOS defines media consumption, focus, and the 10-foot quality bar.
- Each platform uses **its own** native controls: remote focus / lockups on TV, touch gestures on
  iPhone, pointer / sidebar / menus on Mac. Do not force one platform's chrome onto another.
- One app target. Differences live in `#if os(...)` or thin platform bridges.

### Renderers differ by platform, on purpose

> User decision, 2026-08-13. Supersedes any "SwiftUI first everywhere" reading of this document.

| | Renderer | Why |
| --- | --- | --- |
| **tvOS** media surfaces (rails, grids, detail content) | **UIKit + TVUIKit** — `UICollectionView`, the three system cells, `orthogonalLayoutSectionForMediaItems()` | The focus engine, cell reuse, predictable layout and memory all live there. The reference app reached the same conclusion from a performance experiment, not from taste |
| **tvOS** shell, settings, forms, one-off chrome | SwiftUI | Nothing heavy, nothing focus-hostile |
| **iOS / iPadOS / macOS** | SwiftUI, including system navigation transitions (`.navigationTransition(.zoom)`, matched sources) | This is where SwiftUI is strongest and where Apple is investing |

Shared across platforms: **models, services, view models, component semantics, focus priority,
design tokens, assets.** Not shared: view hierarchy, geometry, point values. Apple's own apps do the
same — TV on iPhone and TV on Apple TV share a language, not a view tree. Two renderers for one
semantic component is not a DRY violation; **two components for one idea on one platform is**
(see [component-catalogue](component-catalogue.md)).

TV UI is not touch UI on a big screen. Its primitives are the focus graph, spatial navigation, and
playable intent — not gestures. Mobile-shaped solutions (custom hero-transition libraries,
gesture-driven morphs) do not transfer, and fighting the focus engine with them is where this
codebase already lost time.

**Soft where it has to be.** Rails, grids and cells are settled: system cells in a collection view.
The tvOS **detail page as a whole** — one `UICollectionView` with hero + sections, SwiftUI content
inside cells where it costs nothing — is the direction, not a decree: it is an architecture nobody
can validate from prose, and the user has said as much. Prototype it, look at it, then decide. What
is *not* soft is the direction of travel when SwiftUI and the focus engine disagree on a media
surface: UIKit wins, because it measurably does.

## Control selection order

Start from the question **"which system primitive does Apple provide for this behaviour?"** — not
"how do we reproduce what Apple TV looks like". Only when there is no primitive, and the gap is
named, does anything below step 2 apply. See
[constraints-and-requirements](constraints-and-requirements.md).

1. The stock control **of that platform's renderer** — SwiftUI (`List`, `Form`, `TabView`,
   `NavigationStack`, system buttons, menus, sheets, scroll-edge effects, materials), and on tvOS
   media surfaces the TVUIKit cell / `UICollectionView` equivalent. There, UIKit *is* step 1, not a
   fallback.
2. System UIKit / AppKit / AVKit API through a thin representable / bridge when the platform's own
   renderer cannot express the real system behavior (player, layered images, private filters).
3. Proven pattern from Apple sample code, our reference apps (Rivulet, Silo, IceCubes), or a mature
   library — see [agent-workflow](agent-workflow.md) borrow-before-build.
4. Minimal custom component.

UIKit / AppKit is not a failure of SwiftUI. It is required when the system behavior lives there, or
when Instruments proves SwiftUI cannot hit acceptable focus / layout / performance.

## Custom and private API

- Custom UI needs: the missing system API named, alternatives rejected, and ongoing cost stated.
- Private API (for example `CAFilter` `variableBlur`) is allowed on this personal project when
  isolated behind a thin helper, with availability / fallback and a short decision note.
- Do not sprinkle private symbols through feature views.
- **Distribution is personal builds / TestFlight; App Store review is not a target.** That is what
  keeps private API acceptable. If distribution ever changes, revisit this section first — do not
  quietly ban private API on App Store grounds that do not apply.

## Settled visual decisions

| Topic | Decision |
| --- | --- |
| Appearance | Dark only until the deliberate light-theme stage |
| Accent | White / system; no kino.pub site green |
| Home featured band | Contained 16:9 banner shelf **today**. Not a ban: the user's stated direction is toward a focus-preview / autoplaying hero. Reopen it with prototypes, do not "defend" the current shelf |
| Hero CTAs | White Play pill + translucent circular secondaries — **not** Liquid Glass on hero |
| Blur | Private `variableBlur` over **static** art; **no blur over video on tvOS/macOS**; blur OK over video on iOS/iPadOS |
| Nav / list chrome | Prefer system scroll-edge / materials. No `backgroundExtensionEffect` under sidebar / page shell |
| Contained art bleed | `backgroundExtensionEffect` on a still + own `safeAreaInset` is open (blur axis); prototype before ship |
| Poster focus | tvOS: shared `TVPosterView` atom (shelf + grid) behind `FeatureFlags.tvUIKitPosters`; else SwiftUI `.borderless` + `.hoverEffect` |
| Continue Watching | Long-press context menu; **no** decorative ⋯ button on the card |
| Player | Native `AVPlayerViewController`; single app-scoped `PlaybackSession`; custom overlays only where system cannot (e.g. dual sidecar subs on tvOS) |
| Downloads | Non-TV only; feature-gate until ready |
| Tab bar | **Temporary shape, no pinning requirement.** System `TabView` on tvOS and macOS; iPad adaptive (sidebar-adaptable, or tabs only in landscape). Whatever the system does with it on scroll is what it does — do not chase it with `.toolbar(.hidden:)`, minimize behaviours, or a custom bar |
| Detail hero | The **artwork layer** sits behind the scroll (parallax / blur / crop live there). The hero's own content — logo, buttons, metadata — scrolls with the page, in one focus graph with the sections below |
| Hero state | Two discrete states (hero owns focus / it does not). No continuous scroll-progress scrub, no intermediate rest position |
| Compact title | **None.** No secondary compact title or floating header logo unless navigation chrome requires one |
| Poster caption | Platform-native. tvOS is one line in the system cell's `text`; iOS/macOS line counts are their own business, and neither side inherits the other's geometry |

## Atoms and inheritance

- One media-card component family (poster + landscape), one badge path, one image loader, one type
  scale, one section header.
- New screens compose atoms. Do not re-skin the same card three ways.
- Semantic tokens (`Color.KinoPub.*`, `TypeScale`) over hard-coded greys and one-off fonts.
- **One semantic component, native composition per platform.** A poster is one thing in the product;
  how it is drawn is the platform's business. Copying a layout decision sideways — line counts,
  paddings, point sizes — because "it looks like that on iPhone" is how tvOS ended up with a caption
  that cost tile width and rendered nothing. Parity is in what the component *means*, not in its
  geometry.

## Type

- **Always a Dynamic Type text style**, never `.system(size:)`. Vary weight and colour to build a
  hierarchy; do not vary size by hand. `.system(size:)` survives only where a glyph has to line up
  with fixed geometry (rating plaques, tile numerals) — not for anything that reads as text.
- **One running-text size per page family.** `TypeScale.detailBody` (`.body`) is that size for the
  item page: the hero metadata row, synopsis and credit lines, the vote counts under the rating
  tiles, and every row of the information table. If a new item-page label needs body text, it takes
  this token rather than a fifth number.
- **Level up, not down.** Those four were hand-picked sizes between 12 and 15pt — all *below* body,
  so prose read as a caption. When unifying sizes, unify on the system style the content deserves;
  do not drag everything down to whatever the smallest existing label happened to be.

## Adding a component

1. **Check the atoms first.** A card, badge, section header, image view, or button style probably
   already exists. Extend it instead of adding a sibling.
2. **Reusable UI lives in `KinoPubUI`.** Screen-specific composition stays in the app target.
3. **Semantic tokens only.** `Color.KinoPub.background` is opaque on every platform — if a surface
   needs to be see-through, layer a scrim explicitly; do not expect the token to be transparent.
4. **Ship a working `#Preview`,** on tvOS too when the component is focusable.
5. **tvOS focus is part of "done":** reachable, visibly focusable, verified on the remote — not from
   a preview. See [focus-and-tvui](../apple-platform/focus-and-tvui.md).
6. **One component per idea, called by one name.** `#if os(...)` inside it, or — where the renderer
   genuinely differs (a tvOS `UICollectionView` rail vs a SwiftUI shelf) — one implementation per
   platform behind that one name. What is never allowed is a second implementation for a second
   *screen* on the same platform.

## Motion and interaction

- Prefer system transitions (`navigationTransition(.zoom)`, matched sources) over custom morphs —
  **on iOS / iPadOS / macOS.** On tvOS the motion is the focus engine's: lift, scale, specular,
  parallax, and the collection view's own scroll animator. Do not add a transition library there,
  and do not write focus motion by hand (see
  [constraints-and-requirements](constraints-and-requirements.md) § banned patterns).
- Gesture-driven motion must be interruptible and track 1:1; springs over scripted ease when the user
  can grab the motion.
- Enter / exit along the same path; anchor sheets / menus to their trigger.
- Respect reduced motion, reduced transparency, and increased contrast.
- State UI motion under ~300ms unless illustrative. No decorative delay that blocks input.

## Ambiguous UI

When the system control is predetermined, implement it. When a noticeable custom piece is
ambiguous, build **2–3 genuinely different** isolated Preview / prototype variants on named axes,
then integrate only the chosen one. See [agent-workflow](agent-workflow.md).
