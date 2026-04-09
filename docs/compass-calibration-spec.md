# Twilight Compass iPhone 指南校对功能 Spec

## 1. 目标

为 iPhone 端新增一个低打扰、可持久化的“指南校对”能力，用于修正不同设备之间可能存在的方向偏差，提升用户对罗盘结果的信任感。

本功能的核心目标不是“修复系统指南针”，而是允许用户在自己的设备上，为 app 的罗盘显示保存一个稳定的方向偏移值。

---

## 2. 产品结论

- 校对功能不是主界面常驻操作。
- 校对功能必须通过单独入口进入。
- 校对完成后需要保存，并在后续持续生效。
- 后续若需重新校对，必须再次主动进入该入口。
- 一期只做“太阳校对”，不做“月亮校对”。

---

## 3. 一期范围

### In Scope

- iPhone 宿主 App 内新增“指南校对”入口。
- 新增独立校对页面。
- 基于“当前太阳方位”完成一次人工确认式校对。
- 保存 `heading offset` 到本地持久化存储。
- 主罗盘渲染时应用该 offset。
- 在设置页显示当前校对状态与重新校对入口。

### Out of Scope

- 不在主屏增加“一点即校对”的常驻按钮。
- 不做自动校对。
- 不做基于月亮的夜间校对。
- 不做后台自动检测并自动改写 offset。
- 一期不做 watchOS 校对流程。
- 不做跨设备同步校对结果。

---

## 4. 交互原则

- 这是“设备级设置项”，不是高频主流程动作。
- 用户必须显式进入校对流程，避免误触。
- 校对结果只有在用户点击“保存校对”后才生效。
- 校对页必须允许“取消退出”，且取消不写入任何数据。
- 已保存后默认长期生效，不反复打扰用户。

---

## 5. 入口设计

### 主入口

放在 iPhone 设置页 `GoldenTimePhoneSettingsView` 中，作为独立行项：

- 中文建议文案：`指南校对`
- 英文建议文案：`Compass Calibration`

该入口点击后进入独立校对页面。

本项目当前决定：

- 校对入口进入独立页面
- 不使用 `sheet`

原因：

- 避免额外叠层带来的卡顿或过渡负担
- 更符合“进入设置项并完成一次设备级校对”的交互语义

### 设置页状态文案

入口下方可显示轻量状态摘要：

- 未校对：`未校对`
- 已校对：`已于 YYYY-MM-DD 校对`

若太阳条件暂时不满足，不禁用入口；允许进入页内查看原因。

---

## 6. 主界面提示策略

主界面不显示常驻校对按钮，也不做自动提醒。

一期改为更直接、更稳定的方案：

- 不根据传感器状态自动判断是否提醒用户
- 不弹出轻提醒
- 不做阈值判定
- 只在主罗盘页现有说明文案下方，增加一条常驻说明

原因：

- “是否该提醒”缺乏可靠判定依据
- 阈值难以稳定，误报会非常打扰
- 用户如果觉得方向受影响，可以主动进入设置页调整

### 6.1 常驻说明位置

- 固定放在 iPhone 主罗盘页说明区下方
- 不进入罗盘主视觉核心区域
- 不遮挡罗盘盘面
- 不做关闭按钮
- 不做浮层

### 6.2 常驻说明职责

这条文案只承担“告知存在入口”的职责，不承担自动诊断。

它应该表达的是：

- 如果用户觉得手机指南针受影响
- 可以去设置页手动做自定义调整
- 该调整会持久化保存

### 6.3 文案语气

允许语气：

- `如果你觉得手机指南针受环境影响，可前往设置页手动校对并保存。`
- `如果感觉方向不准，可在设置中手动校对并保存。`

不允许语气：

- `检测到你的指南针有问题`
- `建议立即校对`
- `设备方向错误`

### 6.4 实现约束

- 该说明始终显示，不根据任何阈值动态出现或消失
- 不记录提醒状态
- 不需要节流逻辑
- 不需要传感器质量判定逻辑

---

## 7. 校对流程

### 7.1 进入条件

用户点击 `指南校对` 后进入。

### 7.2 页面内容

页面包含以下信息：

- 标题：`指南校对`
- 说明文案：告知用户将手机朝向当前太阳方向，以修正该设备在 app 内的方向偏差。
- 当前校对状态：未校对 / 已校对时间
- 当前实时方向状态：是否已拿到设备 heading、是否已拿到位置、当前是否可计算太阳方位

### 7.3 可执行状态

只有在以下条件同时满足时，允许用户点击 `保存校对`：

