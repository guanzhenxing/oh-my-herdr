# cowork 框架：通用协议加团队包

日期：2026-11-24
状态：设计方向已由维护者确认，文档待审

## 背景

本仓已收编 `skills/herdr-cowork`：一套以 TEAM.md 为注册表的 Commander 协议。维护者本机另有一套手工安装的调度协议，和它是两套独立的东西。这套协议的规则是：Commander 只调度和报状态，一步一停，下一步由人决定。它已经过一轮改写和冒烟，但装法是一次性的：

- skill 里约 15% 的内容是团队或个人独有的：角色与默认模型、工作区与仓别名、命名前缀、路径。其余是通用规则。
- 五个角色模板的正文全部通用。每个模板只有名字、描述和 command 三行与团队有关。
- 模板是直接放进 hc 模板目录的普通文件。

本仓是公开仓，团队独有的内容不能入库。要让别人装上 oh-my-herdr 就能用这套协议，需要把通用部分和团队部分拆开。

## 决策记录

1. **分三层。** 通用协议进本仓；团队包不进本仓；个人改动落在团队包或装好的文件里。
2. **安装时拼合。** 安装脚本把通用协议和团队附录拼成一份 SKILL.md。Commander 运行时只读一个文件。
3. **模板的源文件放进 skill 目录，安装时逐个软链进 hc 的模板目录。** 实测（hc 0.1.22）：hc 只读 `~/.config/herdr-core/templates`，不扫子目录，会跟随软链。
4. **团队包自成一体。** 每个团队包带完整的五个模板。角色提示词因此有两份：示例包一份，各团队包一份。等出现第二个真实团队包，再考虑把角色正文收回仓库统一维护。
5. **可选安装。** 默认不装，和 `--with-skills` 一致，因为写入面超出了 Herdr home。
6. **放进 `skills/herdr-cowork/`，和收编的 herdr-cowork skill 同一个目录。** 两种装法装出来的都是 skill，名字都以 `herdr-cowork` 结尾：`--with-skills` 装收编的那一份，`--with-cowork` 装团队 skill。源文件因此放在一处，`skills/` 下只有一个目录。`--with-skills` 只读 `SKILL.md` 一个文件，同目录多出来的文件不影响它。验收脚本跟着放进 `skills/herdr-cowork/tests/`，仓库顶层不新增目录，也不设 `plugins/`："插件"在各家 agent 里格式和安装命令都不同，仓里出现 `plugins/`，容易被当成某个 agent 的插件去找安装命令。
7. **skill 的名字写在团队包里，按岗位起。** 起初装出来的 skill 按 `<团队名>-herdr-cowork` 拼，那是维护者早先把它当作 herdr-cowork 的扩展时的叫法。两者成为独立的协议之后，这个名字还在暗示继承关系，还带着团队或公司的名字。维护者决定名字由团队包的 `name` 决定，建议 `herdr-<岗位>`，如 `herdr-backend`；示例包叫 `herdr-example`。名字放开之后，安装器多两条保护：不能叫 `herdr-cowork`；要装的位置上已经有一个不属于团队 skill 的目录时拒绝安装。

被否决的做法：

| 做法 | 否决原因 |
|---|---|
| 通用 skill 加同目录的团队配置文件 | 前台每次要多读一个文件。弱档前台可能漏读，这一点没有验证过 |
| 通用 skill 和团队 skill 各一份，运行时写"以通用为准" | 跨 skill 的"以 X 为准"已经实测会把前台带偏 |
| 团队包的托管与分发 | 维护者决定暂不分发，团队包先留在本机 |
| 把 cowork 做成 agent 插件，放在 `plugins/cowork/` | Claude Code、zcode、Codex、pi、omp 的插件都装得下"一份 skill 加随附文件"，但格式各不相同，要维护五套清单；而且没有一家会在安装时执行脚本，拼合和软链仍然要自己写。维护者只是觉得顶层目录别扭，不需要插件 |
| `skills/` 下另设 `skills/cowork/`，和 `skills/herdr-cowork/` 并列 | 装出来的都是 skill，名字都以 `herdr-cowork` 结尾，源文件没有理由分在两处；`skills/` 下两个并列的目录，维护者看着别扭，于是并进 `skills/herdr-cowork/`。`--with-skills` 只读 `SKILL.md` 一个文件，不受影响 |
| skill 名固定拼成 `<团队名>-herdr-cowork` | 名字还在暗示它是 herdr-cowork 的扩展，而两者是独立的协议。现在名字由团队包决定 |

