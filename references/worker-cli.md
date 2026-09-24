# 工人 CLI：选谁、怎么驱动、哪些开关是真的

> 本文件是「网关形态 + 工人 CLI 契约 + 各 CLI 开关映射」的**唯一定义**；别处只引用，不复制清单。
>
> **出处纪律**：每条都带出处——**官方文档 URL** 或 **本机实测（版本 + 日期）**。文档没写的写「文档未载」，**不许凭记忆、类比或旧版本补齐**。
> **实测基线**：Ubuntu 24.04（WSL2）、2026-09-24；网关只开 OpenAI 兼容 `/v1/chat/completions`；模型 `global:deepseek-v4.1-flash`。版本与日期一起记：CLI 会改名、下线、改旗标语义。

## 0. 先探网关形态（它决定候选集）

网关支持哪种 wire API，直接决定哪些 CLI 能用。**派活之前先探**：

| 形态 | 谁只认它 | 探测（把 `<BASE>` 换成网关的 `/v1`） |
|---|---|---|
| `POST /chat/completions` | aider / crush / opencode / pi / omp 等多数 | `curl -s -o /dev/null -w "%{http_code}" <BASE>/chat/completions -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{"model":"…","messages":[{"role":"user","content":"hi"}]}'` |
| `POST /responses` | **Codex CLI ≥0.130 只认这个**（`wire_api="chat"` 已移除） | 同上换路径 |
| `POST /messages` | **Claude Code 只认这个** | 同上换路径 + `-H "anthropic-version: 2023-06-01"` |

实测（2026-09-24，一个只开 chat 的网关）：`chat=200 / responses=404 / messages=404` ⇒ **codex 与 claude-code 直接不可用**。

**缺哪种就加适配层，不要为此改契约**：

| 缺口 | 适配层 | 实测 |
|---|---|---|
| Responses → Chat | `talkcozy/api2codex`（单文件 FastAPI；`UPSTREAM_BASE_URL` / `UPSTREAM_API_KEY` / `PORT`） | ✅ 配上后 codex 0.156.1 端到端跑通 |
| Messages → Chat | `fuergaosi233/claude-code-proxy`（`OPENAI_BASE_URL` / `OPENAI_API_KEY` / `BIG_MODEL` / `MIDDLE_MODEL` / `SMALL_MODEL`） | ⚠ 直连 `/v1/messages` 200；但 Claude Code 2.1.281 会在 `messages` 里带 `system` 角色，需把 `src/models/claude.py` 的 `role: Literal["user","assistant"]` 改成三值。**打这一行补丁后端到端跑通** |
| 同上（备选） | `@musistudio/claude-code-router` 3.1.1 | ❌ 配置已迁到 SQLite（`~/.claude-code-router/config.sqlite`，只能用 UI 配）；`/v1/messages` 实测 405 ⇒ 不适合脚本化 |

## 1. 选工人：先问用户，不许默认

派第一个窗口之前，「用哪个 CLI + 哪个账号 + 网关是哪种形态」是一条**开放问题**，提给用户（形式见 `templates/freeze-plan.md` §6）。答案写进 `docs/freeze-plan.md`，**不要每片重问**。

| 问什么 | 不问的后果 |
|---|---|
| 用哪个 CLI / 哪个 provider 账号 | 额度与计费归属由我替他决定 |
| 该 CLI 在本机是否已登录、可用 | 首个窗口直接废掉，且现场看起来像"工人崩了" |
| 允许它自动批准工具调用吗 | 这是**权限变更**，不是效率开关 |
| 会话记录要不要留、留在哪 | 审计链断掉：越界读核对与验收归因都做不了 |
| 网关开的是哪种 wire API（见 §0） | 选完才发现要加适配层，或整条路走不通 |

**用户没回答就不开工**（沉默不是同意，见 `SKILL.md`「闸门」）。本次对话里用户已经指定过 CLI ⇒ 视为已答，写进冻结方案即可，不再问一遍。

## 2. 按难度 / 风险选**模型档位**

> 这里的"档位"指**模型强弱与思考深度**，与 `SKILL.md` 的 lite / heavy 不是一回事——那里定的是**流程重量**（文档密度与验收强度）。

选工人是三个维度，不是一个：**哪个 CLI · 哪个模型或思考档 · 独立窗口还是同进程子代理**。

| 任务性质 | 形态 | 档位 |
|---|---|---|
| 机械批量（改名、搬文件、抄数据、数据收集） | 子代理 | 最小 / 最快档 |
| 探索未知代码范围 | 子代理（只读） | 快档 |
| 照契约实现常规切片 | 独立窗口 | 默认档 |
| 高风险（数据正确性 / 并发 / 迁移 / 安全） | 独立窗口 + **我自己写反例** | 最强档 + 高思考 |
| 写规格 / 架构决策 / 最终验收 | **我自己，不派** | 最强档 |
| 对抗审查（独立读者） | 独立窗口 | 最强档 |

