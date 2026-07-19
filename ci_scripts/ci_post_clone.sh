#!/bin/sh
# Xcode Cloud: generate StormCRM.xcodeproj from project.yml (not committed),
# then install the committed Package.resolved Xcode Cloud requires when
# automatic SPM resolution is disabled.
# https://developer.apple.com/documentation/xcode/writing-custom-build-scripts
set -euo pipefail

echo "Installing XcodeGen…"
brew install xcodegen

cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "Generating StormCRM.xcodeproj…"
xcodegen generate

RESOLVED_SRC="$CI_PRIMARY_REPOSITORY_PATH/SwiftPM/Package.resolved"
RESOLVED_DST="$CI_PRIMARY_REPOSITORY_PATH/StormCRM.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

if [ ! -f "$RESOLVED_SRC" ]; then
  echo "error: missing $RESOLVED_SRC" >&2
  exit 1
fi

echo "Installing Package.resolved for Xcode Cloud…"
mkdir -p "$(dirname "$RESOLVED_DST")"
cp "$RESOLVED_SRC" "$RESOLVED_DST"

echo "Generated project:"
ls -la StormCRM.xcodeproj
echo "Package.resolved:"
ls -la "$RESOLVED_DST"
