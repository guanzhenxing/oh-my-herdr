# oh-my-herdr

一个参照 Orca 桌面应用设计的 Herdr 布局：左侧栏是项目，worktree 嵌套在项目之下，各自的 agent 和子代理再嵌套其下；space 可以休眠和唤醒；带分支/issue/PR 徽章和每个 worktree 的悬停卡片；tab 以药丸样式呈现并带运行按钮；带边框的 pane 配头部；右侧有一个可隐藏的面板，放 Files 和 Git changes；状态栏显示 Claude/Codex 用量窗口和实时端口。GitHub issues 和 PR 在应用内打开，新 worktree 可从分支、issue、PR 或新名字创建。

![oh-my-herdr](preview.png)

## 你会看到

从左到右、从上到下。无系统标题栏（`"titlebar": "none"`）；macOS 红绿灯按钮位于侧栏之上 12,16 处。根背景是 `canvas`；终端内边距 14×12。

- **侧栏**（268px，44–480，`cmd-b` 折叠）：
  - `brand`（46px）：Herdr 的 `workspace-chrome` 品牌行。
  - `sidebar-nav`（100px）：Orca 风格的链接，**Automations** 和 **Issues**，各自以弹窗打开其 mod（`automations`、`issues`）；**Sessions** 以主区 tab 打开会话历史面板（`session-history`，`cmd-shift-h` 同效）。
  - **Spaces**（`oh-my-sidebar`）：每台机器一个分节（30px 横条：折叠箭头、显示器或服务器图标、粗体名称、连接时显示绿点、**+**；除第一台外每台机器上方一条 1px 分隔线），其内是你的**文件夹**（着色块：折叠箭头、彩色文件夹图标、名称、计数、**⋯**），未归入文件夹的 space 以同级缩进列在文件夹之后。一个仓库的主 checkout 会把它的 worktree 列在下方（`├─`/`└─` 加分支图标）。
    每行有第二行信息：分支、主 checkout 上的 `primary` 徽章、活跃时的 ↑/↓，有实时端口时的插头图标、关联 issue（绿圈 `#243`，关闭为紫色）及其 PR（状态图标 `#453`，打开为绿色，关闭/失败为红色，合并为紫色，草稿为灰色）。
    在每个 space 或 worktree 下方是它的 **agent**（26px 行，与名称对齐：程序图标、tab 名称、处于该状态的时长、状态）和它们的**子代理**（24px 行，沿树线排布，任意深度）——始终显示。
  - **Agents** 标签（`oh-my-sidebar`，`view: agents`）：侧栏的两个列表是共享全高的两个标签——每个视图在自己的头部绘制 **Spaces | Agents** 分段标签栏（激活实色，未激活灰暗；对 `sidebar-lists` 堆栈用 `layout.select`）。Spaces 标签的头部保留 New folder / New space；Agents 标签的头部保留排序菜单（priority、grouped、main space、prefix）；分组只靠各自的组头区分，如同 Spaces 列表的分节。
    一个页脚（`view: footer`）：左侧 **Settings** 和 **Mod settings**（即收编的 `better-config`）两个图标按钮（tooltip 标明名称），右侧「3 agents · 2 need you」，再加 Add machine。
  - 休眠中的 space 在第二行显示月亮和 **Asleep**。
- **Tab 栏**（42px）：侧栏恢复开关，仅在侧栏隐藏时显示（显示侧栏时，Herdr 的品牌按钮负责隐藏，保证屏上同一时刻只有一个开关；点 Herdr 品牌按钮出现的竖条变成隐藏），space 各 tab 的 `my-tabs` 药丸；右面板开关（36px）。面板的 Files / Changes / Excalidraw 控件不在这行——它们在右面板自己的头部（`panel-head`，Orca 式）。
- **主区**：活动 tab 的 pane 以卡片呈现（圆角 10，间距 8，1px `border`，聚焦时 `accent`，单独时也有边框），配 30px 的 `my-pane` 头部：程序图标、agent 名称、目录、状态，右侧是分屏/缩放/关闭。
- **右面板**（368px，280–900，切换前隐藏）：30px 的 `panel-head`（Orca 式面板头部：**Files | Changes** 分段切换 `panel-body` 堆栈、Excalidraw 图标、✕ 收起）+ **Files**（`files-open-with`）与 **Changes**（收编的 `better-changes`）的堆栈。
- **状态栏**（28px）：Claude Code / Codex 用量窗口（`usage-limits`，左侧）、命令与机器（`my-status`）、**资源占用表**（`resources`，150px：活动图标、`CPU 12% · 3.8 GB`）和**实时端口**计数按钮（`live-ports`，64px）。
- 一个 0px 块运行 `hibernate`（不画任何东西；它的对话框是 overlay）。
- 一个 0px 块运行 `desktop-notifications`（不画任何东西）。

