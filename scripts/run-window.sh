#!/usr/bin/env bash
# 窗口驱动器（omp 实现；协议本身与工具无关——换成任何有非交互模式的 agent CLI 都成立）
#
# 为什么需要它：
#   窗口可能**静默死亡**——进程消失、输出文件只有一行、没有任何退出信息，
#   于是你会在十几分钟后才发现。裸 `agent ... | tee` 在进程被杀时不会留下结局记录。
#
# 本脚本保证：工人正常退出、报错、被杀，以及驱动器收到 INT / TERM / HUP 时，
#   flow 文件末尾都会留下结局标记，并且**会尽力终止工人进程**。
#
#   三处关键实现，改脚本时不要退化：
#   ① 工人跑在**后台**、用 `wait` 等 —— bash 在 `wait` 期间收到信号会**立即**执行 trap；
#      若让工人占着前台，trap 会被推迟到工人自己跑完（可能几十分钟后），等于没有。
#   ② trap 里**先发终止信号、再写结局**，而且结局要写清"做了什么"
#      （SIGNAL-RECEIVED / TERM-SENT / KILL-SENT / WORKER=terminated|still-alive）——
#      **不要提前写一个看起来最终的结局**。
#   ③ 记录目录若在仓库之外，只需用 `--add-dir` 加入 handoffs/。
#      ⚠ 它**只增不限**（`omp --help`：*Add a workspace directory beyond the working
#      directory*）——对已在工作目录内的文件毫无隔离作用。"工人不得读 doc/ 其余部分"
#      是**合同约定，不是技术隔离**。
#
#   ⚠ 做不到的：**无法保证整棵子进程树停止**——只能终止直接子进程（CLI 本身），
#      它派生的孙进程可能存活；**SIGKILL 与机器故障**也无法捕获。
#      判据不是"一定有 EXIT"，而是"**有 EXIT 才说明这次运行正常收尾**"。
#
# 用法:
#   RECORD_DIR=<repo>/doc WORK_DIR=<被构建仓库> bash run-window.sh <窗口ID> <指令文件> [new|continue]
#   第三个参数传 continue 用于**续轮**：同一会话接着上次继续（撞运行上限后的标准处置）。
#
# 必填环境变量（没有合理默认值，猜错会让工人在错误目录里干活）：
#   RECORD_DIR   记录目录（本脚本会把 流水/ 与 .sessions/ 写在它下面）
#                按 references/gates.md「目录布局」应为 <repo>/doc
#   WORK_DIR     被构建仓库的路径
# 可选：
#   AGENT_CMD    工人 CLI（默认 omp）
#   AGENT_CONFIG 窗口配置叠加层（默认与本脚本同目录的 worker-config.yml）
#   MAX_TIME     单轮运行上限（默认 2400 秒）
set -uo pipefail

W="$1"
P="$2"
MODE="${3:-new}"

RECORD_DIR="${RECORD_DIR:?缺少 RECORD_DIR：请显式指定记录目录（本脚本会在它下面写 流水/ 与 .sessions/）}"
WORK_DIR="${WORK_DIR:?缺少 WORK_DIR：请显式指定被构建仓库的路径}"
[ -d "$WORK_DIR" ] || { echo "WORK_DIR 不存在: $WORK_DIR" >&2; exit 2; }
[ -f "$P" ] || { echo "指令文件不存在: $P" >&2; exit 2; }

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_CMD="${AGENT_CMD:-omp}"
AGENT_CONFIG="${AGENT_CONFIG:-$SELF_DIR/worker-config.yml}"
MAX_TIME="${MAX_TIME:-2400}"

# 目录必须先存在：否则下面的重定向会失败，工人根本不会启动，
# 而 CODE=1 是 bash 重定向失败的退出码、不是工人的——排查成本极高。
mkdir -p "$RECORD_DIR/流水" "$RECORD_DIR/.sessions/$W" "$RECORD_DIR/handoffs" \
  || { echo "无法创建记录目录: $RECORD_DIR" >&2; exit 2; }

OUT="$RECORD_DIR/流水/$W-$(date +%Y%m%d-%H%M%S).txt"
START=$(date +%s)

CONT=""
[ "$MODE" = "continue" ] && CONT="-c"