判据：派独立窗口的固定开销（读工人合同 + 契约 + 本轮指令 + 上一窗口交接）与任务的**规格含量**成正比——规格含量低的任务用子代理，不为它付那份开销。

档位落到哪个开关上按 CLI 不同，见 §4 各节「档位」行；CLI 没有独立档位概念时，档位就落在模型名上。**优先用 CLI 自带的难度路由**（omp 的 `--smol` / `--slow` / `--plan`、Claude Code 的 `--effort`、Gemini 的 `plan.modelRouting`），不要自己拼。

## 3. 工人 CLI 契约（10 条语义）

判据：**这些是「工人必须做得到」的事，不是「某个 CLI 的开关名」。** 责任方不在 CLI 的，由驱动器补——所以换 CLI 时先看这张表，再看 §4 的「缺口」行。

| # | 语义 | 责任方 | 怎么验它成立 |
|---|---|---|---|
| C1 | **非交互单轮**：给一段提示词就跑完并退出 | CLI | 无 TTY 下跑一次，进程自行退出 |
| C2 | **可续接同一会话**：续轮时不必重讲上下文 | CLI | 第二次调用能看到第一次的产物 |
| C3 | **工作目录可指定** | CLI 或驱动器 | 产物落在指定目录，而不是调用者的 cwd |
| C4 | **自动批准工具调用**：无 TTY 下不因审批挂住 | CLI | 不给 stdin 跑一次，看它是否卡在审批提示 |
| C5 | **有运行上限** | CLI 或驱动器 | 超过上限后进程自己结束 |
| C6 | **结局写进文件** | 驱动器 | 流水末尾必须有 `EXIT=<code> DURATION=<n>s`；**要求 CLI 的退出码可信** |
| C7 | **收到信号时终止工人** | 驱动器 | 发 TERM 后工人进程消失 |
| C8 | **兜底交接能落进 `handoffs/<W>.md`** | 驱动器 | 上下文将满时的落盘物能被搬到约定位置 |
| C9 | **上下文将满时自动落盘交接** | CLI | 长会话跑到压缩阈值，看有没有产出交接文档 |
| C10 | **越界读判据能从工具调用取证** | CLI | 会话记录里能读到"这一轮读了哪些路径"（判据见 `references/gates.md`「记录系统」） |

> **权限边界不在本契约里。** 没有哪个 CLI 的开关能替我隔离记录目录——`--add-dir` 类开关只增不限（Claude Code 文档原文是 *Grant additional directories*；omp 原文是 *Add a workspace directory beyond the working directory*）。见 `references/gates.md`「记录系统」。

## 4. 各 CLI 的开关映射

把选定 CLI 的那一列填进驱动器调用行；**本仓库哪些位置写死了 omp 形态**，见 `VALIDATION.md`「换工具 / 换语言时要改什么」。
「实测」行给的是**我跑过的命令与结果**；没跑过的写「未实测」。

### omp — 实测通过（18.3.0，npm `@oh-my-pi/pi-coding-agent`，需 bun）

| 语义 | 形态 |
|---|---|
| C1 | `-p` / `--print`；提示词作位置参数；`--mode=text\|json\|rpc\|rpc-ui` |
| C2 | `-c` / `--continue`；`-r` / `--resume=<id 前缀 \| 路径>`；`--no-session` 可关落盘 |
| C3 | `--cwd=<value>` |
| C4 | `--auto-approve`；`--approval-mode=always-ask\|write\|yolo` |
| C5 | `--max-time=<value>`（`600` / `10m` / `1h`） |
| C6 / C7 | 驱动器 |
| C8 | 驱动器 `cp` |
| C9 | `--config` 叠加层：`compaction.methodOrder: [handoff, shake, soft]` + `handoffSaveToDisk: true`；落点 `.sessions/<W>/<session-id>/handoff-<ISO>.md` |
| C10 | 会话 `.jsonl`（`--session-dir` 指定目录），事件 `tool_execution_start.args`；实测落点 `~/.omp/agent/sessions/<项目>/` |
| 档位 | `--smol` / `--slow` / `--plan` / `--model` / `--thinking`；`--prewalk`、`--plan-yolo` |
| 工具面 | `--tools=<list>` / `--no-tools` / `--no-lsp` / `--no-skills` |
| 接自建网关 | `~/.omp/agent/models.json`：`providers.<name>.{baseUrl, api: "openai-completions", apiKey, models[].id}` |
| 实测 | `omp -p --model wb/global:deepseek-v4.1-flash "reply with exactly: OK"` → `OK`，rc=0 |
| 缺口 | 无（本仓库的驱动器就是为它写的） |

### pi — 实测通过（0.87.1，npm `@earendil-works/pi-coding-agent`）

