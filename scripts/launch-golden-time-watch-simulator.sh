#!/usr/bin/env bash
# Build Golden Hour Compass for Watch Simulator, uninstall old build, install, launch.
#
# Important (widgets / 表盘复杂功能 / Smart Stack):
# Watch app declares WKCompanionAppBundleIdentifier. If you only `simctl install` the watch .app,
# the system often does NOT register the WidgetKit extension in the picker. When a paired *iPhone*
# simulator exists, this script defaults to building the **GoldenTime (iOS)** scheme and then:
#   1) install GoldenTime.app on the iPhone (companion)
#   2) install GoldenTime.app/Watch/GoldenTimeWatch.app on the watch (same build as embedded in iOS)
#
# Fallback: no paired phone or GOLDEN_TIME_WATCH_ONLY=1 → build GoldenTimeWatch only (widgets may stay missing).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BUNDLE_ID="time.golden.GoldenHourCompass.watchkitapp"
IOS_BUNDLE_ID="time.golden.GoldenHourCompass"
DERIVED="${GOLDEN_TIME_DERIVED:-/tmp/GoldenHourCompass-watch-derived}"
SCHEME_WATCH="${GOLDEN_TIME_WATCH_SCHEME:-GoldenTimeWatch}"
SCHEME_IOS="${GOLDEN_TIME_IOS_SCHEME:-GoldenTime}"
DEFAULT_SIM_LOCATION="${GOLDEN_TIME_SIM_LOCATION:-31.230416,121.473701}"
DEFAULT_SIM_TZ="${GOLDEN_TIME_SIM_TZ:-Asia/Shanghai}"

resolve_watch_udid() {
  if [[ -n "${GOLDEN_TIME_WATCH_UDID:-}" ]]; then
    echo "${GOLDEN_TIME_WATCH_UDID}"
    return
  fi
  local name="${GOLDEN_TIME_WATCH_SIM_DEVICE:-}"
  local udid=""
  if [[ -n "$name" ]]; then
    udid=$(xcrun simctl list devices available 2>/dev/null | grep -F "${name} (" | grep "(Booted)" | head -1 | sed -n 's/.*(\([A-F0-9-]*\)).*/\1/p' || true)
    if [[ -z "$udid" ]]; then
      udid=$(xcrun simctl list devices available 2>/dev/null | grep -F "${name} (" | head -1 | sed -n 's/.*(\([A-F0-9-]*\)).*/\1/p' || true)
    fi
  fi
  if [[ -z "$udid" ]]; then
    udid=$(xcrun simctl list devices available 2>/dev/null | grep "Apple Watch" | head -1 | sed -n 's/.*(\([A-F0-9-]*\)).*/\1/p' || true)
  fi
  echo "$udid"
}

paired_phone_udid_for_watch() {
  local w="$1"
  [[ -n "$w" ]] || return
  xcrun simctl list pairs 2>/dev/null | awk -v w="$w" '
    /Watch:/ && index($0, w) {
      getline
      if (/Phone:/) {
        if (match($0, /\([A-F0-9-]+\)/))
          print substr($0, RSTART+1, RLENGTH-2)
        exit
      }
    }
  '
}

require_widget_embedded() {
  local app="$1"
  local appex="${app}/PlugIns/GoldenTimeWatchWidgetExtension.appex"
  if [[ ! -d "${appex}" ]]; then
    echo "error: widget extension missing from watch app (expected ${appex})." >&2
    echo "Fix: Xcode → Watch App target → Build Phases → Embed Foundation Extensions → destination PlugIns (dstSubfolderSpec 13)." >&2
    exit 1
  fi
}

WATCH_UDID="$(resolve_watch_udid)"
if [[ -z "${WATCH_UDID}" ]]; then
  echo "error: no Apple Watch simulator found." >&2
  echo "Set GOLDEN_TIME_WATCH_UDID or GOLDEN_TIME_WATCH_SIM_DEVICE (substring of device name)." >&2
  exit 1
fi

open -a Simulator || true

PHONE_UDID="$(paired_phone_udid_for_watch "${WATCH_UDID}")"
if [[ -n "${PHONE_UDID}" ]]; then
  xcrun simctl boot "${PHONE_UDID}" 2>/dev/null || true
fi
xcrun simctl boot "${WATCH_UDID}" 2>/dev/null || true

xcrun simctl location "${WATCH_UDID}" set "${DEFAULT_SIM_LOCATION}" 2>/dev/null || true
if [[ -n "${PHONE_UDID}" ]]; then
  xcrun simctl location "${PHONE_UDID}" set "${DEFAULT_SIM_LOCATION}" 2>/dev/null || true
