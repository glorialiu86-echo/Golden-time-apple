#!/usr/bin/env bash
# Build Golden Hour Compass (iOS) for Simulator, install, and launch. Run from repo root or via path below.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SIM_NAME="${GOLDEN_TIME_SIM_DEVICE:-iPhone 17}"
BUNDLE_ID="time.golden.GoldenHourCompass"
DERIVED="${GOLDEN_TIME_DERIVED:-/tmp/GoldenHourCompass-derived}"
# Default: Shanghai + China time for coherent local solar / twilight in Simulator (override with env if needed).
DEFAULT_SIM_LOCATION="${GOLDEN_TIME_SIM_LOCATION:-31.230416,121.473701}"
DEFAULT_SIM_TZ="${GOLDEN_TIME_SIM_TZ:-Asia/Shanghai}"
# iOS uses system wall clock by default. Optional fixed instant for Simulator QA (see `GTPreviewClock`):
#   GOLDEN_TIME_DEBUG_NOW=2026-04-04T06:02:00+08:00 ./scripts/launch-golden-time-ios-simulator.sh
# Set GOLDEN_TIME_NO_MAP_BASE=1 when invoking this script to force the gradient-only compass (no MapKit underlay), e.g. offline QA.
# Optional: GOLDEN_TIME_SIM_LOCATION=lat,lon to override the default Shanghai pin.
# The script forwards GOLDEN_TIME_NO_MAP_BASE to the Simulator process via SIMCTL_CHILD_* (see `simctl help launch`).
# Does not clear Apple’s map tile cache; turn off Mac Wi‑Fi / Simulator networking separately if you need a truly empty map.

UDID=$(xcrun simctl list devices available | grep -F "${SIM_NAME} (" | head -1 | sed -n 's/.*(\([A-F0-9-]*\)).*/\1/p' || true)
if [[ -z "${UDID}" ]]; then
  echo "error: no available simulator named '${SIM_NAME}'." >&2
  echo "Install an iOS Simulator runtime in Xcode, or set GOLDEN_TIME_SIM_DEVICE to another name (see xcrun simctl list devices available)." >&2
  exit 1
fi

open -a Simulator || true
xcrun simctl boot "${UDID}" 2>/dev/null || true

xcrun simctl location "${UDID}" set "${DEFAULT_SIM_LOCATION}" 2>/dev/null || true

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

# Stop any running instance so uninstall/install always replaces what the user opens (avoids stale in-memory / last session).
xcrun simctl terminate "${UDID}" "${BUNDLE_ID}" 2>/dev/null || true

# Always uninstall first: otherwise the Simulator often keeps an old install / caches and UI or assets look unchanged.
if [[ -z "${GOLDEN_TIME_SKIP_UNINSTALL:-}" ]]; then
  xcrun simctl uninstall "${UDID}" "${BUNDLE_ID}" 2>/dev/null || true
fi

xcrun simctl install "${UDID}" "${APP}"

if [[ "${GOLDEN_TIME_NO_MAP_BASE:-}" == "1" ]]; then
  export SIMCTL_CHILD_GOLDEN_TIME_NO_MAP_BASE=1
fi
export SIMCTL_CHILD_TZ="${DEFAULT_SIM_TZ}"

if [[ -n "${GOLDEN_TIME_DEBUG_NOW:-}" ]]; then
  export SIMCTL_CHILD_GOLDEN_TIME_DEBUG_NOW="${GOLDEN_TIME_DEBUG_NOW}"
fi

if [[ -n "${GOLDEN_TIME_SKIP_LAUNCH:-}" ]]; then
  echo "Installed ${BUNDLE_ID} on ${SIM_NAME} (${UDID}); launch skipped (GOLDEN_TIME_SKIP_LAUNCH=1). Open the app from the Home Screen."
else
  xcrun simctl launch "${UDID}" "${BUNDLE_ID}"
  if [[ -n "${SIMCTL_CHILD_GOLDEN_TIME_DEBUG_NOW:-}" ]]; then
    echo "Launched ${BUNDLE_ID} on ${SIM_NAME} (${UDID}) with TZ=${DEFAULT_SIM_TZ}, location=${DEFAULT_SIM_LOCATION}, GOLDEN_TIME_DEBUG_NOW=${SIMCTL_CHILD_GOLDEN_TIME_DEBUG_NOW}."
  else
    echo "Launched ${BUNDLE_ID} on ${SIM_NAME} (${UDID}) with TZ=${DEFAULT_SIM_TZ}, location=${DEFAULT_SIM_LOCATION}."
  fi
fi
