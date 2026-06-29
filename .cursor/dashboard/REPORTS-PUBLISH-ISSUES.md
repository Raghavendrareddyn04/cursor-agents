# Fleet — Reports Publish (Neel) Known Issues

> **Source:** First production run on `ascenta-core-hub` / `lender.qualityoutsidethebox.org` (2026-06-29).  
> **Use:** Read before running `reports-publish-agent` (Neel) or debugging missing/stale report URLs.  
> **Per-project log:** Leela still appends run-specific entries to `.sunny/KNOWN_ISSUES.md`; this file is the **fleet template** for recurring reports-hosting failures.

Copy this file to new projects only as **reference** — do not paste project-specific paths into `.sunny/KNOWN_ISSUES.md` verbatim.

---

## Issue RP-001 — Pipeline complete but reports never published (watchdog skip)

**Severity:** High  
**Phase:** Post-#23 / `phase: complete`  
**Agent:** watchdog (`sunny-cursor-run.sh`)

### Symptom
- `state.json` shows `phase: complete` and deployment verified.
- `reports-manifest.json` mtime is **hours/days older** than latest `.sunny/context/*.md`.
- `production-report.html` still shows an old iteration (e.g. iter 2 blocked) while `production-report.md` shows iter 5 granted.
- `reportsPublishedAt` missing from `state.json`.

### Root cause
Watchdog treated `phase: complete` as terminal and **exited without running** full `publish-reports.sh`. During active runs it only ran `write-reports-html.py` (partial HTML), not test catalog or artifacts.

### Fix
1. Run `bash .sunny/publish-reports.sh --verify` from project root (or `bin/seed-sunny-reports.sh` first if scripts missing).
2. Ensure `sunny-cursor-run.sh` watchdog backfills when `phase: complete` and `!reportsPublishedAt`.
3. Sunny Phase 5.7: launch Neel **before** setting `phase: complete` on new runs.

### Prevention
- Orchestrator must not mark `complete` until Neel exit phrase: `Reports published and verified.`
- After `git pull` in cursor-agents, run `bin/seed-sunny-reports.sh /opt/your-project`.

---

## Issue RP-002 — `/test-catalog.html` and `/artifacts/*` return 404 on live domain

**Severity:** High  
**Phase:** Phase 5.7 (Neel verify)  
**Agent:** reports-publish-agent / edge nginx

### Symptom
- `curl -I https://<domain>/reports.html` → 200
- `curl -I https://<domain>/test-catalog.html` → **404**
- `curl -I https://<domain>/artifacts/postman/collection.json` → **404**
- Files exist under `.sunny/web/` and `/var/www/sunny` symlink is correct.

### Root cause
Host **nginx** `sites-available` config was installed **before** artifact/test-catalog `location` blocks were added to `deploy/nginx/production.conf`. Symlink serves files, but nginx never had routes for new paths.

### Fix
1. Update site config from repo `deploy/nginx/production.conf` (must include `location /artifacts/`, `location = /test-catalog.html`, etc.).
2. `nginx -t && systemctl reload nginx`
3. Re-run `bash .sunny/publish-reports.sh --verify`

### Prevention
- `install-production-edge.sh` should use `publish-reports.sh --verify` after install.
- Neel agent: on 404, reload nginx once then retry verify.

---

## Issue RP-003 — Production report verdict badge shows `blocked` after iter 5 granted

**Severity:** Medium  
**Phase:** Reports HTML build  
**Agent:** `write-reports-html.py`

### Symptom
- `production-report.md` has `## Final verdict` → **Final approval granted**
- `reports-manifest.json` entry for `production-report` has `"verdict": "blocked"`
- HTML still lists prior iteration blocked verdicts in body (expected), but **sidebar badge** is wrong.

### Root cause
`verdict_for()` scanned full markdown and matched **blocked** from prior iteration history before the final granted verdict.

### Fix
Parse `## Final verdict` section first; prefer tail phrases `Final approval granted`, `Production deployment verified`, `System is live`.

### Prevention
- Re-run `python3 .sunny/write-reports-html.py` after fix; confirm manifest `verdict: granted` for production-report.

---

