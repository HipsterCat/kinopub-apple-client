# PR #21 hig Watch Now shots

Local capture only. CI has no kino.pub session.

Requires `~/.kinopub-dev-session.json` (the DEBUG session mirror). Tests skip without it.

Evidence path is **`XCUIRemote.shared.press(.down)`** until a `piratic.poster.*` cell has focus. Do not rely on `-PIRATICFocusFirstPoster` / `UIFocusSystem.requestFocusUpdate` — that path did not leave the Watch Now tab pill.

```bash
# Both light and dark (tvOS Simulator)
xcodebuild test \
  -project Piratic.xcodeproj \
  -scheme Piratic \
  -destination 'platform=tvOS Simulator,name=Apple TV' \
  -only-testing:PiraticUITests/WatchNowHigShotsUITests

# Light only
xcodebuild test \
  -project Piratic.xcodeproj \
  -scheme Piratic \
  -destination 'platform=tvOS Simulator,name=Apple TV' \
  -only-testing:PiraticUITests/WatchNowHigShotsUITests/testLightHotMoviesCaptionShot

# Dark only
xcodebuild test \
  -project Piratic.xcodeproj \
  -scheme Piratic \
  -destination 'platform=tvOS Simulator,name=Apple TV' \
  -only-testing:PiraticUITests/WatchNowHigShotsUITests/testDarkHotMoviesCaptionShot
```

PNGs:

- `docs/pr21-shots/watch-now-light-hot-movies.png`
- `docs/pr21-shots/watch-now-dark-hot-movies.png`
- copies under `/tmp/kinopub-pr21-shots/`
- XCTAttachments on the test result

Pass: focused Hot Movies 2:3 poster (visible scale + caption under it), not the Watch Now tab pill, not Continue Watching landscape.
