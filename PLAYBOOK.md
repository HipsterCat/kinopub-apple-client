# PLAYBOOK — Kinopub tvOS MVP (agents & Cursor engineers)

Read `CURRENT.md` first. This file is the **execution playbook**.

## Roles

| Role | Who | Does |
| --- | --- | --- |
| Architecture / policy | **archi** | CURRENT, PLAYBOOK, reviews, milestone gates |
| Implementation | **max** (Cursor) | Code in `kinopub-apple-client` only for active milestone |
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
- [ ] `CURRENT.md` + `PLAYBOOK.md` merged
- [ ] ROADMAP header points here
- [ ] Team/agents acknowledged: other platforms postponed

### M1 — Poster shelves (active next)
- Watch Now: poster shelf grammar (Hot/Fresh/Popular-style via `HomeCatalog` patterns)
- Movies + Series/Shows: **same shelf layout**, content-type filter (replace grid-as-home if needed)
- No new Up Next/CW feature work; no LIVE
- Acceptance: focus smooth on tvOS 26.6 device; Menu pops; detail opens; no banned focus chrome

### M2 — Actions everywhere
- Unify `ItemActionState` + performer; wire all cards
- Acceptance: optimistic watchlist/bookmark/watched/hide; no N× bookmark refetch

### M3 — Up Next row (Watch Now only)
- Landscape stills + progress; CW merge rules in `docs/product/continue-watching.md`
- Not on Series/Movies

### M4 — Detail + playback path (system chrome)
### M5 — Library + bookmarks (Sketch sidebar/grid OK)
### M6 — Search + categories completeness
### M7 — Harden on 4K 26.6; strip regressions

**Stop and ping archi** before starting the next milestone letter.

## Engineering rules (non-negotiable)

1. `AGENTS.md` banned patterns — still banned.
2. tvOS media = UIKit + TVUIKit; three system cell families.
3. One semantic component, configured — never `HomeMediaCard`-style forks.
4. Ignore / do not extend despair-era comments and `#if os` chrome experiments for postponed platforms during MVP.
5. Prefer narrow patches on existing stores/services (`ContentStore`, `HomeCatalog`, menu coordinator, TVUIKit rails).
6. Prove focus and menus on device; previews ≠ focus.

## Anti-distraction checklist (before every PR)

- [ ] Does this serve **active milestone** in this playbook?
- [ ] Am I following an unchecked ROADMAP box that CURRENT did not pick up? → stop
- [ ] Am I “improving” iOS/macOS chrome? → stop (postponed)
- [ ] Am I reintroducing archive/hero/parallax research? → stop
- [ ] Would Sasha see this as daily-driver tvOS progress? → if no, stop

## Communication

- Architecture questions → **archi**
- Implementation status → max reports milestone id + acceptance
- Policy changes → only via CURRENT.md update after Sasha/archi

## Success

Sasha daily-drives Kinopub on the 4K with Sketch-simple UI and full basic features. Agents share one policy. Old roadmap noise does not steer the sprint.
