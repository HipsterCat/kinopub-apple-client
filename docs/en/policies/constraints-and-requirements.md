# Policy: constraints are not requirements

> Durable policy, written 2026-08-13 after a full review of what this repo's detail-page
> documentation had accumulated. It exists to **delete** rules, not to add a layer.
> Related: [apple-native-design](apple-native-design.md), [component-catalogue](component-catalogue.md),
> [focus-and-tvui](../apple-platform/focus-and-tvui.md), [agent-workflow](agent-workflow.md).

## The rule

**A workaround discovered while implementing something is not a product requirement.**
It becomes one only when the user accepts it as one, in words, in this conversation or a
feature doc.

The failure this exists to stop is not hypothetical — it is most of what went wrong on the
detail page:

```
SwiftUI (or our use of it) can't do X
  → agent works around it
  → workaround gets written down as "how the page works"
  → next agent reads the doc as law
  → builds the next thing to defend the workaround
  → a second workaround, now load-bearing
```

Half the "architecture" of the detail page arrived this way. None of it was ever asked for.

## Classify before you write anything down

Every limitation you hit gets exactly one of four labels, stated where you record it:

| # | Label | What it needs to be believed | When it expires |
| --- | --- | --- | --- |
| 1 | **Apple API limitation** | The symbol named, from the SDK headers, plus what you tried | Next SDK. Re-probe, don't inherit |
| 2 | **Performance limitation** | A number, from a device or Instruments — not a feeling | Next measurement, or a different renderer |
| 3 | **Focus / navigation invariant** | A state the user can get stuck in, described concretely | Never — it is about the user, not the API |
| 4 | **Product decision** | The user said so | When the user says otherwise |

**Only 3 and 4 may become durable requirements.**

1 and 2 may become an **adapter**: one named place that converts what the system gives into
what we need, with the limitation in its doc comment. An adapter is never a statement about
what the product *is*, never an argument for a second component, and never a reason another
screen has to look different.

Ask the question in this order, and write the answer down:

1. **Which system primitive does Apple provide for this behaviour?** Not "how do we
   reproduce Apple TV" — what is the primitive.
2. Use it. If it is close but not exact, measure the gap.
3. Only with no primitive and a stated gap: an adapter, or custom, per
   [apple-native-design](apple-native-design.md) § Custom and private API.

## What a recorded constraint must carry

Otherwise it is folklore, and the next agent cannot tell folklore from law:

- the named API or the measurement;
- what was actually tried (a compile probe against the SDK beats a guess — see the
  `swiftc -typecheck` note in [focus-and-tvui](../apple-platform/focus-and-tvui.md));
- which of the four labels it is;
- what would retire it.

An unlabelled constraint in a plan is **evidence, not law** — see `AGENTS.md` § Authority.
When you find one, label it or delete it; do not build on it.

## Register — banned patterns

🔴 **Do not reintroduce these.** Each one is us re-implementing something Apple owns, worse.
If a task seems to need one, the design is wrong one level up — stop and ask.