fi

rm -rf "${DERIVED}"

USE_IOS_PAIR=0
if [[ -n "${PHONE_UDID}" && -z "${GOLDEN_TIME_WATCH_ONLY:-}" ]]; then
  USE_IOS_PAIR=1
fi

if [[ "${USE_IOS_PAIR}" -eq 1 ]]; then
  echo "Building ${SCHEME_IOS} for paired iPhone ${PHONE_UDID} (registers watch widgets + companion)…"
  xcodebuild \
    -project GoldenTime.xcodeproj \
    -scheme "${SCHEME_IOS}" \
    -configuration Debug \
    -destination "id=${PHONE_UDID}" \
    -derivedDataPath "${DERIVED}" \
    CODE_SIGNING_ALLOWED=NO \
    build

  IOS_APP="${DERIVED}/Build/Products/Debug-iphonesimulator/GoldenTime.app"
  WATCH_NESTED="${IOS_APP}/Watch/GoldenTimeWatch.app"
  if [[ ! -d "${IOS_APP}" ]]; then
    echo "error: expected iOS app at ${IOS_APP}" >&2
    exit 1
  fi
  if [[ ! -d "${WATCH_NESTED}" ]]; then
    echo "error: expected embedded watch app at ${WATCH_NESTED} (iOS target must embed Watch)." >&2
    exit 1
  fi
  require_widget_embedded "${WATCH_NESTED}"

  xcrun simctl terminate "${PHONE_UDID}" "${IOS_BUNDLE_ID}" 2>/dev/null || true
  xcrun simctl terminate "${WATCH_UDID}" "${BUNDLE_ID}" 2>/dev/null || true
  if [[ -z "${GOLDEN_TIME_SKIP_UNINSTALL:-}" ]]; then
    xcrun simctl uninstall "${PHONE_UDID}" "${IOS_BUNDLE_ID}" 2>/dev/null || true
    xcrun simctl uninstall "${WATCH_UDID}" "${BUNDLE_ID}" 2>/dev/null || true
  fi

  xcrun simctl install "${PHONE_UDID}" "${IOS_APP}"
  xcrun simctl install "${WATCH_UDID}" "${WATCH_NESTED}"
else
  if [[ -z "${PHONE_UDID}" ]]; then
    echo "note: no paired iPhone for this watch — building watch-only. Widgets/complications may not appear in the picker; pair a phone in Simulator or set GOLDEN_TIME_SIM_DEVICE on iPhone + watch." >&2
  else
    echo "note: GOLDEN_TIME_WATCH_ONLY=1 — watch-only install (widgets may not list)." >&2
  fi

  xcodebuild \
    -project GoldenTime.xcodeproj \
    -scheme "${SCHEME_WATCH}" \
    -configuration Debug \
    -destination "id=${WATCH_UDID}" \
    -derivedDataPath "${DERIVED}" \
    CODE_SIGNING_ALLOWED=NO \
    build

  WATCH_APP="${DERIVED}/Build/Products/Debug-watchsimulator/GoldenTimeWatch.app"
  if [[ ! -d "${WATCH_APP}" ]]; then
    echo "error: expected watch app at ${WATCH_APP}" >&2
    exit 1
  fi
  require_widget_embedded "${WATCH_APP}"

  xcrun simctl terminate "${WATCH_UDID}" "${BUNDLE_ID}" 2>/dev/null || true
  if [[ -z "${GOLDEN_TIME_SKIP_UNINSTALL:-}" ]]; then
    xcrun simctl uninstall "${WATCH_UDID}" "${BUNDLE_ID}" 2>/dev/null || true
  fi
  xcrun simctl install "${WATCH_UDID}" "${WATCH_APP}"
fi

export SIMCTL_CHILD_TZ="${DEFAULT_SIM_TZ}"

if [[ -n "${GOLDEN_TIME_SKIP_LAUNCH:-}" ]]; then
  echo "Installed ${BUNDLE_ID} on watch ${WATCH_UDID}; launch skipped (GOLDEN_TIME_SKIP_LAUNCH=1)."
else
  xcrun simctl launch "${WATCH_UDID}" "${BUNDLE_ID}"
  echo "Launched ${BUNDLE_ID} on watch ${WATCH_UDID} with TZ=${DEFAULT_SIM_TZ}, location=${DEFAULT_SIM_LOCATION}."
fi
