# AGENTS.md（Golden-time｜工程执行规范｜给 Codex）

> 目的：把“Golden-time”项目的改动做成**可重复、可验证、每次改完就能在模拟器看到效果**的闭环流程。  
> 语言：所有输出用中文。  
> 注意：你（Codex）**没有截图权限**，不要尝试截图；由我（佑酱）截图与验收。

---

## 0. 你是谁 / 你要做什么

你是这个仓库的工程执行器。你的任务是：
- 严格按我给的修改指令改代码
- 改完后**必须编译 + 部署到 Connect IQ Simulator + monkeydo 运行验证**
- 用中文给我一个“可复现的验证步骤 + 你实际执行的命令 + 结果摘要”

---

## 0.1 Git 仓库同步与多机器协作规则

# 多机器协作采用“单活跃节点”模型

默认工作模式：
- 同一时间仅在一台机器上开发同一仓库。
- 切换机器前必须完成 commit + push。
- 在另一台机器开始工作前必须执行 git pull --rebase。

# 工作前后强制检查流程

开始工作前：

git status
git pull --rebase

结束工作后：

git add .
git commit -m "<message>"
git push

# 严禁跨机器保留未 push 提交

- 不允许在一台机器上存在未 push 的关键提交后切换到另一台机器继续开发。
- 若需要临时保存进度，使用 wip: 前缀提交并 push。

# 目录结构约定

所有 Git 仓库统一存放于：

~/Git-Workspace/

禁止将仓库存放于：
- iCloud Drive
- Desktop
- Documents（若其属于 iCloud 同步目录）

---

## 1. 硬约束（必须遵守）

1) **禁止截图**  
- 不要输出“我给你看截图/我截图了”等内容。你无法截图。  
- 如果需要我验证画面，你只给我“我该点哪里/该怎么设置模拟器”的步骤。

2) **每次改动必须闭环**
- 任何改动都必须包含：  
  - 修改范围说明  
  - 构建命令与结果（BUILD SUCCESSFUL / 错误信息）  
  - 部署与运行命令与结果（monkeydo 无 crash / 日志输出）  
  - 我需要怎么在模拟器里复现（一步一步）

3) **不要引入新依赖**
- 不加第三方库，不改 SDK 结构，不加复杂工具链。

4) **不做“脑补式改动”**
- 只改我明确要求的内容。  
- 如果发现关键前提缺失（会影响结论/可行性/责任），必须停下，列出缺失点并问我一个最小问题。

---

## 2. 标准工作流（每次任务都要走）

### Step A｜改代码
- 仅在我指令范围内改动
- 改动前先快速复述你将改哪些文件、改哪些函数（1–3 行）

### Step B｜构建（必做）
- 用目标设备 `fenix7s` 编译
- 在输出中必须包含：  
  - 使用的 SDK 路径（如已知）  
  - 构建命令  
  - BUILD SUCCESSFUL 或具体错误

### Step C｜部署到模拟器（非必须）
你必须确保模拟器能加载到最新 build 的产物。  
- 使用 `monkeydo` 或 Connect IQ 标准方式部署运行  
- 输出你实际执行的命令与返回信息  
- 如果需要“先启动 simulator 再 monkeydo”，就照做

### Step D｜运行验证（非必须）
- 运行后必须给出：
  - “没有 crash”或“发生 crash + 堆栈/日志”
  - 如果有 debug 日志（System.println），贴关键几行
- 验证点必须与本次改动直接相关（例如布局是否裁切）

---

## 3. 输出格式（你每次交付都必须按这个模板）

### 3.1 改动摘要
- 改了哪些文件：
- 改了哪些函数/逻辑点：

### 3.2 我执行的命令
- build：
- deploy/run：
- （如有）清理/重建：

### 3.3 结果
- 编译结果：
- 运行结果：
- 关键日志（最多 10 行）：

### 3.4 佑酱验收怎么做
- 模拟器里点哪里：
- 设置哪些参数：
- 我应该看到什么现象（以“可观察结果”描述）：

---

## 4. 当前项目专属约定（Golden-time）

1) **命名与入口**
- 项目名：Golden-time
- 入口：GoldenTimeApp / GoldenTimeView（以 manifest.xml 为准）

2) **定位缺失行为**
- 无定位：只显示 `LOC -- / Enable GPS`，不输出 GOLDEN/BLUE 结论与倒计时数字

3) **倒计时语义（核心功能）**
- GOLDEN 与 BLUE 倒计时要**同时展示**（左 BLUE / 右 GOLDEN）
- 倒计时为“到下一次开始区间”的剩余时间
- 高纬度不穿越阈值：当日对应区间不显示（用 `--:--`）

