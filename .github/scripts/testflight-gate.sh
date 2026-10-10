#!/usr/bin/env bash
# Decide whether this TestFlight workflow should archive and upload.
#
# Skip (exit 0, should_upload=false) when:
#   • required secrets are missing
#   • schedule, and main has no commits since the last successful upload
#   • push to main, and MARKETING_VERSION / CURRENT_PROJECT_VERSION did not change
#
# workflow_dispatch always uploads when secrets are present.
set -euo pipefail

should_upload=false
skip_reason=""
platform="${TESTFLIGHT_PLATFORM:-all}"
include_macos=true

notice() {
  echo "::notice::$1"
}

set_output() {
  local name="$1"
  local value="$2"
  echo "${name}=${value}" >> "$GITHUB_OUTPUT"
}

# Upload's matrix job errors on an empty include even when the job is skipped.
dummy_matrix='{"include":[{"platform":"tvos"}]}'

missing=()
for name in \
  APP_STORE_CONNECT_API_KEY_ID \
  APP_STORE_CONNECT_ISSUER_ID \
  APP_STORE_CONNECT_API_KEY_CONTENT \
  BUILD_CERTIFICATE_BASE64 \
  P12_PASSWORD
do
  if [ -z "${!name:-}" ]; then
    missing+=("$name")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  skip_reason="Missing GitHub secrets: ${missing[*]}. Add them under Settings → Secrets and variables → Actions. See docs/testflight.md."
  notice "TestFlight skipped. ${skip_reason}"
  set_output should_upload false
  set_output skip_reason "$skip_reason"
  set_output matrix "$dummy_matrix"
  exit 0
fi

macos_missing=()
for name in MAC_INSTALLER_CERTIFICATE_BASE64 MAC_INSTALLER_CERTIFICATE_PASSWORD; do
  if [ -z "${!name:-}" ]; then
    macos_missing+=("$name")
  fi
done

if [ "${#macos_missing[@]}" -gt 0 ]; then
  include_macos=false
  if [ "$platform" = "macos" ]; then
    skip_reason="macOS TestFlight needs ${macos_missing[*]}. See docs/testflight.md."
    notice "TestFlight skipped. ${skip_reason}"
    set_output should_upload false
    set_output skip_reason "$skip_reason"
    set_output matrix "$dummy_matrix"
    exit 0
  fi
  notice "macOS upload skipped (missing ${macos_missing[*]}); iOS and tvOS will still upload."
fi

event="${GITHUB_EVENT_NAME:-}"
reason=""

case "$event" in
  workflow_dispatch)
    should_upload=true
    reason="manual run"
    ;;
  schedule)
    last_sha="$(python3 - "$GITHUB_API_URL" "$GITHUB_REPOSITORY" "$GITHUB_TOKEN" <<'PY'
import json, sys, urllib.error, urllib.request

api, repo, token = sys.argv[1], sys.argv[2], sys.argv[3]
headers = {
    "Authorization": f"Bearer {token}",
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "kinopub-testflight-gate",
}

def get(url):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)

try:
    runs_url = (
        f"{api}/repos/{repo}/actions/workflows/testflight.yml/runs"
        f"?branch=main&status=completed&per_page=30"
    )
    payload = get(runs_url)
    for run in payload.get("workflow_runs", []):
        if run.get("conclusion") != "success":
            continue
        jobs = get(run["jobs_url"])
        uploaded = any(
            job.get("conclusion") == "success"
            and str(job.get("name", "")).startswith("Upload ")
            for job in jobs.get("jobs", [])
        )
        if uploaded:
            print(run.get("head_sha", ""))
            break
except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, KeyError) as error:
    print(f"Could not read previous TestFlight runs ({error})", file=sys.stderr)
PY
)"
    if [ -n "${last_sha}" ] && [ "${last_sha}" = "${GITHUB_SHA}" ]; then
      skip_reason="No new commits on main since the last TestFlight upload (${last_sha:0:7})."
      notice "TestFlight skipped. ${skip_reason}"
      set_output should_upload false
      set_output skip_reason "$skip_reason"
      set_output matrix "$dummy_matrix"
      exit 0
    fi
    should_upload=true
    if [ -n "${last_sha}" ]; then
      reason="daily run; new commits since ${last_sha:0:7}"
    else
      reason="daily run; no previous successful upload"
    fi
    ;;
  push)
    xcproj="KinoPubAppleClient.xcodeproj/project.xcproj"
    if git rev-parse --verify HEAD^ >/dev/null 2>&1; then
      before="$(git show HEAD^:"$xcproj" 2>/dev/null || true)"
    else
      before=""
    fi
    after="$(cat "$xcproj")"
    changed="$(python3 -c '
import re, sys
def versions(text):
    marketing = re.search(r"\"MARKETING_VERSION\": \"([^\"]+)\"", text)
    build = re.search(r"\"CURRENT_PROJECT_VERSION\": \"([^\"]+)\"", text)
    return (
        marketing.group(1) if marketing else "",
        build.group(1) if build else "",
    )
before, after = versions(sys.argv[1]), versions(sys.argv[2])
print("yes" if before != after else "no")
' "$before" "$after")"
    if [ "$changed" = "yes" ]; then
      should_upload=true
      reason="marketing or build version changed on main"
    else
      skip_reason="Push to main did not change MARKETING_VERSION or CURRENT_PROJECT_VERSION. Daily upload covers new commits."
      notice "TestFlight skipped. ${skip_reason}"
      set_output should_upload false
      set_output skip_reason "$skip_reason"
      set_output matrix "$dummy_matrix"
      exit 0
    fi
    ;;
  *)
    skip_reason="Unsupported event '$event'."
    notice "TestFlight skipped. ${skip_reason}"
    set_output should_upload false
    set_output skip_reason "$skip_reason"
    set_output matrix "$dummy_matrix"
    exit 0
    ;;
esac

matrix="$(python3 -c '
import json, sys
platform, include_macos = sys.argv[1], sys.argv[2] == "true"
if platform == "ios":
    rows = [{"platform": "ios"}]
elif platform == "tvos":
    rows = [{"platform": "tvos"}]
elif platform == "macos":
    rows = [{"platform": "macos"}] if include_macos else []
else:
    rows = [{"platform": "ios"}, {"platform": "tvos"}]
    if include_macos:
        rows.append({"platform": "macos"})
print(json.dumps({"include": rows}, separators=(",", ":")))
' "$platform" "$include_macos")"

if [ "$matrix" = '{"include":[]}' ]; then
  skip_reason="Nothing to upload for platform '$platform'."
  notice "TestFlight skipped. ${skip_reason}"
  set_output should_upload false
  set_output skip_reason "$skip_reason"
  set_output matrix "$dummy_matrix"
  exit 0
fi

notice "TestFlight will upload (${reason})."
set_output should_upload true
set_output skip_reason ""
set_output matrix "$matrix"