- 已授权定位
- 已获得可用位置
- 已获得可用设备 heading
- 当前太阳在地平线上方，且 app 已算出太阳方位

任一条件不满足时：

- 页面仍可进入
- `保存校对` 按钮置灰
- 页面展示明确原因

### 7.4 用户操作步骤

1. 用户进入 `指南校对`
2. 页面提示用户将手机顶部对准当前太阳方向
3. 用户自行完成对准
4. 用户点击 `保存校对`
5. 系统记录当前 offset
6. 退出校对页，返回设置页或主界面

### 7.5 取消行为

- 点击返回或 `取消`
- 不保存
- 不改动现有 offset

---

## 8. 校对算法

### 8.1 输入

- `deviceHeadingDegrees`
  现有 `GoldenTimePhoneViewModel.deviceHeadingDegrees`
- `compassSunBodyAzimuthDegrees`
  现有 `GoldenTimePhoneViewModel.compassSunBodyAzimuthDegrees`

两者都以“相对北方的方位角”表示，单位为度。

### 8.2 偏移定义

定义：

`headingOffsetDegrees = normalized(sunAzimuthDegrees - deviceHeadingDegrees)`

含义：

- 当用户已经把手机正上方对准太阳时，理想情况下屏幕顶部方向应等于太阳当前真实方位。
- 两者差值即为需要额外补偿的设备偏移。

### 8.3 应用方式

主罗盘渲染时使用：

`correctedHeadingDegrees = normalized(deviceHeadingDegrees + headingOffsetDegrees)`

所有现有基于 `headingDegrees` 的罗盘绘制和地图旋转，统一改为读取 `correctedHeadingDegrees`。

### 8.4 归一化

所有角度统一归一化到 `[0, 360)`。

---

## 9. 持久化设计

### 9.1 存储原则

- 仅本地持久化
- 仅当前 iPhone 设备生效
- 不向 watch 复用或同步
- 不做云同步

### 9.2 建议字段

- `gt.phone.compassCalibration.offsetDegrees`
- `gt.phone.compassCalibration.calibratedAt`
- `gt.phone.compassCalibration.source`
- `gt.phone.compassCalibration.version`

字段说明：

- `offsetDegrees`: `Double`
- `calibratedAt`: Unix timestamp 或 ISO8601 字符串
- `source`: 一期固定为 `sun`
- `version`: 预留升级用，初始值为 `1`

### 9.3 存储位置

一期建议存到 iPhone 本地设置中，不作为 watch 侧共享状态的一部分。

如果后续需要让同一台 iPhone 上的其他扩展读取，可再评估是否迁移到 App Group；但一期不将其纳入 watch 同步链路。

---

## 9.4 Watch 处理原则

结论：

- Apple Watch 不能复用 iPhone 的校对值
- Watch 必须拥有自己的独立校对值

原因：

- iPhone 与 Watch 的磁力计不是同一颗传感器
- 两者使用姿态不同，受干扰方式也不同
- 表带、表壳、佩戴位置、手腕朝向都会带来额外偏差

因此：

- `phoneHeadingOffset` 只修正 iPhone 罗盘
- `watchHeadingOffset` 未来只修正 Watch 罗盘
- 两者绝不能互相覆盖

---

## 9.5 一期 Watch 策略

一期虽然不实现 watchOS 校对 UI，但必须明确以下行为：

- iPhone 端保存校对后，Watch 端继续使用自己的原始 heading
- 现有 iPhone -> Watch 同步链路不得携带 iPhone 校对值
- Watch 端当前显示与 iPhone 不一致，视为正常现象，不当作同步缺陷

这意味着一期上线后：

- iPhone 可以拥有已校对罗盘
- Watch 仍然保持未校对状态

这是可接受的，但必须在实现与测试时显式确认，避免后续误把 iPhone offset 带到 watch。

---

## 9.6 二期 Watch 方向

二期若支持 Watch 校对，必须在 Watch 端本机完成，不通过手机代做。

推荐方向：

- 入口位于 Watch 罗盘页
- 用户在 Watch 上进入独立校对流程
- Watch 使用自己的 `deviceHeadingDegrees` 与太阳方位计算 `watchHeadingOffset`
- 结果保存在 Watch 本地

不推荐方案：

- 在 iPhone 上替 Watch 生成校对值
- 直接把 iPhone offset 下发给 Watch

因为这两种方案都不能反映 Watch 自己的真实传感器偏差。

---

## 10. 设置页呈现

建议在现有定位相关 Section 之后新增一个独立 Section：

