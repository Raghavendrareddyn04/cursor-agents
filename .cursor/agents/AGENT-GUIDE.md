# Sunny Agent Guide — What Every Agent Does

A complete, presentation-ready reference for **every agent** in the Sunny multi-agent system. Each entry gives the agent's **codename**, technical **slug**, whether it is **readonly**, the **pipeline stage** it belongs to, what it **reads**, what it **does**, what it **produces**, and (for verify agents) its exact **exit phrase**.

> Companion docs: [`README.md`](README.md) (how the system works), [`ARCHITECTURE.md`](ARCHITECTURE.md) (all diagrams), [`../rules/sunny-orchestrator.mdc`](../rules/sunny-orchestrator.mdc) (the executable playbook).

---

## How to read this guide

- **Codename** — the human name used when talking to the user (e.g. *Vikram*). A family shares a base name; its verify/fix variants add `Verify`/`Fix`.
- **Slug** — the technical agent id used to launch it (e.g. `jhipster-backend-agent`). This never changes.
- **readonly** — a readonly agent only audits and reports; it never edits code. Only readonly verify/audit agents may emit an exit phrase.
- **Exit phrase** — the exact string a verify agent emits when its loop is satisfied. The orchestrator matches it literally to advance.
- **Loop** — generate → verify → fix → re-verify, capped at **5 iterations** per loop before Sunny marks the stage `needs-attention` and continues where possible.

**System totals:** ~74 orchestrated agents + 2 standalone (`documentation`, `fleet-host-agent`) · 25 verify/fix loops · 25 readonly auditors.

**Pipeline order:**

```
Frontend sanitization (Isha) → Architecture (Arjun) → Supabase removal (Kiran)
→ Backend (JHipster, Vikram) → Database (Dhruv) → Nginx & SSL (Naveen)
→ Backend tests → Frontend tests → System integration tests
→ Swagger → Javadoc → API collection → API tests → API performance
→ Production audit (Prakash, #16)
→ Deploy platform (Rajesh) → Provision (Suresh) → Deploy DB (Lakshmi)
→ Deploy backend (Manoj) → Deploy edge (Asha) → Final deploy verify (Om)
→ Live (https://<project-domain>/)
```

## Graphify (token-efficient context)

Operators pre-install Graphify before Sunny runs:

```bash
uv tool install graphifyy
graphify install
```

- **Query first:** `graphify query "<question>"`, `graphify path "<A>" "<B>"`, `graphify explain "<symbol>"` on `graphify-out/` before grepping or reading large trees.
- **Update after changes:** code-changing agents run `graphify update <project-root>` after edits (readonly agents query only).
- See [`../rules/graphify.mdc`](../rules/graphify.mdc).

---

## Orchestration & shared memory

### Sunny — Orchestrator (`sunny`) · not readonly
- The conductor. Coordinates every agent via the Task tool, runs each verify/fix loop until the exact exit phrase, enforces the non-negotiables, and turns capped loops into visible `needs-attention` notifications unless a hard dependency requires a real stop.
- Never writes backend code itself — it delegates and gates.
- **Reads:** user request + `state.json` (loop status). **Produces:** orchestration plan, phase announcements, the final summary to the user.

