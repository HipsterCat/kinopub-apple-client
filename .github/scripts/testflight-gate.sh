#!/usr/bin/env bash
# Decide whether this TestFlight workflow should archive and upload.
#
# Skip (exit 0, should_upload=false) when:
#   • required secrets are missing
#   • schedule or push, and HEAD is still the last SHA that actually uploaded
#
# workflow_dispatch always uploads when secrets are present.
#
# Push and schedule share the same "new commits since last successful upload"
# rule. Version-only push was the reason a missed daily cron left Sasha without
# a build: every main push skipped, and GitHub had dropped the :00 schedule.
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

skip_upload() {
  skip_reason="$1"
  notice "TestFlight skipped. ${skip_reason}"
  set_output should_upload false
  set_output skip_reason "$skip_reason"
  set_output matrix "$dummy_matrix"
  exit 0
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
  skip_upload "Missing GitHub secrets: ${missing[*]}. Add them under Settings → Secrets and variables → Actions. See docs/testflight.md."
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
    skip_upload "macOS TestFlight needs ${macos_missing[*]}. See docs/testflight.md."
  fi
  notice "macOS upload skipped (missing ${macos_missing[*]}); iOS and tvOS will still upload."
fi

# SHA of the last TestFlight run that actually archived (an Upload * job
# succeeded). Skip-successes and failed archives do not count.
last_successful_upload_sha() {
  python3 - "$GITHUB_API_URL" "$GITHUB_REPOSITORY" "$GITHUB_TOKEN" <<'PY'
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
    payload = get(
        f"{api}/repos/{repo}/actions/workflows/testflight.yml/runs"
        f"?branch=main&status=completed&per_page=100"
    )
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
}

upload_if_new_commits() {
  local why="$1"
  local last_sha
  last_sha="$(last_successful_upload_sha)"
  if [ -n "${last_sha}" ] && [ "${last_sha}" = "${GITHUB_SHA}" ]; then
    skip_upload "No new commits on main since the last TestFlight upload (${last_sha:0:7})."
  fi
  should_upload=true
  if [ -n "${last_sha}" ]; then
    reason="${why}; new commits since ${last_sha:0:7}"
  else
    reason="${why}; no previous successful upload"
  fi
}

event="${GITHUB_EVENT_NAME:-}"
reason=""

case "$event" in
  workflow_dispatch)
    should_upload=true
    reason="manual run"
    ;;
  schedule)
    upload_if_new_commits "scheduled run"
    ;;
  push)
    upload_if_new_commits "push to main"
    ;;
  *)
    skip_upload "Unsupported event '$event'."
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
  skip_upload "Nothing to upload for platform '$platform'."
fi

notice "TestFlight will upload (${reason})."
set_output should_upload true
set_output skip_reason ""
set_output matrix "$matrix"