| 语义 | 形态 |
|---|---|
| C1 | `-p` / `--print`；提示词作位置参数（以 `-` 开头时用 `--` 隔开）；`--mode=text\|json\|rpc` |
| C2 | `-c` / `--continue`；`-r` / `--resume`；`--session <路径 \| id>`；`--session-id <id>`；`--fork` |
| C3 | **缺口**：无 `--cwd` ⇒ 调用方 `cd` |
| C4 | `-a` / `--approve` 的语义是**信任项目本地文件**（AGENTS.md 等），**不是**跳过审批——两者不要混；非交互下是否弹审批：未实测 |
| C5 | **缺口**：无超时开关 ⇒ 驱动器 `timeout` |
| C6 / C7 | 驱动器 |
| C8 | 驱动器搬运；会话落点由 `--session-dir` 或 `PI_CODING_AGENT_SESSION_DIR` 决定 |
| C9 | 未找到 compaction / handoff 开关（`--extension` 能否提供：未实测） |
| C10 | 会话 `session.jsonl`；实测落点 `~/.pi/agent/sessions/<项目>/` |
| 档位 | `--model <provider/id>`（支持 `:<thinking>` 简写）、`--thinking=off…max`、`--provider` |
| 工具面 | `-t` / `--tools`、`-xt` / `--exclude-tools`、`-nt` / `--no-tools` |
| 接自建网关 | 同 omp：`~/.pi/agent/models.json`（官方文档 *Configure a compatible endpoint*） |
| 实测 | `pi -p --model wb/global:deepseek-v4.1-flash "reply with exactly: OK"` → `OK`，rc=0 |
| 坑 | **与 omp 抢 `pi` 这个 bin 名**：装 omp 会把 `pi` 覆盖掉 ⇒ 装到独立 prefix（`npm i -g --prefix ~/.local/pi-prefix …`） |

### opencode — 实测通过（1.18.32，npm `opencode-ai`）

| 语义 | 形态 |
|---|---|
| C1 | 子命令 `opencode run [message..]`；`--command`、`--file/-f`。**顶层 `opencode` 是 TUI**，不要用它当工人 |
| C2 | `-c` / `--continue`；`-s` / `--session <id>`；`--fork` |
| C3 | `run` 的旗标表未列工作目录；`attach` 有 `--dir` ⇒ `run` 侧按「文档未载」处理 |
| C4 | TUI 旗标表有 `--auto`（原文：*auto-approve permissions that are not explicitly denied*）；**`run` 的子旗标表里没有它** ⇒ 是否可传：文档未载（本次未用到审批场景） |
| C5 | 文档未载 ⇒ 驱动器 `timeout` |
| C6 / C7 | 驱动器 |
| C8 / C9 | 文档未载 |
| C10 | **记录在 SQLite**（实测 `~/.local/share/opencode/opencode.db`，表：`session` / `message` / `part` / `event` / `permission` / `todo` / `project` …）⇒ 越界读判据要写 SQL 查 `part` / `event.data`，**不是读 jsonl**；另有 `opencode export [sessionID]` |
| 档位 | `-m` / `--model <provider/model>`；`--agent <name>`（`opencode agent create --mode all\|primary\|subagent`） |
| 接自建网关 | `~/.config/opencode/opencode.json`：`provider.<name>.{npm: "@ai-sdk/openai-compatible", options: {baseURL, apiKey}, models}` + `model: "<name>/<model-id>"` |
| 常驻 | `opencode serve` + `opencode run --attach http://localhost:4096`（官方给的理由是免去每次冷启 MCP） |
| 实测 | `opencode run "reply with exactly: OK"` → `OK`，rc=0 |
| 坑 | 短旗标冲突：`opencode attach -p` 是**basic auth password**，不是 print |

### Claude Code — 实测通过（2.1.281，官方安装器；**需 Messages→Chat 适配层**）

| 语义 | 形态 |
|---|---|
| C1 | `claude -p "query"`；支持管道输入 `cat file \| claude -p "query"`；`--output-format=text\|json\|stream-json`、`--input-format` |
| C2 | `-c` / `--continue`；`-r` / `--resume <id \| name \| 会话 .jsonl 绝对路径>`；`--session-id <uuid>`；`--fork-session` |
| C3 | 无 `--cwd`；靠调用方 `cd`。另有 `--add-dir`、`--worktree/-w` |
| C4 | `--permission-mode=default\|acceptEdits\|plan\|auto\|dontAsk\|bypassPermissions\|manual`；`--dangerously-skip-permissions` ≡ `bypassPermissions`；**无人值守**用 `--permission-prompts none`（无人应答时直接拒绝，而不是挂住）；细粒度 `--allowedTools` / `--disallowedTools` |
| C5 | `--max-turns <n>`、`--max-budget-usd <n>`（都是 print 模式）。**墙上时钟超时：文档未载** |
| C6 / C7 | 驱动器 |
| C8 | 驱动器搬运 |
| C9 | `--autocompact <auto\|tokens>` 可设自动压缩窗口；压缩有钩子事件（`PreCompact` / `PostCompact`）⇒ 自动落盘交接要靠钩子实现 |
| C10 | transcript 是 `.jsonl`；实测落点 `~/.claude/projects/<项目 slug>/<session-uuid>.jsonl`（记录形如 `{"type":"queue-operation",…}`）；`--resume` 可直接接 `.jsonl` 路径 |
| 档位 | `--model <alias\|全名>`、`--effort=low\|medium\|high\|xhigh\|max\|ultracode`、`--fallback-model` |
| 其他 | `--bare`（跳过 hooks / skills / 插件 / MCP / CLAUDE.md 发现）、`--settings <file\|json>`、`--tools`、`--no-session-persistence` |
| 接自建网关 | **网关必须有 `/v1/messages`**：`ANTHROPIC_BASE_URL=<适配层> ANTHROPIC_API_KEY=<任意值> claude -p "…"`（直连只开 chat 的网关 = 404） |
| 实测 | 经补丁版 claude-code-proxy：`claude -p "reply with exactly: OK"` → `OK`，rc=0 |
| 坑 | 官方文档明说 **`claude --help` 不列全部旗标**（原文：*`claude --help` does not list every flag*）⇒ 只靠 `--help` 会漏。另有 `--restricted`：把文件工具限制在工作目录内、拒绝 `bypassPermissions`——**与「自动批准」是两件事** |

