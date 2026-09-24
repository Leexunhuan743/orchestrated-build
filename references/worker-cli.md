# 工人 CLI：选谁、怎么驱动、哪些开关是真的

> 本文件是「工人 CLI 契约 + 各 CLI 开关映射」的**唯一定义**；别处只引用，不复制清单。
>
> **出处纪律**：本文件每一条开关都必须能追溯到**官方文档**（URL 见各节「出处」行）。**文档没写的写「文档未载」，不许凭记忆、类比或旧版本补齐**；`--help` 是**落地前的复核动作**，不作为本文件的证据——本机装的是哪个版本，别人的机器未必一样。
> 每条同时记下**查阅日期**：官方文档会过期（CLI 会改名、下线、改旗标语义）。

## 1. 选工人：先问用户，不许默认

派第一个窗口之前，「用哪个 CLI + 哪个账号」是一条**开放问题**，提给用户（形式见 `templates/freeze-plan.md` §6）。答案写进 `docs/freeze-plan.md`，**不要每片重问**。

| 问什么 | 不问的后果 |
|---|---|
| 用哪个 CLI / 哪个 provider 账号 | 额度与计费归属由我替他决定 |
| 该 CLI 在本机是否已登录、可用 | 首个窗口直接废掉，且现场看起来像"工人崩了" |
| 允许它自动批准工具调用吗 | 这是**权限变更**，不是效率开关 |
| 会话记录要不要留、留在哪 | 审计链断掉：越界读核对与验收归因都做不了 |

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

档位落到哪个开关上按 CLI 不同，见 §4 各节「档位」行；CLI 没有独立档位概念时，档位就落在模型名上。**优先用 CLI 自带的难度路由**（见 §4 里 Gemini 的 `general.plan.modelRouting`、omp 的 `--smol` / `--slow` / `--plan`、Claude Code 的 `--effort`），不要自己拼。

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

### omp

**出处**：官方文档 <https://omp.sh/docs/cli>（站点前端渲染，正文抓取不到）；本节以**本仓库驱动器** `scripts/run-window.sh` 为准——它是本 skill 的一部分，不是对本机安装的探测。

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
| C10 | 会话 `.jsonl`（`--session-dir` 指定目录），事件 `tool_execution_start.args` |
| 档位 | `--smol` / `--slow` / `--plan` / `--model` / `--thinking`；`--prewalk`、`--plan-yolo` |
| 工具面 | `--tools=<list>` / `--no-tools` / `--no-lsp` / `--no-skills` |
| 缺口 | 无（本仓库的驱动器就是为它写的） |

### pi

**出处**：官方仓库 <https://github.com/earendil-works/pi>（README）；官方站点 <https://pi.dev>。

| 语义 | 形态 |
|---|---|
| C1 | 官方 README 只说可用 print / JSON / RPC 模式自动化（原文 *automate it in print, JSON, or RPC mode*）；**具体旗标文档未载** |
| C2 | 文档未载 |
| C3 | 文档未载 |
| C4 | 文档未载（README 未写非交互下的审批行为） |
| C5 | 文档未载 ⇒ 按驱动器 `timeout` 准备 |
| C6 / C7 | 驱动器 |
| C8 | 驱动器 |
| C9 | 文档未载 |
| C10 | 文档未载（README 未写会话记录格式与落点） |
| 档位 | 文档未载 |
| 缺口 | 该 README 偏安装向；**派活前按 §5 逐项复核**，不要拿本节当结论 |

### opencode

**出处**：官方文档 <https://opencode.ai/docs/cli/>。

| 语义 | 形态 |
|---|---|
| C1 | 子命令 `opencode run [message..]`；`--command`、`--file/-f`。**顶层 `opencode` 是 TUI**，不要用它当工人 |
| C2 | `-c` / `--continue`；`-s` / `--session <id>`；`--fork` |
| C3 | `run` 的旗标表未列工作目录；`attach` 有 `--dir` ⇒ `run` 侧按「文档未载」处理 |
| C4 | TUI 旗标表有 `--auto`（原文：*auto-approve permissions that are not explicitly denied*）；**`run` 的子旗标表里没有它** ⇒ 是否可传：文档未载 |
| C5 | 文档未载 ⇒ 驱动器 `timeout` |
| C6 / C7 | 驱动器 |
| C8 / C9 | 文档未载 |
| C10 | `opencode export [sessionID]` 导出 JSON；记录本体在 DB（另有 `opencode db`）⇒ 判据要改用 export 产物 |
| 档位 | `-m` / `--model <provider/model>`；`--agent <name>`（`opencode agent create --mode all\|primary\|subagent`） |
| 常驻 | `opencode serve` + `opencode run --attach http://localhost:4096`（官方给的理由是免去每次冷启 MCP） |
| 坑 | 短旗标冲突：`opencode attach -p` 是**basic auth password**，不是 print |

