#!/usr/bin/env bash
# Build Golden Hour Compass (iOS) for Simulator, install, and launch. Run from repo root or via path below.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SIM_NAME="${GOLDEN_TIME_SIM_DEVICE:-iPhone 17}"
BUNDLE_ID="time.golden.GoldenHourCompass"
DERIVED="${GOLDEN_TIME_DERIVED:-/tmp/GoldenHourCompass-derived}"
# Default: Shanghai pin for Simulator (People’s Square area). Override: GOLDEN_TIME_SIM_LOCATION=lat,lon
SHANGHAI_SIM_LOCATION="31.230416,121.473701"
DEFAULT_SIM_LOCATION="${GOLDEN_TIME_SIM_LOCATION:-$SHANGHAI_SIM_LOCATION}"
DEFAULT_SIM_TZ="${GOLDEN_TIME_SIM_TZ:-Asia/Shanghai}"
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

# Quit Simulator UI and shut down the device so the next boot picks up a clean session (no stale state).
killall Simulator 2>/dev/null || true
xcrun simctl shutdown "${UDID}" 2>/dev/null || true
sleep 1
open -a Simulator || true
xcrun simctl boot "${UDID}" 2>/dev/null || true

# Status bar time can be frozen by a prior `simctl status_bar override --time` (shows e.g. 13:01 while app uses real Date()).
xcrun simctl status_bar "${UDID}" clear 2>/dev/null || true

# Default sim location is San Francisco until set; clear any “scenario” then pin Shanghai.
xcrun simctl location "${UDID}" clear 2>/dev/null || true
xcrun simctl location "${UDID}" set "${DEFAULT_SIM_LOCATION}" 2>/dev/null || true

# Cached GPS lives in the App Group plist and survives `simctl uninstall`; drop it so the next fix matches the pin above.
shopt -s nullglob
for plist in "${HOME}/Library/Developer/CoreSimulator/Devices/${UDID}/data/Containers/Shared/AppGroup"/*/Library/Preferences/group.time.golden.GoldenHourCompass.plist; do
  [[ -f "${plist}" ]] || continue
  /usr/libexec/PlistBuddy -c "Delete :gt.cached.latitude" "${plist}" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Delete :gt.cached.longitude" "${plist}" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Delete :gt.cached.timestamp" "${plist}" 2>/dev/null || true
done
shopt -u nullglob

rm -rf "${DERIVED}"
xcodebuild \
  -project GoldenTime.xcodeproj \
  -scheme GoldenTime \
  -configuration Debug \
  -destination "id=${UDID}" \
  -derivedDataPath "${DERIVED}" \
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

# Re-apply pin after install (some runtimes only deliver the first CL update reliably after a fresh set).
xcrun simctl location "${UDID}" set "${DEFAULT_SIM_LOCATION}" 2>/dev/null || true

if [[ "${GOLDEN_TIME_NO_MAP_BASE:-}" == "1" ]]; then
  export SIMCTL_CHILD_GOLDEN_TIME_NO_MAP_BASE=1
fi
export SIMCTL_CHILD_TZ="${DEFAULT_SIM_TZ}"

if [[ -n "${GOLDEN_TIME_SKIP_LAUNCH:-}" ]]; then
  echo "Installed ${BUNDLE_ID} on ${SIM_NAME} (${UDID}); launch skipped (GOLDEN_TIME_SKIP_LAUNCH=1). Open the app from the Home Screen."
else
  xcrun simctl launch "${UDID}" "${BUNDLE_ID}"
  echo "Launched ${BUNDLE_ID} on ${SIM_NAME} (${UDID}) with TZ=${DEFAULT_SIM_TZ}, location=${DEFAULT_SIM_LOCATION}."
fi