### Codex CLI — 实测通过（0.156.1，官方安装器；**需 Responses→Chat 适配层**）

| 语义 | 形态 |
|---|---|
| C1 | `codex exec`（别名 `codex e`）；提示词作参数或从 stdin 读（`-`）；`--json` 得逐行 JSON 事件。**官方原文用途**：*scripted or CI-style runs that should finish without human interaction* |
| C2 | `codex exec resume --last`（当前工作目录最近一次）/ `--all`（跨全部会话）；另有 `codex exec fork` |
| C3 | 全局旗标表有 `--add-dir`（给主工作区之外追加写权限目录）；`exec` 的工作目录由调用方 `cd` 决定 |
| C4 | **审批与沙箱是两个概念**：`--ask-for-approval, -a`（取值示例 `on-request`）与 `--sandbox`（如 `workspace-write`）。实测 `codex exec` 默认 `approval: never` + `sandbox: read-only`（输出里直接打印） |
| C5 | 文档未载 ⇒ 驱动器 `timeout` |
| C6 / C7 | 驱动器 |
| C8 / C9 | 文档未载 |
| C10 | 会话 rollout `.jsonl`；实测落点 `~/.codex/sessions/<YYYY>/<MM>/<DD>/rollout-<ISO>-<uuid>.jsonl`，首行 `session_meta` 含 `session_id` / `cwd` / `runtime_workspace_roots` / `cli_version` / `originator` |
| 档位 | `-m` / `--model`；`-c key=value` 覆盖 `~/.codex/config.toml`；`--profile`、`--oss`、`--enable/--disable <FEATURE>`、`--strict-config` |
| 其他 | `codex exec review`（非交互代码审查）、`codex login status`（凭据存在时退出码 0，便于脚本判定）、`codex app-server` |
| 接自建网关 | 只认 Responses：`~/.codex/config.toml` → `model_provider` + `[model_providers.<名>] base_url/env_key/wire_api="responses"`；网关没有 `/v1/responses` 就必须前置 `api2codex` |
| 实测 | 经 api2codex：`codex exec --skip-git-repo-check "reply with exactly: OK"` → `OK`，rc=0；`codex exec resume --last "…"` → 返回新结果（C2 成立） |
| 坑 | 1) **`wire_api = "chat"` 在 0.156.1 已被移除**（报错原文：*`wire_api = "chat"` is no longer supported*）⇒ 旧文章里"用 chat 就行"的说法已过期。2) 无 bubblewrap 时会警告并改用内置 bwrap。3) 模型元数据缺失时会警告 `Model metadata … not found`（可放 `~/.codex/model_catalog.json`） |

### Gemini CLI — 装得上，但**接不了只开 chat 的网关**（0.61.0，npm `@google/gemini-cli`）

| 语义 | 形态 |
|---|---|
| C1 | `gemini -p "…"`；`-o` / `--output-format=text\|json\|stream-json` |
| C2 | `-r` / `--resume latest\|<序号>`；`--session-id <uuid>`；`--session-file <json>`；`--list-sessions` |
| C3 | `--include-directories`（追加工作目录）；**独立 `--cwd` 开关：文档未载** |
| C4 | `-y` / `--yolo`（= 全自动批准，只能从命令行开）；`--approval-mode=default\|auto_edit\|yolo\|plan`；`--skip-trust` |
| C5 | 文档未载 ⇒ 驱动器 `timeout` |
| C6 / C7 | 驱动器 |
| C8 / C9 | 文档未载 |
| C10 | 文档未载（会话在 `~/.gemini/`，本次未取到） |
| 档位 | `-m` / `--model`；设置项 `general.plan.modelRouting`（规划用 Pro、实现用 Flash） |
| 接自建网关 | **未找到入口**：`--help` 无 provider / base-url / OpenAI 兼容开关，`bundle` 里也搜不到 openai 兼容相关串 ⇒ 只开 `/v1/chat/completions` 的网关下**不可用**（要么给它 Gemini 形态的端点，要么加适配层） |
| 实测 | 仅验证安装与 `--help`（0.61.0）；端到端**未跑通** |
| 坑 | 官方站点公告：*Gemini CLI was replaced by Antigravity CLI on June 18th, 2026*（未付费 / Google One 用户）⇒ 选它之前先确认账号形态 |

