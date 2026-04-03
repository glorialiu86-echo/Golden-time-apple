# Garmin Connect IQ / Monkey C 嵌入式开发复盘与排障手册

**项目**：Golden-time 表盘（可迁移模板）  
**开发周期**：2026-02-18 ~ 2026-02-20（48小时）  
**SDK 版本**：Connect IQ SDK `<CIQ_SDK_VERSION>`  
**目标设备**：`<TARGET_DEVICE>`  
**开发环境**：macOS + VS Code + Monkey C 扩展

---

## 文档健康检查（由 Codex 生成）

本节是文档工程质量审计（非代码审计），用于判断该文档是否可跨仓库复用。

- 硬编码路径：存在。原文多处使用本机绝对路径和固定截图目录，已统一改为 `<REPO_ROOT>/...` 或环境变量形式。
- 设备型号写死：存在。原文多处固定为 `<TARGET_DEVICE>`，已统一改为 `<TARGET_DEVICE>` 占位。
- SDK 版本强绑定：存在。原文固定具体 SDK 小版本及安装目录后缀，已统一改为 `<CIQ_SDK_VERSION>` 占位。
- 步骤缺少失败回退：存在。已补充“构建/运行失败快速分诊图”并为每类故障给出第一检查点。
- 重复或语义重叠：存在。原“常见错误总表”“快速排障决策树”“遇到问题时”有重叠；本次新增热力表与分诊图作为统一入口，原内容保留为扩展阅读。
- 无法独立执行步骤：存在。原文部分步骤依赖本仓库上下文（如提交号、特定脚本名）；已新增“迁移到新表盘仓库的步骤”用于独立落地。

判定结论：经占位符化与新增路由后，可作为跨仓库 CIQ 排障基线文档使用。

---

## 迁移到新表盘仓库的步骤

1. 复制 `docs/ciq-embedded-postmortem.md` 与 `docs/ciq-preflight-checklist.md` 到新仓库 `docs/`。
2. 在新仓库 `README.md` 添加两条入口链接，指向上述两份文档。
3. 全仓替换占位符：`<REPO_ROOT>`、`<TARGET_DEVICE>`、`<CIQ_SDK_VERSION>`。
4. 将构建命令中的输出产物名替换为新项目产物（如 `<REPO_ROOT>/bin/<APP_NAME>.prg`）。
5. 把“证据来源”字段改为新仓库真实证据（脚本路径、构建日志、commit）。
6. 若暂时没有证据，保留规则但在条目末尾标记“经验性规则（Heuristic）”。
7. 在首次可运行后，补录一次“编译成功 + 模拟器运行 + 真机验证（如有）”日志样本。

---

## 构建/运行失败快速分诊图

目标：30 秒内确定第一排查方向。

1. 编译期失败（`monkeyc` 报错）
第一检查点：确认 `monkeyc` 路径与 `<CIQ_SDK_VERSION>` 是否匹配，且 `--device <TARGET_DEVICE>` 与 `monkey.jungle` 一致。
2. rez/资源失败（`resource not found`、尺寸不兼容）
第一检查点：检查 `<REPO_ROOT>/resources/` 与 `manifest.xml` 资源引用名是否一致。
3. 模拟器异常（无法连接、黑屏、无变化）
第一检查点：先启动 Connect IQ GUI，再等待 5-8 秒后执行 `monkeydo`；确认产物时间戳是最新。
4. 真机异常（模拟器正常但真机异常）
第一检查点：检查 `.iq`/`.prg` 是否为同一构建产物，确认权限、API 等级、设备能力是否匹配。
5. 时间/算法逻辑异常（倒计时错误、时区偏差）
第一检查点：对照固定输入（经纬度 + UTC 时间戳）跑 Python/日志双轨比对，先确认基准一致。
6. 日志为空（无 `System.println`）
第一检查点：先判定是否执行到目标路径；若不稳定，切换 UI 可观测验证（显示版本号/状态码）。

---

## CIQ 常见错误概率热力表