4) **时区/DST**
- 跟随手表系统设置

5) **UI**
- 我负责截图验收，你负责把布局做成“不会被圆形屏裁切”的安全区布局

---

## 5. 禁止事项（再次强调）

- 不要截图
- 不要擅自改需求
- 不要为了“看起来更好”去引入渐变/复杂背景/额外图形（除非我明确要求）

---

## 6. 减少权限确认弹窗（yes）约定

1) **优先使用已批准命令前缀**
- Codex 执行命令时，优先复用当前会话里已批准的前缀规则（例如已批准的 `/bin/zsh -lc`、`monkeyc`、`monkeydo`、`simulator` 相关命令）。
- 在能完成任务的前提下，不主动更换为新前缀，尽量避免触发新的权限确认弹窗。

2) **优先走工作区内可执行路径**
- 能在 sandbox/workspace 内完成的操作，不申请提权。
- 构建、部署、运行、日志采集尽量合并到已批准模板命令里执行。

3) **必须新权限时的最小化原则**
- 只有在现有已批准前缀无法完成任务时，才申请新权限。
- 新权限申请要尽量小范围、可复用（避免过宽前缀）。
- 若同类任务会反复出现，优先申请“可复用且边界清晰”的前缀，减少后续反复点 `yes`。

---

## 7. 模拟器启动与部署（固定流程，禁止反复试错）

1) **唯一推荐启动方式（先 GUI）**
- 必须先用 `open "$SDK/bin/ConnectIQ.app"` 启动模拟器，再执行部署。
- 启动后必须等待 `5-8` 秒让 simulator 后台进程就绪，再跑 `monkeydo`。

2) **禁止方式（不要再尝试）**
- 禁止把 `"$SDK/bin/ConnectIQ.app/Contents/MacOS/simulator" fenix7s` 当作默认启动方式反复尝试。
- 出现 `Unable to connect to simulator.` 时，不要连续盲重试同一错误命令；应回到“先 open GUI -> 等待 -> monkeydo”流程。

3) **标准命令模板（按此执行）**
- build：
  - `/bin/zsh -lc 'SDK_ROOT="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks"; SDK_DIR="$(find "$SDK_ROOT" -maxdepth 1 -type d -name "connectiq-sdk-*" | sort | tail -n 1)"; "$SDK_DIR/bin/monkeyc" -f monkey.jungle -o bin/test_fenix7s_Goldentime.prg -y developer_key -d fenix7s'`
- 启动模拟器：
  - `/bin/zsh -lc 'SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-8.4.1-2026-02-03-e9f77eeaa"; open "$SDK/bin/ConnectIQ.app"; sleep 8'`
- deploy/run：
  - `/bin/zsh -lc 'SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-8.4.1-2026-02-03-e9f77eeaa"; "$SDK/bin/monkeydo" bin/test_fenix7s_Goldentime.prg fenix7s'`

---

## 8. Git 远端操作统一约束

1) **默认参数（所有远端操作）**
- 必须默认带：`GIT_TERMINAL_PROMPT=0`
- 必须默认带：`--progress`

2) **超时策略（必要时）**
- 当出现远端卡住/长时间无响应时，增加超时参数，避免命令无限等待。
- 推荐示例：`git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=30 fetch --prune --progress origin`

3) **常用模板**
- `GIT_TERMINAL_PROMPT=0 git fetch --progress origin`
- `GIT_TERMINAL_PROMPT=0 git pull --progress --ff-only origin main`
- `GIT_TERMINAL_PROMPT=0 git push --progress origin main`

---

## 9. UI-only 修改协议

- 允许修改范围（白名单）
  - ✅ source/Golden-timeView.mc 中的 draw/onUpdate 绘制部分：坐标、字体、颜色、对齐、绘制顺序
  - ✅ 资源/布局文件（如有）：resources/drawables/drawables.xml、resources/layouts/*.xml

- 禁止修改范围（红线）
- ❌ 任何服务层/计算层：source/SunAltService.mc 等
- ❌ 任何 snapshot 字段键名与读取链路
- ❌ 任何 hasFix/todayHas* 的过滤语义
- ❌ 倒计时/时间文本的格式化语义（除非任务明确要求）

- 冻结 token（出现即不得改动、不得注释）
  - :nextBlueStartTs
  - :nextGoldenStartTs
  - :todayHasBlueStart
  - :todayHasGoldenStart
  - :hasFix
  - 以及 _formatRemaining / _readSnapFields（如果你把它们抽出来）

- 提交门禁（必须执行）
	1.	git diff --name-only 必须只包含白名单文件
	2.	git diff 中不得出现上述冻结 token 所在行的改动
	3.	不满足则自动撤销改动并报告“越界”