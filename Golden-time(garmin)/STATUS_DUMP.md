# STATUS_DUMP.md

## 1) 当前目标

**Bug:** Monkey C 实现返回 null，导致表盘显示 `--:--`  
**判定标准:** `[SNAPSHOT]` 输出中 `blueTs` 和 `goldenTs` 不为 null，且 `blueCountdown` 和 `goldenCountdown` 显示不同的时间（格式 `HH:MM`）

---

## 2) 复现步骤

**工作目录:**
```
/Users/gloria/Documents/garmin-watch/Golden-time
```

**SDK 路径:**
```
~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-8.4.1-2026-02-03-e9f77eeaa
```

**Python 单测命令:**
```bash
cd /Users/gloria/Documents/garmin-watch/Golden-time
python3 test_algorithm.py
```

**Monkey C 构建命令:**
```bash
cd /Users/gloria/Documents/garmin-watch/Golden-time
~/Library/Application\ Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-8.4.1-2026-02-03-e9f77eeaa/bin/monkeyc -d fenix7s -f monkey.jungle -o bin/Golden-time.prg -y developer_key
```

**Monkey C 运行命令:**
```bash
~/Library/Application\ Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-8.4.1-2026-02-03-e9f77eeaa/bin/connectiq &
sleep 5
~/Library/Application\ Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-8.4.1-2026-02-03-e9f77eeaa/bin/monkeydo bin/Golden-time.prg fenix7s
```

**环境变量:**
无特殊要求

---

## 3) 最新一次失败证据

**Python 单测输出（成功）:**
```
============================================================
测试：上海，2026-02-19 早晨
============================================================

蓝调开始（-10°）：
  ✅ 时间: 05:49:57
  时间戳: 1771451397

金调开始（-4°）：
  ✅ 时间: 06:18:23
  时间戳: 1771453103

时间差: 28 分钟
✅ 测试通过：时间在早晨范围内

============================================================
测试：当前时间倒计时
============================================================

当前时间: 2026-02-18 22:41:13

============================================================
✅ 所有测试通过
============================================================
```

**Monkey C SNAPSHOT 输出（失败）:**
```
[SNAPSHOT] buildId=v1.1 blueCountdown=b=--:-- goldenCountdown=g=--:-- blueTs=null goldenTs=null
```

**关键中间量:**
无（Monkey C 未输出中间量，因为算法返回 null）

---

## 4) 关键已知结论

**已修复：变量绑定错误**
- 位置: `source/SunAltService.mc` 函数 `_scanPeriod`
- 问题: `var goldenStart = blueEnd;` 导致两个变量共享同一个值
- 修复: 改为 6 个独立变量（`morningBlueStart`, `morningBlueGoldenBoundary`, `morningGoldenEnd`, `eveningGoldenStart`, `eveningGoldenBlueBoundary`, `eveningBlueEnd`）
- 时间: 2026-02-18 22:17

**已证实：Python 算法正确**
- 证据: Python 单测输出显示早晨时间（05:49, 06:18）
- 对比巧摄专业版数据，误差在 ±10 分钟内

**已证实：Monkey C 算法返回 null**
- 证据: `[SNAPSHOT]` 输出 `blueTs=null goldenTs=null`
- 原因: 待定位（Python 和 Monkey C 实现不一致）

---

## 5) 代码改动清单

**本次会话修改的文件:**

### 5.1 `source/SunAltService.mc`

**改动 1: 修复变量绑定（行 230-310）**
```diff
- var blueStart = _scanForThreshold(startTs, endTs, lat, lon, -10.0, isMorning);
- var blueEnd = _scanForThreshold(startTs, endTs, lat, lon, -4.0, isMorning);
- var goldenStart = blueEnd;  // Golden 从 Blue 结束时开始
- var goldenEnd = _scanForThreshold(startTs, endTs, lat, lon, 6.0, isMorning);
+ var morningBlueStart = null;
+ var morningBlueGoldenBoundary = null;
+ var morningGoldenEnd = null;
+ var eveningGoldenStart = null;
+ var eveningGoldenBlueBoundary = null;
+ var eveningBlueEnd = null;
+ 
+ if (isMorning) {
+     morningBlueStart = _scanForThreshold(startTs, endTs, lat, lon, -10.0, true);
+     morningBlueGoldenBoundary = _scanForThreshold(startTs, endTs, lat, lon, -4.0, true);
+     morningGoldenEnd = _scanForThreshold(startTs, endTs, lat, lon, 6.0, true);
+ } else {
+     eveningGoldenStart = _scanForThreshold(startTs, endTs, lat, lon, 6.0, false);
+     eveningGoldenBlueBoundary = _scanForThreshold(startTs, endTs, lat, lon, -4.0, false);
+     eveningBlueEnd = _scanForThreshold(startTs, endTs, lat, lon, -10.0, false);
+ }
```

