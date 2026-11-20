#!/bin/bash
# Select the newest Xcode 26.x GM on the runner. Never a 27 beta.
#
# Why this exists: every package declares `// swift-tools-version: 6.2`, which needs
# Xcode 26 (Swift 6.2). The workflow used to run on `macos-15` and take whatever Xcode
# the image happened to default to — Swift 6.1 — so every job died in dependency
# resolution within ~15 seconds, before compiling a single file:
#
#   error: 'kinopubkit': package 'kinopubkit' is using Swift tools version 6.2.0
#          but the installed version is 6.1.0
#
# CI was red on every commit from 2026-08-05 to 2026-08-13 for that reason alone.
#
# The project file is Xcode 14-compatible `project.pbxproj`. Xcode 26.x opens it;
# Xcode 27 is not required and App Store Connect rejects 27 betas. Matching 26.*
# rather than one exact version means an image refresh that drops the oldest
# Xcode cannot break us, and a runner with no Xcode 26 at all fails here with a
# readable message instead of an obscure resolve error seven jobs deep.

set -euo pipefail

shopt -s nullglob
gm=()
for app in /Applications/Xcode_26*.app; do
  base=$(basename "$app" .app)
  case "$base" in
    *beta*|*Beta*|*Release_Candidate*|*ReleaseCandidate*)
      ;;
    Xcode_26|Xcode_26.[0-9]|Xcode_26.[0-9].[0-9])
      gm+=("$app")
      ;;
  esac
done

xcode=""
if [ ${#gm[@]} -gt 0 ]; then
  xcode=$(printf '%s\n' "${gm[@]}" | sort -V | tail -1)
fi

if [ -z "$xcode" ]; then
  echo "::error::No Xcode 26.x GM on this runner. Packages declare swift-tools-version 6.2, which needs it (runs-on: macos-26)."
  echo "Xcodes present on this image:"
  ls -d /Applications/Xcode*.app 2>/dev/null || echo "  (none)"
  exit 1
fi

echo "Selecting $xcode"
sudo xcode-select -s "$xcode"
