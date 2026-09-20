# PLAYBOOK — Kinopub tvOS MVP (agents & Cursor engineers)

Read `CURRENT.md` first. This file is the **execution playbook**.

## Roles

| Role | Who | Does |
| --- | --- | --- |
| Architecture / policy | **archi** | CURRENT, PLAYBOOK, milestone gates; **merge-ready review only** |
| Implementation | **max** (Cursor) | Code in `kinopub-apple-client` only for active milestone |
| Visual / HIG | **hig** | Design/HIG iterate with max on shots — no archi in the loop each commit |
| Product decisions | **Sasha** | Unblocks scope; overrides CURRENT |

Do not invent backlog from ROADMAP. If blocked on product, ask Sasha via the human channel — do not “decide like the old roadmap.”

## Repo

- **Product:** `HipsterCat/kinopub-apple-client`
- **Lab:** `kinopub-lab` = component museum / experiments only — never the app users run

## First commit for any new engineer/agent

1. Land `CURRENT.md` + `PLAYBOOK.md` at repo root (or `docs/` if Sasha prefers — default **repo root** next to `AGENTS.md`).
2. Add a short pointer at the top of `ROADMAP.md`:

   > **Superseded for active work:** see `CURRENT.md`. This roadmap is inventory/history. Unchecked items are not the MVP backlog.

3. Do **not** rewrite all of ROADMAP in the first PR — pointer + CURRENT is enough transparency.

## Milestone gates (full MVP, ordered)

### M0 — Policy in repo (do this before more UI if missing)
- [ ] `CURRENT.md` + `PLAYBOOK.md` merged (includes **Grid & chrome contract**)
- [ ] ROADMAP header points here
- [ ] Team/agents acknowledged: other platforms postponed
- [ ] Grid table + surface→recipe frozen in CURRENT (safe area 80/60, 40 pt gutters, poster **6 @ 260**, stills **4 @ 410**)

### M1 — Poster shelves (blocked until M0 grid contract is in main)
- Watch Now / Series / Movies: **same** poster shelf recipe — **6-col @ 260**, spacing **40 pt**, titled-row clearance ≥ **100 pt** vertical between unfocused rows
- Symmetrical peek on every horizontal rail; `scrollClipDisabled` / no clip of focus scale
- Content-type filter for Series/Movies; replace grid-as-home if needed
- No new Up Next/CW feature work; no LIVE; no invented widths
- Acceptance: `Section(title){rail}`; rowHeader=`.headline`; real header→rail gap; caption clears focused bounds; focused posters don’t overlap neighbors; **symmetrical peek, no edge-clip**; Menu pops; detail opens; system appearance + Dynamic Type; screenshots from feature branch; **hig visual pass** before merge
- Prefer `#Preview` / isolated demos for visual checks — do not burn Sasha’s simulator OTP for routine UI review

### M2 — Actions everywhere
- Unify `ItemActionState` + performer; wire all cards
- Acceptance: optimistic watchlist/bookmark/watched/hide; no N× bookmark refetch

### M3 — Up Next row (Watch Now only)
- Landscape stills + progress; CW merge rules in `docs/product/continue-watching.md`
- Not on Series/Movies

### M4 — Detail + playback path (system chrome)
### M5 — Library + bookmarks
- Before impl: **explicit** Library card recipe — 4-col landscape @ 410 **or** 5/6-col posters (not 2:3 in a 4-col grid)
- Sketch sidebar OK with system list materials + focusSection

### M6 — Search + categories completeness
- **System search only** — Sketch keyboard discarded
- Results default **4-col @ 410** landscape @ 40 pt unless CURRENT picks another table size

### M7 — Harden on 4K 26.6; strip regressions

**Stop and ping archi** before starting the next milestone letter.

## Engineering rules (non-negotiable)

1. `AGENTS.md` banned patterns — still banned.
2. tvOS media = UIKit + TVUIKit; three system cell families.
3. One semantic component, configured — never `HomeMediaCard`-style forks.
4. Ignore / do not extend despair-era comments and `#if os` chrome experiments for postponed platforms during MVP.
5. Prefer narrow patches on existing stores/services (`ContentStore`, `HomeCatalog`, menu coordinator, TVUIKit rails).
6. Prove focus and menus on device; previews ≠ focus.
7. Card widths only from CURRENT HIG grid table; shelf recipes numeric, not “about right.”
9. System light/dark + Dynamic Type; read `.agents/skills` before inventing shelf scroll behavior.
10. Apple Design Resources Sketch UI Kit names/styles over informal mocks.
11. Shelves use SwiftUI `Section`; rowHeader `.headline`; no zero headerSpacing; caption clears focus.
12. Never ship “insets none” / flush-to-edge rails — leading 80 pt content inset is law; peek ≠ no margin.
13. Visual gate: before+after screenshots; **hig** compares to Sketch/Apple stills; archi only at merge-ready.
8. Focus fundamentals in CURRENT (clip, focusSection, caption clearance, focused assets, empty-state escape).

## Anti-distraction checklist (before every PR)

- [ ] Does this serve **active milestone** in this playbook?
- [ ] Am I following an unchecked ROADMAP box that CURRENT did not pick up? → stop
- [ ] Am I “improving” iOS/macOS chrome? → stop (postponed)
- [ ] Am I reintroducing archive/hero/parallax research? → stop
- [ ] Would Sasha see this as daily-driver tvOS progress? → if no, stop

## PRs vs direct commits

| Change | Process |
| --- | --- |
| **UI that changes what appears on screen** | PR **required**. Include **screenshots** (simulator or device) of the affected tvOS surfaces — before/after when useful. No screenshot = not ready for Sasha’s design check or archi review. Saves rebuild loops; the visual proof stays on the PR. |
| **Policy / markdown / comments / tiny non-UI** (`CURRENT.md`, `PLAYBOOK.md`, ROADMAP pointers, typos) | **Direct commit** (no PR). Archi or max may land and approve these without waiting on a PR review. |

Sasha reviews **design** on UI PRs (screenshots). Archi reviews architecture / milestone fit. Max implements.

## When archi reviews

**Archi does not review every commit or mid-iterate screenshot.** While max and hig are fixing UI / design details, archi stays out.

Archi reviews **only** when max declares the PR **merge-ready** (final tip + labeled shots + hig pass or hig still FAIL with open list). Until that signal: max ↔ hig handle visual gates; archi does not re-score each push.

Merge still needs: hig visual pass (or Sasha override) **and** archi’s merge-ready architecture check once max says go.

## Communication

- Architecture questions → **archi**
- Mid-PR UI/HIG iterate → **max ↔ hig** (do not ping archi each commit)
- Merge-ready signal → **max** tells archi once; then archi reviews
- Policy changes → only via CURRENT.md update after Sasha/archi

## Success

Sasha daily-drives Kinopub on the 4K with Sketch-simple UI and full basic features. Agents share one policy. Old roadmap noise does not steer the sprint.
