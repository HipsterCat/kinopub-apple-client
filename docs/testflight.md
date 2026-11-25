# Internal TestFlight

Personal uploads of the one multiplatform target (`KinoPub` / `com.soda.kinopub`) to
App Store Connect. Not a public beta and not an App Store submission. Sasha installs
on Apple TV from TestFlight.

The workflow is `.github/workflows/testflight.yml`. Fastlane lives in `fastlane/`.
Upload jobs run on GitHub's `macos-26` image with Xcode 26.x GM
(`.github/scripts/select-xcode-26.sh`). App Store Connect rejects beta Xcodes;
do not move these jobs onto `xcode-27`. Signing patches the app / Top Shelf
target keys in `project.pbxproj`; archives are `xcodebuild archive` /
`exportArchive`. Do not pass `CODE_SIGN_*` as xcargs — those leak onto SPM
package targets. Fastlane 2.240+ is required: altool can log
`CDUploaderStateInfoResumeFilePath` after `UPLOAD SUCCEEDED`, and 2.238 treated
that as failure (fastlane/fastlane#30130).

A secrets-free check is `.github/workflows/testflight-lint.yml` (`fastlane ios lint`
plus `xcodebuild -list`). It runs on Fastlane / pbxproj changes without Apple
keys.

## When it runs

| Trigger | What happens |
| --- | --- |
| **Push to `main`** | Uploads if HEAD moved since the last successful archive **and** nothing succeeded yet today (UTC). Reliable path: this repo is a fork, and GitHub did not queue `schedule` after a GitHub App last changed the workflow |
| **Cron** (`06:23 UTC`) | Same rule. Best-effort only — keep it, do not rely on it |
| **Actions → TestFlight → Run workflow** | Anytime, if secrets are present. Pick iOS / tvOS / macOS / all |

At most **one successful automatic upload per UTC day**. A failed attempt does not consume the day; `workflow_dispatch` is not capped. Fastlane/pbxproj lint on every change is still `.github/workflows/testflight-lint.yml`.

The build number is **not** committed. The job asks App Store Connect for the latest
TestFlight number on iOS, tvOS and macOS and uses that max + 1, so two uploads cannot
collide.

**What to Test** is the Russian What's New catalog for the current marketing version:
isolated files under `KinoPubAppleClient/Resources/WhatsNew/entries/` (newest first),
then the frozen legacy `whats-new.json`. A manual run can override it in the workflow
input. Local Fastlane falls back to `CHANGELOG.md` then `git log`.

If required secrets are missing the workflow **skips with a notice** and stays green.
It does not fail the run.

## Secrets Sasha must add

GitHub → this repo → **Settings → Secrets and variables → Actions → New repository secret**.

### App Store Connect API key (required)

[App Store Connect](https://appstoreconnect.apple.com) → **Users and Access** →
**Integrations** → **App Store Connect API**.

1. Create a key with **App Manager** (or Admin).
2. Download the `.p8`. Apple will not let you download it again.
3. Note the **Key ID** and the **Issuer ID** on that page.

| Secret | Value |
| --- | --- |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID, e.g. `ABCD123456` |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer UUID from the API keys page |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | The `.p8` itself, **or** `base64 -i AuthKey_XXX.p8 \| pbcopy` |

The lane accepts either the PEM (`-----BEGIN PRIVATE KEY-----`) or its base64.

### Signing (required for iOS and tvOS)

Xcode → Settings → Accounts → Manage Certificates: create **Apple Distribution** if
you do not already have one. Export it from Keychain Access as a `.p12`.

| Secret | Value |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | `base64 -i AppleDistribution.p12 \| pbcopy` |
| `P12_PASSWORD` | Password of that `.p12` |

Do not mint a new distribution certificate per run — Apple caps those.

Provisioning profiles are created on the fly from the API key (`sigh`). They are not
secrets.

### macOS only (optional)

Needed only if you want the Mac build on the same TestFlight. Without these, iOS and
tvOS still upload; macOS is skipped with a notice.

Xcode → Manage Certificates: **Mac Installer Distribution**, export as a second `.p12`.

| Secret | Value |
| --- | --- |
| `MAC_INSTALLER_CERTIFICATE_BASE64` | `base64 -i MacInstaller.p12 \| pbcopy` |
| `MAC_INSTALLER_CERTIFICATE_PASSWORD` | Password of that `.p12` |

### Optional repository variable (not a secret)

| Variable | Value |
| --- | --- |
| `TESTFLIGHT_INTERNAL_GROUPS` | Comma-separated internal group names. If set, the job waits for processing and assigns the build |

Testers who are App Store Connect Users on this app get the build without a named group.

## One-time Apple setup

1. Developer Portal: App ID `com.soda.kinopub` (team `Z2PQ733PSP`) with iOS, tvOS and
   macOS enabled. A local Xcode run with Automatic signing creates it.
2. App Store Connect → Apps → (+): iOS app named **Piratic**, bundle id
   `com.soda.kinopub`. Then add Apple TV and Mac on the same record so one TestFlight
   link covers every device (universal purchase).
3. Top Shelf (tvOS): App Group `group.com.soda.kinopub` enabled on `com.soda.kinopub` and on
   a second App ID `com.soda.kinopub.topshelf`. A local Xcode run of the tvOS app on a
   device with Automatic signing creates both. Until they exist the tvOS lane fails at
   `get_provisioning_profile` for the Top Shelf; iOS and macOS are unaffected.
4. Add testers under Users and Access (they land in Internal Testing as App Store
   Connect Users) or create an Internal group on the app.

## First upload

1. Add the secrets above.
2. Actions → **TestFlight** → **Run workflow**. Platform `tvos` (or `all`).
3. Wait for Apple to process the build, then install from TestFlight on the Apple TV.

A local archive is `bundle exec fastlane ios beta` with `TESTFLIGHT_PLATFORM=tvos` and
the same variables in the environment. CI is the path that matters.

Secrets-free sanity: `bundle exec fastlane ios lint`.

## Related

- In-app What's New: [docs/product/whats-new.md](product/whats-new.md)
- New user-facing bullets: `KinoPubAppleClient/Resources/WhatsNew/entries/`
- Legacy archive (do not extend): `KinoPubAppleClient/Resources/whats-new.json`
