#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf StormCRM.xcodeproj
xcodegen generate
echo "Done. Open StormCRM.xcodeproj in Xcode."