## Issue RP-004 — `reportsUrls` not in progress dashboard after manual publish

**Severity:** Medium  
**Phase:** Post-complete backfill  
**Agent:** Maya / `build-progress-from-state.py`

### Symptom
- `publish-reports.sh --verify` succeeded.
- `state.json` has `reportsUrls` but `agentprogress.html` has no **Published reports** card.

### Root cause
`progress.json` was not rebuilt after `merge_state_reports`, or `build-progress-from-state.py` did not pass through `reportsUrls` / `reportsStats`.

### Fix
```bash
python3 .sunny/build-progress-from-state.py
```
Confirm `progress.json` contains `reportsUrls` and `reportsStats`.

### Prevention
- `publish-reports.sh --verify` should call `build-progress-from-state.py` on success.
- `agentprogress.html` template in `.cursor/dashboard/` must include Published reports panel (synced from fleet).

---

## Issue RP-005 — JaCoCo artifact missing for one service (15/16 available)

**Severity:** Low  
**Phase:** Artifacts manifest  
**Agent:** `build-artifacts-manifest.py`

### Symptom
- `artifacts-manifest.json` shows one service (e.g. `storeService`) `available: false` with note "Run mvn verify to generate".

### Root cause
JaCoCo symlinks only when `{service}/target/site/jacoco/` exists on disk. Service was not built or has no `target/` after deploy.

### Fix
Run `mvn verify` for that module, then `bash .sunny/publish-reports.sh`.

### Prevention
- Expected on fresh VPS until full verify; not a Neel hard-fail unless user requires all 6 JaCoCo reports.

---

## Issue RP-006 — Test catalog counts differ from Sunny stage reports

**Severity:** Low (informational)  
**Phase:** Test catalog build  
**Agent:** `build-test-catalog.py`

### Symptom
- Catalog shows e.g. **1927** BE unit tests; Sunny `backend-test-report` says **~954**.
- FE integration catalog **93** vs report **~127**.

### Root cause
Catalog is **source-derived** (every `@Test` / `it()` in repo). Sunny reports count **executed** Surefire/Vitest tests or use different layer boundaries (e.g. `FunctionalTest.java` classified as unit in catalog).

### Fix
No fix required unless parsing rules are wrong. Use catalog for **inventory**; use stage reports for **CI execution counts**.

### Prevention
- Document in test-catalog UI that totals are from source parse, not last test run.

---

## Issue RP-007 — Missing `.sunny/` scripts on new project (orchestrator self-test fail)

**Severity:** High  
**Phase:** Phase −2 self-test  
**Agent:** Sunny orchestrator

### Symptom
```
MISSING: .sunny/publish-reports.sh
```
or Neel fails immediately — script not found.

### Root cause
Project created before reports toolchain was added to fleet; only `.cursor` symlinked from cursor-agents, not per-project `.sunny/` scripts.

### Fix
```bash
/opt/cursor-agents/bin/seed-sunny-reports.sh /opt/your-project
```

### Prevention
- Run `seed-sunny-reports.sh` after `install-linux.sh` or on intake (Maya step 4 extension).
- Keep templates in `cursor-agents/.cursor/sunny/`.

---

## Quick verification checklist (Neel / operator)

```bash
DOMAIN=lender.qualityoutsidethebox.org  # or from .env

# 1. Scripts present
test -x .sunny/publish-reports.sh && test -f .sunny/build-test-catalog.py

# 2. Symlink
readlink -f /var/www/sunny  # → .../project/.sunny/web

# 3. Build + verify
bash .sunny/publish-reports.sh --verify

# 4. State
python3 -c "import json; s=json.load(open('.sunny/context/state.json')); print(s.get('reportsPublishedAt'), s.get('reportsUrls'))"

# 5. Live URLs
curl -sI -H "Host: $DOMAIN" http://127.0.0.1/reports.html | head -1
curl -sI -H "Host: $DOMAIN" http://127.0.0.1/test-catalog.html | head -1
curl -sI -H "Host: $DOMAIN" http://127.0.0.1/artifacts/postman/collection.json | head -1
```

Expected: all HTTP/1.1 200 (or 301→200). `reportsPublishedAt` set in `state.json`.