| 错误类别 | 发生概率 | 典型触发场景 | 首选检查动作 | 是否曾在本项目出现 |
|---|---|---|---|---|
| SDK 路径/命令不可用 | High | 新机器或 SDK 切换后直接构建 | 打印 `SDK_BIN` 并执行 `monkeyc --help` | Yes |
| 设备目标不匹配 | High | `--device` 与 jungle/模拟器目标不一致 | 统一 `<TARGET_DEVICE>` 并重编译 | Yes |
| 资源引用/尺寸问题 | High | 替换图标或布局文件后 | 核对 `manifest.xml` 与 `<REPO_ROOT>/resources/` | Yes |
| 日志为空导致不可诊断 | Medium | 代码提前 return、日志缓冲、路径未执行 | 增加路径日志或切 UI 证据 | Yes |
| 时区/UTC 基准混乱 | Medium | 算法从脚本移植到 Monkey C | 固定输入比对 UTC 计算链路 | Yes |
| 变量绑定错误（语义正确但值错误） | Medium | 多阶段阈值变量命名不清 | 检查是否存在 `var a = b` 式误绑定 | Yes |
| 模拟器连接失败 | Medium | 直接 `monkeydo` 未先启动 GUI | 回到“open GUI -> wait -> monkeydo” | Yes |
| 真机特有崩溃 | Low | 权限/API/内存差异在真机暴露 | 最小包验证并核对权限与 API | No |

说明：
- `是否曾在本项目出现=Yes` 的条目来自本仓库文档证据（构建日志、commit、脚本记录）。
- `Low` 概率并不代表低风险，真机异常通常影响发布质量。

---

## 模拟器可信度边界

可相信模拟器的现象（仓库证据）：
- 编译后是否能加载最新 `.prg`（可由产物时间戳和界面变化验证）。
- 纯 UI 布局是否越界/被裁切（基础排版问题可在模拟器先发现）。
- 基础逻辑分支是否触发（通过日志或 UI 状态码）。

必须以真机为准的现象（经验性规则 Heuristic）：
- GPS fix 速度与稳定性、后台行为、传感器噪声、功耗表现。
- 不同固件版本下的权限行为和性能边界。
- 长时间运行后的内存压力与回收行为。

模拟器经常“假正常”的场景（经验性规则 Heuristic）：
- 权限链路在模拟器可通过，但真机受限。
- 资源/性能边界在模拟器无感，真机出现卡顿或崩溃。

模拟器经常“假异常”的场景（仓库证据 + 经验性规则）：
- “Unable to connect to simulator” 常由启动顺序引起，不代表程序有错（仓库已有该类记录）。
- 日志偶发为空，不等于逻辑未执行，应切换 L2/L3 证据链。

---

## 一、背景与范围

本手册覆盖 Golden-time 表盘开发过程中遇到的所有关键问题，包括：

- **Monkey C 编译/链接**：语法错误、类型系统、命名空间
- **资源编译（rez）**：图片、布局、资源名冲突
- **Jungle 配置**：设备目标、SDK 路径
- **模拟器调试**：日志抓取、渲染延迟、窗口识别
- **算法验证**：时间基准、变量绑定、精度问题
- **真机部署**：.iq 文件生成、设备适配

**目标读者**：首次接触 Garmin Connect IQ 开发的开发者，或需要快速排查编译/运行问题的维护者。

---

## 二、标准工作流（最短路径）

### 2.1 环境准备

1. **安装 Connect IQ SDK**
   ```bash
   # 下载地址：https://developer.garmin.com/connect-iq/sdk/
   # macOS 默认安装路径：
   <CIQ_SDK_ROOT>/connectiq-sdk-<CIQ_SDK_VERSION>-*/
   ```

2. **配置开发者密钥**
   ```bash
   # 生成密钥（首次）
   openssl genrsa -out developer_key 4096
   
   # 或使用项目现有密钥
   cp developer_key ~/.Garmin/ConnectIQ/developer_key
   ```

3. **安装 VS Code 扩展**
   - Monkey C（Garmin 官方）

### 2.2 构建与运行

**标准构建命令**（来自 `<REPO_ROOT>/deploy.sh`）：
```bash
SDK_BIN="<CIQ_SDK_ROOT>/connectiq-sdk-<CIQ_SDK_VERSION>/bin"

# 构建
"$SDK_BIN/monkeyc" \
    --jungles monkey.jungle \
    --device <TARGET_DEVICE> \
    --output <REPO_ROOT>/bin/Golden-time.prg \
    --private-key developer_key \
    --warn

# 部署到模拟器
"$SDK_BIN/monkeydo" <REPO_ROOT>/bin/Golden-time.prg <TARGET_DEVICE>
```

**证据来源**：`<REPO_ROOT>/deploy.sh` (commit 04db559)

### 2.3 验证流程

**三级验证闭环**（来自 `AGENTS.md`）：

1. **Python 单测**（算法验证）
   ```bash
   python3 test_algorithm.py
   ```