弹窗与对话框：Issues 表格（92% × 90%，无边框）、issue/PR 查看器（86% × 90%）、worktree 悬停卡片（行旁的 340px 窗口）、**Create worktree**（560 × 780）、Add project、Project settings、Excalidraw（cmd-shift-e）、Open in VS Code（cmd-g）以及右键菜单（`my-menu`）。

## 行为

- **Agent 状态**沿用 Herdr：blocked 和 done 显示在 space、tab、agent 和 pane 头部（working 转圈、「Needs you」、done 圆点、idle 圆环）；桌面通知镜像「需要你」和「已完成」。
- **Space 内的 agent**：点击 agent 聚焦其 pane；子代理有 pane 则聚焦，否则打开 peek。agent 的折叠箭头折叠其子代理（折叠态显示数量，用最紧急者的颜色）。仓库行的箭头把它的全部 worktree 及其下 agent 一起折叠；其他行悬停显示箭头，折叠各自 agent。折叠行的第二行显示「2 agents · 3 sub」加最紧急状态（「Needs you」完整显示）。折叠的子代理需要你时，agent 自己也会显示「Needs you」，折叠不会藏掉它。以 pane 形式保留的子代理只列在父级之下。
  `agent.next` / `agent.prev` 沿 Spaces 列表的顺序从上到下，无论 Agents 面板开合。
  `cmd-]` / `cmd-[`（`oh-my-sidebar.next-agent` / `prev-agent`）按同一列表步进，子代理跟随父级：Herdr 自带的 `agent.next` 从聚焦的子代理出发会当成其父级，走不过一个。页脚橙色的「N need you」跳到第一个需要你的 agent。折叠成窄条时不显示 agent 行，只显示每个 space 的状态。
- **Spaces**：点击选中，拖拽在机器内重排，右键打开 `my-menu`。
- **文件夹**：任何 space 或仓库（带其 worktree 的仓库）都可归档。把它拖到文件夹头上（高亮；折叠的拖近 650ms 后展开）、拖到另一文件夹内某行旁边（移动并加入该文件夹）、拖到拖动时出现在文件夹下方的虚线「Drop here to take it out of its folder」或「Drop to make a new folder」目标上，或用 space 菜单的 **Move to folder…**（列出全部文件夹，本机还没有的标「new here」，New folder 直接用它新建，Take out of folder 移出）。文件夹由所有机器共享（同一个名字、颜色和顺序），但只在其容纳该机 space 的机器下显示；空文件夹显示在创建它的机器下。折叠状态按机器记忆。折叠的文件夹或机器显示「N needs you」和「N
  working」。拖拽不会离开所属机器：悬停在其他机器上时出现红色虚线提示只能归入自己机器的文件夹。双击文件夹重命名；其 **⋯** 菜单有颜色、Rename、Add projects、Fold the others 和 Delete folder（其中 space 回到列表）。以任何方式前往某 space（按键、`agent.next`、toast、点击）都会展开它的机器、文件夹和仓库。
  `cmd-alt-]` / `cmd-alt-[` 按列表顺序步进 space（机器、你的文件夹、带 worktree 的仓库，含折叠行），列表会滚动保持活动 space 可见，包括 `agent.next` 或点击之后。列表自行滚动（滚轮和可拖动滑块），因为 Herdr 无法用代码移动原生滚动区。悬停仓库行显示 **⌄/›**（折叠其 worktree，状态被记住；折叠时保持可见）、**⋯**（菜单）和 **+**（为该仓库 Create worktree）。悬停任意行约 450ms 打开**悬停卡片**：Note、Pull request、Issue 和 Live ports 分节；点行打开查看器，图标复制链接或打开 GitHub，端口在浏览器打开；指针离开行和卡片 250ms 后关闭。