## 目标

1. 本仓在 `skills/herdr-cowork/` 里新增：通用协议、通用说明、示例团队包，以及它的验收脚本。收编的 `SKILL.md` 不动。
2. `install.sh --with-cowork --team <团队名或团队包目录>` 把两者拼合并安装到 `~/.agents/skills/<skill 名>/`，名字取自团队包；再软链到各 agent 和 hc 的模板目录。
3. README 如实披露安装面和运行期执行面。
4. 安装器的行为由一个可重复运行的验收脚本覆盖。

## 非目标

- 团队包的托管、分发和迁移工具。
- 把角色正文抽回仓库统一维护。
- 改动收编的 `skills/herdr-cowork/SKILL.md` 和 `sync.sh`。
- 卸载参数。README 写手工卸载步骤。
- 不带团队包的裸通用 skill。

## 设计

### 1. 三层的分工

| 层 | 内容 | 在哪 |
|---|---|---|
| 通用层 | 铁律、动作菜单、首条任务固定写法、启动与等待、停靠报告、故障处理 | 本仓的 `skills/herdr-cowork/PROTOCOL.md` |
| 团队层 | 团队名、命名前缀、角色与默认模型、工作区与仓别名、评审暂存目录、产物目录、本机要留意的其他规则 | 团队包的 `team.md` |
| 个人层 | 改默认模型、加减仓别名 | 团队包，或装好的模板 |

五个角色的键固定为 `arch`、`dev`、`review`、`test`、`run`，对应架构、开发、评审、测试、执行。模板名固定为 `<前缀>-<键>`，例如 `example-arch`。通用协议直接按这个名字引用模板，不再做"角色到模板名"的绑定。

### 2. 仓库内容

```
skills/
└── herdr-cowork/
    ├── SKILL.md              现有：收编的 skill，--with-skills 只装这一个文件
    ├── PROTOCOL.md           新增：装出来是 skill 的源材料
    ├── README.md
    ├── teams/
    │   └── example/
    │       ├── team.md
    │       └── templates/
    │           ├── example-arch.md
    │           ├── example-dev.md
    │           ├── example-review.md
    │           ├── example-test.md
    │           └── example-run.md
    └── tests/
        └── install-cowork.sh
```

`PROTOCOL.md` 不是一份现成的 skill，装的时候才拼出来，所以不叫 `SKILL.md`。同目录的 `SKILL.md` 是收编的 herdr-cowork skill，另一套协议；现有的 `--with-skills` 只读它这一个文件，不受影响。

**PROTOCOL.md** 是一份带 frontmatter 的通用协议，本身不能当 skill 用：

- frontmatter 的 `name` 写成占位符 `TEAM-SKILL`。正文里只有一处再用到它：首条任务末尾告诉成员不要加载哪些 skill 的那一句，要写出本 skill 的名字。安装时把 `TEAM-SKILL` 全部替换成团队包里的 `name`。
- `description` 不提任何团队。
- `metadata` 下的 `version` 是 `0.3.0`。
- 正文沿用维护者本机已冒烟过的那一版规则，只做去团队化的改写：
  - 标题和简介去掉团队字样，说明它是独立于 herdr-cowork 的另一套协议。
  - 动作菜单里的模板名写成 `<前缀>-arch` 这种形式。
  - 成员名写成 `<前缀>-<角色>-<短名>`。
  - 工作区白名单、评审暂存目录改成"见团队配置"。产物目录在固定写法里保留默认位置 docs/design、docs/review、docs/adr、docs/test，并写明以团队配置为准，这样 Commander 起成员时不必逐条查配置。
  - 排他声明里引用的项目记忆原话改成通用说法。具体的条目放进团队配置。

**通用协议对团队配置的引用约定。** 正文只引用团队配置里的小节，标题固定：

| 小节标题 | 必须有 | 内容 |
|---|---|---|
| `### 角色与模板` | 是 | 表：角色、模板、tab 名、默认 harness 与模型 |
| `### 命名前缀` | 是 | 模板名和成员名的前缀 |
| `### 工作区` | 是 | 允许动手的根目录；仓别名 |
| `### 路径` | 是 | 评审暂存目录；产物目录 |
| `### 本机要留意的其他规则` | 否 | 环境里会把 Commander 带偏的具体条目 |

**团队包**是一个目录，放在本仓之外：

```
<团队包>/
├── team.md
└── templates/
    └── <前缀>-<键>.md    五个角色各一个，可以多，不能少
```

