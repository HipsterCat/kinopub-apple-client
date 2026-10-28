#!/bin/bash
# Select Xcode 27.x on the runner, preferring a GM then an RC over a beta.
#
# Why 27: the project file is Xcode 27's `project.xcproj`. Xcode 26.x cannot open it
# ("cannot be opened because it is missing its project.pbxproj file"), so every build and
# test job on the `macos-26` image failed before compiling anything.
#
# Xcode 27 lives on GitHub's `xcode-27` preview image
# (https://github.com/actions/runner-images/issues/14404). Never trust the image default
# (27.0 there). `sort -V` on Apple's names puts `Xcode_27.2_beta_2` *after*
# `Xcode_27.2_Release_Candidate`, so `tail -1` would pick a beta when both are installed.
# App Store Connect rejected 27.2 beta 2 archives on 2026-10-22 (`Unsupported SDK or
# Xcode version`); the RC that followed was accepted.

set -euo pipefail

gm=()
rc=()
beta=()
other=()

shopt -s nullglob
for app in /Applications/Xcode_27*.app; do
  base=$(basename "$app" .app)
  case "$base" in
    *beta*|*Beta*)
      beta+=("$app")
      ;;
    *Release_Candidate*|*ReleaseCandidate*)
      rc+=("$app")
      ;;
    Xcode_27|Xcode_27.[0-9]|Xcode_27.[0-9].[0-9])
      gm+=("$app")
      ;;
    *)
      other+=("$app")
      ;;
  esac
done

newest() {
  printf '%s\n' "$@" | sort -V | tail -1
}

xcode=""
if [ ${#gm[@]} -gt 0 ]; then
  xcode=$(newest "${gm[@]}")
elif [ ${#other[@]} -gt 0 ]; then
  xcode=$(newest "${other[@]}")
elif [ ${#rc[@]} -gt 0 ]; then
  xcode=$(newest "${rc[@]}")
elif [ ${#beta[@]} -gt 0 ]; then
  xcode=$(newest "${beta[@]}")
fi

if [ -z "$xcode" ]; then
  echo "::error::No Xcode 27.x on this runner. The project file needs Xcode 27 (runs-on: xcode-27)."
  echo "Xcodes present on this image:"
  ls -d /Applications/Xcode*.app 2>/dev/null || echo "  (none)"
  exit 1
fi

echo "Selecting $xcode"
sudo xcode-select -s "$xcode"
