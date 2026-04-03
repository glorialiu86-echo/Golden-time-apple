# AGENTS.md — Golden Time（Apple）

给在本仓库里改代码的 **AI Agent / 自动化助手** 用：改完要 **能编译、能装到模拟器、能自动打开 App**，方便人类在 Simulator 里直接看 UI。

---

## 1. 仓库在做什么

- **`Sources/GoldenTimeCore/`** — 离线蓝调/黄金时刻引擎与相位状态机（与 Garmin 参考语义对齐）。
- **`Apps/GoldenTime/`** — iOS 壳 + watchOS 源码；**主工程** 是根目录 **`GoldenTime.xcodeproj`**（与 `Package.swift` 同级，本地 SPM 与 App 同图编译）。
- **Bundle ID（iOS）**：`time.golden.GoldenTime`  
- **Scheme**：`GoldenTime`（跑 iPhone；Watch 随嵌入产物一起编）。

**无业务联网**：应用代码只用 CoreLocation + 本地天文推算；不要在工程里加天气 API、`URLSession` 业务请求等（定位辅助由系统决定）。

---

## 2. 每次改完代码后的必做闭环（重要）

在人类当前 **无法自行点 Run** 时，Agent **每次完成与本项目相关的代码修改后**，应在有权限执行本机命令的环境里 **执行一次**：

```bash
cd "/path/to/Golden-time-apple"
./scripts/launch-golden-time-ios-simulator.sh
```

脚本会：**打开 Simulator → 启动指定机型 → 用独立 DerivedData 编译 iOS App →（先卸载旧包）→ 安装 → 启动** `time.golden.GoldenTime`。

**安装前必须先卸载（重要）**  
模拟器里若直接覆盖安装，经常出现 **旧包 / 缓存** 不刷新，表现为 **改代码、换图标、改 Info 都像没生效**。因此验证 UI 或资源时务必 **先删 App 再装**：

- 脚本默认会在 `simctl install` 之前执行 **`xcrun simctl uninstall <UDID> time.golden.GoldenTime`**（失败则忽略，例如尚未安装过）。
- 若你**手写** `xcodebuild` + `simctl install`，请在 **`install` 前**自行执行同一条 `uninstall`，或先在模拟器主屏幕 **长按删除 App**。
- 临时想跳过卸载（仅调试用，不推荐）：`GOLDEN_TIME_SKIP_UNINSTALL=1 ./scripts/launch-golden-time-ios-simulator.sh`

说明：脚本里每次会 **`rm -rf` 独立 DerivedData**，这只保证 **编译产物干净**；**已装进模拟器的 .app 与部分缓存** 仍可能不更新，所以 **卸载步骤不能省**。

- 默认模拟器名称：**iPhone 17**。若本机没有该机型，可换名：  
  `GOLDEN_TIME_SIM_DEVICE='iPhone 16' ./scripts/launch-golden-time-ios-simulator.sh`
- 可选指定 DerivedData 目录：  
  `GOLDEN_TIME_DERIVED="$HOME/tmp/GT-dd" ./scripts/launch-golden-time-ios-simulator.sh`

**Agent 在回复里应简要说明**：已执行上述脚本（或等价的 `xcodebuild` + `simctl install` + `simctl launch`），以及是否 **BUILD SUCCEEDED**、是否 **launch 成功**（若失败，贴出末尾错误信息）。

**限制说明**：Cursor 沙箱环境可能无法连接 CoreSimulator；若命令报 `CoreSimulatorService` / `Connection refused`，需要在 **非沙箱、可访问本机 Simulator 的终端** 重试，或请人类本地执行同一条脚本。Agent 仍应 **写出** 这条命令，保证流程可复现。

### 2.1 模拟器验证：时区与经纬度须成套（默认）

`GoldenTimeEngine` 使用 **`TimeZone.autoupdatingCurrent`**；Simulator 的时区通常跟 **宿主 Mac** 走。若 **模拟 GPS 在甲地** 而 **Mac 系统时区在乙地**，晨昏时刻会与「人就在当地、自动时区」的真机体验不一致，**不要用这种混搭作为默认测试**。

**以后 Agent 做「拉起模拟器验收 / 定位相关手测」时，默认任选下面一整套（坐标 + 时区语义一致），不要混用：**

| 默认 | 模拟定位（`simctl`） | Mac 日期与时间（与引擎一致） |
|------|----------------------|------------------------------|
| **A（推荐，与中国常用场景一致）** | `xcrun simctl location booted set 31.230416,121.473701`（上海，人民广场附近） | **自动**；若手动固定，选 **亚洲 · 上海**（或与华东一致的东八区 civil 时区） |
| **B（北美参考，贴近 Xcode 习惯）** | `xcrun simctl location booted set 37.3349,-122.0090`（Apple Park 一带） | **自动**；若手动固定，选 **美洲 · 洛杉矶**（或与加州一致的时区） |

**建议顺序**：确保目标 Simulator 已 **Booted** → 执行上表 **`location booted set …`** → 再跑 **`./scripts/launch-golden-time-ios-simulator.sh`**。需要清掉自定义 GPS：`xcrun simctl location booted clear`。

**单元测试**：涉及「某日清晨蓝调/金调顺序」等断言时，`GoldenTimeEngine(timeZone:)` 应与 **坐标所在地区** 一致（参见 `Tests/GoldenTimeCoreTests/GoldenTimeEngineTests.swift`）；不要默认写成「中国时区 + 美洲坐标」这类组合，除非明确在测边界情况。

---

## 3. 仅编译（不启动模拟器）

```bash
xcodebuild -project GoldenTime.xcodeproj -scheme GoldenTime -configuration Debug \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

SwiftPM 单测：

```bash
swift test
```

---

## 4. 真机与签名

- `DEVELOPMENT_TEAM` 可能在工程里为空；真机需在 Xcode 里为 **GoldenTime** 与 **Watch** 目标设置 **Team**。
- 模拟器可用 **`CODE_SIGNING_ALLOWED=NO`**（脚本已带）。

---

## 5. 改代码时的约定（简）

- **只改任务相关文件**，不顺带大重构、不擅自加文档（除非用户要）。
- UI 字符串若面向用户，可与产品其余中文文案保持一致；引擎与类型命名保持英文。
- **不要**在回复里假装「已截图」；人类自己在 Simulator 里验收画面。

---

## 6. 与 Garmin 子目录的关系

- **`Golden-time(garmin)/`** 是 Connect IQ 参考实现；**本 AGENTS.md 针对 Apple 工程**。Garmin 侧若有单独规范，以该目录内文档为准。
