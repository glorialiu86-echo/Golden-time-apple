# Golden Time Apple Bootstrap

当前仓库已经具备：

- `GoldenTimeCore` 共享计算层
- 离线 GOLDEN/BLUE snapshot 语义
- 基础 smoke tests

下一阶段目标：

1. 新建原生 Xcode 工程，包含 `iPhone App`、`Watch App`、`Shared`。
2. `iPhone App` 负责定位权限、单次拉取 GPS、缓存经纬度。
3. `Watch App` 负责离线展示和倒计时。
4. `GoldenTimeCore` 继续作为统一计算引擎，不把算法散落到 UI 层。

建议的工程结构（当前已实现一版）：

- `GoldenTime.xcodeproj`（与 `Package.swift` 同目录，便于本地包与 App 共用构建输出）
- `Apps/GoldenTime/iOS/` — iPhone 壳应用
- `Apps/GoldenTime/Watch/` — watchOS SwiftUI
- `Sources/GoldenTimeCore/`
- `Tests/GoldenTimeCoreTests/`

Apple 端第一版功能边界：

- 无网可看
- 拉一次 GPS 后缓存位置
- 跟随系统时区和 DST
- 无定位时只显示定位提示
- 同时显示 `BLUE` 和 `GOLDEN`