### aider — 实测通过（0.86.2，`uv tool install aider-chat`）

| 语义 | 形态 |
|---|---|
| C1 | `aider --message "…" file1 file2`（`-m` / `--msg` / `--message`）；`--message-file / -f`；也可用 Python API（官方声明**不受支持、可能随时变**） |
| C2 | 文档未载（Python API 里连续 `coder.run(...)` 可接着上一次） |
| C3 | 文档未载（按调用方 `cd` 处理） |
| C4 | `--yes`（对每个确认一律同意） |
| C5 | 文档未载 ⇒ 驱动器 `timeout` |
| C6 / C7 | 驱动器 |
| C8 / C9 | 文档未载 |
| C10 | **记录是 Markdown，不是 jsonl**：实测仓库内 `.aider.chat.history.md` + `.aider.input.history`（另有 `.aider.tags.cache.v4/cache.db`） |
| 档位 | 文档未载（见 options 参考页） |
| 接自建网关 | `OPENAI_API_BASE=<网关>/v1` + `OPENAI_API_KEY` + `--model openai/<model-id>` |
| 其他 | `--dry-run`（不改文件）、`--commit`（提交全部待提交改动后退出）、`--stream / --no-stream` |
| 实测 | `aider --model openai/global:deepseek-v4.1-flash --message "reply with exactly: OK" --yes --no-auto-commits --no-stream hello.py` → `OK`，rc=0 |
| 坑 | **`--auto-commits` 默认为 `True`**：工人会自动提交它改的东西——与「代码与文档分开提交」「显式列出路径」冲突，用它当工人时必须显式 `--no-auto-commits` |

### crush — 实测通过（v0.96.1，npm `@charmland/crush`）

| 语义 | 形态 |
|---|---|
| C1 | `crush run -q "<提示词>"`（`run` 非交互、`-q` 静默） |
| C2 | 文档未载 |
| C3 | 文档未载（按调用方 `cd` 处理） |
| C4 | 配置里 `permissions allow …`（`crushrc` 内置命令）；`--yolo` 一类开关：文档未载 |
| C5 | 文档未载 ⇒ 驱动器 `timeout` |
| C6 / C7 | 驱动器 |
| C8 / C9 | 文档未载 |
| C10 | 文档未载（本次未取） |
| 档位 | 配置 `models.large` / `models.small`（实测用同一模型填两处） |
| 接自建网关 | `~/.config/crush/crush.json`：`providers.<id>.{type: "openai", base_url, api_key, models[]}` + `models.large/small.{provider, model}` |
| 实测 | `crush run -q "reply with exactly: OK"` → `OK`，rc=0 |
| 坑 | 配置是 `crushrc`（Bash + 内置命令）与 JSON 两套并存，改错文件不报错、静默不生效——改完先跑一次确认 |

### cline — 实测通过（3.0.65，npm `cline`）

| 语义 | 形态 |
|---|---|
| C1 | `cline "<提示词>"`（**默认 act 模式且自动批准已开**）；`-p` / `--plan` 只读规划；`--json` 结构化输出 |
| C2 | 文档未载 |
| C3 | `-c` / `--cwd <path>` |
| C4 | `--auto-approve <true\|false>`（默认 `true`） |
| C5 | 文档未载 ⇒ 驱动器 `timeout` |
| C6 / C7 | 驱动器 |
| C8 / C9 | `--compaction agentic\|basic\|off`（默认 `agentic`） |
| C10 | **SQLite**：`~/.cline/data/db/sessions.db`（另有 `tasks.db` / `connectors.db`） |
| 档位 | `--thinking none\|low\|medium\|high\|xhigh` |
| 接自建网关 | `cline auth openai -k <key> -m <model-id> -b <网关>/v1`（落到 `~/.cline/data/settings/providers.json`）；要隔离状态用 `--data-dir` |
| 实测 | `cline "reply with exactly: OK"` → `OK`，rc=0 |
| 坑 | 默认 act + 自动批准 ⇒ 直接当工人等于放开写入；stdout 会被 AI SDK 弃用警告污染（要干净输出用 `--json` 或只取 stdout） |

### qwen-code — 实测通过（0.24.4，npm `@qwen-code/qwen-code`）

