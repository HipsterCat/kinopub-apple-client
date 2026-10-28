source "https://rubygems.org"

# CI and local TestFlight uploads. Ruby version is pinned in
# .github/workflows/testflight.yml (`ruby/setup-ruby` 3.3).
# 2.240.0 treats altool's "UPLOAD SUCCEEDED with no errors" as success even when
# Xcode 27 logs a spurious CDUploaderStateInfoResumeFilePath ERROR (fastlane#30130).
gem "fastlane", "~> 2.240"