{
  echo "=== WINDOW $W START $(date -Iseconds) MODE=$MODE ==="
  echo "=== PROMPT $P ==="
  echo "=== CWD $WORK_DIR ==="
  echo ""
} > "$OUT"

# 工人跑在后台 —— 这样 trap 才能在收到信号时**立即**执行（见文件头 ①）。
"$AGENT_CMD" -p $CONT \
  --cwd "$WORK_DIR" \
  --session-dir "$RECORD_DIR/.sessions/$W" \
  --config "$AGENT_CONFIG" \
  --add-dir "$RECORD_DIR/handoffs" \
  --auto-approve \
  --max-time "$MAX_TIME" \
  "$(cat "$P")" >> "$OUT" 2>&1 &
AGENT_PID=$!

# 驱动器自身被杀。**分三步记录，不要提前写一个看起来最终的结局**：
#   ① 收到信号  ② 已发终止信号（TERM，必要时 KILL）  ③ 尽力确认工人是否退出
# 做不到的：**无法保证整棵子进程树停止**——这里只能终止直接子进程（CLI 本身），
#   它派生的孙进程可能存活。所以结局行写的是"我们做了什么"，不是"工人已死"。
on_signal() {
  local now; now=$(date +%s)
  echo "" >> "$OUT"
  echo "=== WINDOW $W SIGNAL-RECEIVED DURATION=$(( now - START ))s END $(date -Iseconds) ===" >> "$OUT"

  kill -TERM "$AGENT_PID" 2>/dev/null \
    && echo "=== WINDOW $W TERM-SENT pid=$AGENT_PID ===" >> "$OUT" \
    || echo "=== WINDOW $W TERM-FAILED pid=$AGENT_PID（进程可能已自行退出）===" >> "$OUT"

  sleep 2
  if kill -0 "$AGENT_PID" 2>/dev/null; then
    kill -KILL "$AGENT_PID" 2>/dev/null \
      && echo "=== WINDOW $W KILL-SENT pid=$AGENT_PID ===" >> "$OUT" \
      || echo "=== WINDOW $W KILL-FAILED pid=$AGENT_PID ===" >> "$OUT"
  fi

  # 尽力确认；这只覆盖直接子进程，不含它的后代。
  if kill -0 "$AGENT_PID" 2>/dev/null; then
    echo "=== WINDOW $W EXIT=driver-killed WORKER=still-alive（无法确认已停止，请自行检查残留进程）===" >> "$OUT"
  else
    echo "=== WINDOW $W EXIT=driver-killed WORKER=terminated ===" >> "$OUT"
  fi
  exit 130
}
trap on_signal INT TERM HUP

wait "$AGENT_PID"
CODE=$?

END=$(date +%s)
{
  echo ""
  echo "=== WINDOW $W EXIT=$CODE DURATION=$((END - START))s END $(date -Iseconds) ==="
} >> "$OUT"

# 兜底 handoff 的搬运：配置叠加层让工人在上下文将满时自动把交接文档写进会话产物目录，
# 而下一窗口被要求读的是 handoffs/$W.md —— 落点不同。
# 不搬的话，"我忘记换窗口"这个兜底场景下交接确实落盘了，但落在没人会去读的地方。
#
# ⚠ 两个曾经踩过的坑：
#   ① 会话产物目录在 `--session-dir` 下**再深一层**（.sessions/<W>/<session-id>/），
#      只 glob `.sessions/<W>/handoff-*.md` 永远匹配不到 —— 这里两种深度都覆盖。
#   ② 续轮时工人会**更新**交接；用 `[ ! -f 目标 ]` 做条件会把新的静默丢弃、留下旧的。
LATEST="$(ls -t "$RECORD_DIR/.sessions/$W"/handoff-*.md \
              "$RECORD_DIR/.sessions/$W"/*/handoff-*.md 2>/dev/null | head -1 || true)"
if [ -n "${LATEST:-}" ]; then
  TARGET="$RECORD_DIR/handoffs/$W.md"
  if [ ! -f "$TARGET" ] || [ "$LATEST" -nt "$TARGET" ]; then
    cp "$LATEST" "$TARGET" && echo "auto-handoff copied -> handoffs/$W.md"
  fi
fi

echo "exit=$CODE duration=$((END - START))s"
echo "flow=$OUT"
tail -60 "$OUT"
