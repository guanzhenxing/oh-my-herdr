# oh-my-herdr

一个 Herdr Desktop 布局，参照 Orca 应用设计：项目侧栏内嵌 worktree，并挂各自的 issue/PR 徽章；每个条目下方直接列出它的 agent 和子代理；space 可以休眠、重启后恢复 agent；带资源占用表、每个 worktree 的悬停卡片、应用内的 GitHub issues 和 pull requests、Create worktree 对话框（可从分支、issue、PR 或新名字创建）、Files 与 Git changes 面板、全局搜索（⌘⌥P：任何机器上的 tab、agent、space、文件、Herdr 命令，`/` 前缀搜文件、`?` 搜 agent 输出、Cmd+Enter 直接给 agent 发消息或移交文件）、用量窗口、实时端口，以及参照 Orca「代理会话历史」的会话历史面板（扫描 Claude、Codex、Pi、OMP、Gemini、OpenCode、ZCode 等本机 transcript 存储，可搜索、过滤、一键恢复、在工作树中恢复、移交给另一个代理、打开日志查看器；侧栏 Sessions 入口或 cmd-shift-h 打开）。

![oh-my-herdr](preview.png)

本项目 fork 自 [VladTemp27/herdr-orca](https://github.com/VladTemp27/herdr-orca)（「Orca for Herdr」布局），在此基础上一路修改而来，并更名为 oh-my-herdr。

它的功能与构建方式见 [RECIPE.md](RECIPE.md)，第三方来源与许可见 [THIRD_PARTY.md](THIRD_PARTY.md)。issues、live ports、usage limits 和 actions 这几个 mod 也在
[VladTemp27/herdr-mods](https://github.com/VladTemp27/herdr-mods) 单独发布。

## 安装

让 Herdr 里的 agent 执行：

> Read ~/.config/herdr-app/AGENTS.md, then add this layout: https://github.com/guanzhenxing/oh-my-herdr

布局还用到 [munza](https://github.com/munza/herdr-mods) 的三个 mod，已收编在本仓库（`mods/better-changes/`、`mods/better-config/`、`mods/better-search/`）——无需手动添加。

或者，从本仓库的克隆里一条命令完成：`sh install.sh`（`--yes` 会覆盖已有的 mods 和布局——加上 `--with-skills` 时还会替换不一致的 skill 副本，并**删除下方链接位置里用户自装的 `herdr-cowork` 目录**；`--dry-run` 可先预览）。它会合并 `keys.json`——你已占用的按键保留原有动作——并把 Herdr 自带的默认键补回来（见下方守卫说明；`keys.json` 被 `cp` 覆盖或在 app 首次运行前装入局部文件会静默丢掉全部默认键，含 `cmd-v` 粘贴；补齐时会打印 `restored N Herdr default binding(s)`）。它按 `mod.schema.json` 的描述保留 Mod 设置，对安装的每个 mod 跑 `herdr-app check`，且从不碰它不随包发布的 mod。日常部署改动时请勿 `cp` 仓库的 keys.json 直盖 `~/.config/herdr-app/keys.json`，只用本脚本或手动 merge。

加 `--with-skills` 还会安装 [herdr-cowork](https://gist.github.com/ninehills/eef70810238f779362a820786ae4a096)
agent skill（收编在 `skills/`，可选）。SKILL.md 会装到 `~/.agents/skills/herdr-cowork/`
——这是 DeepSeek Harness、Codex、OpenCode、Gemini 和 pi 原生读取的跨 agent skills 根目录——并软链到 Claude Code（`~/.claude/skills/`）、Codex（`~/.codex/skills/`，旧路径）、Gemini（`~/.gemini/skills/`）、OpenCode（`~/.config/opencode/skills/`）和 pi
（`~/.pi/agent/skills/`）；home 目录不存在的 agent 会被跳过并列出，而不是创建；未安装 Cursor 则不建链接——装好之后照其他条目补一个软链即可。卸载：`rm -rf ~/.agents/skills/herdr-cowork` 和那五个 `herdr-cowork`
软链。

加 `--with-team --team <包名或团队包目录>` 还会安装一个团队 skill（[skills/herdr-backend/](skills/herdr-backend/README.md)，可选）。它把仓库里的通用协议和团队包的配置拼成一份 SKILL.md，装到 `~/.agents/skills/<skill 名>/`（名字由团队包决定），软链到同样五处 agent 目录，并把团队包里的角色模板软链进 hc 的模板目录 `~/.config/herdr-core/templates/`（hc 的模板目录不存在则跳过并列出）。团队包放在 `~/.config/herdr-teams/<包名>/`，不随本仓库分发（仓库自带的示例包除外），做法见 [skills/herdr-backend/README.md](skills/herdr-backend/README.md)；不带 `--team` 只列出已知的团队包。hc 模板目录里已有的同名普通文件，内容与要链接到的模板相同的会换成软链；这一步不需要 `--yes`，内容不变。带 `--yes` 时，它会覆盖该目录里受管理的四项（SKILL.md、README.md、team.md、`templates/`），删掉团队包里已经没有的旧模板和它们的软链，并重建指向别处的软链；五处 agent 目录里已有的 `<skill 名>` 真实目录或普通文件会被删掉再重建；hc 模板目录里内容不同的同名普通文件和目录不动。卸载：删 `~/.agents/skills/<skill 名>`、那五处 `<skill 名>` 软链，以及 hc 模板目录里指向该目录的软链。

手动安装：

1. 把 `layouts/oh-my-herdr.json` 拷进 `~/.config/herdr-app/layouts/`，把 `mods/` 里的每个目录拷进
   `~/.config/herdr-app/mods/`。与你已有名字冲突的重命名。Better Changes 自带
   `"place": "none"`——布局已经为它留了位置。
2. 把 `keys.json` 合并进 `~/.config/herdr-app/keys.json`（它的 `layout:oh-my-herdr` 段只在
   本布局显示时生效）。
3. 对每个 mod 跑 `herdr-app check ~/.config/herdr-app/mods/<name>`，然后
   `herdr-app do layout.switch '{"name":"oh-my-herdr"}'`。`ctrl-shift-l` 切回原布局。

按键遵循 Herdr 自身的约定：`cmd-n` 仍是「新建 space」，Create worktree
对话框改用 `cmd-alt-n`。`keys.json` 的 `layout:oh-my-herdr` 段里的所有绑定
（agent 导航、侧栏面板开关、关闭 tab 和 pane）只在本布局显示时生效，不会遮蔽你其他布局的按键。

需要 `git` 和已登录的 `gh`。用量窗口读取 `claude` 和 `codex` CLI；Automations 使用随包的
`herdr-automations` CLI（由 `install.sh` 安装；缺失时面板会说明）；桌面通知在装有 `terminal-notifier` 时使用它——macOS 上可跑 `mods/desktop-notifications/setup-notifier.sh`，装一个带 Herdr 图标的副本（`~/Applications/Herdr Notifier.app`），系统通知就统一由它发出、点击即聚焦对应 agent。在 macOS、Herdr 0.1.18 上构建并测试——macOS 优先：Linux 和 Windows 上 issue 预填改为把任务放进剪贴板（用 Ctrl+Shift+V 粘贴），Windows 没有 space 休眠功能（hibernate mod 会在运行时警告）；其余功能走相同
路径。所有 mod 会执行和访问什么，见下文「这个布局会运行什么」。

## 这个布局会运行什么

各 mod 会调用外部程序并访问网络；这是完整清单，供你在安装前判断：

- **程序：** `git`（分支、远程、worktree），`gh`（issues、PR、仓库——需要已登录的
  `gh`），`lsof`、`ss`、`ps`、`pgrep` 和 `kill`（实时端口、资源占用、休眠），`sysctl`
  （资源占用），`curl`（下文「网络」），`open` / `xdg-open` / `powershell` / `code`（打开文件、文件夹或链接），`sips` / `convert`（项目图标），`osascript` / `terminal-notifier` /
  `notify-send`（桌面通知），`pbcopy` / `pbpaste`（issue 预填），`printenv`（远程机器的 home 目录），`herdr-automations`（Automations：定时提示——它的启动横幅会安装一个按用户的调度服务，macOS 经 `launchctl` 装 LaunchAgent，Linux 装 systemd 用户单元；数据在 `~/.config/herdr/plugins/config/dnzzl.automations/` 和
  `~/.local/state/herdr/plugins/dnzzl.automations/`；收编在 `cli/herdr-automations/`），
  `hc`（Herdr 自带 CLI），以及使用常见工具（`grep`、`sed`、`awk`、`jq`、`mkdir`、`find`、`cp`、`rm`、`date`、
  `sleep`）的小段 `sh`
  脚本和一段 `python3` 脚本（session-history 的会话扫描器；macOS 自带）。用量窗口会调用 `claude` 和 `codex` CLI：鉴权由 CLI 自己完成，
  这里的任何代码都看不到它们的令牌。
- **网络：** 只连 GitHub。`gh` 访问 GitHub API。`curl` 从 `github.com` 下载头像和项目图片，以及 issue/PR 正文引用的图片。对私有仓库的图片，`gh` 的令牌经 stdin 交给 curl——绝不走参数或命令行——且仅用于 `https://github.com/` 的 URL；当 GitHub 重定向到其存储主机时 curl 会丢弃令牌。
  除此之外不抓取任何内容。
- **文件：** usage-limits 的 helper 读取会话日志（`~/.claude/sessions/`，遵循
  `CLAUDE_CONFIG_DIR`，以及 Codex 的 rollout 文件）统计 token 和调用次数——离开这些脚本的只有数字。Hibernate 只从同样的文件里读会话 id，用于休眠后恢复 agent。session-history
  读取各 agent CLI 的会话 transcript 存储（`~/.claude/projects/`、`~/.codex/sessions/`、
  `~/.pi/agent/sessions/`、`~/.omp/agent/sessions/`、`~/.gemini/tmp/`、OpenCode 的
  `storage/session/` 与 `opencode.db`（只读查询）、`~/.zcode/cli/agents/`）来列出和恢复
  历史会话，并把这些会话的索引缓存在 `~/.config/herdr-app/data/session-history/`；
  「删除」会删除选中的 transcript 文件或目录（两步确认）。不读取任何凭证。
- **Skills（可选，`--with-skills`）：** 不联网——收编的
  `skills/herdr-cowork/SKILL.md` 被拷贝并软链（位置见上）。这个 skill 是一套提示词协议：采用它作为 commander 的 agent 会运行 `hc` 启动成员 agent CLI
  （各自在自己的权限下），在当前工作区写 `TEAM.md`，并通过 `herdr-app` 重命名 tab。它的 frontmatter `allowed-tools` 只在 Claude Code 里预授权 `hc`/`herdr-app`；其他 agent 走各自的审批流程。
- **团队 skill（可选，`--with-team --team`）：** 不联网——`skills/herdr-backend/` 里的通用协议和本机的团队包拼成一份 skill，连同五处 agent 软链和 hc 模板目录里的软链（位置见上）。它是一套提示词协议：采用它的 agent 作为 Commander 经 `hc` 启动成员 CLI；成员按团队包模板的 `command` 运行，权限随各自的 harness，其中执行角色可以按用户的点名提交、推送、发布部署，开发角色在实现任务时会自行提交。团队包不随本仓库分发。它的 frontmatter `allowed-tools` 同样只在 Claude Code 里预授权 `hc`/`herdr-app`。

## 更新本仓库

`./sync.sh` 把布局和这些 mods 从你的 Herdr home 拷回仓库。
收编的 better-changes、better-config 和 better-search 手动跟随 [munza/herdr-mods](https://github.com/munza/herdr-mods)：
在应用里从它的仓库重新添加 mod（或把新文件拷进你的 Herdr home），在 `mod.json` 里把 Better Changes 的 `"place"` 改回 `"none"`，跑 `./sync.sh` 并提交；
已安装用户用 `sh install.sh --yes` 升级。
收编的 skill 手动刷新：抓取 gist，把 frontmatter 的 `name` 改成
`herdr-cowork`，替换 `skills/herdr-cowork/SKILL.md` 并提交；已安装用户用
`sh install.sh --with-skills --yes` 升级（软链指向目录，会跟随新副本）。
`skills/herdr-backend/` 的通用协议更新后，没有直接改过装好的文件的，重跑 `sh install.sh --with-team --team <包名> --yes`；直接改过的（包括对 Commander 说过"以后 X 都用 Y"），把 `--team` 指向 `~/.agents/skills/<skill 名>`，本机的改动才会保留。验收：`sh skills/herdr-backend/tests/install-team.sh`。
`previews/render.sh` 用无头 Chrome 从 `previews/preview.html` 重绘 `preview.png`：
预览是一份带演示数据的 HTML mockup，所以不会发布你自己工作的截图。

## 许可

Apache-2.0，见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。