- **Notes**（类似 Orca 的 worktree 评论）：space 菜单的 **Note…** 为该 checkout 打开一条自由文本备注（⌘↩ 保存；存空即删除）。有备注的行在分支旁显示备注图标（悬停显示文本，点击编辑），悬停卡片将其置顶。备注按机器和文件夹存于共享 `worktree.notes`，space 关闭再打开时仍随其 worktree。
  每个**新建 space 的 +**（Spaces 头部、机器头部、「New space there」和菜单里的「New space」）都以该机器的 home 目录为起点。
- **Close & remove worktree**（space 菜单，或关闭 worktree space 的最后一个 tab）：当同一机器上还有另一个打开的 space 位于该 checkout 时，对话框变为 **Close space**：文件夹显示 Kept，指名另一个 space，只关闭当前 space。
- **徽章**：点击打开 issue/PR 查看器；⌘-点击打开 GitHub。
- **休眠 space**（space 菜单 → **Sleep space**，或资源占用表里的 **Sleep**）：先记录其各 tab 里的每个程序（argv、目录，Claude 取
  `~/.claude/sessions/<pid>.json` 里的会话 id，Codex 取其打开的 rollout 文件）到
  `data/hibernate/state.json`，然后停止：agent 收到中断和 `/exit`（Codex 为 `/quit`），
  其他程序向其进程组发 SIGTERM，最后 SIGKILL。shell、pane 和 tab 保留。working 或 blocked 的 agent 会先询问。**Wake space** 向每个空闲 shell 键入 `cd <folder> && <command>`：`claude --resume <id>`（保留 `--model` 等旗标）、`codex resume --no-daemon <id>`，或原始命令；终端已消失的，在同一 tab 里开新 shell。
- **重启之后**：mod 每 30 秒记录每个 Herdr 终端在运行什么（有变化才写）。重启或 herdr-core 丢失后，保留的终端以**新的** shell pid 恢复为 shell；它们会出现在一个对话框里（逐个复选框、Resume all、Not now、「Resume automatically next
  time」）。你手动退出的程序保留其 shell pid，因此永远不会被列出。
- **设置**（Mod settings → Hibernate，`mod.schema.json`），短标签给选择按钮留出说明空间：**Wake sleeping spaces**：Manual（默认：space 菜单或占用表）、On open（前往该 space 时）、On start（每次 Herdr 启动一次）。**After a restart**：Ask（默认）、Automatic、Off。
- **资源占用表**：每 5 秒（窗口不在前台时 30 秒）一次 `ps`，按 space 汇总每个本地终端的进程树，外加 Herdr 自身的 app 和 core。CPU 占全部核心的份额：30% 起黄色，60% 起红色；内存达 RAM 30% 起黄色，50% 起红色。点击：按内存列出 space 及其 CPU、内存和最重进程，可展开到终端（点击跳转）、一个 Herdr 行，以及每个 space 的 Sleep / Wake。
- **Issues**（来自侧栏导航）：Issues/PRs/Projects 标签（Projects：仓库的 GitHub
  Projects 看板或表格，Group by，迭代和字段的 Filter 面板，字段编辑）、仓库选择器、过滤器、指派/状态菜单（锚定在控件下方）、每行 Start/Open。**Start** 打开选中该 issue 或 PR 的 Create worktree，或已有 space 时直接切换过去。
