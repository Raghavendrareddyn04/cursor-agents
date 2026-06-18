# Cursor Agents → Hermes Agent Mapping

This document explains how the **Sunny multi-agent system** (originally built for **Cursor IDE**) is wired to run on **Hermes Agent** on a VPS.

The Cursor agent definitions are **not rewritten**. Hermes reads the same files and orchestrates the same pipeline using its own tools.

---

## Repos and paths on this VPS

| Component | Path | Git remote |
|-----------|------|------------|
| Cursor agents (Sunny system) | `/opt/cursor-agents/` | `https://github.com/Raghavendrareddyn04/cursor-agents.git` |
| Hermes Agent | `/root/.hermes/hermes-agent/` | `https://github.com/NousResearch/hermes-agent.git` |
| Hermes Sunny skill (bridge) | `/root/.hermes/skills/devops/sunny/SKILL.md` | local skill |
| Jarvis voice + HUD | `/opt/jarvis/` | `https://github.com/eadmin2/jarvis_ai.git` |

---

## High-level architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  YOU (CLI / Telegram / Jarvis / gateway)                        │
│  "Sunny, build backend for ./frontend — domain X — fleet Y"     │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  HERMES AGENT (orchestrator runtime)                            │
│  • Loads skill: /sunny  (or natural language trigger)           │
│  • Reads playbook: cursor-agents/.cursor/rules/sunny-orchestrator.mdc │
│  • Acts as Sunny — does NOT write backend code itself           │
└────────────────────────────┬────────────────────────────────────┘
                             │ delegate_task (per stage)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  HERMES SUBAGENTS (one per specialist)                          │
│  • Persona loaded from: cursor-agents/.cursor/agents/<slug>.md  │
│  • Tools: terminal, file, code, web (restricted for verify)   │
└────────────────────────────┬────────────────────────────────────┘
                             │ writes code, tests, configs
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  PROJECT WORKSPACE (your app repo)                              │
│  • frontend/          React source                              │
│  • gateway/, services/  generated JHipster microservices        │
│  • .cursor/ → symlink to cursor-agents/.cursor                  │
│  • .sunny/context/    shared memory (state.json, summaries)     │
│  • .env               secrets (Maya generates)                  │
│  • graphify-out/      codebase knowledge graph                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Concept mapping: Cursor → Hermes

| Cursor | Hermes | Notes |
|--------|--------|-------|
| Main chat agent | Hermes main session | Same orchestrator role as Sunny in Cursor |
| `.cursor/rules/sunny-orchestrator.mdc` | Hermes `/sunny` skill + `read_file` on `.mdc` | Playbook is still the source of truth |
| `.cursor/agents/<slug>.md` | `read_file` then pass content into `delegate_task` context | Agent personas unchanged |
| **Task** tool with `subagent_type: "architecture-agent"` | **`delegate_task`** with goal + agent file as context | No `subagent_type` registry in Hermes — slug is convention |
| `readonly: true` on verify agents | Restrict subagent toolsets (no file write / patch) | Verify agents audit only |
| Context Agent (Maya) | Same — delegate to `context-agent` persona | Writes `.sunny/context/` |
| `.sunny/context/state.json` | Same file on disk | Resume works across Hermes sessions |
| `graphify query` / `graphify update` | Hermes `terminal` tool in project root | Must install graphify on VPS |
| Live dashboard `:8787` / domain | Same — Maya seeds `.sunny/web/` | Unchanged |
| Fleet push to central host | Same — Maya fetches token from `/api/fleet-config` | Hari deploys `.cursor/central/` |
| Cursor always-on session | `hermes gateway`, SSH tmux, or `Sunny, resume` | Long runs may need persistent session |

---

## How a Cursor agent becomes a Hermes subagent

For every specialist in the Sunny pipeline, Hermes does this:

### Step 1 — Resolve the agent slug

The slug matches the filename without `.md`:

```
cursor-agents/.cursor/agents/architecture-agent.md  →  slug: architecture-agent
```

### Step 2 — Load the persona

```text
read_file("/opt/cursor-agents/.cursor/agents/architecture-agent.md")
```

