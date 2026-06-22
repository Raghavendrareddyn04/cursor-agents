# Merge Gap Audit — Sunny + Deployment Remediation

Accurate status after reconciling `.cursor/` with `reference-new/`. Use this file (not the old `WHAT-WAS-LACKING.md`) to confirm the orchestration contract matches the agent files on disk.

**Last audited:** 2026-06-22

---

## 1. Executive summary

| Layer | Status |
|-------|--------|
| Deployment agent `.md` files + codename aliases | On disk |
| Bunny deploy-only orchestrator (#17–#23) | Aligned |
| Maya (`context-agent.md`) 23-stage contract | **Fixed** — phases, counters, dashboard map, deploy handoffs |
| Sunny full orchestrator (#1–#23) | **Fixed** — `sunny-orchestrator.mdc`, `sunny.md`, `ARCHITECTURE.md` |
| Isha + Kiran boundary (pre-arch vs post-arch) | **Clarified** in agent files + orchestrator |
| `deploy/` Minikube/Grafana assets | Present; current tree is a **superset** of `reference-new/deploy/` (see §4) |

Sunny can now track intake → Isha → Arjun → Kiran → … → Prakash (#17) → Rajesh→Om (#18–#23) without skipping deployment or marking `complete` early.

---

## 2. Blocking gaps (must fix before end-to-end Sunny run)

All items below were **blocking** before remediation; each is now closed with evidence.

| Gap | Resolution | Evidence |
|-----|------------|----------|
| `context-agent.md` had 16 stages; `production → complete` | Upgraded to 23 stages; deploy phases + `deploymentVerifyIterations` | `rg "counts.total: 23" .cursor/agents/context-agent.md` |
| Phase handoff skipped Kiran | `architecture approved → supabase_removal` | `rg "supabase_removal" .cursor/agents/context-agent.md` |
| Deploy never ran after production | `production approved → deployment_platform`; Om exit → `complete` | `rg "deployment_platform" .cursor/agents/context-agent.md` |
| `ARCHITECTURE.md` state machine ended at production | §6.5 + §10 deploy transitions; §8 sequence through Om | `.cursor/agents/ARCHITECTURE.md` |

---

## 3. Consistency gaps (docs / phrases / counters)

| Item | Target | Status |
|------|--------|--------|
| Dashboard stage count | 23 | `progress.json` writer uses `counts.total: 23` in `context-agent.md` |
| Bunny scope | #17–#23 | `bunny.md`, `bunny-orchestrator.mdc` |
| Om fix agent slug | `om-fix-agent` | No `deployment-fix-agent` in `.cursor/` (excl. `reference-new/`) |
| Om fix log artifact | `deployment-fix-log.md` | `sunny-orchestrator.mdc` Phase 5.6 |
| Final deploy counter | `deploymentVerifyIterations` | No `deploymentFinalVerifyIterations` in `.cursor/` |
| Kiran exit phrase | `Supabase removal complete.` | `AGENT-GUIDE.md`, `sunny-orchestrator.mdc`, `supabase-removal-verify-agent.md` |
| `agentprogress.html` fallback total | `0` (not `16`) | `.cursor/dashboard/agentprogress.html` |
| Codename dashboard #s | Prakash #17 … Om #23 | `prakash.md`, `rajesh.md`, … `om.md` |

---

## 4. Verified complete (with file evidence)

| Area | Evidence |
|------|----------|
| 23-stage dashboard map in Maya | `.cursor/agents/context-agent.md` — `frontend_sanitize` #2, `supabase_removal` #4, `production` #17, `deployment_*` #18–#23 |
| 25 verify/fix loops documented | `.cursor/agents/ARCHITECTURE.md` §0; `AGENT-GUIDE.md` system totals |
| Deployment canonical agents | `deployment-platform-*`, `server-provision-*`, `deployment-database-*`, `deployment-backend-*`, `deployment-edge-*`, `deployment-verify-agent`, `om-fix-agent` |
| Codename aliases | `rajesh.md`, `suresh.md`, `lakshmi.md`, `manoj.md`, `asha.md`, `om.md`, `prakash.md`, `maya.md`, `bunny.md` |
| Extras preserved | Isha trio, Leela (`issues-log-agent`), `bin/start-sunny.sh`, `bin/smoke-test-deploy.sh` |
| `deploy/` vs `reference-new/deploy/` | All reference paths exist under `deploy/`; current adds `service-template.yaml`, `jarvis`/`hermes` extras; `health-check.sh` is **stricter** than reference (pod grace window, retries) — **intentionally kept** |

---

## 5. Verification checklist

Run from repo root:

```bash
# 23-stage contract in Maya
rg -c "total:23" .cursor/agents/context-agent.md          # expect >= 1

# Deploy + supabase phases in Maya
rg "deployment_platform|supabase_removal" .cursor/agents/context-agent.md

# No stale 16-stage orchestration refs
rg "total:16|16 entries|16 stages" .cursor/                 # expect 0 (CSS #161b22 is OK)

# Unified counter name
rg "deploymentFinalVerifyIterations" .cursor/               # expect 0

# Wrong fix agent slug (active tree only)
rg "deployment-fix-agent" .cursor/ --glob "!reference-new/**"  # expect 0

# Sunny resume uses /23
rg "\(/23\)" .cursor/rules/sunny-orchestrator.mdc           # expect 1
```

### Manual smoke (operator)

1. `@sunny` intake on a test project — confirm `progress.json` has `counts.total: 23` and stage keys include `frontend_sanitize`, `supabase_removal`, `deployment_platform`.
2. `@bunny` with missing #1–#16 — confirm warning; with #17 `done` — confirm Rajesh launches at #18.
3. Open `.cursor/dashboard/agentprogress.html` with empty `counts` — bar should not assume 16 stages.

---

## 6. Delete when

Remove this file when:

- [ ] All grep checks above pass on `main` after your review
- [ ] One full Sunny dry-run (or colleague sign-off) confirms Maya phase transitions match the playbook
- [ ] `reference-new/` diff baseline no longer needed

---

## What we did NOT change

- Did not merge Isha + Kiran into one agent (different pipeline timing)
- Did not remove Bunny, Leela, or Sunny extras
- Did not overwrite project-specific `deploy/` extras (`jarvis`, `hermes`, `service-template.yaml`)
- Did not edit the remediation plan file or commit/push
