#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/radar-holiday-check.XXXXXX")
trap 'rm -rf "$CHECK_DIR"' EXIT
python3 - "$CHECK_DIR/JSONValue.swift" <<'PY'
from pathlib import Path
import sys
source = Path('StormCRM/Core/Models/Models.swift').read_text()
a = source.index('enum JSONValue:')
b = source.index('\nstruct PartsRunGetResponse', a)
Path(sys.argv[1]).write_text('import Foundation\n' + source[a:b])
PY
swiftc -module-cache-path "${RADAR_SWIFT_MODULE_CACHE:-$CHECK_DIR/cache}" "$CHECK_DIR/JSONValue.swift" StormCRM/Features/HolidayLighting/HolidayQuoteModels.swift StormCRM/Features/Schedule/ScheduleTimelineGeometry.swift StormCRM/Features/HolidayLighting/HLMapHitTesting.swift NativeTests/HolidayQuoteModelsChecks.swift -o "$CHECK_DIR/check"
"$CHECK_DIR/check" "$@"