This file is the **full system prompt** for that specialist (same as Cursor's subagent definition).

### Step 3 — Delegate

Hermes calls `delegate_task` approximately like:

```text
delegate_task(
  goal="<stage instructions from sunny-orchestrator.mdc>",
  context="<full architecture-agent.md content>
          + relevant .sunny/context/*.md summaries
          + excerpt from state.json",
  toolsets="terminal,file,code,web"   # or read-only subset for verify agents
)
```

### Step 4 — Checkpoint

After each handoff, delegate to **context-agent** (Maya) to update:

- `.sunny/context/state.json`
- `.sunny/web/progress.json`
- fleet push (if `fleetDomain` set)

### Step 5 — Graphify (after code changes)

After any generate/fix agent:

```bash
graphify update <project-root>
```

---

## Orchestrator mapping

| Role | Cursor | Hermes |
|------|--------|--------|
| **Sunny** (orchestrator) | Main Cursor agent + `sunny-orchestrator.mdc` | Hermes session with `/sunny` skill loaded |
| **Maya** (context / memory) | `context-agent` via Task | `delegate_task` + `context-agent.md` |
| **Hari** (fleet host) | `fleet-host-agent` via Task (explicit only) | Same — standalone deploy, not auto-launched |

Sunny in Hermes **never implements backend code**. It only:

1. Reads the playbook
2. Launches specialists via `delegate_task`
3. Runs verify → fix loops until exit phrases pass
4. Reports progress to the user and dashboards

---

## Full agent registry

Each row: **Codename** · **Slug** · **File** · **Hermes delegation** · **Readonly**

### Singletons

| Codename | Slug | Agent file | Readonly |
|----------|------|------------|----------|
| Sunny | `sunny` | `sunny.md` + `sunny-orchestrator.mdc` | No (orchestrator — Hermes main session, not delegated) |
| Maya | `context-agent` | `context-agent.md` | No |
| Leela | `issues-log-agent` | `issues-log-agent.md` | No |
| Deepa | `documentation` | `documentation.md` | No |
| Hari | `fleet-host-agent` | `fleet-host-agent.md` | No (standalone fleet deploy) |

### Pipeline agents (generate · verify · fix)

| Family | Generate | Verify | Fix |
|--------|----------|--------|-----|
| Isha (frontend sanitize) | `frontend-sanitize-agent` | `frontend-sanitize-verify-agent` | `frontend-sanitize-fix-agent` |
| Arjun (architecture) | `architecture-agent` | `architecture-verify-agent` | `architecture-fix-agent` |
| Vikram (backend build) | `jhipster-backend-agent` | `jhipster-verify-agent` | `issue-resolution-agent` |
| Dhruv (database) | `database-agent` | `database-verify-agent` | `database-fix-agent` |
| Naveen (nginx & SSL) | `nginx-agent` | `nginx-verify-agent` | `nginx-fix-agent` |
| Rohan (backend unit tests) | `backend-unit-test-agent` | `backend-unit-test-verify-agent` | `backend-unit-test-fix-agent` |
| Karan (backend integration) | `backend-integration-test-agent` | `backend-integration-test-verify-agent` | `backend-integration-test-fix-agent` |
| Aditya (backend functional) | `backend-functional-test-agent` | `backend-functional-test-verify-agent` | `backend-functional-test-fix-agent` |
| Priya (frontend unit) | `frontend-unit-test-agent` | `frontend-unit-test-verify-agent` | `frontend-unit-test-fix-agent` |
| Neha (frontend integration) | `frontend-integration-test-agent` | `frontend-integration-test-verify-agent` | `frontend-integration-test-fix-agent` |
| Anika (frontend functional / E2E) | `frontend-functional-test-agent` | `frontend-functional-test-verify-agent` | `frontend-functional-test-fix-agent` |
| Sanjay (system integration) | `system-integration-test-agent` | `system-integration-test-verify-agent` | `system-integration-test-fix-agent` |
| Surya (Swagger) | `swagger-agent` | `swagger-verify-agent` | `swagger-fix-agent` |
| Jaya (Javadoc) | `javadoc-agent` | `javadoc-verify-agent` | `javadoc-fix-agent` |
| Chetan (Postman / API collection) | `api-collection-agent` | `api-collection-verify-agent` | `api-collection-fix-agent` |
| Tara (API tests) | `api-test-agent` | `api-test-verify-agent` | `api-test-fix-agent` |
| Pawan (API performance) | `api-performance-test-agent` | `api-performance-test-verify-agent` | `api-performance-test-fix-agent` |
| Prakash (production audit) | — | `production-standards-agent` | `production-fix-agent` |

### Hermes `delegate_task` toolsets by agent type

| Agent type | Suggested Hermes toolsets | Blocked |
|------------|---------------------------|---------|
| Generate / fix | `terminal`, `file`, `code`, `web` | `delegate_task`, `memory`, `send_message` (inherited subagent defaults) |
| Verify (readonly) | `terminal`, `file` (read-only usage) | file write/patch, code execution that mutates |
| context-agent | `file`, `terminal` | — |
| fleet-host-agent | `terminal`, `file` | — |

---

## Shared state (unchanged between Cursor and Hermes)

| Path | Purpose |
|------|---------|
| `.sunny/context/state.json` | Phase, stage, iterations, blockers, resume checkpoint |
| `.sunny/context/*.md` | Per-stage summaries (Maya) |
| `.sunny/web/progress.json` | Live dashboard feed |
| `.sunny/web/agentprogress.html` | Progress UI |
| `.sunny/KNOWN_ISSUES.md` | Issues ledger (Leela) |
| `.env` | Secrets (generated at intake, append-only) |
| `graphify-out/` | Codebase knowledge graph |

Because state is **on disk**, a Hermes session can end and you can resume with:

```text
Sunny, resume
```

Phase −1 in the playbook reads `state.json` and continues from the last checkpoint.

---

## Project wiring

Before the first Sunny run on a project:

```bash
# 1. Clone your frontend/app repo
cd /opt/my-app

# 2. Symlink Sunny agent definitions (Pattern B from INSTALL.md)
ln -sf /opt/cursor-agents/.cursor /opt/my-app/.cursor

# 3. Bootstrap graphify once
graphify .

# 4. Point Hermes at the project
hermes config set terminal.cwd /opt/my-app
```

---

## How to invoke Sunny on Hermes

### Fleet host (first VPS only)

```text
Sunny, set up the fleet dashboard host.
Fleet domain: global.example.com
Certbot email: admin@example.com
```

### Backend build (any worker VPS)

```text
Sunny, build the backend for ./frontend.
Project domain: example.com
Fleet domain: global.example.com
```

### Resume after interrupt

```text
Sunny, resume
```

### Slash command

```text
/sunny build backend for ./frontend — domain example.com — fleet global.example.com
```

---

## Prerequisites on the VPS

| Requirement | Purpose |
|-------------|---------|
| Docker + Docker Compose | JHipster stack, PostgreSQL, Nginx |
| Graphify (`uv tool install graphifyy`) | Token-efficient codebase context |
| Hermes LLM provider configured | `hermes model` or `hermes setup --portal` |
| DNS A-records | Project domain + fleet domain → VPS IP |
| Ports 80, 443 open | HTTPS + Certbot |

See [`INSTALL.md`](INSTALL.md) and [`FLEET-QUICKSTART.md`](FLEET-QUICKSTART.md) in this repo.

---

## What is NOT mapped (Cursor-only today)

| Cursor feature | Hermes equivalent |
|----------------|-------------------|
| `.mdc` rules auto-injected by Cursor | Loaded explicitly via `/sunny` skill + `read_file` |
| Built-in Task subagent picker | Manual `delegate_task` per slug |
| Cursor UI agent panel | Hermes TUI / gateway / Jarvis HUD |
| `alwaysApply: false` on rules | Skill triggered by user message or `/sunny` |

---

## Related files

| File | Description |
|------|-------------|
| [`HERMES-SUNNY-GUIDE.md`](HERMES-SUNNY-GUIDE.md) | **Start here** — how Sunny works on Hermes, LLM/API prerequisites |
| [`HERMES-MAPPING.md`](HERMES-MAPPING.md) | Cursor → Hermes technical mapping |
| [`~/.hermes/skills/devops/sunny/SKILL.md`](../.hermes/skills/devops/sunny/SKILL.md) | Hermes skill Hermes loads at runtime |
| [`.cursor/rules/sunny-orchestrator.mdc`](.cursor/rules/sunny-orchestrator.mdc) | Authoritative orchestration playbook |
| [`.cursor/agents/README.md`](.cursor/agents/README.md) | Sunny system overview |
| [`.cursor/agents/AGENT-GUIDE.md`](.cursor/agents/AGENT-GUIDE.md) | Per-agent reference |

---

## Summary

- **cursor-agents** = agent definitions + playbook (designed for Cursor).
- **Hermes** = runtime that executes the same playbook using `delegate_task`.
- **No duplication** — Hermes reads `/opt/cursor-agents/.cursor/agents/*.md` as-is.
- **Same `.sunny/` state** — resume, dashboards, and fleet push work the same way.
- **You talk to Hermes** instead of opening Cursor on the VPS; the specialist roster is unchanged.
