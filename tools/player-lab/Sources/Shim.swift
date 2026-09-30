import Foundation

// KinoPubMedia is a SwiftPM target and reads `genres.json` through `Bundle.module`. The lab
// compiles its sources straight into the app, so this stands in for the generated accessor;
// `build.sh` copies the file into the app bundle.
extension Bundle {
  static var module: Bundle { .main }
}