| Banned | Why | Instead |
| --- | --- | --- |
| A focus-routing layer of our own (`focusBridge`-shaped: one object deciding who gets focus next) | We do not own the focus engine. UIKit does, and it is spatial | Layout: `.focusSection()`, `defaultFocus`, the collection view's own `indexPathForPreferredFocusedView(in:)` |
| One `@FocusState` case bound by several sibling views | Ambiguous — the engine cannot resolve it. Cost a full misdiagnosed revert on 2026-08-09 (six hero buttons on `heroOther`, focus frozen dead, Menu quit the app) | One case per focusable view, or no `@FocusState` at all |
| Manual focus delays — `asyncAfter`, same-press guards, "wait 60 ms then focus" | Racing the engine's own animator. The race comes back on a different box | Let the engine land focus; react to where it landed |
| Hand-rolled focus chrome — `scaleEffect` / `brightness` / shadow / parallax on focus | Non-native by construction; the user's verdict on ours was "не выглядит нативно" | `.buttonStyle(.card)` on tvOS, the system cells, `.borderless` + `.hoverEffect` where the label *is* an image |
| Continuous scroll-progress choreography (`washProgress`, `scrollProgress`, "at 0.37 move the artwork") | Read from incidental content geometry, re-ran the whole page body per frame, and produced the blur that "only worked for series". Apple TV has no such number | Discrete state: hero owns focus, or it does not |
| Hand-driven scrolling (`isScrollEnabled = false` + `CADisplayLink` writing `contentOffset`) | Replacing the focus engine's scroll animator to win a fight we started | Let focus scroll the page; if the landing is wrong, fix the layout or use a collection view |
| A custom hero focus graph (hero as a detached layer with its own focus rules) | Broke directional continuity *and* the `NavigationStack` back-context on 2026-08-09 | One connected focus graph: hero content and sections are siblings in the same scroll |
| A state machine around preview / trailer playback in SwiftUI | The reference app's least attractive code, and ours was worse | If a preview surface is ever built: UIKit — collection view + `UIViewPropertyAnimator` |
| **Screen-specific component variants** (`HomeMediaCard` / `DetailMediaCard` / `SearchMediaCard`) | Architectural defect, not a style choice | One component, configured. See [component-catalogue](component-catalogue.md) |

## Register — invalid, agent-invented

❌ **These were never requirements.** They are recorded here so nobody re-derives them from
an old sentence somewhere.

- **"The tab bar must stay pinned through scroll."** No such product requirement exists, and
  the tvOS API for it does not either (`.tabBarMinimizeBehavior(.never)` is iOS 26+, explicitly
  unavailable on tvOS/macOS). The tab bar today is a **temporary shape**: system `TabView` on
  tvOS and macOS, adaptive on iPad (sidebar-adaptable, or tabs only in landscape). If its
  behaviour is wrong, the question is which UX we want — not how to pin it.
- **"`TVMediaItemContentConfiguration` cannot show an icon, so we need our own badge overlay."**
  `badgeText` is a `String`, and a `String` can carry a glyph: an SF Symbol is a character in
  the SF Symbols font (and a custom symbol or an asset is the next fallback — worst case, a
  letter). The overlay may still earn its place for other reasons (a scrim, a progress bar, a
  paired checkmark — see [component-catalogue](component-catalogue.md) § the tvOS cell standard);
  "Apple gives no icon" is not one of them. Probe it before claiming it back.
- **Cross-platform geometry parity.** "iOS and macOS show two lines under a poster, so tvOS
  must too" is not a requirement — it is a visual-parity reflex. The two-line tvOS caption cost
  a wider tile and rendered nothing. Semantics are shared; composition is native (see
  [apple-native-design](apple-native-design.md) § Platform stance).
- **"The hero must live outside the scrolling container."** As written, this described one
  broken SwiftUI attempt, not a product need. What is actually outside the scroll is the
  **artwork layer**; the hero's own content scrolls with the page. See
  [focus-and-tvui](../apple-platform/focus-and-tvui.md) § Detail page.
- **A secondary compact title / floating header logo.** Product decision 2026-08-13: we don't
  ship one unless navigation chrome requires it. It existed to soften a transition that the
  continuous scrub created in the first place.

## Register — accepted adapters

✅ Bucket 1 / 2 items that are allowed to exist, each in exactly one place, each with its
limitation in its own doc comment:

- **`TVUIKitMediaItemMetrics`** — `orthogonalLayoutSectionForMediaItems()` exposes neither its
  group nor its item, so it cannot be resized. We measure what it produces once per width and
  rebuild an equivalent section at our scale. Apple keeps owning the proportions.
- **The progress bar in `TVUIKitMediaItemOverlayView`** — `configuration.playbackProgress` only
  paints on the *focused* tile, and "started, not finished" is what an idle rail has to say.
  Stated trade: we own a bar, and it is visible when it matters.

An adapter that stops being needed gets deleted, not kept "in case".

## For agents

Before you write down that something must be a certain way, answer:

1. Which of the four labels is this?
2. If 1 or 2 — where is the named API or the number?
3. If 3 or 4 — where did the user say so?
4. If none of the above, it is a workaround. Ship it if you must, label it as one, and do
   **not** let it change any other file.
