#!/bin/bash
# Select the newest Xcode 27.x on the runner.
#
# Why 27: the project file is Xcode 27's `project.xcproj`. Xcode 26.x cannot open it
# ("cannot be opened because it is missing its project.pbxproj file"), so every build and
# test job on the `macos-26` image failed before compiling anything.
#
# Xcode 27 lives on GitHub's `xcode-27` preview image
# (https://github.com/actions/runner-images/issues/14404). Same rule as the old script:
# match the major, never trust the image default (27.0 there), so the newest 27.x wins
# and a refresh that renames a beta cannot break the job.

set -euo pipefail

xcode=$(ls -d /Applications/Xcode_27*.app 2>/dev/null | sort -V | tail -1 || true)

if [ -z "$xcode" ]; then
  echo "::error::No Xcode 27.x on this runner. The project file needs Xcode 27 (runs-on: xcode-27)."
  echo "Xcodes present on this image:"
  ls -d /Applications/Xcode*.app 2>/dev/null || echo "  (none)"
  exit 1
fi

echo "Selecting $xcode"
sudo xcode-select -s "$xcode"