### Claude Code

**出处**：官方 CLI 参考 <https://code.claude.com/docs/en/cli-reference>。

| 语义 | 形态 |
|---|---|
| C1 | `claude -p "query"`（print / SDK 模式）；支持管道输入 `cat file \| claude -p "query"`；`--output-format=text\|json\|stream-json`、`--input-format=text\|stream-json` |
| C2 | `-c` / `--continue`（当前目录最近一次）；`-r` / `--resume <id \| name \| 会话 .jsonl 绝对路径>`；`--session-id <uuid>`；`--fork-session` |
| C3 | 无 `--cwd`；靠调用方 `cd`。另有 `--add-dir`（追加可读写目录）、`--worktree/-w`（在独立 git worktree 里起会话） |
| C4 | `--permission-mode=default\|acceptEdits\|plan\|auto\|dontAsk\|bypassPermissions\|manual`；`--dangerously-skip-permissions` ≡ `bypassPermissions`；**无人值守**用 `--permission-prompts none`（无人应答时直接拒绝，而不是挂住）；细粒度用 `--allowedTools` / `--disallowedTools` |
| C5 | `--max-turns <n>`（agentic 轮数，print 模式，超限报错退出）；`--max-budget-usd <n>`（花费上限，print 模式）。**墙上时钟超时**：文档未载（仅 `claude ultrareview --timeout <分钟>`） |
| C6 / C7 | 驱动器 |
| C8 | 驱动器搬运；会话记录是 `.jsonl`（`--resume` 可直接接 `.jsonl` 路径） |
| C9 | `--autocompact <auto\|tokens>` 可设自动压缩窗口；压缩有钩子事件（`PreCompact` / `PostCompact`，见 `--include-hook-events` 说明）⇒ 自动落盘交接要靠钩子实现 |
| C10 | 会话 transcript 为 `.jsonl`（见官方 sessions 文档「Where transcripts are stored」）；`--forward-subagent-text` 可让子代理文本进入输出流 |
| 档位 | `--model <alias\|全名>`、`--effort=low\|medium\|high\|xhigh\|max\|ultracode`、`--fallback-model` |
| 其他 | `--bare`（跳过 hooks / skills / 插件 / MCP / CLAUDE.md 发现，脚本化更快）、`--settings <file\|json>`、`--setting-sources`、`--tools`、`--verbose`、`--no-session-persistence`、`--json-schema` |
| 坑 | **官方文档明说 `claude --help` 不列全部旗标**（原文：*`claude --help` does not list every flag*）⇒ 只靠 `--help` 会漏。另有 `--restricted`：把文件工具限制在工作目录内、拒绝 `bypassPermissions`——**这是评测/共享机场景的隔离开关，与「自动批准」是两件事** |

### Codex CLI

**出处**：官方参考 <https://developers.openai.com/codex/cli/reference>（旗标表为前端渲染，抓不到正文）；沙箱与审批的区分见 <https://developers.openai.com/codex/sandbox>。

| 语义 | 形态 |
|---|---|
| C1 | `codex exec`（别名 `codex e`）——官方原文用途：*scripted or CI-style runs that should finish without human interaction*；加 `--json` 得到逐行 JSON 事件 |
| C2 | `codex exec resume`；`--last`（当前工作目录最近一次）/ `--all`（跨全部会话） |
| C3 | 文档未载（全局旗标表另有 `--add-dir`：给主工作区之外追加写权限目录，见官方参考页） |
| C4 | **审批与沙箱是两个概念，文档明确分开**：审批策略 `--ask-for-approval, -a`（正文给出的取值示例是 `on-request`，完整取值见参考页），沙箱 `--sandbox`（如 `workspace-write`）。官方建议的低摩擦组合是 `--sandbox workspace-write --ask-for-approval on-request` |
| C5 | 文档未载 ⇒ 驱动器 `timeout` |
| C6 / C7 | 驱动器 |
| C8 / C9 | 文档未载 |
| C10 | 文档未载（会话可 `archive` / `delete`，但记录落点与格式未在文档中给出） |
| 档位 | 配置来自 `~/.codex/config.toml`；单次覆盖用 `-c key=value`；`--profile`、`--oss` |
| 其他 | `codex review`（非交互代码审查）、`codex login status`（凭据存在时退出码 0，便于脚本判定）、`codex app-server`（stdio / ws / unix socket） |
| 坑 | 参考页的旗标表由前端组件渲染 ⇒ 抓取只拿到说明文字；**落地前按 §5 复核** |

### Gemini CLI

**出处**：官方仓库 README <https://github.com/google-gemini/gemini-cli>；配置参考 <https://geminicli.com/docs/reference/configuration/>。