| 语义 | 形态 |
|---|---|
| C1 | `qwen -m <model> "<提示词>"`（`-p/--prompt` 仍在但已标 deprecated）；**非交互必须先选 auth type** |
| C2 | 帮助文本提到 `--continue` / `--resume`（`--chat-recording=false` 会让它们失效）；未实测 |
| C3 | `--include-directories` / `--add-dir` |
| C4 | `-y` / `--yolo`；`--approval-mode plan\|default\|auto-edit\|auto\|yolo` |
| C5 | 文档未载 ⇒ 驱动器 `timeout` |
| C6 / C7 | 驱动器 |
| C8 / C9 | 文档未载 |
| C10 | `~/.qwen/projects/<项目 slug>/chats/<session-uuid>.jsonl`（记录含 `uuid` / `parentUuid` / `sessionId` / `cwd`）；另有 `~/.qwen/usage_record.jsonl` |
| 档位 | `-m` / `--model`；`--fallback-model` |
| 接自建网关 | `OPENAI_API_KEY` + `OPENAI_BASE_URL=<网关>/v1` + **`--auth-type openai`**（缺 auth type 直接拒绝非交互运行） |
| 实测 | `OPENAI_BASE_URL=<网关>/v1 qwen --auth-type openai -m global:deepseek-v4.1-flash -p "reply with exactly: OK"` → `OK` |
| 坑 | 自带 vendored ripgrep 可能没有执行位（报 `EACCES` 并降级内置 grep）⇒ `chmod +x …/vendor/ripgrep/x64-linux/rg` |

### goose — 实测通过（1.52.0，官方安装脚本）

| 语义 | 形态 |
|---|---|
| C1 | `goose run -t "<文本>"`（或 `-i <文件>`）；`goose session` 是交互模式 |
| C2 | 文档未载（`goose session` 侧有 resume） |
| C3 | 文档未载（按调用方 `cd` 处理） |
| C4 | 文档未载（在 `goose configure` 里配） |
| C5 | 文档未载 ⇒ 驱动器 `timeout` |
| C6 / C7 | 驱动器 |
| C8 / C9 | 文档未载 |
| C10 | **SQLite**：`~/.local/share/goose/sessions/sessions.db` |
| 档位 | 配置里选 provider / model |
| 接自建网关 | 环境变量：`GOOSE_PROVIDER=openai GOOSE_MODEL=<model-id> OPENAI_HOST=<网关根，**不含** /v1> OPENAI_API_KEY=<key>` |
| 实测 | 上述四变量 + `goose run -t "reply with exactly: OK"` → `OK`，rc=0 |
| 坑 | 官方安装脚本依赖 `bzip2` 解 `.tar.bz2`；无 root 装不了 bzip2 时用 Python 的 `tarfile` + `bz2` 自己解包到 `~/.local/bin`（本次即如此） |

### droid — 装得上，但**要 Factory 账号**（0.226.2，官方安装脚本）

| 语义 | 形态 |
|---|---|
| C1 | `droid exec --auto low\|medium\|high [-m <模型>] "<提示词>"`；`--skip-permissions-unsafe` 关掉全部权限检查；`-o/--output-format`、`--input-format stream-json` |
| C3 | `--cwd <path>`；`-w/--worktree` |
| C2 | `-r/--resume [sessionId]`、`--last`、`--fork <id>` |
| 档位 | `-m/--model`、`-r/--reasoning-effort` |
| 接自建网关 | `~/.factory/config.json` 的 `custom_models[]`（`model_display_name` / `model` / `base_url` / `api_key` / `provider`）**能被加载**，模型 id 形如 `custom:<slug>-<n>` |
| 实测 | **未跑通**：自定义模型已列出，但 `droid exec` 日志 `No authentication credentials available (storage empty, no API key)`，进程挂到超时 ⇒ 即使给了自定义模型，仍要 Factory 凭据 |
| 判据 | **先确认用户有没有该 SaaS 账号**，再把它列入候选 |

### amp — 装得上，但**是 SaaS 登录墙**（0.0.179…，npm `@sourcegraph/amp`）

- `amp -x "<提示词>"` 需先 `amp login`；实测直接进浏览器登录流程并打印 `https://ampcode.com/auth/cli-login?...` 后停在"粘贴验证码"
- **接不了自建网关**：没有 base-url / provider 开关，凭据由 Amp 账号签发（只有 `--settings-file`）

### reasonix — 实测通过（1.38.12，npm `reasonix`，Go 单二进制）

