---
name: sunny
description: "Sunny on this VPS: Hermes/Rukmini launches Cursor CLI for all pipeline work. Use when user says Sunny, build backend, Sunny resume, Sunny status, Sunny deploy, Bunny, project domain, fleet domain, or /sunny. NEVER use delegate_task for Sunny stages on this VPS."
version: 3.0.0
author: ascenta-core-hub + cursor-agents
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [sunny, cursor-cli, rukmini, jhipster, orchestration]
    related_skills: []
---

# Sunny on this VPS — Cursor CLI only

## Architecture (non-negotiable)

```
Rukmini (voice) → Hermes (thin coordinator) → Cursor CLI `agent` (does ALL coding)
```

| Layer | Role | Uses |
|-------|------|------|
| **Rukmini** | Mic + speaker | jarvis-voice → Hermes API :8642 |
| **Hermes** | Launch Cursor, report status | **This skill only** — NOT pipeline coding |
| **Cursor CLI** | Sunny orchestrator + all agents | `.cursor/agents/*.md` + `sunny-orchestrator.mdc` |
| **Disk state** | Resume + dashboard | `.sunny/context/state.json` |

### What Hermes must NEVER do on this VPS

- **NEVER** `delegate_task` for Sunny pipeline stages (Isha, Vikram, Maya, etc.)
- **NEVER** load `~/.hermes/skills/devops/sunny-agents/*` personas for pipeline work
- **NEVER** implement backend code, run JHipster, or advance stages yourself
- **NEVER** start a second Cursor run if tmux `sunny-cursor` is already running

The 98 Hermes persona skills under `~/.hermes/skills/devops/sunny-agents/` are **inactive on this VPS**. Cursor CLI reads agents from the project.

---

## Project paths

| What | Path |
|------|------|
| Project root | `/opt/ascenta-core-hub` |
| Agents + playbook | `/opt/ascenta-core-hub/.cursor/` |
| Launcher script | `/opt/ascenta-core-hub/.cursor/bin/sunny-cursor-run.sh` |
| State | `/opt/ascenta-core-hub/.sunny/context/state.json` |
| Cursor log | `/opt/ascenta-core-hub/.sunny/logs/cursor-run-latest.log` |
| Dashboard | `http://77.107.95.73:8787/agentprogress.html` |

Frontend path: **repo root** (no `./frontend` subfolder).

Domains (already in state.json): `lender.qualityoutsidethebox.org` / `fleet.qualityoutsidethebox.org`

---

## Your only three actions

### 1. User says build / resume / deploy

Check if Cursor is already running:

```bash
tmux has-session -t sunny-cursor 2>/dev/null && echo RUNNING || echo IDLE
```

- If **RUNNING**: tell user Cursor is already working; offer status.
- If **IDLE**, run **one** of:

```bash
# Resume (default — project already mid-pipeline at backend stage)
/opt/ascenta-core-hub/.cursor/bin/sunny-cursor-run.sh resume

# Full build from scratch (only if user explicitly asks fresh start)
/opt/ascenta-core-hub/.cursor/bin/sunny-cursor-run.sh build
```

Reply to user (spoken, 2–3 sentences max):

> "Cursor is running Sunny on ascenta-core-hub. Backend generation is in progress. Ask me anytime for status, or check the dashboard."

### 2. User asks status / progress / what's happening

```bash
/opt/ascenta-core-hub/.cursor/bin/sunny-cursor-run.sh status
```

Summarize: phase, active stage, lastVerdict, whether tmux is running, one line from log tail. Spoken prose only.

### 3. User asks to stop / cancel

```bash
/opt/ascenta-core-hub/.cursor/bin/sunny-cursor-run.sh stop
```

Confirm stopped. State on disk is preserved — they can resume later.

---

## Triggers

| User says | Action |
|-----------|--------|
| Sunny, build… / Sunny, resume | `sunny-cursor-run.sh resume` or `build` |
| Sunny, what's the status? / progress? | `sunny-cursor-run.sh status` |
| Sunny, stop / cancel | `sunny-cursor-run.sh stop` |
| Sunny deploy / @bunny | `sunny-cursor-run.sh resume` (deploy-only in playbook — Cursor handles) |

---

## Pitfalls (tell user if relevant)

1. **Cursor CLI must be logged in** (`agent login`). Hermes cannot fix auth.
2. **Multi-hour job** — Cursor runs in tmux `sunny-cursor`; survives Hermes/Rukmini session end.
3. **4.5 GB RAM** — JHipster may OOM; Cursor playbook has mitigations.
4. **Do not use `hermes chat -q`** for Sunny — that mode is unrelated; user should use Rukmini or `sunny-cursor-run.sh` directly.

---

## Slash command

`/sunny resume` → same as voice "Sunny, resume" → launch Cursor CLI.
