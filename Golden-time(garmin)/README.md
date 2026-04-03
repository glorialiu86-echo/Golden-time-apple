# Golden-time

摄影师的黄金时刻表盘 - 实时显示蓝调（Blue Hour）和金调（Golden Hour）倒计时

## 开发前阅读

**首次开发 Connect IQ 表盘？** 请先阅读：

- 📋 [开发前检查清单](docs/ciq-preflight-checklist.md) - 5 分钟快速检查
- 📖 [排障手册](docs/ciq-embedded-postmortem.md) - 完整的问题诊断与解决方案

## 快速开始

```bash
# 构建
./deploy.sh

# 或手动构建
SDK_BIN="<CIQ_SDK_ROOT>/connectiq-sdk-<CIQ_SDK_VERSION>/bin"
"$SDK_BIN/monkeyc" --jungles monkey.jungle --device <TARGET_DEVICE> --output <REPO_ROOT>/bin/Golden-time.prg --warn
"$SDK_BIN/monkeydo" <REPO_ROOT>/bin/Golden-time.prg <TARGET_DEVICE>
```

## 项目文档

- [产品需求文档 (PRD)](Garmin%20Watch%20Face%20Golden-time%20PRD.md)
- [UI 设计规范](WatchFace_UI_Specification.md)
- [工作空间规则](agents.md)

## 功能特性

- ✨ 实时蓝调/金调倒计时
- 📍 基于 GPS 位置自动计算
- 🎨 动态 UI（6 个时段自动切换）
- 🌍 支持全球任意经纬度

## 技术栈

- **语言**：Monkey C
- **SDK**：Connect IQ SDK <CIQ_SDK_VERSION>
- **目标设备**：<TARGET_DEVICE>（更多设备即将支持）

## 开发状态

- ✅ Beta 版本已封板（v1.2）
- ✅ 核心功能已验证（上海地区）
- 🔄 待优化：极端纬度、多设备、定制字体

## License

MIT
