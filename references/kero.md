# 终端会话载体映射（kero 及同类）

**载体不止子代理。** 工人可以是子代理，也可以是一个终端会话里跑的 CLI agent 或命令。本文件把 `references/delegation.md` 的委托能力映射到终端会话驱动器上。

适用对象：kero 一类「会话在后台存活、可用命令行驱动」的终端。其他同类工具按自身命令核对后套用同一张能力表，不照抄命令。kero 的命令用法与环境约定见所在环境的 `kero` skill（`skill://kero`），本文件只记本流程需要的映射与限制。

> 下列 kero 接口与行为是 2026-10-21 在 Windows 10 + pwsh/bash、kero protocol 3 上的实测记录。**换平台、换版本前重新核对**；未核实处已标注。

## 何时用终端会话，而不是子代理

| 需要 | 载体 |
|---|---|
| 真实 TTY / 交互式 agent CLI（claude、omp、codex 等） | **终端会话** |
| 进程在我这一轮结束后继续跑（长构建、长测试、迁移脚本） | **终端会话** |
| 用户要看得见、或需要用户当场介入（批准、输入密钥） | **终端会话** |
| 换 harness 或换模型来取得独立判断 | **终端会话** |
| 结构化产出（`outputSchema`）、工具级原始转录、批量编排 | 子代理（`references/omp.md`） |

两者都是载体，纪律不变：契约先写、冻结方案先落、验收由我复现。终端会话**没有**子代理那种结构化转录与 schema 产出，审计能力更弱，不是更强。

## 能力映射

| 事 | kero 形态 | 备注 |
|---|---|---|
| **派工** | `kero new -n <name> -d <dir> -- <cmd>`，打印会话 id | 会话 id 是续接、取产出、审计的入口，记进台账 |
| 旁挂面板 | `kero split <target> --down -- <cmd>`，打印面板 id | 面板随会话关闭；`kero close <pane>` 在会话已关时返回 not found |
| 同步等命令结束 | `kero new … --wait -- <cmd>`；或 `kero wait <id> --exit` | 退出码即命令退出码（实测 `exit 5` → rc=5） |
| **续接** | `kero send <id> "<文本>" --enter`（`kero prompt` 发送后等它停手并回屏） | 会话只要没 close 就还在；**不要**用 `kero restart` 续接 agent，那是重启已退出的 shell |
| 中途纠正 | 同上 `kero send` | 会话里的 agent 收到的是真实输入，不是旁注 |
| 状态查询 | `kero status <id> --json`：`status` / `process` / `title` / `dir` / `commandExit` | 命令结束后面板回 `idle`，`commandExit` 保留 |
| 读产出 | `kero read <id> -n <行>`；`-a` 带回滚 | 只有屏缓冲，**没有**结构化转录 |
| **审计** | `kero read -a` + `kero diff <id>` + 目标工作区 git 状态 | `kero diff` 输出该面板工作区相对 HEAD 的改动（含未跟踪文件）；`--turn` 需要 agent 回合记录，在非 agent 面板上返回「the pane's agent hasn't started a turn」 |
| **隔离** | `-d <dir>` 指向独立 worktree 或独立目录 | 没有内置分支/补丁机制；隔离靠 `git worktree` 加 `-d` |
| 列出全部 | `kero ls [--json]` | 收尾前核对没有遗留会话 |
| 通知用户 | `kero notify <id> "<消息>"`；`kero report blocked "<原因>" --kind permission` | 只在真的需要用户时用 |
| 退出码 | 目标不存在 rc=3（实测）；kero 未运行 rc=4（来自 kero 自带说明，未实测） | 收尾脚本可据此判断 |

## 已知限制（实测）

- **`kero send` 只可靠传 ASCII。** 中文被丢弃或改写（`中文测试` → `0`，`abc中文def` → `abcdef`，`符号，。` → `` ` ``），emoji 同样丢失；含中文的路径也被改写（`w1-轮1.md` → `w1-1.md`），工人读不到文件。**指令与路径一律用 ASCII**；需要中文内容时写进文件，只发送 ASCII 路径让它自己读。
- **`kero diff` 读的是面板当前 shell 的目录。** 命令刚退出、面板尚未回到提示符时可能返回 `not in a git repository`，等它回到 `idle` 后重试。
- **`report` 不是可靠的状态机。** 面板状态是瞬时信号：在嵌套 shell 里跑 `kero report working`，`status` 读到的仍是 `idle`；`report blocked` 只在一个采样窗口内可见，随后回 `idle`。直接把 `kero report …` 作为面板命令时 `status`/`progress` 可稳定读到。
  ⇒ 判断工人是否结束，用 `wait --exit` / `commandExit` / `read` 屏内容，**不要**依赖 `status` 的 working 标志。
- **交互式 TUI 的 `status` 不代表 agent 在想事。** 启动 `claude` 后面板可显示 `idle` 而界面在等输入。等 agent 用 `kero prompt` 或轮询 `read`。
- **无原始转录。** 审计只能看到屏缓冲与工作区 diff，读文件的历史动作不可还原。读取边界只能靠指令约束，无法事后核对 ⇒ 这类审计缺口按 `references/gates.md`「记录系统」标为未验证。
- 并发上限、`--for idle,error,exited` 各状态、kero 未运行时的具体退出码、GUI 侧边栏呈现、macOS/Linux 行为：**未核实**。

## 派工时的追加要求

终端会话没有子代理的初始上下文注入，指令必须**一次性自包含**：

- 首条 `kero send` 之前，把切片指令写到 `orch-doc/prompts/<工人 id>-轮<k>.md`，再用 `kero prompt <id> "读取 <绝对路径> 并按其执行"`——不要试图把整份契约塞进一次按键输入。
- **工人 id、轮次目录与路径全用 ASCII**（如 `w1-round1.md`）：非 ASCII 路径经 `kero send` 会被改写，工人读不到文件。中文写在文件内容里，不写在路径和发送文本里。
- 交接文档路径、读取边界、提交责任照 `templates/prompt-slice.md` 下发，不因载体变化而省略。
- 工人是交互式 agent 时，屏缓冲会被 TUI 重绘覆盖；要求它把真实命令输出写进交接文档，我再按 `references/verification.md` 复跑。
- 收尾时 `kero close <id>`，并核对 `kero ls` 没有遗留会话。

## 与预算的衔接

`kero new` 起的是本机进程，不计入 `task` 的请求预算，但**计入时间与机器资源**。冻结方案 §8 的轮次与时间上限同样覆盖终端会话；卡住的会话要显式 close，不用「它还在跑」代替失败判定。
