# session-history — 改动记录

收编自 [itisvincent/herdr-session-history](https://github.com/itisvincent/herdr-session-history)
（MIT，收编时为其 main 分支的 `mods/session-history/`）。上游以 Windows 为第一平台；
本副本按 oh-my-herdr 的约定改为 **macOS 优先**，并修正三个源在本机的真实路径。

## M1：收编与源修正

### scan.sh（macOS/Linux 扫描器）

- **OMP**：专属解析器。上游通用目录写成 `~/.omp/sessions`（本机不存在）；
  实际存储在 `~/.omp/agent/sessions/<munged-cwd>/*.jsonl`，`type:"title"` 行带会话摘要、
  `type:"session"` 行带 id 与 cwd。恢复命令 `omp --resume <transcript 路径>`。
- **ZCode**：专属扫描器。上游写成 `~/.zcode/projects`（本机不存在）；实际是
  `~/.zcode/cli/agents/sess_<id>/` 目录（其下 `agent_*/metadata.json` 带 cwd 与 description，
  取最新一份）。**恢复形式未知，行不带 argv**：只可查看 / Reveal / 删除。
  `~/.zcode/cli/rollout/model-io-*.jsonl` 是模型 I/O 日志，不当作会话。
- **Gemini**：专属解析器。`~/.gemini/tmp/<project-hash>/chats/*.json` 单文件 JSON，
  取 `sessionId` 与第一条 user 消息；cwd 不落盘（只有 project hash），留空。
  恢复命令 `gemini --session-file <路径>`（`--resume` 只收 latest/序号，不能按 id）。
- 通用目录（CATALOG）中移除 gemini/omp/zcode（改专属解析后重复入列）与 opencode
  （与上方专属解析器重复，原本每条会出两行）。

### main.js

- 动作按平台分发：剪贴板 macOS `pbcopy`（Linux 回退 xclip/wl-copy）、Reveal macOS
  `open -R`（Linux 打开父目录）、删除 macOS/Linux `rm -rf`（兼容 ZCode 的整目录会话）；
  Windows 保留上游 PowerShell 路径（scan.ps1 未同步源修正——见文末）。
- 没有 argv 的会话行（ZCode）不再显示 Resume / Copy cmd 按钮。
- 移除头部「收起面板」按钮（`layout.hide {id:"panel"}`）：本布局把它作为主区 tab 打开，
  tab 自带关闭。
- `init` 的扫描任务加 `checking()` 守卫（`herdr-app check` 不再真扫盘）。

## M2：持久增量索引与 Orca 式界面

### scan.sh

- **持久缓存**：`--cache <file>`（写到 `data/session-history/index.json`）。每个
  transcript 一条缓存，keyed by 路径 + `mtime`/`size`；未变的文件直接复用，不再重读；
  消失的文件从缓存剪除。本机 Claude 2164 个主会话文件首轮约 3 轮收完，稳态扫描 <1s。
- **两段预算制索引**：头部解析只花预算的前 60%，其余给深度流读；每轮
  `--budget-ms`（默认 8000）+ 48 MiB 字节预算，超了置 `partial: true`，下一轮继续。
  深读按 mtime 新→旧排序，最新会话最先补全；切片按行对齐（读到下一个换行），
  记录不跨轮漏计。
- **深度字段**：`msgs`（消息数）与 `model`。消息数是 transcript 里 `"type":"user"` /
  `"role":"user"` 等标记的子串计数——快，但为近似值；model 取切片里最后一个
  `"model":"…"` / `"modelId":"…"` 匹配。另输出 `first_prompt`（≤400 字符）供展开卡片。
- **OpenCode 走 SQLite**：`sqlite3 -json opencode.db` 查询（时间戳毫秒、`model` 列是
  JSON 字符串需二次解析、子查询数消息行），legacy `storage/session/*.json` 保留并计入
  总数。
- **输出**：`{"ok, partial, count, sources:{agent:{total,indexed}}, sessions:[…]}`，
  sources 供面板画每源进度条；omp 的数据文件（changes.jsonl 等）不计入 total。

### main.js

- **watch 驱动刷新**：7 个存储根目录各一个 `watchFolder` 循环（首次扫描落地后才注册，
  避开 hot reload 首帧），加 5 分钟兜底定时器；活跃会话不停写盘，watch 触发与上次
  扫描至少间隔 8s；refresh 带 mutex，扫描期间的重触发折叠为一次跟进。
- **筛选与分组缓存**：2k+ 条目的 filter / 分组不在每次窗口重绘时重算（活跃 agent
  每秒都在触发重绘），只在数据、搜索词、scope 或 agent 过滤变化时重建。
- **虚拟列表**：列表改用 gpui-kit 的 `list`（按需渲染可见行），去掉上游「最多画
  40 行」的 CAP——全量 2319 条可直接滚动；折叠分组按 cwd 稳定键。
- **界面**（对齐 Orca）：头部「会话历史」；可折叠的**来源进度区**（每源
  indexed/total 进度条）；**工作区 / 项目 / 全部** 三档视图（项目 = 按会话 cwd 分组、
  可折叠计数）；`N 个会话` 计数行 + 索引状态；展开卡片新增 `N 条消息 · model` 与
  **首次提示** 全文块。
- **教训**：app 的 `readTextFile` 对 MB 级文件会无限挂起（`fs/promises` 同样挂，
  `fs` 同步模块被 runtime 禁止导入）——扫描结果走 exec stdout 直传（1.4 MB 实测
  正常）；hot reload 弃读造成的僵尸扫描由 exec 60s timeout 兜底。

## M3：操作补全与入口

- **`log.py`（新）**：`text`（查看器可读文本，120 KB 上限）与 `summary`（移交摘要
  JSON：firstUser / lastUsers / lastAssistant / count 等）两个子命令。
  claude/codex/pi/omp 逐行解析，gemini 整文件，zcode 目录取最新 `metadata.json` +
  `output.txt` 尾段；跳过 `isSidechain`/`isMeta` 与 `<…>` 包裹的记录。
- **一份类，四种 copy**：`props()` 分支 panel / viewer（日志查看器 tab）/ handoff
  （移交弹窗）/ menu（轻弹窗）——弹窗 copy 轻初始化，不再触发面板的扫描与 watch。
- **展开卡片按钮精简**为 Resume / ⋯ / Delete（两步内联确认，保留上游行为）；
  **⋯ 菜单**：复制恢复命令、复制会话 ID、复制日志路径、打开日志、打开工作目录、
  在 Finder 中显示、在工作树中恢复…、移交给另一个代理…。
- **在工作树中恢复**：`git rev-parse --git-common-dir` 匹配同仓库的 space，弹窗列出
  （名称 + 目录），选中后切过去并在其中 `tab.new`（cwd = 该 worktree、原恢复 argv）；
  无匹配时 toast 提示。
- **移交给另一个代理**：镜像 agent-handoff 的协议——`knownAgents` 已安装列表 +
  「聚焦续接（推荐）/ 完整历史」两种 brief（原会话路径、最初任务、最近指令、最后交底、
  工作区），`space.new` 在会话目录启动目标代理（task = brief），原会话不动。
- **打开日志**：新 tab 的 transcript 查看器（同 mod viewer 模式，`log.py text`，
  「── 用户 ── / ── 助手 ──」分段）。
- **入口**：sidebar-nav 第三项 **Sessions**（tab 方式打开，`history.svg` 时钟图标；
  布局里 sidebar-nav 块 70 → 100 px 容纳三行）；`keys.json` 的 `layout:oh-my-herdr`
  段加 **cmd-shift-h**（tab.new Sessions）。
- 删除动作保留上游的两步内联确认，未改走 `confirm` mod——内联两步已够用，少一次
  overlay 依赖（与原计划的偏差）。

## 图标（M3 后续）

> 迭代教训（三连修）：① 首版用程序表 `tile` 底色给每个图标垫黑块——菜单不用
> tile；② 第二版按 svg 文件内容用正则**重算** `tint` 标志——codex 的渐变图标被
> 误判成单色 glyph，被 `svg().text_color()` 整体染成黑方块白纹；③ 最终版与启动
> 菜单（new-menu）逐字节同源：**`knownAgents` 的 `icon`/`tint` 原样使用，不做任何
> 本地推导**——`tint` 单色 glyph 画前景色，其余 `image()` 原样（渐变/彩色图标走
> 这条，codex 即恢复正常蓝紫渐变）。

显示名同样与启动菜单一致：优先取 `knownAgents` 的官方 `name`（Claude Code /
oh-my-pi 等），`omp` 经 `NAME_ALIASES` 别名到 `oh-my-pi`（名称与图标一并生效）；
搜索匹配也包含官方名。来源进度区与会话行的代理标签改用**正式程序图标**，与启动菜单同源同规则；程序表
没有的 OMP/ZCode 用 mod 内 `icons/omp.svg`（Herdr 自带，tint 绘制）与
`icons/zcode.svg`（同仓库 usage-limits 的 ZCode 品牌图），都没有时回退字母块。
行内缩进 44 → 24 px。

## 修复（M3 后续）：面板永久卡在 "Scanning sessions…"

现象：打开面板后 banner「This view could not be re-rendered — interrupted」，
堆栈死在 `normPath → String.replace`，列表永远是空的 Scanning 态。

三个叠加的根因，全部修掉：

1. **缓存重建在 render 里同步执行**：数据到达后的首帧 render 要重建 2k+ 条目的
   筛选/分组；每 space 一遍 `list.filter(assignSpace)`、每 pair 两次正则 normPath——
   12 个 space × 2319 条 ≈ 数万次正则，远超渲染预算（~50ms）→ 被运行时掐断。
   **且 `_dirty` 不复位**，每次重试都重复同样的重活 → 永久卡死。
   → 重建挪进 `scheduleRebuild(cx)` 的 spawned 任务（任务不受渲染预算约束）；
   渲染只读 `this._cache`，未就绪时画一行占位（来源区 + 「整理会话索引…」）。
2. **normPath 无记忆化**：会话 cwd 高度重复。加 `Map` 记忆化后，数千次调用塌缩成
   几十次正则。
3. **spMembers 逐 space 过滤**（spaces × entries 次正则）改为单遍遍历按 owner 分桶。

另发现 **gpui-kit 的 `list`（虚拟列表）在本环境不渲染任何行**（原因未知，M2 验收时
被 pixel 检查误导以为正常）——回退为普通滚动列表，渲染上限 50 行 + 底部
「已显示 50 / N」提示；真正的性能问题已由上面三条解决，50 行的元素构建远低于预算。

## 已知限制（M1 + M2 + M3）

- **消息计数为近似值**（标记子串计数，非解析记录数）；**子代理数未统计**（Orca 有）。
- 深度索引首轮需多轮收敛：每轮最多深读 48 MiB，存量约 3 GB 时前几分钟新会话的
  msgs/model 可能暂缺，进度条与 `索引中` 状态行如实反映。
- OpenCode 的 db 会话只有 title 作预览（首条消息正文在 `part` 表，未展开）。
- Codex `archived_sessions/*.jsonl.zst` 不扫（压缩归档）。
- `scan.ps1`（Windows）保留上游原样：Windows 上 OMP/ZCode/Gemini 三源仍是旧路径；
  M3 的 log.py 已跨平台（python3），但查看器/移交在 Windows 未验证。
- cmd-shift-h 每次按都会新开一个 Sessions tab（tab.new 不查重；要合并需先查已开 tab）。
- 在工作树中恢复只列「已存在的同仓库 space」；要「新建 worktree 后恢复」需先走
  New worktree 再从面板选。
- 移交 brief 不含 git 状态（agent-handoff 的对话框含）；新代理自行 git status。
- 通用 CATALOG 的 antigravity 源（`~/.gemini/antigravity`）在本机扫出 72 条噪音，
  但不在面板的 AGENTS 列表里，永不显示；仅为与上游目录保持一致而保留。

## Windows 分支移除（2026-11-23）

本布局只跑 macOS（Linux 次之），Windows 从未验证过。砍掉：`scan.ps1` 与扫描器的
PowerShell 分发（现在无条件走 `scan.sh`）、copy/reveal/remove/openDir 四个函数的
explorer/powershell 分支。macOS 直呼、Linux 的 xdg-open/xclip/wl-copy 回退不变。
上文「scan.ps1 保留上游原样」的记录就此作废。
