# Golden Time Apple

This repository is the Apple-platform migration workspace for Golden Time.

## Layout

- `Golden-time(garmin)/` — Garmin (Monkey C) reference implementation.
- `Sources/GoldenTimeCore/` — Swift port of the offline GOLDEN/BLUE engine and phase state machine (same semantics as Garmin).
- `Tests/GoldenTimeCoreTests/` — Package tests.
- `Apps/GoldenTime/` — iOS shell + watchOS UI sources.
- `GoldenTime.xcodeproj` — Xcode project at the **repository root** (next to `Package.swift`) so local SwiftPM and app targets share one build graph.

## Run on device

1. Open `GoldenTime.xcodeproj` in Xcode.
2. Set your **Team** on both targets (`GoldenTime`, `GoldenTime Watch App`).
3. Build & run the **GoldenTime** scheme on iPhone; install the watch app from the embedded Watch build.

**No networking:** iPhone 与 Apple Watch 端都只使用 **CoreLocation（GPS/定位服务）** 与 **`GoldenTimeEngine` 本地天文公式**（`Sources/GoldenTimeCore`）。工程内 **没有** `URLSession`、天气 API 或其它远程接口；推算不依赖互联网。定位服务本身可能由系统使用网络辅助，但应用代码不发起网络请求。

手机 App 展示当前日期时间、经纬度，以及「下一次」蓝调/金调的开始与结束时刻（由事件流配对得出）。手表端展示相位与下一次开始时刻等。

## Command-line build (unsigned smoke test)

```bash
xcodebuild -project GoldenTime.xcodeproj -scheme GoldenTime -configuration Debug \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Notes

- The watch target uses `com.apple.product-type.application` (watchOS) instead of `watchapp2` to avoid an Xcode 26 “multiple commands produce … executable” issue when linking SwiftPM. The iOS app still embeds the watch product under `Watch/`.
- Bundle IDs are `time.golden.GoldenTime` (iOS) and `time.golden.GoldenTime.watchkitapp` (watch); change them if you ship.
