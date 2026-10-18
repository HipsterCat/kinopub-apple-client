# CURRENT — scope now

What is active. If this file and [AGENTS.md](AGENTS.md) disagree on *scope*, this file wins;
AGENTS.md wins on *how* things are built. Sasha's explicit decision overrides both.

Last updated: 2026-10-18.

## Goal

The tvOS daily driver is in place: every feature of kino.pub's own TVML app, in standard Apple tvOS
UI. Next, the same client on **iOS, iPadOS and macOS**, and features kino.pub's apps may not have
at all — this is an experimental client, not a port. Work comes from Sasha's asks and from the
Asana tasks ([Kinopub Engineering project plan](https://app.asana.com/1/1218266299921477/project/1219403693009374)).

## Platforms

| Platform | Status |
| --- | --- |
| **tvOS 26.5+** (Apple TV 4K 1st gen through current) | Active — the reference for media, focus and the 10-foot bar |
| **iOS / iPadOS / macOS** | Active again from 2026-10-18 — same layout grammar, adaptive, platform-native controls. Not a second design system and not TV chrome forced sideways |

## Layout contract (all devices)

Layout comes from **container bounds + safe area + Dynamic Type** — not `UIScreen`, a 1920 canvas
or fixed cell frames.

- Prefer a **preferred item size** (aspect + density class) and let the column count follow the
  available width. Do not hardcode column counts or cell sizes.
- HIG numbers are **density examples**, not law. Unfocused widths Apple lists for a full-width tvOS
  1920 reference with ~40 pt gutters: 2 → 860, 3 → 560, 4 → 410, 5 → 320, 6 → 260, 7 → 217,
  8 → 184, 9 → 160. HIG safe margins ~60 pt top/bottom and ~80 pt sides are starting points —
  match the container's insets and do not apply them twice.
- Vertical rhythm between titled rows: **~80 pt** (Sasha, 2026-09), one value per page.
- Dynamic Type everywhere practical: UIKit labels set `adjustsFontForContentSizeCategory`, cells
  self-size, larger text grows captions and headers without clipping.

### tvOS shelves

- **Leading inset and trailing peek.** A rail keeps its leading content inset (header and first
  card on one line, from the safe area) and shows a peek of the next card. No peek, or the first
  card flush to the screen edge, are both defects. Disable scroll clipping so focus scale shows —
  without deleting the margin.
- Poster rails (Watch Now, Series, Movies) are one recipe: 2:3, ~6-column class on full width.
  Landscape stills (16:9, ~4-column class) carry progress; the Up Next / Continue Watching row is
  on Watch Now only, not on Series or Movies. No LIVE badge on catalogue cards.
- **Row header:** `TypeScale.rowHeader` = `.headline.weight(.semibold)` + `.secondary`, leading.
- **Captions** clear the focused (scaled) lockup; focused caption colour is `UIColor.label`. Rails
  are never captioned, grids always.
- Large or repeating media surfaces are UIKit / TVUIKit; small chrome (buttons, menus, chips,
  alerts) can be SwiftUI. Measure on an Apple TV 4K 1st gen before growing a SwiftUI rail.
- **Search on tvOS is the system UIKit search** (`UISearchController` path) — no custom keyboard.
  SwiftUI `.searchable` is fine on iOS and macOS.
- Tab labels: **Watch Now** / **Series**, never Home / Shows.

### Focus fundamentals

A grid of focusables (no diagonal hit geometry); `focusSection` on headers, sidebars and filter
rows so focus does not jump to the tab bar; assets sharp at focused size; empty and error states
keep a focusable escape.

## Design references

"Sketch" means **Apple Design Resources — tvOS UI Kit** (and the matching iOS / macOS kits):
components and styles as Apple named them. System apps — TV, App Store, Podcasts, Music,
TestFlight, Fitness — are the orientation. A mock that diverges from the kits and system patterns
is non-binding.

## Not doing

- Custom focus, parallax, scroll-scrub or player chrome (AGENTS.md › Banned).
- A custom search keyboard or glass approximations of system chrome.
- A hardcoded canvas or fixed column counts.
- Promoting `docs/archive/**` or `docs/research/**` into requirements without Sasha.
- `kinopub-lab` / KinoBook as the product shell.
