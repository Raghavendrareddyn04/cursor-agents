#!/usr/bin/env bash
# Launch Sunny pipeline via Cursor CLI (agent) in a persistent tmux session.
# Hermes/Rukmini invokes this; Cursor does the work; logs + .sunny/ hold state.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"
PROJECT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$PROJECT/.sunny/logs"
SESSION="sunny-cursor"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOG_DIR/cursor-run-${STAMP}.log"
LATEST="$LOG_DIR/cursor-run-latest.log"
PLAYBOOK="$PROJECT/.cursor/rules/sunny-orchestrator.mdc"

mkdir -p "$LOG_DIR"

usage() {
  cat <<EOF
Usage: sunny-cursor-run.sh <build|resume|status|attach|stop|watchdog|ensure>

  build    — full Sunny intake + pipeline (or fresh build prompt)
  resume   — Sunny, resume from .sunny/context/state.json
  status   — print stage + tail of latest log
  attach   — attach to tmux session sunny-cursor
  stop     — kill tmux session sunny-cursor
  watchdog — if pipeline incomplete and agent not running, auto-resume (for cron/systemd)
  ensure   — alias for watchdog
EOF
}

AGENT="/root/.local/bin/agent"

agent_cli_ready() {
  command -v "$AGENT" >/dev/null 2>&1 || return 1
  # Fast auth probe — never spawn a full agent session (watchdog-safe).
  [[ -f "${HOME}/.config/cursor/auth.json" ]] || [[ -f "${HOME}/.cursor/auth.json" ]] || return 1
  return 0
}

agent_ok() {
  agent_cli_ready || { echo "ERR: agent not found or not authenticated at $AGENT"; exit 1; }
  "$AGENT" -p --trust "Reply OK" >/dev/null 2>&1 || {
    echo "ERR: Cursor CLI not authenticated — run: agent login"
    exit 1
  }
}

