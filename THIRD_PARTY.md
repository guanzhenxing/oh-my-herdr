# 第三方来源与许可

本仓库使用了以下第三方作品。按使用方式分三组：**收编并修改**（代码进入仓库且有本地改动）、**收编未修改**（代码进入仓库，原样保留）、**参考与致谢**（只用思路或素材，未复制代码）。

## 收编并修改

| 组件 | 来源 | 许可 | 使用方式 |
| --- | --- | --- | --- |
| oh-my-sidebar（Better Sidebar 3.0.0 基底） | [munza/herdr-mods](https://github.com/munza/herdr-mods)，© 2026 Tawsif Aqib | Apache-2.0 | `mods/oh-my-sidebar/`，深度修改，并挑选移植了上游 3.3.0 / 3.7.0 / 3.10.0 的部分修复：见其 `CHANGES.md`；`init` 里有 orca → oh-my-herdr 的一次性共享状态迁移 |
| t3-actions | [JinJieBeWater/herdr-t3](https://github.com/JinJieBeWater/herdr-t3) | Apache-2.0 | `mods/t3-actions/`，修改：见其 `CHANGES.md` |
| session-history | [itisvincent/herdr-session-history](https://github.com/itisvincent/herdr-session-history) | MIT | `mods/session-history/`，修改：见其 `CHANGES.md`（macOS 化动作、OMP/ZCode/Gemini 源路径修正、去掉面板收起按钮）；其 `icons/omp.svg` 取自 Herdr 自带图标（Apache-2.0）、`icons/zcode.svg` 来自本仓库 `mods/usage-limits/icons/` |
| herdr-automations | [DnzzL/herdr-automations](https://github.com/DnzzL/herdr-automations)，© 2026 Thomas Legrand | MIT | `mods/automations/` 是它的应用 mod（仅调整 `mod.json`）；其 Go CLI 收编在 `cli/herdr-automations/`，带两处原子写入补丁——见其 `VENDOR.md` |
| Herdr Desktop 自带 mods | [herdrdev/herdr-app](https://github.com/herdrdev/herdr-app) | Apache-2.0 | `my-menu`、`my-new-menu`、`my-pane`、`my-status`、`my-tabs`、`my-worktree`、`files-open-with`、`file-icons` 分别是 Herdr 自带 `menu`、`new-menu`、`pane`、`workspace-status`、`tabs`、`worktree`、`files` 的修改副本；`issues`、`new-worktree` 与 Better Sidebar 的部分代码和图标也取自它 |

## 收编未修改

| 组件 | 来源 | 许可 | 使用方式 |
| --- | --- | --- | --- |
| Better Changes 2.7.0 | [munza/herdr-mods](https://github.com/munza/herdr-mods)，© 2026 Tawsif Aqib | Apache-2.0 | `mods/better-changes/`，零改动；`place` 设为 `"none"`（布局自带槽位） |
| Better Config 0.4.0 | [munza/herdr-mods](https://github.com/munza/herdr-mods)，© 2026 Tawsif Aqib | Apache-2.0 | `mods/better-config/`，零改动 |
| Image Viewer | [dougcunha/herdr-mods](https://github.com/dougcunha/herdr-mods)，© 2026 Douglas Cunha | MIT | `mods/image-viewer/`，带一处 PowerShell 弯引号转义补丁（见其 `CHANGES.md`）；`mods/files-open-with/` 对图片文件调用它（`mod` 菜单动作与 `tabs.js` 路由） |
| Excalidraw | [excalidraw/excalidraw](https://github.com/excalidraw/excalidraw) | MIT | 打包在 `mods/excalidraw/`，声明见其 `LICENSE*` 文件 |
| Material Icon Theme | [material-extensions/vscode-material-icon-theme](https://github.com/material-extensions/vscode-material-icon-theme) | MIT | 图标在 `mods/file-icons/`，声明见 `LICENSE-material-icon-theme.txt` |
| herdr-cowork skill | [ninehills 的 gist](https://gist.github.com/ninehills/eef70810238f779362a820786ae4a096)，© 2026 ninehills，v1.3.0 | 未声明 | `skills/herdr-cowork/SKILL.md`；frontmatter `name` 由 cowork 改为 herdr-cowork；其 `version:` 字段超出 Agent Skills 规范，原样保留 |

## 参考与致谢

| 来源 | 关系 |
| --- | --- |
| [jmalicki/herdr-mod-ai-usage](https://github.com/jmalicki/herdr-mod-ai-usage)，© 2026 Joseph Malicki（MIT） | 仅思路。`mods/usage-limits/helpers/` 以相同方式向 `claude` 和 `codex` CLI 询问用量；未复制代码 |
| [Orca for Herdr](https://github.com/VladTemp27/herdr-orca)，© 2026 VladTemp27 | 本项目 fork 自它并更名；设计出处（见 `NOTICE`）。README/RECIPE 中「参照 Orca 应用」均指此 |
| [Orca 桌面应用](https://orca.app) | 设计参照：「移交给另一个代理」（`mods/agent-handoff/`）与「防止电脑休眠」（`mods/keep-awake/`）两个功能的交互形态来自它；代码为本项目自研 |

另注：Lucide 图标（ISC）贯穿全仓库使用，与 Herdr 自带 mods 的做法一致。munza/herdr-mods 的许可与 NOTICE 原文已并入根目录 `NOTICE`。
