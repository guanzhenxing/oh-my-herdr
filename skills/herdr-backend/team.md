---
name: herdr-backend
prefix: backend
---

## 团队配置

以下是本团队的配置。通用协议里说"团队配置"的地方，都指这里。

### 角色与模板

| 角色 | 模板 | tab 名 | 默认 harness 与模型 |
|---|---|---|---|
| 架构 | backend-arch | 架构 | claude，用它的默认模型 |
| 开发 | backend-dev | 开发 | claude，用它的默认模型 |
| 评审 | backend-review | 评审 | codex，用它的默认模型 |
| 测试 | backend-test | 测试 | omp，用它的默认模型 |
| 执行 | backend-run | 执行 | omp，用它的默认模型 |

默认命令唯一存在模板 frontmatter，本表只是索引。成员的启动命令只取模板，不另加参数。

### 命名前缀

模板文件名的前缀是 `backend`：模板是 backend-<键>.md。成员名不带前缀，是 <键>-<短名>，评审是 review-<短名>-<类型>-r<N>，短名不超过 10 个字符。

### 工作区

只在 $HOME/code/ 下的仓动手。这是示例值，安装前改成你的工作区。
仓别名：demo→$HOME/code/demo。这是示例，安装前照你的仓改。
"当前仓"=Commander 会话的 cwd。说了别名或当前仓直接用；不在工作区内的仓，先问用户。

### 路径

评审暂存目录：~/.cache/herdr-teams/herdr-backend/review/
产物目录：仓内 docs/ 下的 design、adr、review、test。