**改动 2: 替换 `_solveAltitudeCrossing` 函数（行 320-400）**
```diff
旧实现使用：
- ra_deg, gmst, solarNoonOffset = (ra_deg - gmst - lonDeg) / 15.0
- eventHour = 12.0 + solarNoonOffset + (rising ? -timeOffset : timeOffset)

新实现使用 NOAA 标准公式：
+ 计算时间方程（equation of time）
+ timezoneOffset = _round(lonDeg / 15.0)
+ solarNoonMinutes = 720.0 - 4.0 * lonDeg - eqOfTime + timezoneOffset * 60.0
+ solarNoonHourLocal = solarNoonMinutes / 60.0
+ eventHourLocal = solarNoonHourLocal + (rising ? -timeOffsetHours : timeOffsetHours)
+ eventHourUtc = eventHourLocal - timezoneOffset
+ eventTs = dayStartTs + (eventHourUtc * 3600.0).toNumber()
```

**改动 3: 添加辅助函数（行 650-710）**
```diff
+ function _tan(rad) {
+     return Math.tan(rad);
+ }
+ 
+ function _round(v) {
+     if (v >= 0) {
+         return (v + 0.5).toNumber();
+     } else {
+         return (v - 0.5).toNumber();
+     }
+ }
```

### 5.2 `source/LocationService.mc`

**改动: 启用测试模式（行 8）**
```diff
- const TEST_MODE = false;  // 生产模式：使用真实 GPS
+ const TEST_MODE = true;  // 测试模式：硬编码上海位置
```

### 5.3 `source/Golden-timeView.mc`

**改动: 添加状态快照输出（行 195-200）**
```diff
+ // 🔍 状态快照（用于自动验证）
+ System.println(Lang.format(
+     "[SNAPSHOT] buildId=v1.1 blueCountdown=$1$ goldenCountdown=$2$ blueTs=$3$ goldenTs=$4$",
+     [bText, gText, snap[:nextBlueStartTs], snap[:nextGoldenStartTs]]
+ ));
```

### 5.4 `test_algorithm.py`

**改动: 完全重写 `solve_altitude_crossing` 函数**
```diff
旧实现：
- 使用 ra_deg, gmst 计算太阳正午
- 时区处理错误

新实现：
+ 使用 NOAA 标准公式
+ 计算时间方程（equation of time）
+ 正确处理 UTC 和本地时间转换
+ timezone_offset = round(lon_deg / 15.0)
+ solar_noon_minutes = 720 - 4 * lon_deg - eq_of_time + timezone_offset * 60
+ event_hour_utc = event_hour_local - timezone_offset
```

**文件时间戳:**
- `source/SunAltService.mc`: 2026-02-18 22:40
- `source/LocationService.mc`: 2026-02-18 22:42
- `source/Golden-timeView.mc`: 2026-02-18 22:00
- `test_algorithm.py`: 2026-02-18 22:30

---

## 6) 未完成事项

### 6.1 定位 Monkey C 返回 null 的原因

**位置:** `source/SunAltService.mc` 函数 `_solveAltitudeCrossing`

**检查项:**
- [ ] 验证 `_tan` 函数是否正确实现
- [ ] 验证 `_round` 函数是否正确实现
- [ ] 验证时间方程计算是否溢出或返回 NaN
- [ ] 验证 `cosH` 是否在 [-1, 1] 范围内
- [ ] 添加 DEBUG 日志输出中间变量（`eqOfTime`, `solarNoonMinutes`, `eventHourLocal`, `eventHourUtc`）

**完成判定:**
`[SNAPSHOT]` 输出中 `blueTs` 和 `goldenTs` 不为 null

### 6.2 验证 Monkey C 计算结果与 Python 一致

**位置:** `source/SunAltService.mc` 函数 `_solveAltitudeCrossing`

**检查项:**
- [ ] 对比 Monkey C 和 Python 的 `solarNoonMinutes` 值
- [ ] 对比 Monkey C 和 Python 的 `eventHourLocal` 值
- [ ] 对比 Monkey C 和 Python 的 `eventTs` 值

**完成判定:**
`[SNAPSHOT]` 输出的 `blueCountdown` 和 `goldenCountdown` 与 Python 单测结果一致（误差 < 5 分钟）

### 6.3 验证六个时间点

**位置:** `source/SunAltService.mc` 函数 `_scanPeriod`

**检查项:**
- [ ] 验证早晨三个时间点（晨蓝调起点、晨蓝调结束/晨金调起点、晨金调结束）
- [ ] 验证傍晚三个时间点（夜金调起点、夜金调结束/夜蓝调起点、夜蓝调结束）
- [ ] 对比巧摄专业版数据（2026-02-18）：05:59, 06:18, 07:06, 17:11, 17:44, 18:18

**完成判定:**
所有六个时间点误差 < 15 分钟

---

**最后更新:** 2026-02-18 22:44