`team.md` 的开头是两个登记项，正文是团队配置的各个小节：

```markdown
---
name: herdr-example
prefix: example
---

## 团队配置

### 角色与模板
…

### 命名前缀
…
```

- `name` 是装出来的 skill 的名字，目录和软链都叫这个。按 Agent Skills 规范：小写字母和数字，中间用单个连字符，最长 64 个字符。不能是 `herdr-cowork`，那是收编的 skill。名字由团队自己起，和 `--team` 给的目录名无关；建议按岗位起，如 `herdr-backend`。
- `prefix` 是模板名和成员名的前缀，只用小写字母、数字和连字符。在本机要唯一：hc 的模板目录是平的，两个团队共用前缀会争同一个模板名。
- 模板是完整的 hc 模板：文件名就是模板名，frontmatter 的 `name` 必须等于文件名（不带 `.md`），长度不超过 32。这是 hc 对模板名的规则。

**示例团队包** `skills/herdr-cowork/teams/example/` 用占位的工作区和不带模型参数的命令。别人可以先装它，再照它做一个自己的团队包。它同时是五个角色提示词的标准版本。它装出来的 skill 叫 `herdr-example`：工作区是占位的，不该看起来像一支配好的团队。

### 3. 安装命令

```
sh install.sh --with-cowork --team <团队名或团队包目录>
```

`--team` 的值带斜杠时按路径处理：绝对路径原样使用，相对路径相对于运行安装器时所在的目录。不带斜杠时按团队名处理，依次找 `~/.config/cowork/teams/<团队名>` 和仓库里的 `skills/herdr-cowork/teams/<团队名>`，本机的优先。这样，一个和仓库顶层目录同名的团队不会被当成目录。报告里写明用的是哪一个。下文说的"已知团队包"，指这两个位置下的每个子目录。

### 4. install.sh

**环节结构**和 `--with-skills` 相同：前置守卫在参数解析之后；全部状态判定在 dry-run 门之前，结果经 `say()` 报告；写入块放在 herdr-cowork 的写入块之后、`herdr-app check` 之前。

**参数规则与退出码：**

| 情况 | 退出码 | 输出 |
|---|---|---|
| `--with-cowork` 不带 `--team` | 2 | 列出已知的团队包 |
| `--team` 不带 `--with-cowork`，值为空也算给了 | 2 | 报错 |
| `--team` 后面没有值 | 2 | 报错 |
| 团队包找不到 | 1 | 报错，并列出已知的团队包 |
| 团队包不合法，或仓库缺 `skills/herdr-cowork/PROTOCOL.md`、`skills/herdr-cowork/README.md` | 1 | 报错 |
| 前缀已被另一个团队使用 | 1 | 报错，点名那个团队的 skill |
| skill 要装的位置上已经有一个不是团队 skill 的目录，里面没有 `team.md` | 1 | 报错，`--yes` 也不覆盖 |
| 参数未知 | 2 | 用法提示里列出新增的两个参数 |

**团队包校验。** 任何一项不过就退出 1，不写任何文件：

- `team.md` 存在，`name` 和 `prefix` 非空且符合字符规则；`name` 不超过 64 个字符，也不是 `herdr-cowork`。
- 必须有的四个小节标题都存在。
- `team.md` 的 frontmatter 以 `---` 闭合，不用 Windows 换行。这两种毛病下登记项照样读得出来，正文却不会进入 SKILL.md。
- `templates/` 里五个 `<前缀>-<键>.md` 齐全。每个模板，包括多出来的，frontmatter 的 `name` 等于文件名，文件名最长 32 个字符、不带空白。长度是 hc 对名字的上限；名字里有空白还会把要建的软链清单拆散。
- `skills/herdr-cowork/PROTOCOL.md` 里 `name: TEAM-SKILL` 恰好出现一次。

**拼合。** 目标 SKILL.md 由四段依次拼成：

1. `skills/herdr-cowork/PROTOCOL.md`，其中的 `TEAM-SKILL` 全部替换成团队包里的 `name`。
2. 一个空行。
3. 一行分界注释，说明以上是通用协议、以下是团队配置，并提示个人改动落在团队包或模板里，改 `team.md` 后要重跑安装器。
4. `team.md` 去掉开头 frontmatter 之后的正文，紧跟 frontmatter 的空行不算。

判定阶段把拼合结果写进一个临时文件，用它和已装的 SKILL.md 比较。dry-run 不写任何目标文件。