| 语义 | 形态 |
|---|---|
| C1 | `gemini -p "…"`；`--output-format=json`（结构化）/ `stream-json`（逐行事件） |
| C2 | 文档未载（有会话 checkpointing：`general.checkpointing.enabled`，默认 `false`） |
| C3 | 文档未载（另有 `--include-directories` 加入更多目录） |
| C4 | 审批模式：设置项 `general.defaultApprovalMode=default\|auto_edit\|plan`；**YOLO（全自动批准）只能从命令行开**：`--yolo` / `--approval-mode=yolo` |
| C5 | 文档未载 ⇒ 驱动器 `timeout` |
| C6 / C7 | 驱动器 |
| C8 / C9 | 文档未载（`general.sessionRetention.*` 只管会话清理） |
| C10 | 文档未载 |
| 档位 | `-m <model>`；**自带难度路由**：`general.plan.modelRouting`（规划用 Pro、实现用 Flash） |
| 其他 | 配置分层：默认值 → 系统默认 → 用户 `~/.gemini/settings.json` → 项目 `.gemini/settings.json` → 系统 settings → 环境变量 → 命令行 |
| 坑 | **该 CLI 正在迁移**：官方站点公告 *Gemini CLI was replaced by Antigravity CLI on June 18th, 2026*（针对未付费 / Google One 用户）⇒ 选它之前先确认用户的账号形态 |

### aider

**出处**：官方文档 <https://aider.chat/docs/scripting.html>；完整旗标见 <https://aider.chat/docs/config/options.html>。

| 语义 | 形态 |
|---|---|
| C1 | `aider --message "…" file1 file2`（`-m` / `--msg` / `--message`）；`--message-file / -f`；也可用 Python API（`Coder.create(...).run("…")`）——但官方声明 Python API **不受支持、可能随时变** |
| C2 | 文档未载（Python API 里连续 `coder.run(...)` 可接着上一次） |
| C3 | 文档未载 |
| C4 | `--yes`（对每个确认一律同意） |
| C5 | 文档未载 ⇒ 驱动器 `timeout` |
| C6 / C7 | 驱动器 |
| C8 / C9 | 文档未载 |
| C10 | 文档未载 |
| 档位 | 文档未载（见 options 参考） |
| 其他 | `--dry-run`（不改文件）、`--commit`（提交全部待提交改动后退出）、`--stream / --no-stream` |
| 坑 | **`--auto-commits` 默认为 `True`**：工人会自动提交它改的东西——与「代码与文档分开提交」「显式列出路径」冲突，用它当工人时必须显式 `--no-auto-commits` |

### 未列的 CLI

`cursor-agent` / `crush` / `droid` / `amp` 等不在本节：**要么官方文档没查到，要么没核实过**。要加一个，走 §5 的流程，不要凭印象补一行。

## 5. 新增一个 CLI 的取证流程

**先取证再写进来**，顺序不许颠倒（凭项目简介、旧记忆或类比断言工具能力，是本 skill 里唯一导致过返工的缺陷类型，见 `references/gates.md`「规格自检」第四问）。

1. 找**官方文档**（站点 / 官方仓库 README / `--help` 的官方说明页），逐条记 URL。
2. 按下面 12 项填；填不出的写「文档未载」，**不要用类比补齐**。
3. 写进 §4 时带上**查阅日期**——CLI 会改名、下线、改旗标语义（Gemini CLI 被 Antigravity CLI 取代就是一例）。
4. 落地前做一次 §3 的验收（C1–C10 真跑一遍），把命令与真实输出贴进流水。**这一步是复核，不是结论来源**：跑不通的写进未验证清单。

| # | 项 |
|---|---|
| 1 | 非交互单轮调用：完整命令行示例（提示词怎么传：位置参数 / `--prompt` / stdin） |
| 2 | 续接同一会话：继续最近一次；指定某个会话 id |
| 3 | 指定工作目录（无 ⇒ 写「靠调用方 cd」） |
| 4 | 自动批准工具调用：开关名。**必须与「放宽沙箱 / 信任项目本地文件 / 限制文件工具范围」区分开**——这四个是不同的东西 |
| 5 | 运行上限 / 超时（无 ⇒ 写「靠驱动器 `timeout`」） |
| 6 | 输出模式：是否支持结构化输出（text / json / stream-json / rpc） |
| 7 | 会话记录落盘位置与格式（jsonl / sqlite / DB） |
| 8 | 能否从记录里读到「这一轮调用了哪些工具、参数是什么」（C10 的判据） |
| 9 | 上下文将满时的自动压缩 / 交接钩子（无 ⇒ 写「无」） |
| 10 | 配置叠加 / 环境变量：能否为单次运行指定额外配置 |
| 11 | 退出码语义：正常结束 / 出错 / 被中断 |
| 12 | 模型 / 思考档开关（用于 §2 的选档） |