### Maya — Context Agent (`context-agent`) · not readonly
- The system's shared memory and the **only** agent allowed to write to `.sunny/context/` and `.sunny/web/`. Every other agent hands its output to Maya for persistence.
- Summarizes each agent's output into structured reports, updates `state.json` (phase, counters, `lastVerdict`, `project` domain/email, `workflowStartedAt`, per-stage timing), and builds the trimmed handoff for the next agent.
- **Owns the live progress dashboard:** at intake she seeds `.sunny/web/` (dashboard + early publisher), and after **every** handoff she rewrites `.sunny/web/progress.json` (completed/pending stages, current phase, time consumed/estimated/remaining, ETA).
- **Bootstraps secrets:** at intake she auto-generates the root `.env` with strong random secrets (PostgreSQL password, JWT base64 secret, registry password) + `DOMAIN`/`ACME_EMAIL` from the prompt — so no human writes secrets. Idempotent (never clobbers an existing `.env`) and secret values are never logged to context, the dashboard, or chat.
- **Seeds an empty per-project** `.sunny/KNOWN_ISSUES.md` from the generic template (no issues copied from other projects).
- **Pushes to the fleet board (optional):** if `CENTRAL_DASHBOARD_URL` + `CENTRAL_PUSH_TOKEN` are set, after every handoff she runs `python3 .sunny/push-fleet.py` so this run appears on the global dashboard. Best-effort — a failed push never blocks the run.
- **The recovery point for resume:** she checkpoints `state.json`/`progress.json` **atomically after every handoff** (temp + rename), marking a stage `active` on entry and `done` on its exit verdict. On `sourceAgent: resume` she restores idempotently (recreates only what's missing, never regenerates secrets) so Sunny can continue an interrupted run from the exact stage it stopped at.
- **Reads:** the previous agent's raw output + current store. **Produces:** all `.sunny/context/*.md` reports + `state.json` + `.sunny/web/progress.json`.

### Leela — Issues Log Agent (`issues-log-agent`) · not readonly
- **Per-project issues ledger.** When any stage reports findings, blockers, or runtime/deployment problems, Sunny invokes Leela after Maya's capture. She appends structured entries (symptom, root cause, fix, prevention) to **`.sunny/KNOWN_ISSUES.md`** only — generic enough to help the **next** Lovable frontend, never copied from another repo's run.
- **Reads:** verify reports, blocker payloads, phase/stage, source agent. **Produces:** updated `.sunny/KNOWN_ISSUES.md` + a short Issues Log Report for Sunny.

---

## Inputs you give at kickoff & the live dashboard

**You only provide two domains** (plus the frontend path in the Sunny prompt):

| You give | Agents handle automatically |
|----------|------------------------------|
| **Project domain** | `DOMAIN`, default `ACME_EMAIL=admin@<domain>`, Nginx/SSL, local dashboard, all DB/JWT secrets |
| **Fleet domain** | `CENTRAL_DASHBOARD_URL`, `CENTRAL_PUSH_TOKEN` (fetched from `/api/fleet-config`), fleet pushes, `RUN_ID` |

Optional: Certbot email (else `admin@<project-domain>`). **Never** passwords, tokens, `.env`, or dashboard URLs.

- **Secrets are automatic:** Maya generates the gitignored `.env` with strong secrets at intake.
- **New secrets mid-run don't block agents:** any **internal** secret a later stage needs is appended to `.env` on the fly (strong `openssl` value, key name registered with Maya). An **external** third-party provider key (one no agent can mint) becomes a surfaced **"Action required"** item on the dashboard — the run keeps going; you drop the value into `.env` and that stage picks it up.
- **Non-blocking by default:** loops keep their hard iteration cap, but when a loop gives up or an external value is missing, it becomes a `needs-attention`/`actionRequired` **notification** and the pipeline continues. Only a hard technical dependency (e.g. backend won't build) causes a real stop.
- **Resumable by default:** if a run is interrupted (VPS reboot, closed session, crash), re-invoke **"Sunny, resume"** (or the original prompt). Sunny skips completed stages, re-enters the interrupted one (agents are idempotent), and continues with iteration counters and pending "action required" items intact. Nothing is lost — state is checkpointed to disk after every handoff.
- **Fleet (one domain):** deploy `.cursor/central/` once on the fleet host (`CENTRAL_DOMAIN` + `ACME_EMAIL` only — push token auto-generated). Every worker VPS gives Sunny **project domain + fleet domain**; Maya fetches the token and pushes progress.
- **Live progress dashboard (from agent #1):** completed/pending stages, current phase, time consumed, estimated total, time remaining — auto-refreshing every 5 minutes.
  - Early (intake → before Nginx): `http://<server-ip>:8787/agentprogress.html` (tiny static publisher).
  - From the Nginx stage on: `https://<domain>/agentprogress.html` over HTTPS (publisher retired).
  - Global/fleet: `https://<central-domain>/` (all runs, if the collector is deployed).
  - It is a read-only artifact in `.sunny/web/`; it never modifies the generated backend.
- **Service restarts:** the system runs as a Docker Compose stack. Code/config-changing agents rebuild + restart the affected services (`docker compose up -d --build <service>`) so changes take effect; the frontend is rebuilt when its API base URL moves to the domain (`/api`); Nginx uses a graceful reload; and the testing stages run against a freshly (re)started, healthy stack. The dashboard survives every restart (separate publisher + static mount + Nginx graceful reload).

---

## Stage 1 — Frontend sanitization (codename family: **Isha**)

### Isha — Frontend Sanitize Agent (`frontend-sanitize-agent`) · not readonly
- Runs **after intake and before architecture** on Lovable-exported frontends. Removes all Supabase and Lovable dependencies, integration folders, env vars, branding, and platform artifacts. Leaves compile-safe stubs only — JHipster JWT/API wiring is downstream work.
- **Reads:** `project-context.md`. **Produces:** sanitized frontend + `frontend-sanitize-summary.md`.

### Isha Verify — Frontend Sanitize Verify Agent (`frontend-sanitize-verify-agent`) · readonly
- Zero-tolerance audit: no Supabase/Lovable deps, dirs, or `src/` references; no Lovable branding; `npm run build` passes.
- **Reads:** `frontend-sanitize-summary.md`, `project-context.md`. **Exit phrase:** `Frontend sanitization complete.`

### Isha Fix — Frontend Sanitize Fix Agent (`frontend-sanitize-fix-agent`) · not readonly
- Fixes every finding from Isha Verify, then returns for re-review.
- **Reads:** `frontend-sanitize-verify-report.md`. **Produces:** fixes + `frontend-sanitize-fix-log.md`.

---

## Stage 2 — Architecture (codename family: **Arjun**)

### Arjun — Architecture Agent (`architecture-agent`) · not readonly
- Runs **after frontend sanitization**, before any JHipster generation. Turns the frontend into a concrete **architecture blueprint and project boilerplate**: service decomposition (bounded contexts), domain model, API contract map, auth design (JHipster JWT — not Supabase), and a **draft JDL** + scaffolding.
- Enforces microservices + PostgreSQL + no mock data at the design level.
- **Reads:** `project-context.md`, `frontend-sanitize-summary.md`. **Produces:** `architecture-summary.md`.

### Arjun Verify — Architecture Verify Agent (`architecture-verify-agent`) · readonly
- Reviews the blueprint: decomposition soundness, **API contract coverage** (every frontend call mapped), JDL consistency, and auth design.
- **Reads:** `architecture-summary.md`, `project-context.md`. **Exit phrase:** `Architecture approved.`

### Arjun Fix — Architecture Fix Agent (`architecture-fix-agent`) · not readonly
- Fixes every finding from Arjun Verify on the blueprint/JDL/boilerplate, then returns for re-review.
- **Reads:** `architecture-verify-report.md`. **Produces:** updated blueprint + `architecture-fix-log.md`.

---

## Stages 3–4 — Backend build & verify (codename family: **Vikram**)

### Vikram — JHipster Backend Agent (`jhipster-backend-agent`) · not readonly
- Generates the complete **JHipster microservices** backend from the approved blueprint: gateway + services + service registry, PostgreSQL + Liquibase, JWT/OAuth2 + RBAC, Docker, production config. No mock/fake data.
- **Reads:** `project-context.md`, `architecture-summary.md`. **Produces:** the backend + `backend-summary.md`.

### Vikram Verify — JHipster Verify Agent (`jhipster-verify-agent`) · readonly
- Audits the generated backend: REST/OpenAPI/RFC 7807 standards, security and vulnerabilities, microservices architecture integrity, and PostgreSQL/Liquibase correctness.
- **Reads:** `backend-summary.md`, `architecture-summary.md`, `project-context.md`. **Exit phrase:** `No issues found. Backend approved.`

### Vikram Fix — Issue Resolution Agent (`issue-resolution-agent`) · not readonly
- Fixes every finding Vikram Verify reports without weakening controls, rebuilds, runs tests, and returns for re-audit.
- **Reads:** `verify-report.md`. **Produces:** code fixes + `issue-resolution-log.md`.

---

## Stage 5 — Database (codename family: **Dhruv**)

### Dhruv — Database Agent (`database-agent`) · not readonly
- Runs after the backend is approved and before testing. **Hardens the database layer** of every service: PostgreSQL connections + HikariCP pooling, Liquibase migrations, constraints, indexes, relationships, schema standards. No mock data.
- **Reads:** `backend-summary.md`, `project-context.md`. **Produces:** `database-summary.md`.

### Dhruv Verify — Database Verify Agent (`database-verify-agent`) · readonly
- Audits schema/migrations/integrity and confirms migrations apply cleanly on a fresh PostgreSQL.
- **Reads:** `database-summary.md`, `backend-summary.md`. **Exit phrase:** `Database approved.`

### Dhruv Fix — Database Fix Agent (`database-fix-agent`) · not readonly
- Fixes every database finding (connections, schema, migrations, indexes, standards), then returns for re-audit.
- **Reads:** `database-verify-report.md`. **Produces:** fixes + `database-fix-log.md`.

---

## Stage 6 — Nginx & SSL edge (codename family: **Naveen**)

### Naveen — Nginx & SSL Edge Agent (`nginx-agent`) · not readonly
- Runs after the database is approved and **before** testing. Configures **Nginx** as the reverse proxy so the **frontend and gateway are reachable on the domain over HTTPS**, with **Certbot/Let's Encrypt** certificates and automatic renewal. No self-signed shortcuts in production.
- Uses the **intake-provided** domain + Certbot email (never a placeholder). Also **publishes the progress dashboard** on the domain (`https://<domain>/agentprogress.html` + `/progress.json`, from a read-only `.sunny/web` mount) and **retires the early publisher** so its port is free for Certbot.
- **Reads:** `backend-summary.md`, `database-summary.md`, `architecture-summary.md`, `project-context.md` (domain/routing). **Produces:** Nginx config, compose wiring, Certbot automation + `nginx-summary.md`.

### Naveen Verify — Nginx Verify Agent (`nginx-verify-agent`) · readonly
- Audits reverse-proxy routing, TLS termination, HTTP→HTTPS redirect, Certbot issuance/renewal, and security headers.
- **Reads:** `nginx-summary.md`, `backend-summary.md`, `project-context.md`. **Exit phrase:** `Nginx and SSL approved.`

### Naveen Fix — Nginx Fix Agent (`nginx-fix-agent`) · not readonly
- Fixes every nginx/SSL finding (routing, certs, renewal, headers, compose), then returns for re-audit.
- **Reads:** `nginx-verify-report.md`. **Produces:** fixes + `nginx-fix-log.md`.

---

## Stage 7 — Backend testing (three layers)

Generate all three layers once, then verify/fix each layer in order: **unit → integration → functional**. Target **≥95% line and branch coverage** per layer.

### Backend unit — codename family **Rohan**
- **Rohan — Backend Unit Test Agent** (`backend-unit-test-agent`) · not readonly — isolated JUnit 5 + Mockito tests for services, mappers, validators, utilities (all dependencies mocked).
- **Rohan Verify** (`backend-unit-test-verify-agent`) · readonly — audits unit-layer coverage and isolation. **Exit:** `Backend unit testing requirements satisfied.`
- **Rohan Fix** (`backend-unit-test-fix-agent`) · not readonly — closes unit-layer gaps only.

### Backend integration — codename family **Karan**
- **Karan — Backend Integration Test Agent** (`backend-integration-test-agent`) · not readonly — Spring Boot tests against **real PostgreSQL via Testcontainers**: repositories, custom queries, Liquibase migrations, transactions. No H2.
- **Karan Verify** (`backend-integration-test-verify-agent`) · readonly — audits real-DB integration coverage. **Exit:** `Backend integration testing requirements satisfied.`
- **Karan Fix** (`backend-integration-test-fix-agent`) · not readonly — closes integration-layer gaps only.

### Backend functional — codename family **Aditya**
- **Aditya — Backend Functional Test Agent** (`backend-functional-test-agent`) · not readonly — black-box HTTP tests (REST Assured / MockMvc): endpoints, auth flows, pagination, ProblemDetails contracts, gateway E2E.
- **Aditya Verify** (`backend-functional-test-verify-agent`) · readonly — audits endpoint/contract coverage. **Exit:** `Backend functional testing requirements satisfied.`
- **Aditya Fix** (`backend-functional-test-fix-agent`) · not readonly — closes functional-layer gaps only.

---

## Stage 8 — Frontend testing (three layers)

Same per-layer structure for the frontend: generate once, then **unit → integration/component → functional/E2E**. Target **≥95% line and branch coverage** per layer.

### Frontend unit — codename family **Priya**
- **Priya — Frontend Unit Test Agent** (`frontend-unit-test-agent`) · not readonly — isolated tests (Vitest/Jest) for pure functions, hooks/composables, stores, reducers, validators, formatters.
- **Priya Verify** (`frontend-unit-test-verify-agent`) · readonly — audits unit-layer coverage. **Exit:** `Frontend unit testing requirements satisfied.`
- **Priya Fix** (`frontend-unit-test-fix-agent`) · not readonly — closes unit-layer gaps only.

### Frontend integration/component — codename family **Neha**
- **Neha — Frontend Integration Test Agent** (`frontend-integration-test-agent`) · not readonly — Testing Library tests rendering components/pages with **mocked APIs (MSW)**, routing, and state; forms, events, loading/error states.
- **Neha Verify** (`frontend-integration-test-verify-agent`) · readonly — audits component-layer coverage. **Exit:** `Frontend integration testing requirements satisfied.`
- **Neha Fix** (`frontend-integration-test-fix-agent`) · not readonly — closes component-layer gaps only.

### Frontend functional/E2E — codename family **Anika**
- **Anika — Frontend Functional Test Agent** (`frontend-functional-test-agent`) · not readonly — Playwright (or Cypress) E2E covering critical journeys: login, core CRUD, navigation, error handling, in a real browser.
- **Anika Verify** (`frontend-functional-test-verify-agent`) · readonly — audits journey coverage. **Exit:** `Frontend functional testing requirements satisfied.`
- **Anika Fix** (`frontend-functional-test-fix-agent`) · not readonly — closes E2E gaps only.

---

## Stage 9 — System integration testing (codename family: **Sanjay**)

### Sanjay — System Integration Test Agent (`system-integration-test-agent`) · not readonly
- Tests the **whole system together** — the real frontend driving the real gateway + microservices, persisting to a real PostgreSQL database. Validates cross-tier journeys, auth propagation through the gateway, and end-to-end persistence.
- **Reads:** `project-context.md` (critical journeys), `architecture-summary.md`, `backend-summary.md`, `database-summary.md`, `nginx-summary.md`. **Produces:** `system-integration-test-report.md`.

### Sanjay Verify — System Integration Test Verify Agent (`system-integration-test-verify-agent`) · readonly
- Re-runs the full-stack suite on the real running stack; confirms every critical journey asserts UI + API + DB persistence (no mocked backend, no H2). **Exit:** `System integration testing requirements satisfied.`

### Sanjay Fix — System Integration Test Fix Agent (`system-integration-test-fix-agent`) · not readonly
- Closes cross-tier gaps, fixes auth-propagation/persistence assertions, stabilizes the stack, resolves flaky journeys.

---

## Stage 10 — Swagger / OpenAPI (codename family: **Surya**)

### Surya — Swagger Agent (`swagger-agent`) · not readonly
- Makes every REST endpoint discoverable and accurate via **springdoc-openapi** annotations + a JWT security scheme, and exports the `openapi.json`/`.yaml` spec per service. The spec feeds the API collection and API tests.
- **Produces:** annotations/config + exported spec + `swagger-report.md`.

### Surya Verify — Swagger Verify Agent (`swagger-verify-agent`) · readonly
- Confirms every public endpoint is in the spec, schemas/status codes/security match the code, and the exported spec is valid. **Exit:** `Swagger documentation requirements satisfied.`

### Surya Fix — Swagger Fix Agent (`swagger-fix-agent`) · not readonly
- Closes documentation gaps: missing annotations, wrong status codes/schemas, security gaps, spec export issues.

---

## Stage 11 — Javadoc (codename family: **Jaya**)

### Jaya — Javadoc Agent (`javadoc-agent`) · not readonly
- Documents every public Java API (controllers, services, DTOs/entities, exceptions, config) for **intent and behavior**, adds `package-info.java`, and configures a Javadoc build that passes with `failOnWarnings`.
- **Produces:** Javadoc + build config + `javadoc-report.md`.

### Jaya Verify — Javadoc Verify Agent (`javadoc-verify-agent`) · readonly
- Confirms coverage of public APIs and a clean build (`failOnWarnings`) with browsable HTML. **Exit:** `Javadoc documentation requirements satisfied.`

### Jaya Fix — Javadoc Fix Agent (`javadoc-fix-agent`) · not readonly
- Closes Javadoc gaps and resolves every build warning without lowering doclint.

---

## Stage 12 — API collection / Postman (codename family: **Chetan**)

### Chetan — API Collection Agent (`api-collection-agent`) · not readonly
- Builds a runnable **Postman collection + environments** generated from the OpenAPI spec (so it never drifts): a request per endpoint, automated login → token, collection-level bearer auth, test scripts, variable chaining, and Newman CI.
- **Produces:** `postman/` collection + environments + `api-collection-report.md`.

### Chetan Verify — API Collection Verify Agent (`api-collection-verify-agent`) · readonly
- Runs the collection via Newman; confirms a request exists for every endpoint, auth is automated, and the run is green. **Exit:** `API collection requirements satisfied.`

### Chetan Fix — API Collection Fix Agent (`api-collection-fix-agent`) · not readonly
- Adds missing requests, fixes auth/chaining/environments, and makes Newman pass green.

---

## Stage 13 — API tests / status (codename family: **Tara**)

### Tara — API Test Agent (`api-test-agent`) · not readonly
- Calls **every endpoint** on the real running stack (through the gateway) and asserts each returns its **correct HTTP status**: `200/201/204` on success, and the appropriate `400/401/403/404/409` for negative cases. Covers auth and role-protected access.
- **Produces:** runnable API tests + `api-test-report.md`.

### Tara Verify — API Test Verify Agent (`api-test-verify-agent`) · readonly
- Re-runs the suite; flags any endpoint not asserted or returning a wrong status (expected vs actual). **Exit:** `API testing requirements satisfied.`

### Tara Fix — API Test Fix Agent (`api-test-fix-agent`) · not readonly
- Adds missing assertions and fixes wrong-status endpoints at the root cause (validation, exception handler, `@PreAuthorize`) — never weakens an assertion to force a pass.

---

## Stage 14 — API performance (codename family: **Pawan**)

### Pawan — API Performance Test Agent (`api-performance-test-agent`) · not readonly
- Load-tests every key endpoint at **1, 10, 20, and 30 concurrent requests** against the real stack (k6/JMeter/Gatling/autocannon), capturing p50/p95/p99 latency, throughput, and error rate per level, and asserting thresholds.
- **Produces:** load scripts + results matrix + `api-performance-report.md`.

### Pawan Verify — API Performance Test Verify Agent (`api-performance-test-verify-agent`) · readonly
- Re-runs all four concurrency levels; confirms metrics captured and thresholds met (no 5xx/connection failures; p95 within budget). **Exit:** `API performance testing requirements satisfied.`

### Pawan Fix — API Performance Test Fix Agent (`api-performance-test-fix-agent`) · not readonly
- Remediates breaches at the root cause (indexes, N+1, pool tuning, caching, timeouts/circuit breakers) and re-tests; never relaxes a threshold to pass.

---

## Stage 15 — Production (codename family: **Prakash**)

### Prakash — Production Standards Agent (`production-standards-agent`) · readonly
- The final gate. **First** runs a completeness audit of every prior stage (a do's-and-don'ts check that each stage emitted its exact verdict and its artifacts exist on disk). **Then** audits security, production readiness, industry standards, performance, and data integrity. **Finally** produces one **comprehensive final report** that consolidates every prior report — including all test coverage, documentation, and API/performance results.
- **Reads:** **all** `.sunny/context/` files. **Exit phrase:** `Final approval granted. System is production-ready.` (otherwise `Final approval blocked.`).

### Prakash Fix — Production Fix Agent (`production-fix-agent`) · not readonly
- Remediates every blocking finding from Prakash (security, readiness, standards, performance) without weakening controls, rebuilds + tests, and returns for re-audit.

---

## Stages 16–22 — Production deployment (VPS / Minikube)

Runs **only after** `Final approval granted. System is production-ready.` Six sub-stages each follow **generate → verify → fix** (cap 5); the final stage is **verify → fix only** (Om). Same pattern as database and nginx.

| Step | Generate | Verify | Fix | Exit phrase |
|------|----------|--------|-----|-------------|
| 16 Platform | Rajesh — `deployment-platform-agent` | Rajesh Verify | Rajesh Fix | `Deployment platform approved.` |
| 17 Provision | Suresh — `server-provision-agent` | Suresh Verify | Suresh Fix | `Server provisioning approved.` |
| 18 Database | Lakshmi — `deployment-database-agent` | Lakshmi Verify | Lakshmi Fix | `Deployment database approved.` |
| 19 Backend | Manoj — `deployment-backend-agent` | Manoj Verify | Manoj Fix | `Deployment backend approved.` |
| 20 Edge | Asha — `deployment-edge-agent` | Asha Verify | Asha Fix | `Deployment edge approved.` |
| 21 Final | Om — `deployment-verify-agent` | Om | Om Fix | `Production deployment verified. System is live.` |

### Rajesh — Deployment Platform Agent (`deployment-platform-agent`) · not readonly
- Brings up the production platform: Minikube production profile, kube-prometheus-stack, Grafana + Sunny `progress.json` integration, and the entire `deploy/` scaffold (manifests, dashboards, scripts). Pre-authorized to install host tools; never asks the user for install permission. Targeted fix on failure (no `rm -rf` / `minikube delete` loops).
- **Produces:** `deployment-platform-summary.md`.

### Rajesh Verify — `deployment-platform-verify-agent` · readonly
- Audits Minikube, Helm, kube-prometheus-stack, Grafana provisioning, K8s skeleton. **Exit phrase:** `Deployment platform approved.`

### Rajesh Fix — `deployment-platform-fix-agent` · not readonly
- Closes platform verify findings without delete-redownload loops.

### Suresh — Server Provisioning Agent (`server-provision-agent`) · not readonly
- Installs VPS host dependencies (Java, Node, PostgreSQL client, Nginx, PM2, Docker, Minikube prereqs) via `deploy/scripts/provision.sh`. Idempotent — re-running is a safe no-op.
- **Produces:** `server-provision-summary.md`.

### Suresh Verify — `server-provision-verify-agent` · readonly
- Verifies every host tool is installed and prefetched. **Exit phrase:** `Server provisioning approved.`

### Suresh Fix — `server-provision-fix-agent` · not readonly
- Closes provisioning findings without destructive reinstalls.

### Lakshmi — Deployment Database Agent (`deployment-database-agent`) · not readonly
- Creates and hardens production PostgreSQL on the VPS host; generates/accepts `POSTGRES_PASSWORD` and records it in `.env` (never echoed). Documents the chosen host alias in `deployment-database-summary.md`.
- **Produces:** `deployment-database-summary.md`.

### Lakshmi Verify — `deployment-database-verify-agent` · readonly
- Verifies the production DB, schema, and that `deploy/scripts/sync-secrets.sh` wired the K8s `sunny-postgres` secret. **Exit phrase:** `Deployment database approved.`

### Lakshmi Fix — `deployment-database-fix-agent` · not readonly
- Closes deployment DB findings.

### Manoj — Deployment Backend Agent (`deployment-backend-agent`) · not readonly
- Deploys every JHipster microservice to Minikube: Deployment + Service + ConfigMap + ServiceMonitor per service, with **liveness + readiness + startup probes**, **CPU/memory requests + limits**, distinct ports, and ClusterIP (no public NodePort for internal services). Completes the per-service rows in `deploy/port-map.md`. Uses `kubectl apply -k deploy/minikube/`.
- **Produces:** `deployment-backend-summary.md`.

### Manoj Verify — `deployment-backend-verify-agent` · readonly
- Verifies pods, probes, limits, distinct ports, Prometheus scrape annotations, and that `port-map.md` matches live state. **Exit phrase:** `Deployment backend approved.`

### Manoj Fix — `deployment-backend-fix-agent` · not readonly
- Closes backend deploy findings.

### Asha — Deployment Edge Agent (`deployment-edge-agent`) · not readonly
- Configures **host Nginx** (TLS via Certbot/Let's Encrypt), **PM2** for the rebuilt frontend, and the routes: `/` → PM2 frontend, `/api` → Minikube gateway NodePort, `/progress.json` + `/agentprogress.html` → static mount, `/grafana` → Grafana NodePort 30300. Verifies HTTPS works and the dashboard survives reloads.
- **Produces:** `deployment-edge-summary.md`.

### Asha Verify — `deployment-edge-verify-agent` · readonly
- Verifies routing, TLS, PM2, `/grafana` proxy. **Exit phrase:** `Deployment edge approved.`

### Asha Fix — `deployment-edge-fix-agent` · not readonly
- Closes edge findings.

### Om — Deployment Verify Agent (`deployment-verify-agent`) · readonly
- **Final** collective production audit: confirms all five prior per-step exit phrases, runs `deploy/scripts/health-check.sh` (kubectl/minikube, pod readiness, gateway `/management/health`, public `/api`, Grafana `/api/health`, progress.json), and verifies live state matches `deploy/port-map.md`. **Exit phrase:** `Production deployment verified. System is live.`

### Om Fix — `om-fix-agent` · not readonly
- Closes cross-cutting Om findings without weakening production controls.

---

## Standalone (not orchestrated by Sunny)

### Deepa — Documentation Agent (`documentation`) · not readonly
- A one-shot, do-everything documentation specialist that produces complete Swagger/OpenAPI docs, Postman collections + environments (Newman CI), and Javadoc for any Spring Boot / JHipster codebase. Run it on demand; it is **not** part of the Sunny pipeline (the orchestrated Surya/Chetan/Jaya families cover those concerns inside the pipeline).

### Hari — Fleet Host Agent (`fleet-host-agent`) · not readonly
- A **run-once** agent that deploys the **global/fleet dashboard** on the host owning the **fleet domain**. It brings up the central collector (`.cursor/central/`): writes `.env` (token auto-generated), issues the Let's Encrypt cert, starts the collector + Nginx stack, schedules renewal, and validates `https://<fleet-domain>/` end to end. Idempotent and self-healing (reports DNS/port blockers instead of hanging).
- Invoke it **once** on the fleet host: *"Sunny, set up the fleet dashboard host. Fleet domain: `global.mememates.org` (admin@…)."* Worker VPSs then only need the fleet domain at kickoff — Maya fetches the push token from `/api/fleet-config` automatically. Not part of the per-project pipeline; does not use the Context Agent.

---

## Quick reference — codename → slug → exit phrase

| Codename | Slug | Readonly | Exit phrase (verify agents) |
|----------|------|----------|------------------------------|
| Sunny | `sunny` | No | — |
| Maya | `context-agent` | No | — |
| Leela | `issues-log-agent` | No | — |
| Isha | `frontend-sanitize-agent` | No | — |
| Isha Verify | `frontend-sanitize-verify-agent` | Yes | `Frontend sanitization complete.` |
| Isha Fix | `frontend-sanitize-fix-agent` | No | — |
| Arjun | `architecture-agent` | No | — |
| Arjun Verify | `architecture-verify-agent` | Yes | `Architecture approved.` |
| Arjun Fix | `architecture-fix-agent` | No | — |
| Vikram | `jhipster-backend-agent` | No | — |
| Vikram Verify | `jhipster-verify-agent` | Yes | `No issues found. Backend approved.` |
| Vikram Fix | `issue-resolution-agent` | No | — |
| Dhruv | `database-agent` | No | — |
| Dhruv Verify | `database-verify-agent` | Yes | `Database approved.` |
| Dhruv Fix | `database-fix-agent` | No | — |
| Naveen | `nginx-agent` | No | — |
| Naveen Verify | `nginx-verify-agent` | Yes | `Nginx and SSL approved.` |
| Naveen Fix | `nginx-fix-agent` | No | — |
| Rohan | `backend-unit-test-agent` | No | — |
| Rohan Verify | `backend-unit-test-verify-agent` | Yes | `Backend unit testing requirements satisfied.` |
| Rohan Fix | `backend-unit-test-fix-agent` | No | — |
| Karan | `backend-integration-test-agent` | No | — |
| Karan Verify | `backend-integration-test-verify-agent` | Yes | `Backend integration testing requirements satisfied.` |
| Karan Fix | `backend-integration-test-fix-agent` | No | — |
| Aditya | `backend-functional-test-agent` | No | — |
| Aditya Verify | `backend-functional-test-verify-agent` | Yes | `Backend functional testing requirements satisfied.` |
| Aditya Fix | `backend-functional-test-fix-agent` | No | — |
| Priya | `frontend-unit-test-agent` | No | — |
| Priya Verify | `frontend-unit-test-verify-agent` | Yes | `Frontend unit testing requirements satisfied.` |
| Priya Fix | `frontend-unit-test-fix-agent` | No | — |
| Neha | `frontend-integration-test-agent` | No | — |
| Neha Verify | `frontend-integration-test-verify-agent` | Yes | `Frontend integration testing requirements satisfied.` |
| Neha Fix | `frontend-integration-test-fix-agent` | No | — |
| Anika | `frontend-functional-test-agent` | No | — |
| Anika Verify | `frontend-functional-test-verify-agent` | Yes | `Frontend functional testing requirements satisfied.` |
| Anika Fix | `frontend-functional-test-fix-agent` | No | — |
| Sanjay | `system-integration-test-agent` | No | — |
| Sanjay Verify | `system-integration-test-verify-agent` | Yes | `System integration testing requirements satisfied.` |
| Sanjay Fix | `system-integration-test-fix-agent` | No | — |
| Surya | `swagger-agent` | No | — |
| Surya Verify | `swagger-verify-agent` | Yes | `Swagger documentation requirements satisfied.` |
| Surya Fix | `swagger-fix-agent` | No | — |
| Jaya | `javadoc-agent` | No | — |
| Jaya Verify | `javadoc-verify-agent` | Yes | `Javadoc documentation requirements satisfied.` |
| Jaya Fix | `javadoc-fix-agent` | No | — |
| Chetan | `api-collection-agent` | No | — |
| Chetan Verify | `api-collection-verify-agent` | Yes | `API collection requirements satisfied.` |
| Chetan Fix | `api-collection-fix-agent` | No | — |
| Tara | `api-test-agent` | No | — |
| Tara Verify | `api-test-verify-agent` | Yes | `API testing requirements satisfied.` |
| Tara Fix | `api-test-fix-agent` | No | — |
| Pawan | `api-performance-test-agent` | No | — |
| Pawan Verify | `api-performance-test-verify-agent` | Yes | `API performance testing requirements satisfied.` |
| Pawan Fix | `api-performance-test-fix-agent` | No | — |
| Prakash | `production-standards-agent` | Yes | `Final approval granted. System is production-ready.` |
| Prakash Fix | `production-fix-agent` | No | — |
| Kiran | `supabase-removal-agent` | No | — |
| Kiran Verify | `supabase-removal-verify-agent` | Yes | `Supabase and Lovable removal complete.` |
| Kiran Fix | `supabase-removal-fix-agent` | No | — |
| Rajesh | `deployment-platform-agent` | No | — |
| Rajesh Verify | `deployment-platform-verify-agent` | Yes | `Deployment platform approved.` |
| Rajesh Fix | `deployment-platform-fix-agent` | No | — |
| Suresh | `server-provision-agent` | No | — |
| Suresh Verify | `server-provision-verify-agent` | Yes | `Server provisioning approved.` |
| Suresh Fix | `server-provision-fix-agent` | No | — |
| Lakshmi | `deployment-database-agent` | No | — |
| Lakshmi Verify | `deployment-database-verify-agent` | Yes | `Deployment database approved.` |
| Lakshmi Fix | `deployment-database-fix-agent` | No | — |
| Manoj | `deployment-backend-agent` | No | — |
| Manoj Verify | `deployment-backend-verify-agent` | Yes | `Deployment backend approved.` |
| Manoj Fix | `deployment-backend-fix-agent` | No | — |
| Asha | `deployment-edge-agent` | No | — |
| Asha Verify | `deployment-edge-verify-agent` | Yes | `Deployment edge approved.` |
| Asha Fix | `deployment-edge-fix-agent` | No | — |
| Om | `deployment-verify-agent` | Yes | `Production deployment verified. System is live.` |
| Om Fix | `om-fix-agent` | No | — |
| Deepa | `documentation` | No | — (standalone) |
| Hari | `fleet-host-agent` | No | — (standalone; deploys global dashboard) |