2. **Monkey C 编译**
   ```bash
   monkeyc --device <TARGET_DEVICE> --jungles monkey.jungle --output <REPO_ROOT>/bin/test.prg
   ```

3. **模拟器/真机验证**
   ```bash
   monkeydo <REPO_ROOT>/bin/test.prg <TARGET_DEVICE>
   # 检查 [SNAPSHOT] 日志输出
   ```

**证据来源**：`AGENTS.md` 第七章"修复闭环规则"

---

## 三、常见错误总表

| 错误现象 | 典型报错关键词 | 根因类别 | 快速判断 | 解决步骤 | 预防措施 | 证据来源 |
|---------|---------------|---------|---------|---------|---------|---------|
| 编译失败：找不到 monkeyc | `command not found` | 环境配置 | 检查 SDK 是否安装 | 使用完整路径：`$SDK_BIN/monkeyc` | 在脚本中硬编码 SDK 路径 | `<REPO_ROOT>/deploy.sh` 修复记录 |
| 编译警告：图标尺寸不匹配 | `launcher icon (24x24) isn't compatible` | 资源配置 | 检查 manifest.xml | 提供 40x40 图标或忽略警告 | 按设备要求准备多尺寸图标 | 构建输出 (2026-02-20) |
| 运行时：倒计时显示 `--:--` | `blueTs=null goldenTs=null` | 算法逻辑 | 检查 [SNAPSHOT] 日志 | 验证算法返回值，检查变量绑定 | 先用 Python 验证算法 | commit 0b149b4 |
| 变量值相同（应该不同） | `blueStart == goldenEnd` | 变量绑定错误 | 打印变量值对比 | 检查是否有 `var a = b;` 导致共享引用 | 使用独立变量，避免互相赋值 | commit 0b149b4, PRD 5.1 |
| 时间计算错误（偏差数小时） | 时间与预期差 ±8 小时 | 时区/UTC 混乱 | 对比 Python 输出 | 统一使用 UTC 时间戳，时区修正只做一次 | 在 NOAA 公式中统一处理时区 | commit 0b149b4, PRD 8.2 |
| 模拟器日志为空 | 无 System.println 输出 | 代码未执行到 | 检查是否提前 return | 在关键路径添加日志，或用 UI 显示 debug 信息 | 使用 L2 验证（UI 可观测） | AGENTS.md "验证证据等级" |
| 模拟器窗口无法自动识别 | AppleScript 错误 -1728 | 进程名不匹配 | 手动查看进程名 | 使用手动截图或简化脚本 | 用系统快捷键截图 | `screenshot.sh` 修复记录 |
| 整数除法导致精度丢失 | 二分查找死循环 | 类型系统 | 检查除法运算 | 改用 `/ 2.0` 强制浮点运算 | 涉及精度的计算用浮点数 | commit a258bbe |
| 资源编译失败 | `resource not found` | 资源路径 | 检查 resources/ 目录结构 | 确保资源文件存在且路径正确 | 遵循 Connect IQ 资源命名规范 | - |
| 设备目标不匹配 | `0 OUT OF 2 DEVICES BUILT` | jungle 配置 | 检查 --device 参数 | 确保 jungle 和命令行参数一致 | 在 jungle 中明确列出支持设备 | 构建输出 |
| 后台权限警告 | `Background permission enabled but no source code annotated` | manifest 配置 | 检查是否真的需要后台 | 移除 manifest.xml 中的 Background 权限 | 按需配置权限 | 构建输出 (2026-02-20) |
| 使用已弃用 API | `getProperty is deprecated` | API 版本 | 检查 SDK 文档 | 使用新 API 替代 | 参考最新 SDK 文档 | 构建输出 (2026-02-20) |

---

## 四、Monkey C / Connect IQ 典型坑

### 4.1 资源编译（rez）

**问题**：图标尺寸不匹配
- **现象**：`WARNING: The launcher icon (24x24) isn't compatible with the specified launcher icon size of the device '<TARGET_DEVICE>' (40x40)`
- **根因**：不同设备要求不同尺寸的启动图标
- **解决**：
  1. 准备多尺寸图标（24x24, 40x40, 80x80）
  2. 或接受警告（图标会被自动缩放）
- **证据**：构建输出 (2026-02-20 00:03)

### 4.2 Jungle 配置

**问题**：设备目标不一致
- **现象**：`0 OUT OF 2 DEVICES BUILT`
- **根因**：`monkey.jungle` 中未列出目标设备，或命令行参数错误
- **解决**：
  ```
  # monkey.jungle
  project.manifest = manifest.xml
  
  # 命令行必须匹配
  monkeyc --device <TARGET_DEVICE> --jungles monkey.jungle
  ```