**目标位置：**

| 内容 | 位置 |
|---|---|
| SKILL.md，即拼合结果 | `~/.agents/skills/<name>/SKILL.md` |
| README.md | 同一目录，是 `skills/herdr-cowork/README.md` 的原样副本 |
| team.md | 同一目录，是团队包 `team.md` 的原样副本 |
| `templates/*.md` | 同一目录的 `templates/`，是团队包模板的原样副本 |
| agent 软链 | 五处，和 `--with-skills` 相同：claude、codex、gemini、opencode、pi |
| hc 模板软链 | `~/.config/herdr-core/templates/<模板名>.md`，指向 `../../../.agents/skills/<name>/templates/<模板名>.md` |

**决策表：skill 目录。** "一致"指 SKILL.md、README.md、team.md 三个文件逐字节相同，且两个 `templates/` 目录内容相同（忽略 `.DS_Store`）。

| 目标状态 | 默认 | 加 `--yes` |
|---|---|---|
| 目录不存在 | 安装 | 同左 |
| 目录存在且一致 | 报 "up to date" | 同左 |
| 目录存在但不一致 | 保留，提示可加 `--yes` 覆盖 | 覆盖上表的前四项。`templates/` 镜像团队包：多余的旧模板删掉，它们在 hc 目录里的软链也删掉。目录里的其他文件不动 |
| 目录本身是软链 | 保留并提示 | 同左，`--yes` 也不动 |
| 位置上是普通文件，不是目录 | 保留并提示 | 同左，`--yes` 也不动 |
| 位置上是真实目录，里面没有 `team.md` | 退出 1 | 同左，`--yes` 也不覆盖 |

团队包就是装好的目录时，覆盖只重写 SKILL.md 和 README.md；`team.md` 和 `templates/` 是用户改过的，原样不动。装好的 `team.md` 或模板和团队包不一致时，报告写明这一点、`--yes` 会覆盖它们，以及想保留就把 `--team` 指向装好的目录。

**决策表：agent 软链。** 五条规则和 `--with-skills` 完全相同：agent 主目录不存在就跳过；链接已指向该目录就不动；位置不存在就建；软链指向别处时默认保留、`--yes` 重建；位置上是真实目录或普通文件时默认保留、`--yes` 删除后重建。位置上有东西时，报告写明那是什么、`--yes` 会对它做什么；hc 目录里指向别处的软链加 `--yes` 重建时，同样写明。skill 目录是软链而目标里没有 SKILL.md，或者那个位置上是普通文件时，不建链，提示里不建议加 `--yes`。

**决策表：hc 模板软链。** 对 `templates/` 里的每个 `.md` 各判一次：

| hc 模板目录里的状态 | 默认 | 加 `--yes` |
|---|---|---|
| hc 的模板目录不存在 | 整体跳过，并提示建好目录后重跑 | 同左 |
| 位置不存在 | 建相对软链 | 同左 |
| 是软链，解析后就是目标文件 | 报 "up to date" | 同左 |
| 是断链 | 重建 | 同左 |
| 是软链，指向别处 | 保留并提示 | 重建 |
| 是软链，指向另一个团队的 skill 目录 | 退出 1，点名那个团队的 skill | 同左 |
| 是普通文件，内容与链接将指向的模板相同 | 换成软链 | 同左 |
| 是普通文件，内容不同 | 保留，提示自行移走 | 同左 |
| 是目录 | 保留并提示 | 同左 |

"内容相同就换成软链"是为迁移准备的：早先的装法把模板当普通文件放在这里，内容相同就没有损失。比较的是链接将指向的那一份：skill 目录被写入时是团队包里的模板，被保留时是已装的那份。只有真的不损失内容才换，所以不需要 `--yes`。"内容不同"的文件即使加 `--yes` 也不动，宁可不装，也不丢用户的文件。

是不是另一个团队的 skill 目录，看那个目录里 `team.md` 的 `name`，不看目录叫什么。

**写入顺序。** 先写 skill 目录；写成功后才建两种软链，沿用"复制失败不建链"的原则，免得留下断链让每个 agent 都列出一个坏 skill。hc 软链按团队包里的模板逐个建；skill 目录被保留、其中缺某个模板时，那一条跳过并提示。写入会删掉的旧模板和会断的 hc 软链，在判定阶段就定下来并报告，dry-run 也列。

