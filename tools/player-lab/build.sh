#!/bin/zsh
# Builds the Player Lab for the tvOS simulator, installs and launches it.
#   ./build.sh                 build + install + launch
#   ./build.sh -autoplay 8739-e1   ... open a row straight away (id = catalogue id + -eN)
# The lab compiles the real KinoPubMedia sources (PlayerInfo, MediaContext, genres) into the app.
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
OUT=build/PlayerLab.app; rm -rf $OUT; mkdir -p $OUT
[[ -f build/clip.mp4 ]] || ffmpeg -y -loglevel error -f lavfi -i testsrc2=size=1280x720:rate=24 -f lavfi -i sine=frequency=440 \
  -t 120 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest build/clip.mp4
cp build/clip.mp4 $OUT/clip.mp4
cp ../../Packages/KinoPubMedia/Sources/KinoPubMedia/Resources/genres.json $OUT/genres.json
cp "${CATALOG:-$HOME/Documents/GitHub/Plozz/Sources/ProviderKinoPubDemo/Resources/KinoPubDemoCatalog.json}" $OUT/catalog.json
xcrun --sdk appletvsimulator swiftc -parse-as-library -swift-version 5 -target arm64-apple-tvos26.0-simulator \
  ../../Packages/KinoPubMedia/Sources/KinoPubMedia/*.swift Sources/*.swift -o $OUT/PlayerLab
cat > $OUT/Info.plist <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.kinopub.playerlab</string>
<key>CFBundleExecutable</key><string>PlayerLab</string>
<key>CFBundleName</key><string>Player Lab</string>
<key>CFBundleDisplayName</key><string>Player Lab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/>
<key>UISceneConfigurations</key><dict><key>UIWindowSceneSessionRoleApplication</key><array><dict>
<key>UISceneConfigurationName</key><string>Default</string>
<key>UISceneDelegateClassName</key><string>PlayerLab.SceneDelegate</string></dict></array></dict></dict>
</dict></plist>
PL
codesign -s - --force $OUT
DEVICE=${DEVICE:-$(xcrun simctl list devices booted | grep "Apple TV" | head -1 | grep -o '[0-9A-F-]\{36\}')}
xcrun simctl install $DEVICE $OUT
xcrun simctl terminate $DEVICE dev.kinopub.playerlab 2>/dev/null || true
xcrun simctl launch $DEVICE dev.kinopub.playerlab "$@"
