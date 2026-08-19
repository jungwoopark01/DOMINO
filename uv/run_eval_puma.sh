#!/bin/bash
# One-command evaluation: start the policy server, wait for it, run the
# simulation, shut the server down. Wraps uv/serve_puma.sh + uv/eval_puma.sh.
#
#   bash uv/run_eval_puma.sh adjust_bottle demo_clean_dynamic
#   MANIFEST=auto bash uv/run_eval_puma.sh click_bell demo_clean_dynamic
#   bash uv/run_eval_puma.sh <task> <task_config> [ckpt_setting] [seed] [gpu_id]
#
# If a server is already listening on $PORT it is reused and left running, so
# you can keep one up across many tasks and still use this script.
#
# Server log -> uv/logs/policy_server.log

set -uo pipefail

TASK_NAME=${1:?usage: bash uv/run_eval_puma.sh <task> <task_config> [ckpt_setting] [seed] [gpu_id]}
TASK_CONFIG=${2:?missing task_config, e.g. demo_clean_dynamic}

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LOG="$REPO_ROOT/uv/logs/policy_server.log"
mkdir -p "$(dirname "$LOG")"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-9001}"
STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-900}"   # a 10 GB checkpoint is not fast

port_open() { (exec 3<>"/dev/tcp/$HOST/$PORT") 2>/dev/null; }

SERVER_PID=""
cleanup() {
    [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null || return 0
    echo; echo "==> stopping policy server"
    # Negative PID kills the process GROUP, so the python child dies too --
    # otherwise a 10 GB model would sit on the GPU after Ctrl-C.
    kill -TERM -- "-$SERVER_PID" 2>/dev/null || kill -TERM "$SERVER_PID" 2>/dev/null
}
trap cleanup EXIT INT TERM

if port_open; then
    echo "==> reusing server already on $HOST:$PORT"
else
    echo "==> starting policy server (log: $LOG)"
    # setsid puts it in its own process group for the cleanup above.
    setsid env PORT="$PORT" bash "$REPO_ROOT/uv/serve_puma.sh" > "$LOG" 2>&1 &
    SERVER_PID=$!

    echo -n "==> waiting for $HOST:$PORT "
    waited=0
    until port_open; do
        # If it died during startup, say why instead of waiting out the timeout.
        kill -0 "$SERVER_PID" 2>/dev/null || {
            echo; echo "ERROR: server exited during startup:" >&2; tail -30 "$LOG" >&2; exit 1; }
        [ "$waited" -ge "$STARTUP_TIMEOUT" ] && {
            echo; echo "ERROR: no server after ${STARTUP_TIMEOUT}s:" >&2; tail -30 "$LOG" >&2; exit 1; }
        sleep 3; waited=$((waited + 3)); echo -n "."
    done
    echo " up (${waited}s)"
fi

echo
HOST="$HOST" PORT="$PORT" MANIFEST="${MANIFEST:-}" \
    bash "$REPO_ROOT/uv/eval_puma.sh" "$@"