- **证据**：`monkey.jungle` 内容

### 4.3 类型系统与变量绑定

**问题 1：变量共享引用**
- **现象**：两个变量应该不同，但值相同
- **根因**：`var goldenStart = blueEnd;` 导致两个变量指向同一个值
- **解决**：使用独立变量，避免互相赋值
- **证据**：commit 0b149b4 "fix: 修复变量绑定错误"

**问题 2：整数除法精度丢失**
- **现象**：二分查找死循环，或时间戳计算错误
- **根因**：`(hi - lo) / 2` 的整数截断
- **解决**：改用 `/ 2.0` 强制浮点运算
- **证据**：commit a258bbe "Add integer conversion"

### 4.4 算法/时间基准

**问题：UTC vs 本地时间混乱**
- **现象**：计算出的时间与预期差 ±8 小时（或其他时区偏移）
- **根因**：
  1. 时间戳基准不统一（有的用 UTC，有的用本地时间）
  2. 时区修正做了多次（或没做）
- **解决**：
  1. **所有时间戳统一用 UTC**
  2. **时区修正只在 NOAA 公式中做一次**：
     ```monkey-c
     solarNoon = 720 - 4*lon - eqTime + tz*60  // 本地时间（分钟）
     eventTs = dayStartTs + (eventHourLocal - tz) * 3600  // 转回 UTC
     ```
  3. **禁止在多处加减时区偏移**
- **证据**：commit 0b149b4, PRD 第八章"变量结构约束"

**问题：变量绑定导致"看似对但全错"**
- **现象**：Python 算法正确，Monkey C 移植后全错
- **根因**：`var goldenStart = blueEnd;` 导致两个时间点相同
- **解决**：使用 6 个独立变量：
  ```monkey-c
  var morningBlueStart;
  var morningBlueGoldenBoundary;
  var morningGoldenEnd;
  var eveningGoldenStart;
  var eveningGoldenBlueBoundary;
  var eveningBlueEnd;
  ```
- **证据**：PRD 第八章"六个时间点变量"

### 4.5 运行时崩溃

**问题：模拟器可跑但真机不行**
- **可能原因**：
  1. 资源文件在模拟器中存在，但未正确打包到 .iq
  2. 使用了模拟器特有的 API
  3. 内存占用超出真机限制
- **诊断**：
  1. 检查 .iq 文件大小（本项目：53KB）
  2. 检查 manifest.xml 中的权限和 API 级别
  3. 使用 `--package-app` 生成完整包
- **证据**：`<REPO_ROOT>/deploy.sh` 构建命令

---

## 五、模拟器不稳定/日志抓不到

### 5.1 症状

- **日志为空**：`System.println()` 无输出
- **窗口无法识别**：AppleScript 无法自动截图
- **渲染延迟**：部署后需要等待 5-10 秒才能看到效果

### 5.2 可能原因

1. **代码未执行到日志语句**：提前 return 或异常退出
2. **模拟器进程名不匹配**：AppleScript 查找失败
3. **日志输出被缓冲**：需要等待或刷新

### 5.3 替代诊断策略

**L1：日志证据**（优先）
- 在关键路径添加 `System.println()`
- 使用唯一标记（如时间戳、版本号）确认代码执行

**L2：UI 可观测证据**（日志不稳定时默认）
- 在界面显示 debug 信息：
  ```monkey-c
  dc.drawText(x, y, Graphics.FONT_TINY, "v1.1", Graphics.TEXT_JUSTIFY_RIGHT);
  ```
- 使用颜色/图标变化表示状态
- 截图验证

**L3：产物一致性证据**
- 检查 .prg 文件时间戳
- 确认 target device 与模拟器一致
- 验证 SDK 版本

**证据来源**：AGENTS.md "验证证据等级"

### 5.4 模拟器截图自动化

**问题**：AppleScript 无法识别模拟器窗口
- **根因**：进程名不是 `simulator`，而是 `ConnectIQ.app/Contents/MacOS/simulator`
- **解决**：
  1. 使用系统快捷键手动截图：`Cmd + Shift + 4 + 空格`
  2. 修改系统截图保存位置：
     ```bash
     defaults write com.apple.screencapture location <REPO_ROOT>/screenshots
     killall SystemUIServer
     ```
- **证据**：`screenshot.sh` 修复记录

---

## 六、开发前检查清单