**agent 表共享。** 五家 agent 的 `名字|主目录|相对层级` 表抽成一个函数 `skill_agent_homes`。`--with-skills` 现有的两处 heredoc 改为调用它，行为不变。

### 5. 测试

`skills/herdr-cowork/tests/install-cowork.sh` 在一次性的 `$HOME` 里跑 `install.sh`，不联网、不碰真实目录：

- PATH 上放 `herdr-automations` 和 `herdr-app` 的空壳，让安装器既不构建也不联网，再不带上真实 PATH 里的 `herdr-app`。
- 现场生成一个团队包。
- 每项验收打印通过或失败，有任何一项失败就以非零退出。

这个脚本是新增文件，仓库此前没有测试目录。

### 6. 文档

**仓库的 `README.md`：**

- Install 段加 `--with-cowork` 和 `--team` 的说明。
- 新增 "Cowork (opt-in)" 条目，披露三面：
  - 安装面：一个 skill 目录，五个 agent 软链位置，hc 模板目录里每个模板一条软链。
  - 运行期执行面：Commander 经 `hc` 启动成员 CLI；成员按模板的 command 运行，权限随各自的 harness；执行角色可以按用户的点名提交、推送、部署。
  - `--yes` 的破坏范围：覆盖 skill 目录里受管理的四项；删除多余的旧模板和它们的软链；重建指向别处的软链；删除 agent 软链位置上的真实目录或普通文件。
- 升级和手工卸载的步骤。
- `name` 怎么起：按岗位，如 `herdr-backend`；一个名字在一台机器上只能装一份。

**`skills/herdr-cowork/README.md`** 给人看，装进 skill 目录。内容依次是：这是什么；能说什么；角色与模型；标准流程；为什么这样设计；安装、升级、卸载；做一个团队包；个人改动放在哪；文件在哪。安装放在做团队包之前，因为示例包可以直接装。

### 7. 升级与卸载

装好的目录本身就是一个合法的团队包：它有带登记项的 `team.md`，也有 `templates/`。协议让 Commander 直接改装好的模板来换默认模型，原来的团队包不会跟着变。所以直接改过装好的文件之后，升级时要把 `--team` 指向装好的目录。指向原来的团队包再加 `--yes`，会用旧值覆盖这些改动。

- 升级通用协议：更新本仓后重跑 `sh install.sh --with-cowork --team <团队名> --yes`。
- 直接改过装好的模板或 `team.md`，包括对 Commander 说过"以后 X 都用 Y"：升级时把 `--team` 指向 `~/.agents/skills/<name>`，新的通用协议和本机的改动都会保留。这时更新的是 SKILL.md 和 README.md；`team.md` 和 `templates/` 不动。
- 改 skill 的名字：改团队包里的 `name` 再装，会装出另一份 skill。旧的那份照卸载清掉；不清的话它还占着模板前缀，新的一份会被拒绝。
- 改团队内容：改团队包，再重跑。
- 卸载：删 `~/.agents/skills/<name>`，删五处 agent 软链，删 hc 模板目录里指向该目录的软链。

## 错误处理

`install.sh` 顶部有 `set -e`，所以 cowork 环节的每条写入命令都带 `|| { echo …; }` 守卫。任何单点失败都不中断整体安装：

- skill 目录写入失败：跳过全部建链，输出一条汇总。
- 单处建链失败：逐条报错，继续其余位置。
- 团队包不合法或仓库文件缺失：在写入任何文件之前退出。
- 要装的位置上已有不属于团队 skill 的目录：在写入任何文件之前退出。

## 验收

`skills/herdr-cowork/tests/install-cowork.sh` 覆盖下面各项，全部在一次性的 `$HOME` 里进行。脚本的小节按执行顺序编号，和这里的条目不一一对应：

1. `sh -n install.sh` 语法通过。
2. 不带 `--with-cowork`：没有 cowork 相关的动作和输出。
3. `--with-skills` 不受影响：全新安装后 `herdr-cowork` 的副本和五处软链都正确。另外在实施时核对一次：改动前后各跑一遍 `--with-skills --dry-run`，两份输出逐字相同，证明抽出 `skill_agent_homes` 没有改变原有行为。
4. `--with-cowork` 不带 `--team`：列出已知团队包，退出码 2，零写入。
5. `--team x` 不带 `--with-cowork`：退出码 2。
6. `--with-cowork --team nope`：退出码 1。
7. `--with-cowork --team example --dry-run`：报告可达，零写入。
8. 全新安装，预建五家 agent 的主目录和 hc 的模板目录：
   - SKILL.md 等于四段依次拼接的结果；
   - README.md、team.md、`templates/` 与源相同；
   - 五处 agent 软链解析到 skill 目录；
   - 每个模板在 hc 目录里有一条软链，解析到 skill 目录里的文件。