- Section 标题：`指南`
- 行 1：`指南校对`
- 行 2：状态摘要
- 行 3：若已校对，提供 `清除校对` 或 `恢复默认方向`

### 行为定义

- `指南校对`：进入校对页
- `清除校对`：删除 offset，恢复系统原始 heading

`清除校对` 需要二次确认，避免误触。

---

## 11. 校对页文案建议

### 中文

- 标题：`指南校对`
- 说明：
  `将手机顶部对准当前太阳方向，然后点“保存校对”。`
- 辅助说明：
  `校对结果会保存在这台 iPhone 上，之后罗盘会一直使用这次校对值，直到你再次手动校对或清除。`
- 按钮：
  `保存校对`
  `取消`
  `清除校对`

### 英文

- Title: `Compass Calibration`
- Body:
  `Point the top of your phone toward the sun, then tap Save Calibration.`
- Secondary:
  `This calibration is saved on this iPhone and stays active until you recalibrate or clear it.`
- Buttons:
  `Save Calibration`
  `Cancel`
  `Clear Calibration`

---

## 12. 状态与异常文案

### 未满足条件时

- 无定位权限：`需要定位权限后才能校对`
- 无可用位置：`暂时无法获取当前位置`
- 无可用方向：`暂时无法获取设备方向`
- 太阳不可用：`当前太阳不可见，暂时无法进行太阳校对`

### 保存成功

- `已保存指南校对`

### 已存在校对值

- `当前设备已保存校对值`

### 主罗盘页常驻说明

- `如果你觉得手机指南针受环境影响，可前往设置页手动校对并保存。`

---

## 13. 实现接入点

### 13.1 ViewModel

文件：

- `Apps/GoldenTime/iOS/GoldenTimePhoneViewModel.swift`

建议新增：

- 校对配置读取
- `correctedHeadingDegrees`
- `hasCompassCalibration`
- `compassCalibrationStatusText`
- `saveCompassCalibrationFromCurrentSunAlignment()`
- `clearCompassCalibration()`

### 13.2 方向数据源

文件：

- `Apps/GoldenTime/iOS/PhoneLocationReader.swift`

一期无需修改采集策略，只需要继续输出原始 `headingDegrees`。

### 13.3 罗盘渲染

文件：

- `Apps/GoldenTime/iOS/TwilightCompassCard.swift`
- `Apps/GoldenTime/iOS/GoldenTimePhoneRootView.swift`

当前 `TwilightCompassCard` 读取 `deviceHeadingDegrees`。一期需要改为传入修正后的 heading。

### 13.4 设置入口

文件：

- `Apps/GoldenTime/iOS/GoldenTimePhoneSettingsView.swift`

新增：

- 校对入口
- 当前状态摘要
- 清除校对入口

### 13.5 本地化文案

文件：

- `Apps/GoldenTime/iOS/PhoneContentLanguage.swift`

新增中英文文案。

---

## 14. 数据流

1. `PhoneLocationReader` 提供原始 `headingDegrees`
2. `GoldenTimePhoneViewModel` 读取已保存的 `headingOffsetDegrees`
3. ViewModel 计算 `correctedHeadingDegrees`
4. 主界面罗盘使用 `correctedHeadingDegrees`
5. 用户在校对页点击 `保存校对`
6. ViewModel 用 `sunAzimuth - rawHeading` 计算 offset
7. offset 写入本地存储
8. 主界面立即使用新 offset 刷新罗盘

---

## 15. 非目标与风险

### 非目标

- 不保证与系统 Compass app 完全一致
- 不保证在强磁场或金属干扰环境中仍然精准
- 不承诺一次校对永久绝对准确

### 风险

- 用户无法肉眼精确对准太阳，校对结果可能带入人工误差
- 晴天与阴天体验差异大
- 保护壳、磁吸配件、车载支架仍可能持续影响结果

因此一期文案必须强调：

- 这是“对当前设备方向显示做校正”
- 不是“修复所有指南针问题”

---

## 16. 一期验收标准

- 设置页存在明确且独立的 `指南校对` 入口
- 主界面无常驻校对按钮
- 主界面说明区下方存在常驻说明文案，提示用户可去设置页手动调整
- 用户可进入校对页并看到当前状态
- 在太阳可用时可执行 `保存校对`
- 保存后重启 app 仍保留校对结果
- 罗盘显示会持续使用该校对值
- 用户可手动清除校对结果
- watch 端不继承该 iPhone 校对值

---

## 17. 后续可选迭代

- 二期增加“为什么需要校对”的教育说明
- 三期评估是否支持月亮校对
- 三期评估是否加入“偏差过大时建议重校”的提示逻辑