### 必须检查（10 项）

- [ ] SDK 已安装且路径正确
- [ ] 开发者密钥已生成（`developer_key`）
- [ ] `monkey.jungle` 中列出了目标设备
- [ ] `manifest.xml` 中的权限与实际需求一致
- [ ] 资源文件（图片、布局）存在且路径正确
- [ ] 所有时间戳使用 UTC 基准
- [ ] 关键变量使用独立声明，避免互相赋值
- [ ] 涉及精度的计算使用浮点数（`/ 2.0`）
- [ ] 添加了足够的日志输出（或 UI debug 信息）
- [ ] 准备了截图/日志保存路径

### 建议检查（8 项）

- [ ] 算法先用 Python 验证通过
- [ ] 准备了多尺寸启动图标
- [ ] 设置了自动化构建脚本（如 `<REPO_ROOT>/deploy.sh`）
- [ ] 配置了截图保存目录
- [ ] 准备了测试用的固定经纬度（如上海 31.2°N, 121.5°E）
- [ ] 文档中记录了已知问题和解决方案
- [ ] 使用 Git 管理代码，关键修复有清晰的 commit message
- [ ] 准备了 PRD 或设计文档

---

## 七、最小复现与二分法

### 7.1 问题缩小策略

当遇到复杂问题时，按以下顺序缩小范围：

1. **禁用模块**
   - 注释掉非核心功能（如 UI、后台服务）
   - 只保留最小可运行代码

2. **替换资源**
   - 用简单的纯色图片替换复杂背景
   - 移除自定义字体

3. **锁定输入**
   - 使用固定时间戳（如 `1771478406`）
   - 使用固定经纬度（如上海 31.2°N, 121.5°E）
   - 禁用 GPS 请求

4. **逐步恢复**
   - 每次恢复一个功能
   - 验证通过后再恢复下一个

### 7.2 二分注释法

**示例**：算法返回 null，但不知道哪里出错

```monkey-c
function calculateEvent() {
    System.println("[DEBUG] Step 1: Start");
    var a = computeA();
    System.println("[DEBUG] Step 2: a=" + a);
    
    var b = computeB(a);
    System.println("[DEBUG] Step 3: b=" + b);
    
    var c = computeC(b);
    System.println("[DEBUG] Step 4: c=" + c);
    
    return c;
}
```

通过日志定位到哪一步返回了 null，然后深入该函数继续二分。

---

## 八、下次如何采集证据

### 8.1 遇到新问题时记录的字段

创建 `docs/issues/YYYY-MM-DD-问题描述.md`，包含：

```markdown
## 问题描述
[一句话描述问题]

## 环境信息
- SDK 版本：connectiq-sdk-<CIQ_SDK_VERSION>
- 目标设备：<TARGET_DEVICE>
- 开发环境：macOS 14.x + VS Code
- Commit hash：[当前 commit]

## 复现步骤
1. [步骤 1]
2. [步骤 2]
3. [步骤 3]

## 完整报错
```
[粘贴完整的编译/运行错误]
```

## 日志输出
```
[粘贴相关日志]
```

## 截图/视频
[保存到 <REPO_ROOT>/docs/issues/screenshots/]

## 尝试过的解决方案
- [ ] 方案 1：[描述] → [结果]
- [ ] 方案 2：[描述] → [结果]

## 最终解决方案
[描述最终有效的方案]

## 根因分析
[为什么会出现这个问题]

## 预防措施
[如何避免再次出现]
```

### 8.2 关键证据采集

**编译错误**：
- 完整的 `monkeyc` 命令
- 完整的错误输出（不要截断）
- 相关代码片段（前后 5-10 行）

**运行时错误**：
- 模拟器日志（完整）
- 截图（显示问题现象）
- [SNAPSHOT] 输出（如果有）

**算法错误**：
- Python 验证输出
- Monkey C 日志输出
- 对比数据（预期 vs 实际）

---

## 九、典型案例复盘

### 案例 1：变量绑定错误导致倒计时相同

**Commit**：0b149b4 "fix: 修复变量绑定错误和时间基准问题"

**问题**：
- 蓝调和金调倒计时显示相同的值
- [SNAPSHOT] 输出：`blueTs=1771492349 goldenTs=1771492349`

**根因**：
```monkey-c
// 错误代码
var blueEnd = calculateThreshold(-4);
var goldenStart = blueEnd;  // ❌ 导致两个变量相同
```

