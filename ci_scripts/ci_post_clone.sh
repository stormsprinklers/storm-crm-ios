#!/bin/sh
# Xcode Cloud: generate StormCRM.xcodeproj from project.yml (not committed).
# https://developer.apple.com/documentation/xcode/writing-custom-build-scripts
set -euo pipefail

echo "Installing XcodeGen…"
brew install xcodegen

echo "Generating StormCRM.xcodeproj…"
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

echo "Generated project:"
ls -la StormCRM.xcodeproj
