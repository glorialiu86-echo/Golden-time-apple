# RESOURCE_MATRIX

## 资源入口与保留策略
- 当前资源入口文件：`resources/drawables/drawables.xml`
- 本次新增分辨率资源入口文件：
  - `resources-round-240x240/drawables/drawables.xml`
  - `resources-round-260x260/drawables/drawables.xml`
  - `resources-round-280x280/drawables/drawables.xml`
- 旧目录 `resources/`：保留不动，作为当前默认/fallback 资源来源（未迁移、未删除）

## 当前 bitmap 资源清单（原始映射）
- `LauncherIcon` -> `resources/drawables/launcher_icon.svg`（原 XML 中 filename=`launcher_icon.svg`）
- `bg_day` -> `pics/Day/Day-background.png`
- `bg_golden` -> `pics/Golden/Golden-background.png`
- `bg_night` -> `pics/Night/Night-background.png`
- `sun_day` -> `pics/Day/Day-sun.png`
- `sun_golden` -> `pics/Golden/Golden-sun.png`
- `moon_night` -> `pics/Night/Night-moon.png`

## 三套目录需要放置的文件（资源 id 与文件名）
以下 3 个目录的 `drawables/` 子目录都应包含同一组文件：
- `launcher_icon.svg`（id: `LauncherIcon`）
- `bg_day.png`（id: `bg_day`）
- `bg_golden.png`（id: `bg_golden`）
- `bg_night.png`（id: `bg_night`）
- `sun_day.png`（id: `sun_day`）
- `sun_golden.png`（id: `sun_golden`）
- `moon_night.png`（id: `moon_night`）

对应目录：
- `resources-round-240x240/drawables/`
- `resources-round-260x260/drawables/`
- `resources-round-280x280/drawables/`

## 你后续需要复制图片到哪里
请将每个分辨率版本的图片分别复制到对应目录（文件名保持不变）：
- 240 圆屏：复制到 `resources-round-240x240/drawables/`
- 260 圆屏：复制到 `resources-round-260x260/drawables/`
- 280 圆屏：复制到 `resources-round-280x280/drawables/`

## 说明（当前占位状态）
- 为避免新增分辨率资源目录在编译时因缺图失败，三个目录已先放入与现有资源同名的临时占位文件（直接复制现有资源/图片，不修改图片内容）。
- 你后续可直接用目标分辨率图片覆盖这些占位文件，无需改 `source/`、`manifest.xml` 或资源 id。