| 语义 | 形态 |
|---|---|
| C1 | `reasonix run "<任务>"`（一次性，流式到 stdout）；`reasonix -p/--print "<任务>"`；`--output-format text\|json\|stream-json`；`--max-steps N` |
| C2 | `-c` / `--continue`；`-r` / `--resume [QUERY]`；`reasonix run --resume <路径>` |
| C3 | `--add-dir <PATH>`（文件工具默认锁在启动目录） |
| C4 | `--permission-mode MODE`；配置里 `[permissions] mode = ask\|allow\|deny` + `deny/allow/ask` 规则 |
| C5 | 文档未载（有 `--max-steps` 是**步数**上限）⇒ 墙上时钟仍靠驱动器 `timeout` |
| C6 / C7 | 驱动器 |
| C8 / C9 | `[agent] compact_ratio`（默认 0.8）触发自动压缩；交接落盘机制：未找到 |
| C10 | `reasonix session list --json` / `session show <id> --json`（机器可读）；权威会话在 `~/.reasonix/sessions/`，本次 one-shot 未落盘 |
| 档位 | `--model NAME`、`--effort LEVEL`；`[agent] planner_model`（双模型：执行 + 规划）、`subagent_model` |
| 接自建网关 | `~/.reasonix/config.toml`：`[[providers]]` 数组，`name` / `kind = "openai"` / `base_url` / `models[]` / `default` / `api_key_env`；**密钥写在 `~/.reasonix/.env`**（`api_key_env` 只存变量名） |
| 实测 | `reasonix run "reply with exactly: OK"` → `OK`，rc=0；`reasonix doctor` 显示 provider `wb … key:present` |
| 坑 | 默认要 **shell 沙箱**：无 bubblewrap 时直接拒绝执行 bash（警告原文 *refusing to run unconfined*）⇒ 要么装 `bwrap`，要么显式选 Full access 权限模式。另外 npm 上的 README 是**旧 TS 线**（0.x，maintenance），现行是 Go 重写（`main-v2`）——文档要看对分支 |

### codewhale — 实测通过（0.10.0，npm `codewhale`，Rust）

| 语义 | 形态 |
|---|---|
| C1 | `codewhale exec "<提示词>"`（非交互）；`--auto` 开工具+自动批准；`--json` 摘要；`--output-format text\|stream-json` |
| C2 | `--resume <SESSION_ID>` / `--session-id <id>` / `--continue`；另有 `codewhale resume` / `fork` |
| C3 | 文档未载（按调用方 `cd`；工作目录由 workspace 决定） |
| C4 | `--auto`（工具模式 + 自动批准）；`--skip-permissions-unsafe` 一类见 `droid` 对照，codewhale 侧为 `auth`/权限配置 |
| C5 | 文档未载 ⇒ 驱动器 `timeout` |
| C6 / C7 | 驱动器 |
| C8 / C9 | 文档未载 |
| C10 | `codewhale sessions`（列会话）；记录目录 `~/.codewhale/sessions/`（另有 `~/.codewhale/logs/`） |
| 档位 | `CODEWHALE_MODEL` / `[providers.<t>].model`；`codewhale models --provider <id>` 刷新目录 |
| 接自建网关 | `~/.codewhale/config.toml`：`provider = "openai"` + `[providers.openai] base_url / model / api_key`（或 `OPENAI_BASE_URL` + `OPENAI_MODEL`）；`codewhale config doctor` 可校验 |
| 实测 | `DEEPSEEK_ALLOW_INSECURE_HTTP=1 codewhale exec --auto "reply with exactly: OK"` → `OK`，rc=0；`codewhale config doctor` → *credentials and endpoints clean* |
| 坑 | **非 loopback 的 `http://` base_url 会被拒**（官方原文：*Non-local `http://` base URLs are rejected unless `DEEPSEEK_ALLOW_INSECURE_HTTP=1`*）——自建网关常用内网 IP，这一条不设就是连不上 |

### 未列的 CLI

`cursor-agent` / `kilo` / `openhands` / `plandex` / `codebuff` 等不在本节：本次没装过，或官方文档没查到入口。要加一个，走 §6 的流程，不要凭印象补一行。

**判据（本次归纳）**——候选先分两类，②类必须先问用户有没有账号：

| 类 | 判据 | 已实测的成员 |
|---|---|---|
| ① **能指向自建网关** | 有 provider / base-url / OpenAI 兼容配置入口 | aider · crush · opencode · pi · omp · cline · qwen-code · goose · codewhale · reasonix |
| ② **SaaS 绑定，只认自家账号** | 登录流程换不出可替换的凭据；没有 base-url 开关 | amp · droid；以及只认自家 wire API 的 gemini-cli（Gemini API）、codex（Responses）、claude-code（Messages）——后三者**加适配层**后可归入① |

## 5. 装工人 CLI 的环境前提（Linux / WSL2，无 root）

判据：**没有 root 也能装**——全部走用户级路径，不要为了装 CLI 去要 sudo。

| 缺什么 | 用户级装法 |
|---|---|
| node（多数 CLI 的底座） | 官方 tarball 解到 `~/.local/node`（`tar -xzf` 即可，无需 unzip），再 `export PATH=$HOME/.local/node/bin:$PATH` |
| bun（omp 的 bin 是 bun 脚本） | `npm i -g bun` |
| Python 包（api2codex / aider / 适配层） | `uv`（从 GitHub release 取静态二进制）；Ubuntu 自带 python3 **没有 pip、`ensurepip` 也缺**，别指望 `python3 -m venv` |

**网络与地址（WSL2 特有，踩过）**：

