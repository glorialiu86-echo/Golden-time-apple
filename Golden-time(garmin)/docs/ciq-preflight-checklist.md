# Connect IQ 开发前检查清单

**快速参考**：开始开发前 5 分钟检查

---

## 文档健康检查（由 Codex 生成）

- 硬编码路径：原文使用了 SDK 默认安装路径和 `screenshots/` 固定目录；已改为 `<REPO_ROOT>/...` 或变量化表述。
- 设备型号写死：原文构建命令固定具体机型；已替换为 `<TARGET_DEVICE>`。
- SDK 版本强绑定：原文未显式版本，但步骤隐含本地 SDK 结构；已增加 `<CIQ_SDK_VERSION>` 占位约定。
- 缺少失败回退：原清单偏“做什么”，本次补充“失败先查什么”的极简路由提示。
- 重复段落：原“代码检查/验证准备/快速构建”有交叉，本次新增 30 秒版作为第一入口，完整版保留。
- 独立执行性：原步骤依赖当前仓库约定，本次新增迁移步骤以支持新仓库落地。

---

## 迁移到新表盘仓库的步骤

1. 复制本文件到新仓库 `docs/` 目录。
2. 将所有路径替换为新仓库真实路径，统一使用 `<REPO_ROOT>/...` 表达。
3. 将 `<TARGET_DEVICE>` 替换为目标设备（如需多设备，写成列表）。
4. 将 `<CIQ_SDK_VERSION>` 替换为当前 CIQ SDK 版本号。
5. 把“快速构建测试”命令里的产物名改成新项目产物名。
6. 在 `README.md` 增加本清单链接，确保新成员可 1 跳到达。

---

## Preflight（30 秒极简版）

- [ ] SDK 可用：`monkeyc --help` 可执行（版本 `<CIQ_SDK_VERSION>`）
- [ ] 目标设备统一：命令、`monkey.jungle`、模拟器均为 `<TARGET_DEVICE>`
- [ ] 开发者密钥存在：`<REPO_ROOT>/developer_key`
- [ ] 入口与权限正确：`manifest.xml` 与真实需求一致
- [ ] 资源主路径存在：`<REPO_ROOT>/resources/`
- [ ] 构建产物目录可写：`<REPO_ROOT>/bin/`
- [ ] 时间基准统一：UTC 链路单一，时区修正只做一次
- [ ] 至少一个可观测证据：日志标签或 UI 状态码
- [ ] 一条最小构建命令可直接运行：`monkeyc ... --device <TARGET_DEVICE>`

失败先查（经验性规则 Heuristic）：若跑不通，先看 SDK 路径/设备目标/资源引用三项。

---

## 环境检查（5 项）

- [ ] SDK 已安装：`<REPO_ROOT>/../(本机 CIQ SDK 安装目录)` 或等效环境变量
- [ ] 开发者密钥存在：`<REPO_ROOT>/developer_key`
- [ ] VS Code + Monkey C 扩展已安装
- [ ] 模拟器可启动：`monkeydo --help` 有输出
- [ ] 截图目录已创建：`<REPO_ROOT>/screenshots/`（可选）

---

## 配置检查（5 项）

- [ ] `monkey.jungle` 列出了目标设备
- [ ] `manifest.xml` 权限与实际需求一致
- [ ] 资源文件存在：`<REPO_ROOT>/resources/drawables/`, `<REPO_ROOT>/resources/layouts/`
- [ ] 启动图标准备好（建议多尺寸：24x24, 40x40, 80x80）
- [ ] `.gitignore` 包含 `bin/`, `.DS_Store`

---

## 代码检查（8 项）

- [ ] 所有时间戳使用 UTC 基准
- [ ] 时区修正只在一处完成（NOAA 公式）
- [ ] 关键变量独立声明，避免 `var a = b;`
- [ ] 涉及精度的计算使用浮点数：`/ 2.0`
- [ ] 添加了日志输出：`System.println("[TAG] message")`
- [ ] 或添加了 UI debug 信息（版本号、状态码）
- [ ] 使用了语义明确的变量名
- [ ] 避免了魔法数字（用常量或注释说明）

---

## 验证准备（5 项）

- [ ] 算法先用 Python 验证通过
- [ ] 准备了测试用固定经纬度（如上海 31.2°N, 121.5°E）
- [ ] 准备了测试用固定时间戳
- [ ] 知道如何截图（系统快捷键或脚本）
- [ ] 知道如何查看日志（monkeydo 输出）

---

## 文档准备（2 项）

- [ ] README 中记录了构建命令
- [ ] 已知问题记录在 PRD 或 AGENTS.md

---

## 快速构建测试

```bash
# 1. 构建
monkeyc --jungles monkey.jungle --device <TARGET_DEVICE> --output <REPO_ROOT>/bin/test.prg --warn

# 2. 部署
monkeydo <REPO_ROOT>/bin/test.prg <TARGET_DEVICE>

# 3. 检查日志
# 查找 [SNAPSHOT] 或 [DEBUG] 标记

# 4. 截图
# Cmd + Shift + 4 + 空格 → 点击模拟器窗口
```

---

## 遇到问题时

1. **编译失败** → 检查 SDK 路径、语法、资源
2. **运行时错误** → 检查日志、截图、变量值
3. **日志为空** → 切换到 UI 验证（显示版本号）
4. **问题复杂** → 使用二分法缩小范围

详细排障手册：`docs/ciq-embedded-postmortem.md`

---

**版本**：v1.0  
**更新**：2026-02-20