9. 重复执行：全部 "up to date"。
10. 篡改已装的 SKILL.md 后重跑：默认保留并提示；加 `--yes` 恢复；已经正确的软链不被重建。
11. hc 目录里放一个内容相同的普通文件：换成软链。放一个内容不同的普通文件：保留并提示，加 `--yes` 也不动。
12. hc 的模板目录不存在：跳过并提示，其余照装。
13. 缺一家 agent 的主目录：那一处跳过，其余照装。
14. skill 目录是软链：默认和 `--yes` 都保留。
15. `--team` 给目录路径：照常安装。
16. 团队包不合法的五种情况各自退出 1 且零写入：缺 `name`；缺 `prefix`；缺一个必须有的小节；少一个模板；模板的 `name` 与文件名不符。
17. 从 `templates/` 里删掉一个多余的模板后加 `--yes` 重跑：旧模板和它的 hc 软链都被删除。
18. `--team` 后面没有值，或后面跟的是另一个参数：退出码 2。参数未知时，用法提示里列出新增的两个参数。
19. 三张决策表的其余各格：hc 目录里的断链重建；指向别处的软链默认保留并提示，加 `--yes` 重建；hc 目录里的目录始终保留；agent 软链指向别处、或位置上是真实目录或普通文件时，默认保留并提示，加 `--yes` 重建。
20. skill 目录被保留且里面没有 SKILL.md：不建任何软链，并说明原因。被保留且缺某个模板时，那一条 hc 软链不列进要建的单子，并说明原因。
21. 本机和仓库里有同名的团队包：用本机的，报告里写明是哪一个。
22. 团队名和仓库的顶层目录同名：按团队名找到团队包，不被当成目录。
23. `--team` 给相对路径：相对于运行安装器时所在的目录。
24. 两个团队共用前缀：后装的退出码 1，点名先装的那个 skill，零写入；加 `--yes`、加 `--dry-run` 都一样。
25. skill 目录被保留时，hc 目录里的普通文件只有和已装的模板相同才换成软链；和团队包里的相同而和已装的不同，保留并提示。
26. `--team` 指向已装目录升级：SKILL.md 和 README.md 更新，`team.md` 和 `templates/` 不动，再跑一次报 "up to date"。
27. `team.md` 的 frontmatter 没有闭合，或用了 Windows 换行：退出码 1。
28. 多出来的模板：`name` 与文件名不符、文件名超过 32 个字符、文件名带空白：各自退出码 1。
29. 直接改过装好的 `team.md` 或模板：报告写明它和团队包不一致、`--yes` 会覆盖、想保留就把 `--team` 指向装好的目录；指向装好的目录升级时，这些改动进入 SKILL.md。
30. 写入会删掉的旧模板和会断的 hc 软链，dry-run 也列出来。
31. skill 目录的位置上是普通文件：保留，不建链，`--yes` 也不动。位置是软链而目标里没有 SKILL.md 时，提示里不建议加 `--yes`。
32. `--with-skills` 和 `--with-cowork` 同用：两个 skill 各装各的。`--team ""` 不带 `--with-cowork`：退出码 2。
33. skill 的名字取自团队包的 `name`，和 `--team` 给的目录名无关：目录叫 backend、`name` 是 herdr-backend 时，装在 `~/.agents/skills/herdr-backend/`，agent 软链和 hc 软链都跟着这个名字。
34. 两个团队、两个前缀、两个名字：并排安装，互不影响。
35. `name` 不合规的几种：含空格，叫 `herdr-cowork`，超过 64 个字符，各自退出码 1；正好 64 个字符的通过。
36. 要装的位置上已经有一个不是团队 skill 的目录：退出码 1，零写入，`--yes` 也不覆盖；同一次运行里带了 `--with-skills`，收编的 skill 也不装。
37. 首条任务末尾那句写明了两个名字，`herdr-cowork` 和本 skill；拼合结果里不剩占位符。
38. 团队 skill 目录里有 `team.md` 但没有 SKILL.md：保留，不建链并说明原因；加 `--yes` 后补齐并建链。

真机抽验两条，不在脚本里：`hc templates` 能列出经软链安装的模板；`omp skill list` 能发现装好的 skill。