- **WSL 里的 `127.0.0.1` 到不了宿主**：宿主的网关与代理都要用宿主 IP（NAT 网关地址：`ip route | awk '/^default/{print $3}'`，实测 `172.18.240.1`）。同一台宿主上的 `http://127.0.0.1:7863` 在 WSL 里是 000，换宿主 IP 就是 200。
- 宿主有出网代理（如 `127.0.0.1:7897`）时，WSL 里写 `http_proxy=http://<宿主IP>:7897`。但**能直连就别挂代理**：挂错代理会出现 `curl: (35) SSL_ERROR_SYSCALL`。
- 个别站点在 HTTP/2 下直接失败（`000`），加 `--http1.1` 即可（实测：`chatgpt.com/codex/install.sh`、`opencode.ai/install`）。
- **自建网关多是内网 IP + `http://`**：有的 CLI 直接拒（codewhale 需 `DEEPSEEK_ALLOW_INSECURE_HTTP=1`），有的不拒（aider / opencode / pi / omp / cline / goose / reasonix 实测都直接吃）。选 CLI 时先确认这一条——不设的现象是"连不上"，而不是"配置写错了"。

**安装器（三家都踩过）**：

- **无 TTY 会挂**：安装器在等 stdin 时不会超时（实测 codex 安装器装完后仍挂着不退出）⇒ 一律 `</dev/null`，必要时设该安装器的非交互环境变量。
- **看清 shebang**：Claude Code 的安装器是 **bash** 脚本，用 `sh` 跑会报 `Syntax error: "(" unexpected`。
- **bin 名会互相覆盖**：`@oh-my-pi/pi-coding-agent`（omp）与 `@earendil-works/pi-coding-agent`（pi）都提供 `pi` ⇒ 至少一个装到独立 prefix。
- 装完立刻冒烟（C1 一条命令），**别等到派活那天才发现它起不来**。

**无 root 时的绕法（本次新得）**：

- 安装脚本要 `bzip2` / `unzip` 而没有时，用 Python 标准库自己解，再把二进制拷进 `~/.local/bin`：
  `python3 -c "import tarfile; tarfile.open('/tmp/x.tar.bz2','r:bz2').extractall('/tmp/x')"`（goose 即如此装上）。
- **落点**：二进制安装器（codex / claude / droid / opencode / goose）都落 `~/.local/bin`；npm 装的 CLI 落 node 的 bin 目录（`$HOME/.local/node/bin`）。
- **npm 包里可能带没有执行位的 vendored 二进制**（qwen 的 ripgrep 报 `EACCES`）⇒ `chmod +x` 一下，别让它静默降级。
- **装成功 ≠ 能用**：SaaS 绑定的 CLI（amp / droid）装完仍卡在登录/凭据上——先确认账号，再列入候选。

## 6. 新增一个 CLI 的取证流程

**先取证再写进来**，顺序不许颠倒（凭项目简介、旧记忆或类比断言工具能力，是本 skill 里唯一导致过返工的缺陷类型，见 `references/gates.md`「规格自检」第四问）。

1. 先探**网关形态**（§0）——它决定这个 CLI 要不要适配层。
2. 找**官方文档**（站点 / 官方仓库 README / 包内 `docs/`），逐条记 URL。
3. 按下面 12 项填；填不出的写「文档未载」，**不要用类比补齐**。能装上就**跑一遍 §3 的 C1–C10**，把命令与真实输出记进「实测」行。
4. 写进 §4 时带上**版本 + 查阅日期**——CLI 会改名、下线、改旗标语义（Codex 移除 `wire_api="chat"`、Gemini CLI 被 Antigravity CLI 取代都是实例）。
5. 跑不通的写进未验证清单；**不许把"文档说有"当成"我验过"**。

| # | 项 |
|---|---|
| 1 | 非交互单轮调用：完整命令行示例（提示词怎么传：位置参数 / `--prompt` / stdin） |
| 2 | 续接同一会话：继续最近一次；指定某个会话 id |
| 3 | 指定工作目录（无 ⇒ 写「靠调用方 cd」） |
| 4 | 自动批准工具调用：开关名。**必须与「放宽沙箱 / 信任项目本地文件 / 限制文件工具范围」区分开**——这四个是不同的东西 |
| 5 | 运行上限 / 超时（无 ⇒ 写「靠驱动器 `timeout`」） |
| 6 | 输出模式：是否支持结构化输出（text / json / stream-json / rpc） |
| 7 | 会话记录落盘位置与格式（jsonl / sqlite / DB / markdown） |
| 8 | 能否从记录里读到「这一轮调用了哪些工具、参数是什么」（C10 的判据） |
| 9 | 上下文将满时的自动压缩 / 交接钩子（无 ⇒ 写「无」） |
| 10 | 配置叠加 / 环境变量：能否为单次运行指定额外配置；**如何指向自建网关** |
| 11 | 退出码语义：正常结束 / 出错 / 被中断 |
| 12 | 模型 / 思考档开关（用于 §2 的选档） |