build_prompt() {
  cat <<PROMPT
You are Sunny, the orchestrator for this project. Read and follow exactly:
$PLAYBOOK

Project root: $PROJECT (frontend IS the repo root — no ./frontend subfolder).

User request:
Sunny, build the JHipster microservices backend for this project.
Project domain: lender.qualityoutsidethebox.org
Fleet domain: fleet.qualityoutsidethebox.org
ACME email: devteamqobox@gmail.com

Use Cursor subagents per .cursor/agents/*.md slugs. Checkpoint via context-agent to .sunny/context/.
Run graphify update after code changes. Do not stop until backend stage completes or you hit a hard blocker.
PROMPT
}

resume_prompt() {
  cat <<PROMPT
You are Sunny, the orchestrator. Read and follow exactly:
$PLAYBOOK

Project root: $PROJECT
Resume from .sunny/context/state.json — continue the next non-done stage.
Frontend is repo root (not ./frontend). Domains already in state.json.
PROMPT
}

PROMPT_FILE="$LOG_DIR/current-prompt.txt"
WATCHDOG_LOG="$LOG_DIR/watchdog.log"
LOCK_FILE="$PROJECT/.sunny/sunny-watchdog.lock"

workflow_terminal() {
  python3 -c "
import json, sys
p = '$PROJECT/.sunny/context/state.json'
try:
    s = json.load(open(p))
except FileNotFoundError:
    sys.exit(1)
phase = s.get('phase', '')
if phase in ('complete', 'blocked'):
    sys.exit(0)
stages = s.get('stages', [])
if stages and all(x.get('status') == 'done' for x in stages):
    sys.exit(0)
sys.exit(1)
" 2>/dev/null
}

sunny_agent_running() {
  # Any in-flight Sunny agent (orchestrator prompt uses --force).
  if pgrep -f "index.js -p --trust --force" >/dev/null 2>&1; then
    return 0
  fi
  # Tmux up but agent still booting — avoid duplicate resume for ~2 min.
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    local log
    log="$(readlink -f "$LATEST" 2>/dev/null || true)"
    if [[ -n "$log" && -f "$log" ]]; then
      local age=$(( $(date +%s) - $(stat -c %Y "$log") ))
      if (( age < 120 )); then
        return 0
      fi
    fi
    watchdog_log "stale tmux (no agent, log idle) — will restart"
    return 1
  fi
  return 1
}

watchdog_log() {
  mkdir -p "$LOG_DIR"
  echo "$(date -Is) $*" >>"$WATCHDOG_LOG"
}

reports_already_published() {
  python3 -c "
import json, sys
p = '$PROJECT/.sunny/context/state.json'
try:
    s = json.load(open(p))
except FileNotFoundError:
    sys.exit(0)
if s.get('phase') != 'complete':
    sys.exit(0)
if s.get('reportsPublishedAt'):
    sys.exit(0)
sys.exit(1)
" 2>/dev/null
}

run_watchdog() {
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    watchdog_log "skip: another watchdog holds the lock"
    exit 0
  fi

  if workflow_terminal; then
    if reports_already_published; then
      watchdog_log "skip: workflow complete, reports published"
    else
      watchdog_log "terminal: publishing reports (backfill)"
      bash "$PROJECT/.sunny/publish-reports.sh" --verify >>"$WATCHDOG_LOG" 2>&1 || true
      python3 "$PROJECT/.sunny/build-progress-from-state.py" >>"$WATCHDOG_LOG" 2>&1 || true
    fi
    exit 0
  fi

  if sunny_agent_running; then
    watchdog_log "ok: sunny-cursor agent still running"
    python3 "$PROJECT/.sunny/write-reports-html.py" >>"$WATCHDOG_LOG" 2>&1 || true
    python3 "$PROJECT/.sunny/build-progress-from-state.py" >>"$WATCHDOG_LOG" 2>&1 || true
    exit 0
  fi

  if tmux has-session -t "$SESSION" 2>/dev/null; then
    watchdog_log "stale tmux session (agent exited) — restarting"
    tmux kill-session -t "$SESSION" 2>/dev/null || true
  else
    watchdog_log "no tmux session — auto-resuming pipeline"
  fi

  if ! agent_cli_ready; then
    watchdog_log "ERR: Cursor CLI not installed or not authenticated — will retry on next tick"
    exit 1
  fi

  resume_prompt >"$PROMPT_FILE"
  start_tmux resume
  watchdog_log "resumed: new log $LOG"
  disown -a 2>/dev/null || true
}

start_tmux() {
  local mode="$1"
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  # setsid: detach from systemd/cron cgroup so watchdog exit does not reap the agent.
  setsid tmux new-session -d -s "$SESSION" bash -lc "
    cd '$PROJECT'
    export PATH=\"\$HOME/.local/bin:\$PATH\"
    AGENT=/root/.local/bin/agent
    echo '=== Sunny via Cursor CLI ($mode) started '\$(date -Is)' ===' | tee '$LOG'
    ln -sf '$LOG' '$LATEST'
    \"\$AGENT\" -p --trust --force --output-format stream-json --stream-partial-output \\
      \"\$(cat '$PROMPT_FILE')\" 2>&1 | tee -a '$LOG'
    echo '=== finished '\$(date -Is)' exit='\$?' ===' | tee -a '$LOG'
  "
  echo "OK  Cursor Sunny running in tmux session: $SESSION"
  echo "    log: $LOG"
  echo "    attach: sunny-cursor-run.sh attach"
}

cmd="${1:-status}"
case "$cmd" in
  build)
    agent_ok
    build_prompt >"$PROMPT_FILE"
    start_tmux build
    ;;
  resume)
    agent_ok
    resume_prompt >"$PROMPT_FILE"
    start_tmux resume
    ;;
  status)
    if [[ -f "$PROJECT/.sunny/context/state.json" ]]; then
      python3 -c "
import json
s=json.load(open('$PROJECT/.sunny/context/state.json'))
active=[x for x in s.get('stages',[]) if x.get('status')=='active']
done=len([x for x in s.get('stages',[]) if x.get('status')=='done'])
print('phase:', s.get('phase'))
print('lastVerdict:', s.get('lastVerdict'))
print('active:', active[0].get('label') if active else 'none')
print('done_stages:', done)
print('project:', s.get('project',{}).get('domain'))
"
    else
      echo "No state.json yet"
    fi
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "tmux: $SESSION RUNNING"
    else
      echo "tmux: $SESSION not running"
    fi
    if [[ -f "$LATEST" ]]; then
      echo "--- log tail ---"
      tail -15 "$LATEST"
    fi
    ;;
  attach)
    exec tmux attach -t "$SESSION"
    ;;
  stop)
    tmux kill-session -t "$SESSION" 2>/dev/null && echo "stopped $SESSION" || echo "no session"
    ;;
  watchdog|ensure)
    run_watchdog
    ;;
  *)
    usage
    exit 1
    ;;
esac