- **查看器**：issues 和 PRs。PR 有 Conversation / Checks / Files changed（展开文件看 diff，前 400 行）、Pull request 卡片（squash/merge/rebase 带确认步骤、关闭或重开、ready for review）、可编辑的指派、reviewers 和标签、关联 issues，以及 Start/Open workspace。
- **Create worktree**：Branch · Issue · PR · New 标签；`#123` 或 GitHub 链接跳到对应标签。Branch 列出 checkout（Open）、本地与仅远程分支；↻ 拉取 origin。选择后填充可编辑的 **Branch** 和 **Space name**；Branch 下的说明会讲 Create 将做什么（打开、checkout、跟踪 origin，或从指定起点建新分支）。Issue 用 `dev/feat/{number}`（在 `mods/new-worktree/mod.json` 设 `issue_branch`）或关闭它的 PR 的分支。选择 Claude 时，issue/PR 任务粘进 Claude 的输入框但不发送。每次对话框只建一个。项目有 setup 脚本时，出现 **Setup script** 行，可选 **Run** / **Skip**。
- **Worktree setup hooks**：新 worktree 会先跑仓库的团队脚本（`herdr.yaml` 的 `scripts.setup`，否则 Orca 的 `orca.yaml`），再跑项目的本地 setup 脚本，并设置
  `HERDR_ROOT_PATH`、`HERDR_WORKTREE_PATH`、`HERDR_WORKSPACE_NAME`（Orca 的 `ORCA_*` 名称与
  `CONDUCTOR_ROOT_PATH` 也会设置，Orca 脚本无需改动即可运行）。它在你的登录 shell
  （`$SHELL -lic`）里运行，所以 profile 放上 PATH 的工具（pnpm、nvm、mise）都能找到。默认运行、默认跳过或每次询问。「Wait for setup」先跑脚本再在同一终端启动 agent；否则 agent 立即启动，setup 在自己的 **Setup** tab 里运行，agent 的 tab 保持在前。完成后报告「Setup finished.」或「Setup failed (exit N).」
- **Project settings**（space 菜单 → Project settings…）：显示名称和图标（Automatic、Emoji 或 Letter，可配色）；
  **Worktrees**：默认基础分支、worktree 位置（替代 `~/.herdr/worktrees/<repo>`）、issue 分支名（`{number}`、`{slug}`）、默认 agent；**Worktree hooks**：各变量（悬停看含义）、团队脚本（`herdr.yaml` 或 `orca.yaml`，只读）、本地 setup 脚本（保存在本机）、**When to run**（Ask every time / Run by default / Skip by default）与 **Wait for setup
  to complete before starting agent**；以及 Remove project。
- **Files**：点击文件在独立 tab 打开（Markdown 渲染显示，可 Source 切换源码），复用已在显示它的 tab；右键在你的应用中打开。被 git 忽略的文件和文件夹（及忽略文件夹下的一切）灰显；软链接在名字后显示链接图标。代码按 **Code colors** 设置（Mod settings）着色：Editor（默认；亮暗两用的柔和配色）、Terminal（主题 ANSI 色）或 Off。`.env`、`.env.*`、`*.env` 和 `.envrc`
  按 shell 高亮。
- **Changes**：暂存、提交/修补、历史、集中在一个 tab 的 diff（详见 Better Changes 自己的文档）。
- **Automations**：定时的 agent 提示，经 `herdr-automations` CLI——收编在
  `cli/herdr-automations/`（MIT，见其 `VENDOR.md`）；`install.sh` 负责构建或下载，面板的启动横幅安装按用户的调度服务。
- 按键（合并 `keys.json`）：`cmd-n` new worktree、`cmd-shift-n` add project、`cmd-g` VS Code、
  `cmd-shift-e` Excalidraw；本布局内 `cmd-shift-a` 切换侧栏 Spaces/Agents 标签、`cmd-shift-b` 开关右面板、`cmd-shift-h` 开一个会话历史 tab、`cmd-alt-]` / `cmd-alt-[` 下一个 / 上一个 space、`cmd-]` / `cmd-[` 下一个 / 上一个 agent、`cmd-w` / `cmd-shift-w` 关 tab / pane。按键关闭 tab 会先询问（「Close tab
  …?」，Enter 确认）；tab 的 ×、其菜单的 Close 和 pane 的关闭按钮则不问。

## 构成

`layouts/oh-my-herdr.json` 与 `mods/` 下的 26 个 mod。原样使用的 Herdr 自带 mod：`workspace-chrome`、`files`、
`changes`、`pane`、`confirm`、`picker`、`machine-add`。自 munza/herdr-mods 收编、未修改：`better-changes`（占 `changes` 槽位，`"place": "none"`）和 `better-config`。

- `oh-my-sidebar`（munza 的 Better Sidebar，有修改；`props.view` 选视图：spaces、`agents`、
  `footer`、`panel-toggle`、`card`、`groups`、`note`；`views/space-agents.js` 从 `agents()` 与 `terminals()`（`parent`）在 spaces 列表里绘制 agent，复用 Agents 面板的辅助函数）、`my-tabs`、`my-pane`、`my-status`、`my-menu`
  （终端与 space 菜单；`terminal_menu: "my-menu"`）、`my-new-menu`、`my-worktree`（删除确认）：Herdr mod 的修改克隆。