**解决**：
```monkey-c
// 正确代码
var morningBlueGoldenBoundary = calculateThreshold(-4);  // 晨蓝调结束 = 晨金调起点
var eveningGoldenBlueBoundary = calculateThreshold(-4);  // 夜金调结束 = 夜蓝调起点
```

**教训**：
- 避免变量互相赋值
- 使用语义明确的变量名
- 先用 Python 验证逻辑

---

### 案例 2：时间基准混乱导致偏差 8 小时

**Commit**：0b149b4 "fix: 修复变量绑定错误和时间基准问题"

**问题**：
- 计算出的时间与预期差 8 小时（上海时区 UTC+8）
- Python 算法正确，Monkey C 移植后错误

**根因**：
- 时间戳基准不统一（有的用 UTC，有的用本地时间）
- 时区修正做了多次

**解决**：
1. 统一使用 UTC 时间戳
2. 时区修正只在 NOAA 公式中做一次：
   ```monkey-c
   var solarNoon = 720 - 4*lon - eqTime + tz*60;  // 本地时间（分钟）
   var eventTs = dayStartTs + (eventHourLocal - tz) * 3600;  // 转回 UTC
   ```

**教训**：
- 时间基准必须在文档中明确声明
- 时区修正只做一次，不要重复加减

---

### 案例 3：模拟器日志为空，无法诊断

**问题**：
- `System.println()` 无输出
- 无法确认代码是否执行

**解决**：
- 切换到 L2 验证（UI 可观测）
- 在界面右下角显示版本号：`v1.1`
- 通过截图确认代码执行

**教训**：
- 不要依赖单一诊断方式
- 准备多级验证策略（L1/L2/L3）

---

## 十、证据缺口与待补充

### 10.1 当前证据缺口

1. **模拟器崩溃日志**：未能稳定抓取模拟器崩溃时的完整日志
2. **真机部署失败**：未在真机上测试，缺少真机特有问题的案例
3. **资源编译错误**：未遇到资源编译失败的案例，缺少相关排查经验
4. **多设备适配**：仅在 <TARGET_DEVICE> 上测试，缺少其他设备的适配经验

### 10.2 下次需要补充的证据

如果遇到以下问题，请按此格式记录：

1. **模拟器崩溃**
   - 崩溃前的最后一条日志
   - 崩溃时的截图
   - 崩溃后的 .crash 文件（如果有）

2. **真机部署失败**
   - 真机型号和固件版本
   - .iq 文件大小
   - 部署时的错误信息

3. **资源编译错误**
   - 资源文件路径和大小
   - manifest.xml 中的资源配置
   - 完整的编译错误输出

4. **多设备适配问题**
   - 设备型号和屏幕分辨率
   - 安全区域计算结果
   - UI 显示异常的截图

---

## 十一、参考资料

### 11.1 项目文档

- `AGENTS.md` - 工作空间规则与验证流程
- `Garmin Watch Face Golden-time PRD.md` - 产品需求文档
- `WatchFace_UI_Specification.md` - UI 设计规范
- `test_algorithm.py` - Python 算法验证脚本

### 11.2 官方文档

- [Connect IQ SDK 文档](https://developer.garmin.com/connect-iq/api-docs/)
- [Monkey C 语言参考](https://developer.garmin.com/connect-iq/monkey-c/)
- [Connect IQ 开发者论坛](https://forums.garmin.com/developer/connect-iq/)

### 11.3 关键 Commit

- `5991875` - Initial commit
- `0b149b4` - 修复变量绑定错误和时间基准问题
- `04db559` - 修复背景图与顶部日月贴图随时间切换

---

## 十二、快速排障决策树

```
遇到问题
├─ 编译失败？
│  ├─ 找不到 monkeyc → 检查 SDK 路径
│  ├─ 语法错误 → 检查 Monkey C 语法
│  ├─ 资源错误 → 检查 resources/ 目录
│  └─ 设备不匹配 → 检查 jungle 配置
│
├─ 运行时错误？
│  ├─ 显示 --:-- → 检查算法返回值
│  ├─ 时间偏差 → 检查时区处理
│  ├─ 变量值相同 → 检查变量绑定
│  └─ 崩溃 → 检查日志/截图
│
└─ 无法诊断？
   ├─ 日志为空 → 切换到 L2（UI 验证）
   ├─ 问题复杂 → 使用二分法缩小范围
   └─ 仍无法解决 → 记录证据，寻求帮助
```

---

**文档版本**：v1.0  
**最后更新**：2026-02-20  
**维护者**：Gloria + 小龙虾🦞
