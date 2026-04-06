# agents.md

本仓库给 **AI Agent / 自动化助手** 的完整约定在 **`AGENTS.md`**（同目录，首字母大写）。

请直接打开并遵循：**[AGENTS.md](./AGENTS.md)**。

**每一次改动后，自动 commit，并请求是否需要 push**

---

## iOS 模拟器：请用启动脚本（与 Xcode Run 的差异）

- **推荐闭环**：在仓库根目录执行 `./scripts/launch-golden-time-ios-simulator.sh`。脚本会：`killall Simulator` → `simctl shutdown` 该机型 → 再打开并 `boot`；**`simctl status_bar clear`**（去掉可能被写死的状态栏时间，例如长期显示 13:01）；**`simctl location clear` 后 `set`** 默认 **上海** 坐标（`31.230416,121.473701`，可用 `GOLDEN_TIME_SIM_LOCATION` 覆盖）；删除 App Group 内 **`gt.cached.latitude` / `longitude` / `timestamp`**（卸载主 App 不会清这组缓存，否则会一直显示旧坐标如旧金山）；**卸载** `time.golden.GoldenHourCompass` → 安装 → `launch`，并向进程注入 `TZ=Asia/Shanghai`（`GOLDEN_TIME_SIM_TZ` 可覆盖）。
- **若只按 Xcode Run**：不会跑上述 `simctl`，模拟器默认定位多在**旧金山**；状态栏时间若曾被 `simctl status_bar override` 固定，会与 App 内 **`Date()`** 显示不一致。
- 其他环境变量与跳过卸载等说明见脚本内注释（如 `GOLDEN_TIME_SIM_DEVICE`、`GOLDEN_TIME_SKIP_UNINSTALL`）。

---

## 范围与确认（对用户意图）

- **只实现用户明确说到的改动**；不要擅自隐藏/删除/重排用户**没提到**的界面、文案或行为（包括图标、额外「优化」、顺带重构）。
- 若一句话里**可能有多种理解**（例如「下面那个」「放大一点」），**先用自然语言向用户问清楚**再改代码；**不要默认替用户做主**。
- 用户要求把约定写进本文件时，**更新本节并保持简短可执行**。

## App Store URL

- `Privacy Policy URL`：`https://twilightcompass.auroracapture.com/privacy-policy.html`
- `Support URL`：`https://twilightcompass.auroracapture.com/support.html`