- `issues`（表格、查看器、`projects.js`、`pr.js`、`start.js`、`prefill.sh`）、`new-worktree`（对话框、`git.js`、
  `hooks.js`）、`project-settings`（共用同一份 `hooks.js`：保持两份一致）、
  `files-open-with`（+ Material 图标的 `file-icons`）、`sidebar-nav`、
  `automations`、`usage-limits`（`helpers/*.sh`）、`live-ports`、`desktop-notifications`、
  `hibernate`（`core.js` 快照/停止/启动、`ui.js` 对话框、与
  `oh-my-sidebar` 共享的 `settings.js`）、`resources`（`measure.js`）、
  `new-project`、`open-vscode`、`excalidraw`、
  `session-history`（收编自 itisvincent/herdr-session-history，有修改：见其 `CHANGES.md`；
  代理会话历史面板，持久增量索引并扫描 Claude/Codex/Pi/OMP/Gemini/OpenCode/ZCode 等
  本机 transcript 存储：工作区/项目/全部三档视图、每源进度条、搜索、按 space 过滤、
  恢复、在工作树中恢复（同 git 仓库的 space 选择器）、移交给另一个代理（brief 镜像
  `agent-handoff`）、打开日志（`log.py` 渲染的可读 transcript tab）、复制恢复命令/会话
  ID/日志路径、Reveal、两步删除。入口：侧栏 **Sessions** 或 `cmd-shift-h` →
  `tab.new {mod:"session-history"}`；一份类四种 props copy：panel / viewer / handoff /
  轻弹窗。缓存索引在 `data/session-history/index.json`）。
- 共享状态键：`live-ports`、`oh-my-sidebar.hover`、`oh-my-sidebar.inline-agents`、
  `oh-my-sidebar.groups`（`{groups: [{id, name, color, home}], projects: {<unit>: <folder id>},
  folds: {"<machine>|<folder id>": bool}}`；unit 是仓库的 `JSON.stringify([machine, git common
  dir])` 或 `space:<id>`）、`oh-my-sidebar.space-parents`（仓库 space 的 unit，`my-menu` 会读；其他 space 为 `space:<id>`）、
  `hibernate.sleeping`（`{space: {at, count}}`）、`hibernate.request`（`{nonce, action, space}`，菜单与占用表的请求方式）、`hibernate.answer`（恢复对话框的应答）、`pane-heads`、`issues.pick`、
  `issues.changed`、`projects.settings`（按 `JSON.stringify([machine, main checkout])`：name、icon、
  `base`、`location`、`issue_branch`、`issue_prompt`、`pr_prompt`、`agent`、`setup`、`setupWhen`、`setupWait`）、
  `projects.location`、`files-open-with.tabs`、
  `better-changes.*`。Git 配置：`branch.<b>.herdr-issue` / `herdr-pr` = `owner/repo#N`。
- 程序：`git`、`gh`（已登录）、`curl`（头像）、macOS 的 `osascript`/`pbcopy`/`open`、
  用量与恢复用的 `claude` / `codex` CLI、端口和 Codex 会话的 `lsof`、
  资源占用与休眠的 `ps` / `sysctl` / `kill` / `pgrep`、装了才用的 `terminal-notifier`、VS Code 的 `code`、`herdr-automations`、`hc` 与 `herdr-app`。

## 注意

- 弹窗默认锚定「指针」，而 Herdr 在对话框之上不跟踪指针：从被按控件的 `bounds` 锚定（`issues` 的做法）。
- `hc wait <自己的终端>` 不支持 `--timeout`；不要用它来 sleep。
- Claude 会在 `❯` 后打印一个不换行空格；prefill 辅助匹配 `^❯`，并等待越过目录信任提示。
- `cx.spawn` 在第一个 `await` 前同步执行；不要调用构造函数还没建好的状态。
- GitHub 只在 PR 指向默认分支时才关联「Closes #N」；徽章还会读正文和分支名。
- space 列表和 Agents 面板是两个独立 mod 拷贝，各有自己的 `localStorage`
  （折叠、状态时长）；切换时保持其一显示（对 `agents` 块用 `layout.hide` / `layout.show`），布局出厂时该块为 `"hidden": true`。
