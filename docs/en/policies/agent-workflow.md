# Agent workflow

How agents approach work in this repo. Authority and preservation rules live in
[`AGENTS.md`](../../../AGENTS.md).

## Sequence

0. **Model before layout.** What is the thing the user acts on, and what can they do with it right
   now? A page that keeps growing per-type sections is usually a data question being answered in
   the view layer.
1. **Capability and data flow** — what the user can do, which services / models / stores change,
   what old path to remove or merge.
2. **Recon** — read the relevant policy, feature doc, and 1–2 Apple-platform knowledge sections.
   Check Apple API / HIG, then our code, then reference apps / community fork / mature libraries.
3. **Presentation**
   - If the control is predetermined by the system → implement it.
   - If a noticeable UI piece is ambiguous → isolated 2–3 variants (see below), wait for a choice.
4. **Small slice** — one reviewable change. Do not touch unrelated dirty files.
5. **Verify by risk** — see tiers below. Be honest when verification is deferred.
6. **Docs** — update the feature doc checklist / validation notes after acceptance. Touch README
   only for macro-stage or public-capability changes. Append notable facts to `CHANGELOG.md`.
   **Update the plan itself as you go** — check boxes when landed, dated notes when reverted. A
   plan mid-execution that isn't updated is exactly as useless as no plan.

## Borrow before build

Order of reuse:

1. Apple public API (and isolated private helpers when already accepted).
2. Existing atoms in `KinoPubUI` / app services.
3. Proven code from reference apps or the `community` remote (backend slices only for UI-adjacent
   ports — keep our screens).
4. Mature libraries (Nuke, Boutique, Introspect, palette extractors, Pow / Wave, etc.) after a short
   capability review: which hole they close, why system API is insufficient, platforms, wrapper
   boundary, maintenance cost.
5. New in-house code.

Do not add a dependency because a list of cool repos exists. Do not rewrite a working library-shaped
problem overnight.

## Prototype variants

Use when the user asks, or when a visible custom piece has multiple defensible directions.

- Default **3** variants; max 5. Each needs a named axis (layout, density, motion, interaction).
- **Where they live:** `Packages/KinoPubUI/Sources/KinoPubUI/Previews/`, one
  `<Thing>Variants.swift` per ambiguous piece, wrapped in `#if DEBUG`. Use the `VariantGallery` /
  `Variant` containers in `VariantGallery.swift` so the axis is labelled and the candidates sit side
  by side. Never build variants in production paths.
- Every variant must be fully interactive with realistic content. A static mock is not a variant.
- Previews do not prove tvOS focus. Anything focusable still needs a run on the remote.
- Promote only the chosen variant, then **delete the variants file** — a stale gallery is worse than
  no gallery. Keep it only if the user asks.
- Predetermined system controls (Play button style already decided, native player, Form settings)
  do **not** get variant theatre.

## Feature flags and incomplete work

- Prefer finishing a thin vertical slice or **feature-gating** it (`FeatureFlags`,
  Downloads-style) over shipping half-chrome. An off flag must skip the work
  (network, sampling), not only hide UI.
- Do not claim recommendations / Top Shelf / light theme / advanced subtitles exist when they do not.
- Dual subtitles and other parked surfaces stay parked until their feature doc says otherwise.

## Verification tiers

| Risk | Examples | Required before `done` |
| --- | --- | --- |
| Low | Copy, localization keys, swap label → existing SF Symbol / asset | Diff review; build optional |
| Medium | New reusable view, layout tweak, model mapping, image state | `#Preview` / component harness or focused package/target build |
| High | Navigation, focus, sidebar, blur/materials, player, cache/session lifetime, private API | Build affected platforms + visual or remote/input check, or remain `validation pending` |

Long builds and single-machine limits are real. Deferred verification is allowed; silent
"everything landed" claims are not.

### Shared debug session

Every DEBUG build (macOS app, tvOS / iOS Simulator) mirrors the kino.pub session to one file,
`~/.kinopub-dev-session.json`, and reseeds its Keychain from it when the Keychain is empty —
see `DevSessionMirror` in
[AccessTokenServiceImpl.swift](../../../KinoPubAppleClient/Services/AccessToken/AccessTokenServiceImpl.swift).
So a reinstall, a wiped DerivedData or a switch between platforms does **not** need a fresh
activation code. The account has five device slots; do not spend them on the dev loop.

- Simulator reaches the real home through `SIMULATOR_HOST_HOME`; the sandboxed macOS app needs
  `com.apple.security.temporary-exception.files.home-relative-path.read-write` for that one path,
  which is why Debug has its own `KinoPubAppleClient-Debug.entitlements`. **Release must keep
  pointing at `KinoPubAppleClient.entitlements`** — temporary exceptions fail App Review.
- In `project.pbxproj` a configuration's `name = Debug` line comes **after** its settings. Check
  which block you are editing before changing `CODE_SIGN_ENTITLEMENTS`, and verify with
  `codesign -d --entitlements - --xml <app>` rather than trusting the edit.
- Sign out (`clear()`) deletes the shared file, on purpose.

## Anti-patterns seen here

- Inventing design-decision blockers that the user did not set.
- Encoding agent assumptions into README / plans, then treating them as law.
- **Promoting a workaround to a requirement.** Label it, keep it local, or ask — see
  [constraints-and-requirements](constraints-and-requirements.md). Documenting a hack as "how this
  page works" is how the next agent inherits it as a constraint to defend.
- Claiming an API limitation without a probe. `swiftc -typecheck` against the SDK settles most of
  them in a minute; guessing from a header name has cost days here.
- Copying a sample's *constants* along with its mechanism, when the sample was written for a
  different input model (swipe vs focus). Copy the mechanism, re-derive the numbers.
- Marking phases complete after tvOS-only compile while macOS sidebar / banner / artwork broken.
- Overwriting user blur / glass / banner / badge decisions.
- Placeholder grids that violate continuity policy.
- Treating one stream survey as a global ban on capability badges the user still wants when flags exist.
