#!/usr/bin/env bash
# Build GoldenTime for iOS Simulator, install, and launch. Run from repo root or via path below.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SIM_NAME="${GOLDEN_TIME_SIM_DEVICE:-iPhone 17}"
BUNDLE_ID="time.golden.GoldenTime"
DERIVED="${GOLDEN_TIME_DERIVED:-/tmp/GoldenTime-derived}"
# Set GOLDEN_TIME_NO_MAP_BASE=1 when invoking this script to force the gradient-only compass (no MapKit underlay), e.g. offline QA.
# The script forwards that to the Simulator process via SIMCTL_CHILD_* (see `simctl help launch`).
# Does not clear Apple’s map tile cache; turn off Mac Wi‑Fi / Simulator networking separately if you need a truly empty map.

UDID=$(xcrun simctl list devices available | grep -F "${SIM_NAME} (" | head -1 | sed -n 's/.*(\([A-F0-9-]*\)).*/\1/p' || true)
if [[ -z "${UDID}" ]]; then
  echo "error: no available simulator named '${SIM_NAME}'." >&2
  echo "Install an iOS Simulator runtime in Xcode, or set GOLDEN_TIME_SIM_DEVICE to another name (see xcrun simctl list devices available)." >&2
  exit 1
fi

open -a Simulator || true
xcrun simctl boot "${UDID}" 2>/dev/null || true

rm -rf "${DERIVED}"
xcodebuild \
  -project GoldenTime.xcodeproj \
  -scheme GoldenTime \
  -configuration Debug \
  -destination "id=${UDID}" \
  -derivedDataPath "${DERIVED}" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="${DERIVED}/Build/Products/Debug-iphonesimulator/GoldenTime.app"
if [[ ! -d "${APP}" ]]; then
  echo "error: expected app at ${APP}" >&2
  exit 1
fi

# Always uninstall first: otherwise the Simulator often keeps an old install / caches and UI or assets look unchanged.
if [[ -z "${GOLDEN_TIME_SKIP_UNINSTALL:-}" ]]; then
  xcrun simctl uninstall "${UDID}" "${BUNDLE_ID}" 2>/dev/null || true
fi

xcrun simctl install "${UDID}" "${APP}"

if [[ "${GOLDEN_TIME_NO_MAP_BASE:-}" == "1" ]]; then
  export SIMCTL_CHILD_GOLDEN_TIME_NO_MAP_BASE=1
fi
xcrun simctl launch "${UDID}" "${BUNDLE_ID}"

echo "Launched ${BUNDLE_ID} on ${SIM_NAME} (${UDID})."
