#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Pick a watchOS Simulator destination. Override with GOLDEN_TIME_WATCH_DESTINATION if needed.
SCHEME="${GOLDEN_TIME_WATCH_SCHEME:-GoldenTimeWatch}"
if [[ -n "${GOLDEN_TIME_WATCH_DESTINATION:-}" ]]; then
  DEST="$GOLDEN_TIME_WATCH_DESTINATION"
else
  DEST="$(xcodebuild -project GoldenTime.xcodeproj -scheme "$SCHEME" -showdestinations 2>/dev/null \
    | grep -E 'platform:watchOS Simulator' \
    | head -1 \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' || true)"
  if [[ -z "$DEST" ]]; then
    echo "No watchOS Simulator destination found. Set GOLDEN_TIME_WATCH_DESTINATION, e.g.:"
    echo "  GOLDEN_TIME_WATCH_DESTINATION='platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'"
    exit 1
  fi
fi

echo "Scheme: $SCHEME"
echo "Using destination: $DEST"

xcodebuild test \
  -project GoldenTime.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "$DEST" \
  -only-testing:GoldenTimeWatchUITests \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
