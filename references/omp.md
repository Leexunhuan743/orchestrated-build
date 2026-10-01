# OMP 工具映射示例

仅在 OMP 环境中映射工具时读本文件。

**载体是子代理**：`task`（批量走 `tasks[]`，`context` 装共享背景）、或需要脚本编排时用 `eval` 的 `agent()` / `workpool()`。

下列 OMP 接口、状态和默认值是已有用法记录，**当前版本未核实**。使用前核对本环境工具文档或实际能力；不可直接当作其他 harness 的执行指令。无法取得完整转录时，明确留下审计缺口。

| 事 | 形态 |
|---|---|
| 读什么 | 见 `SKILL.md` 纪律 2 |
| **续接** | `hub` `send` 给已 `parked` 的工人会**复活**它——`task` 没有 resume 参数，消息是唯一的续接原语 |
| **中途纠正** | 同样用 `hub` `send`：注入为非中断性旁注（steering），回复是真实回合；`await: true` 阻塞等它回一条 |
| 双向提问 | 工人可以反向 `hub` `send` 给我 |
| 结构化产出 | `outputSchema` + `schemaMode`（`permissive` / `strict`） |
| **审计** | `history://<id>`（简洁转录）· `agent://<id>`（最终产出）· `<id>.jsonl`（原始会话）· Agent Hub 实时看 |
| **隔离** | `isolated: true`：需 git 仓库，产出 patch 或 `omp/task/<id>` 分支；**完成即拆解、不可复活** |
| 并行上限 | `task.maxConcurrency`；后台作业不阻塞我的轮次 |

**OMP 上限示例**（使用前核实实际状态与续接能力）：

| 设置 | 默认 | 撞上之后 |
|---|---|---|
| `task.softRequestBudget` | 200 请求 | 1.5× 时**强制收尾**并 yield 部分结果 ⇒ 工人转 `idle`，**可续接** |
| `task.maxRuntimeMs` | `0`（关闭） | 到点中止 ⇒ 转 `aborted`，终态、不可续 |
| `task.agentIdleTtlMs` | 7 分钟 | `idle` 转 `parked`（会话保留）⇒ 发消息复活 |

撞上软预算后，若工人处于可续接状态，就用 `hub` `send` 下发窄任务（只修失败项 + 收尾）；`aborted` 或已拆解的隔离工人无法走这条路。

**记下工人的 id**（`task` 的 `name` 字段自定，默认是生成的 `AdjectiveNoun`）。id 是续接、取产出、审计三件事的入口——不记就等于关掉了这三件事。