- 滚动会让行从静止的指针下滑过，逐行触发 hover。这些 hover 不能打开卡片或 `setShared`（那会重绘窗口内所有 mod）：`spaces.js` 只把最近 150ms 内指针移动过的 hover 当真，只在卡片打开期间写 `oh-my-sidebar.hover`，并给滚动区一个稳定的 `.id("spaces-list")`。
- mod 里没有元素拖拽（`on_drop` 只接外部文件）：拖拽是行上的 `on_mouse_down` 加指针下元素的 `on_mouse_move` / `on_mouse_up`，所以每个放置目标两者都要处理。拖拽状态在列表自己的 `on_mouse_up` 里复位（它在目标之后执行）。
- 「space 变为活动时展开其文件夹」放在 250ms 数据定时器里做，不放
  `render`：在 render 里 `setShared` 会再次重绘所有 mod。
- 不带 folder 的 `space.new` 从聚焦终端的位置启动。在 worktree 里，这会在同一 worktree 上开第二个 space，移除其中任一个会删掉两者共用的文件夹：始终传机器与其 home（远程的用当地 `printenv HOME` 查询并缓存），并在 `git worktree remove` 前检查同一 checkout 上是否还有其他 space。
- 永远不要用 ctrl+c 停程序：Herdr 经 `zsh -lic '"$@"; exec "$0" -li'` 启动 agent，
  SIGINT 会让包装层中止并直接关掉 pane，而不是回到提示符。
- 「Herdr 启动时」比较 Herdr.app 进程启动时间与上次记录值，因为 mod 在任何编辑或布局切换时也会重启。一次丢失 = 同一地址上有存活终端、shell pid 是新的、且没有程序在运行；恢复中的终端会宽限 15 分钟。
- 勾选「Resume automatically next time」会把 `after_restart` 写进 `mods/hibernate/mod.json`，这会重载该 mod。
- 代码视图把 `//`、`/*` 和字符串引号标成 `punctuation`，优先级高于 `comment`，且只有文档列出的语法名生效；于是注释与标点共用一种灰
  （暗色 `#8b949e`、亮色 `#6e7781`），否则注释斜杠会和正文不同色。
- 悬停卡片是 `window` overlay（不抢键盘）；worktree 徽章需要 `gh`。
- 远程机器：预填退回剪贴板；媒体与文件夹监视仅限本机。
- `herdr.yaml` / `orca.yaml` 只解析 `scripts.setup`（单行，或 `|` / `>` 块），不按完整 YAML 解析。两者同时存在时 `herdr.yaml` 优先。
  Create 打开一个还没有 space 的既有 checkout 时，setup 脚本同样会运行。

## 完成标准

- 每个 mod 通过 `herdr-app check`，`layout.switch {"name":"oh-my-herdr"}` 能显示，且
  `herdr-app status` 无错误。
- 仓库行悬停显示 ⌄ ⋯ +；+ 打开该仓库的 Create worktree。
- agent 显示在其 space 或 worktree 之下；在该 agent 里 `hc run -- sleep 60` 会在其下树线上出现嵌套行；折叠仓库行两者都消失、第二行计入数量；关闭 Agents 开关显示 Agents 面板。
- 选中仅远程分支会创建跟踪 worktree 和 space；选中 issue 填入 `dev/feat/N` 和标题；连按两次 ⌘↵ 建出一个 space。
- 仓库 `herdr.yaml` 里有 `scripts: setup: echo $HERDR_WORKTREE_PATH`（或 Project settings 里的本地脚本）时，创建 worktree 会打印新 worktree 的路径和「Setup finished.」；关掉「Wait for setup」则与 agent 的 tab 并排跑在 Setup tab。
- 关联了 issue 和 PR 的 worktree 显示两个徽章；悬停出卡片；点徽章打开带 PR 标签和合并卡片的查看器。
- 在 Files 里点 Markdown 文件在新 tab 渲染打开；再点复用该 tab。
- 在草稿 space 跑 `sleep 600`，Sleep space 后留下同 pid 的空闲 shell，行显示 Asleep；Wake space 在其中重新运行 `sleep 600`。「When I open the space」开启时，前往该 space 即唤醒。
- `kill -9` 一个测试终端的 shell：herdr-core 以新 pid 恢复并出现在恢复对话框列表；手动退出的程序不出现。
- 状态栏显示 `CPU n% · n GB`；点击列出 space 及其 Sleep 按钮。
