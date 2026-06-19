# Sunny Orchestrator — Architecture & Workflow

Visual reference for the Sunny multi-agent system: component architecture, control flow, the verification/testing/production loops, shared-memory data flow, and state transitions.

> For prose explanation and run instructions, see [`README.md`](README.md).

---

## 0. System at a glance

**54 orchestrated agents** (plus 2 standalone agents: `documentation` and `fleet-host-agent`), driven through **18 bounded verify/fix loops**.

| Group | Count | Agents |
|-------|-------|--------|
| Orchestration & memory | 3 | `sunny`, `context-agent`, `issues-log-agent` |
| Frontend sanitization | 3 | `frontend-sanitize-agent`, `frontend-sanitize-verify-agent` (readonly), `frontend-sanitize-fix-agent` |
| Architecture & boilerplate | 3 | `architecture-agent`, `architecture-verify-agent` (readonly), `architecture-fix-agent` |
| Backend build & verify | 3 | `jhipster-backend-agent`, `jhipster-verify-agent` (readonly), `issue-resolution-agent` |
| Database | 3 | `database-agent`, `database-verify-agent` (readonly), `database-fix-agent` |
| Nginx & SSL edge | 3 | `nginx-agent`, `nginx-verify-agent` (readonly), `nginx-fix-agent` |
| Backend tests (3 layers × gen/verify/fix) | 9 | `backend-{unit,integration,functional}-test-agent` + `-verify-agent` (readonly) + `-fix-agent` |
| Frontend tests (3 layers × gen/verify/fix) | 9 | `frontend-{unit,integration,functional}-test-agent` + `-verify-agent` (readonly) + `-fix-agent` |
| System integration tests (collective) | 3 | `system-integration-test-agent`, `system-integration-test-verify-agent` (readonly), `system-integration-test-fix-agent` |
| Swagger / OpenAPI docs | 3 | `swagger-agent`, `swagger-verify-agent` (readonly), `swagger-fix-agent` |
| Javadoc | 3 | `javadoc-agent`, `javadoc-verify-agent` (readonly), `javadoc-fix-agent` |
| API collection (Postman) | 3 | `api-collection-agent`, `api-collection-verify-agent` (readonly), `api-collection-fix-agent` |
| API tests (status) | 3 | `api-test-agent`, `api-test-verify-agent` (readonly), `api-test-fix-agent` |
| API performance (1/10/20/30) | 3 | `api-performance-test-agent`, `api-performance-test-verify-agent` (readonly), `api-performance-test-fix-agent` |
| Production | 2 | `production-standards-agent` (readonly), `production-fix-agent` |
| Standalone (not orchestrated) | 2 | `documentation`, `fleet-host-agent` |

- **18 verify/fix loops:** frontend sanitization + architecture + backend code + database + nginx & SSL + 3 backend test layers + 3 frontend test layers + system integration + Swagger + Javadoc + API collection + API tests + API performance + production.
- **18 readonly auditors:** `frontend-sanitize-verify-agent`, `architecture-verify-agent`, `jhipster-verify-agent`, `database-verify-agent`, `nginx-verify-agent`, the 6 per-layer test-verify agents, `system-integration-test-verify-agent`, the 5 documentation/API verify agents, and `production-standards-agent`.
- **Pipeline order:** frontend sanitization → architecture → backend (JHipster) → database → nginx & SSL (domain + Certbot) → backend tests → frontend tests → system integration tests → Swagger → Javadoc → API collection → API tests → API performance → production.
- **Graphify:** operators pre-install graphify (`uv tool install graphifyy`); agents query `graphify-out/` first and run `graphify update` after code changes to reduce token use.
- **Domain at intake:** the user provides **project domain + fleet domain** only; agents derive `ACME_EMAIL` (`admin@<project-domain>` by default), all secrets, fleet URL, and push token (fetched from `/api/fleet-config`).
- **Secrets auto-generated:** at intake Maya creates a gitignored root `.env` with strong random secrets (PostgreSQL, JWT, registry); no human writes secrets and values are never logged. Downstream agents consume them as `${VAR}` and never hardcode literals.
- **Live progress dashboard:** web-visible from the first agent — early via a static publisher (`http://<server-ip>:8787/agentprogress.html`), then on the domain (`https://<domain>/agentprogress.html`). Maya rewrites `.sunny/web/progress.json` every handoff; read-only, never touches the generated backend. "Action required" asks (e.g. an external key) surface here without halting the run.
- **Fleet / global dashboard:** every VPS uses the **same** `.cursor/` agents but runs **independently** (own project, domain, `.env`, `RUN_ID`). Each optionally **pushes** progress to a central collector (`.cursor/central/`, deployed once), so all runs show on one global board at `https://<central-domain>/` — one card per run, best-effort, never blocking.
- **Non-blocking by default:** loops still have a hard iteration cap, but when a loop gives up or an external value is missing, it becomes a `needs-attention`/`actionRequired` **notification** and the pipeline continues; only a hard technical dependency causes a real stop.
- **Resumable by default:** all state lives on disk (`state.json` + context summaries + `.env` + generated code), checkpointed atomically after every handoff. On (re)invocation Sunny runs a **resume check** (Phase −1): if a prior run is incomplete it skips done stages, re-enters the interrupted one, and continues with counters intact. Every agent is idempotent (patches, never duplicates), so re-running a stage is safe; Docker services auto-restart (`restart: unless-stopped`).
- **Service lifecycle:** the stack runs via Docker Compose; code/config-changing agents rebuild + restart the affected services (`docker compose up -d --build <service>`), Nginx uses graceful reload, and testing stages run against a fresh, healthy stack. The dashboard survives every restart (decoupled static mount + separate publisher).
- **Production agent** audits every prior stage's completeness (do's and don'ts) and emits one comprehensive final report.
- **Every loop:** independent exit phrase + iteration counter, capped at **5** — then `needs-attention` notifications and continue by default (hard stop only on a technical dependency).
- **One writer of shared memory:** `context-agent` owns `.sunny/context/` and `.sunny/web/`.
- **Per-project issues ledger:** `issues-log-agent` (Leela) owns `.sunny/KNOWN_ISSUES.md` when problems are reported.

### Agent codenames

Each agent has a human codename; a family shares a base name and its verify/fix variants add `Verify`/`Fix`.

| Family | Base | Verify | Fix |
|--------|------|--------|-----|
| frontend sanitization | Isha | Isha Verify | Isha Fix |
| architecture | Arjun | Arjun Verify | Arjun Fix |
| backend build | Vikram | Vikram Verify | Vikram Fix |
| database | Dhruv | Dhruv Verify | Dhruv Fix |
| nginx & SSL | Naveen | Naveen Verify | Naveen Fix |
| backend unit / integration / functional | Rohan / Karan / Aditya | + Verify | + Fix |
| frontend unit / integration / functional | Priya / Neha / Anika | + Verify | + Fix |
| system integration | Sanjay | Sanjay Verify | Sanjay Fix |
| Swagger / Javadoc | Surya / Jaya | + Verify | + Fix |
| API collection / tests / performance | Chetan / Tara / Pawan | + Verify | + Fix |
| production | Prakash | Prakash (audit) | Prakash Fix |

**Singletons:** Sunny (orchestrator) · Maya (context/shared memory) · Leela (issues log) · Deepa (standalone documentation) · Hari (standalone fleet-host — deploys the global dashboard). Full mapping: [`README.md`](README.md#agent-codenames).

---

## 1. System architecture (pipeline order)

The agents run as an **ordered pipeline**: sanitize the Lovable frontend (remove Supabase/Lovable), design the architecture, generate the backend, verify and fix it, harden the database, configure Nginx & SSL, then generate and verify tests (backend, then frontend), then collective system integration tests (frontend + backend + database together), then the documentation & API stages (Swagger, Javadoc, API collection, API status tests, API performance), then the final production audit. **16 dashboard stages** (intake + 15 execution stages). The Driver launches each stage via the Task tool; Maya persists output after every stage; Leela logs actionable problems to `.sunny/KNOWN_ISSUES.md`.

```mermaid
flowchart TB
    User([User]) --> Driver["Driver: main chat agent<br/>follows sunny-orchestrator.mdc"]

    subgraph pipeline [Execution Pipeline - top to bottom]
        direction TB
        S0["Stage 1 - Frontend sanitization<br/>frontend-sanitize-agent<br/>verify: frontend-sanitize-verify-agent (readonly)<br/>fix: frontend-sanitize-fix-agent"]
        S1["Stage 2 - Architecture & boilerplate<br/>architecture-agent<br/>verify: architecture-verify-agent (readonly)<br/>fix: architecture-fix-agent"]
        S2["Stage 3 - Generate backend<br/>jhipster-backend-agent"]
        S3["Stage 4 - Verify backend (readonly)<br/>jhipster-verify-agent<br/>fix: issue-resolution-agent"]
        SD["Stage 5 - Database hardening<br/>database-agent<br/>verify: database-verify-agent (readonly)<br/>fix: database-fix-agent"]
        SN["Stage 6 - Nginx & SSL edge<br/>nginx-agent: reverse proxy + domain + Certbot<br/>verify: nginx-verify-agent (readonly)<br/>fix: nginx-fix-agent"]
        SB["Stage 7 - Backend tests<br/>per layer: unit, integration, functional<br/>each layer has its own verify (readonly) + fix agent"]
        SF["Stage 8 - Frontend tests<br/>per layer: unit, integration, functional<br/>each layer has its own verify (readonly) + fix agent"]
        SI["Stage 9 - System integration tests (collective)<br/>frontend + backend + PostgreSQL together<br/>system-integration-test-agent<br/>verify: system-integration-test-verify-agent (readonly)<br/>fix: system-integration-test-fix-agent"]
        SDOC["Stages 10-14 - Documentation & API<br/>Swagger -> Javadoc -> API collection -> API tests -> API performance<br/>each: generate + verify (readonly) + fix loop"]
        S5["Stage 15 - Production (readonly audit)<br/>production-standards-agent: audits ALL prior outputs<br/>+ comprehensive final report<br/>fix: production-fix-agent"]
        S0 --> S1 --> S2 --> S3 --> SD --> SN --> SB --> SF --> SI --> SDOC --> S5
    end

    Driver -->|launches each stage in order| pipeline

    subgraph memory [Shared Memory and Issues]
        Ctx["context-agent"]
        Store[(".sunny/context/<br/>reports + state.json")]
        Leela["issues-log-agent<br/>.sunny/KNOWN_ISSUES.md"]
        Ctx <-->|read / write| Store
    end

    pipeline -.output after each stage.-> Ctx
    Ctx -.trimmed handoff to next stage.-> pipeline
    pipeline -.findings / blockers.-> Leela
```

### 1.1 Agents and their responsibilities

Each agent with its key points, grouped by stage. Readonly agents only audit and report; all others write code/tests/config.

```mermaid
flowchart TB
    subgraph orch [Orchestration and Memory]
        direction LR
        DRV["Sunny / Driver<br/>• Orchestrates all 18 verify/fix loops<br/>• Matches exact exit phrases<br/>• Enforces quality gates<br/>• Invokes Leela on findings"]
        CTX["context-agent<br/>• Sole writer of .sunny/context<br/>• Structured summaries + state.json<br/>• Trims handoffs to next agent<br/>• Tracks phase + iteration counters"]
        LEL["issues-log-agent<br/>• Per-project KNOWN_ISSUES.md<br/>• Symptom / cause / fix / prevention"]
    end

    subgraph sSan [Stage 1 - Frontend sanitization]
        direction LR
        ISH["frontend-sanitize-agent<br/>• Remove Supabase/Lovable deps<br/>• Strip branding + integrations<br/>• Compile-safe stubs only"]
        ISHV["frontend-sanitize-verify-agent - readonly<br/>• Zero supabase/lovable in src/<br/>• Build passes<br/>• Exit: Frontend sanitization complete."]
        ISHF["frontend-sanitize-fix-agent<br/>• Closes sanitization findings"]
        ISH --> ISHV
        ISHV -->|issues| ISHF --> ISHV
    end

    subgraph sArch [Stage 2 - Architecture and boilerplate]
        direction LR
        ARC["architecture-agent<br/>• Service decomposition (bounded contexts)<br/>• Domain model + API contract map<br/>• Draft JDL + boilerplate/scaffolding<br/>• Microservices, PostgreSQL, no mock data"]
        ARCV["architecture-verify-agent - readonly<br/>• Decomposition + API coverage review<br/>• JDL consistency + auth design<br/>• Exit: Architecture approved."]
        ARCF["architecture-fix-agent<br/>• Fixes blueprint/JDL/boilerplate findings"]
        ARC --> ARCV
        ARCV -->|issues| ARCF --> ARCV
    end

    subgraph s12 [Stage 3-4 - Backend build and verify]
        direction LR
        GEN["jhipster-backend-agent<br/>• Microservices: gateway + services + registry<br/>• PostgreSQL + Liquibase<br/>• JWT/OAuth2 + RBAC, Docker<br/>• No mock/fake data"]
        VER["jhipster-verify-agent - readonly<br/>• REST/OpenAPI/RFC7807 audit<br/>• Auth + vulnerability checks<br/>• Microservices + DB integrity<br/>• Exit: No issues found. Backend approved."]
        ISS["issue-resolution-agent<br/>• Fixes every verify finding<br/>• No control weakening<br/>• Rebuild + run tests<br/>• Returns for re-audit"]
        GEN --> VER
        VER -->|issues| ISS --> VER
    end

    subgraph sDb [Stage 5 - Database hardening]
        direction LR
        DBA["database-agent<br/>• PostgreSQL connections + HikariCP<br/>• Liquibase migrations, constraints, indexes<br/>• Schema standards, no mock data"]
        DBV["database-verify-agent - readonly<br/>• Schema/migrations + integrity audit<br/>• Migrations apply on fresh PostgreSQL<br/>• Exit: Database approved."]
        DBF["database-fix-agent<br/>• Fixes DB connection/schema/migration findings"]
        DBA --> DBV
        DBV -->|issues| DBF --> DBV
    end

    subgraph sNg [Stage 6 - Nginx & SSL edge]
        direction LR
        NG["nginx-agent<br/>• Reverse proxy: frontend + gateway on domain<br/>• TLS termination, HTTP→HTTPS redirect<br/>• Certbot/Let's Encrypt + auto-renewal"]
        NGV["nginx-verify-agent - readonly<br/>• Routing + TLS + Certbot audit<br/>• Exit: Nginx and SSL approved."]
        NGF["nginx-fix-agent<br/>• Fixes edge proxy/SSL/cert findings"]
        NG --> NGV
        NGV -->|issues| NGF --> NGV
    end

    subgraph s3 [Stage 7 - Backend testing - per-layer verify and fix]
        direction TB
        subgraph s3u [Unit layer]
            direction LR
            BU["backend-unit-test-agent<br/>• JUnit5 + Mockito<br/>• Services, mappers, validators<br/>• Fully mocked/isolated"]
            BUV["backend-unit-test-verify-agent - readonly<br/>• Unit coverage + isolation<br/>• Exit: Backend unit testing requirements satisfied."]
            BUF["backend-unit-test-fix-agent<br/>• Closes unit-layer gaps"]
            BU --> BUV
            BUV -->|gaps| BUF --> BUV
        end
        subgraph s3i [Integration layer]
            direction LR
            BI["backend-integration-test-agent<br/>• Testcontainers PostgreSQL<br/>• Repos, queries, migrations<br/>• Real DB, no H2"]
            BIV["backend-integration-test-verify-agent - readonly<br/>• Real-DB + integration coverage<br/>• Exit: Backend integration testing requirements satisfied."]
            BIF["backend-integration-test-fix-agent<br/>• Closes integration-layer gaps"]
            BI --> BIV
            BIV -->|gaps| BIF --> BIV
        end
        subgraph s3f [Functional layer]
            direction LR
            BF["backend-functional-test-agent<br/>• REST Assured / MockMvc<br/>• Endpoints, auth, pagination<br/>• ProblemDetails + gateway E2E"]
            BFV["backend-functional-test-verify-agent - readonly<br/>• Endpoint + contract coverage<br/>• Exit: Backend functional testing requirements satisfied."]
            BFF["backend-functional-test-fix-agent<br/>• Closes functional-layer gaps"]
            BF --> BFV
            BFV -->|gaps| BFF --> BFV
        end
        s3u --> s3i --> s3f
    end

    subgraph s4 [Stage 8 - Frontend testing - per-layer verify and fix]
        direction TB
        subgraph s4u [Unit layer]
            direction LR
            FU["frontend-unit-test-agent<br/>• Vitest/Jest<br/>• Utils, hooks, stores<br/>• Isolated"]
            FUV["frontend-unit-test-verify-agent - readonly<br/>• Unit coverage + isolation<br/>• Exit: Frontend unit testing requirements satisfied."]
            FUF["frontend-unit-test-fix-agent<br/>• Closes unit-layer gaps"]
            FU --> FUV
            FUV -->|gaps| FUF --> FUV
        end
        subgraph s4i [Integration / component layer]
            direction LR
            FI["frontend-integration-test-agent<br/>• Testing Library + MSW<br/>• Components, pages, routing<br/>• Events + loading/error states"]
            FIV["frontend-integration-test-verify-agent - readonly<br/>• Component coverage + states<br/>• Exit: Frontend integration testing requirements satisfied."]
            FIF["frontend-integration-test-fix-agent<br/>• Closes component-layer gaps"]
            FI --> FIV
            FIV -->|gaps| FIF --> FIV
        end
        subgraph s4f [Functional / E2E layer]
            direction LR
            FF["frontend-functional-test-agent<br/>• Playwright E2E<br/>• Critical user journeys<br/>• Login, CRUD, navigation"]
            FFV["frontend-functional-test-verify-agent - readonly<br/>• Journey coverage in real browser<br/>• Exit: Frontend functional testing requirements satisfied."]
            FFF["frontend-functional-test-fix-agent<br/>• Closes E2E journey gaps"]
            FF --> FFV
            FFV -->|gaps| FFF --> FFV
        end
        s4u --> s4i --> s4f
    end

    subgraph sSi [Stage 9 - System integration testing - collective full-stack]
        direction LR
        SI["system-integration-test-agent<br/>• Runs whole stack together<br/>• Real frontend + gateway + services + PostgreSQL<br/>• Cross-tier journeys + auth propagation"]
        SIV["system-integration-test-verify-agent - readonly<br/>• Full-stack journey coverage on real stack<br/>• UI + API + DB persistence asserted<br/>• Exit: System integration testing requirements satisfied."]
        SIF["system-integration-test-fix-agent<br/>• Closes cross-tier journey gaps"]
        SI --> SIV
        SIV -->|gaps| SIF --> SIV
    end

    subgraph sDoc [Stages 10-14 - Documentation and API]
        direction TB
        subgraph sSw [Swagger / OpenAPI]
            direction LR
            SW["swagger-agent<br/>• springdoc annotations per service<br/>• security scheme + exported spec"]
            SWV["swagger-verify-agent - readonly<br/>• Spec completeness + accuracy<br/>• Exit: Swagger documentation requirements satisfied."]
            SWF["swagger-fix-agent<br/>• Closes documentation gaps"]
            SW --> SWV
            SWV -->|gaps| SWF --> SWV
        end
        subgraph sJd [Javadoc]
            direction LR
            JD["javadoc-agent<br/>• Javadoc for public APIs<br/>• failOnWarnings build"]
            JDV["javadoc-verify-agent - readonly<br/>• Coverage + clean build<br/>• Exit: Javadoc documentation requirements satisfied."]
            JDF["javadoc-fix-agent<br/>• Closes Javadoc gaps"]
            JD --> JDV
            JDV -->|gaps| JDF --> JDV
        end
        subgraph sAc [API collection - Postman]
            direction LR
            AC["api-collection-agent<br/>• Postman from OpenAPI<br/>• auth + chaining + Newman"]
            ACV["api-collection-verify-agent - readonly<br/>• Endpoint coverage + Newman green<br/>• Exit: API collection requirements satisfied."]
            ACF["api-collection-fix-agent<br/>• Closes collection gaps"]
            AC --> ACV
            ACV -->|gaps| ACF --> ACV
        end
        subgraph sAt [API tests - status]
            direction LR
            AT["api-test-agent<br/>• Calls every endpoint<br/>• Asserts 200/appropriate status"]
            ATV["api-test-verify-agent - readonly<br/>• Every endpoint correct status<br/>• Exit: API testing requirements satisfied."]
            ATF["api-test-fix-agent<br/>• Fixes wrong-status endpoints"]
            AT --> ATV
            ATV -->|gaps| ATF --> ATV
        end
        subgraph sAp [API performance - 1/10/20/30]
            direction LR
            AP["api-performance-test-agent<br/>• Load at 1,10,20,30 concurrency<br/>• latency/throughput/error rate"]
            APV["api-performance-test-verify-agent - readonly<br/>• All levels + thresholds met<br/>• Exit: API performance testing requirements satisfied."]
            APF["api-performance-test-fix-agent<br/>• Remediates perf breaches"]
            AP --> APV
            APV -->|gaps| APF --> APV
        end
        sSw --> sJd --> sAc --> sAt --> sAp
    end

    subgraph s5 [Stage 15 - Production]
        direction LR
        PS["production-standards-agent - readonly<br/>• Audits ALL prior stage outputs (do's/don'ts)<br/>• Security + readiness + standards + performance<br/>• Comprehensive final report<br/>• Exit: Final approval granted. System is production-ready."]
        PF["production-fix-agent<br/>• Remediates PR findings<br/>• No control weakening<br/>• Rebuild + run tests<br/>• Returns for re-audit"]
        PS -->|findings| PF --> PS
    end

    orch --> sSan --> sArch --> s12 --> sDb --> sNg --> s3 --> s4 --> sSi --> sDoc --> s5
```

---

## 2. End-to-end workflow (control flow)

The strict call order with all loops and their exact exit phrases.

```mermaid
flowchart TD
    Start(["Frontend Input<br/>+ project domain + fleet domain"]) --> Intake["Intake<br/>context-agent: .env secrets<br/>fleet token fetch, RUN_ID<br/>dashboard + fleet push"]
    Intake --> Pub["Early publisher<br/>http://server-ipv4:8787/agentprogress.html"]

    Intake --> ISan[frontend-sanitize-agent]
    ISan --> PIS1["context-agent<br/>frontend-sanitize-summary.md"]
    PIS1 --> ISanVer[frontend-sanitize-verify-agent]
    ISanVer --> PIS2["context-agent<br/>frontend-sanitize-verify-report.md"]
    PIS2 --> ISanApproved{"lastVerdict ==<br/>'Frontend sanitization complete.'?"}
    ISanApproved -->|No| CapIS{"frontendSanitizeVerifyIterations<br/>>= 5?"}
    CapIS -->|No| ISanFix[frontend-sanitize-fix-agent] --> PIS3["context-agent<br/>frontend-sanitize-fix-log.md"] --> ISanVer
    CapIS -->|Yes| Attention
    PIS2 -.->|if findings| Leela1[issues-log-agent]

    ISanApproved -->|Yes| AGen[architecture-agent]
    AGen --> PA1["context-agent<br/>architecture-summary.md"]
    PA1 --> AVer[architecture-verify-agent]
    AVer --> PA2["context-agent<br/>architecture-verify-report.md"]
    PA2 --> AApproved{"lastVerdict ==<br/>'Architecture approved.'?"}
    AApproved -->|No| CapA{"architectureVerifyIterations<br/>>= 5?"}
    CapA -->|No| AFix[architecture-fix-agent] --> PA3["context-agent<br/>architecture-fix-log.md"] --> AVer
    CapA -->|Yes| Attention["stage = needs-attention<br/>notify + continue if possible<br/>(blocked only on hard dependency)"]

    AApproved -->|Yes| Gen[jhipster-backend-agent]
    Gen --> P1["context-agent<br/>backend-summary.md"]

    P1 --> Verify[jhipster-verify-agent]
    Verify --> P2["context-agent<br/>verify-report.md"]
    P2 --> Approved{"lastVerdict ==<br/>'No issues found.<br/>Backend approved.'?"}
    Approved -->|No| CapB{"backendVerifyIterations<br/>>= 5?"}
    CapB -->|No| Fix[issue-resolution-agent] --> P3["context-agent<br/>issue-resolution-log.md"] --> Verify
    CapB -->|Yes| Attention

    Approved -->|Yes| DGen[database-agent]
    DGen --> PD1["context-agent<br/>database-summary.md"]
    PD1 --> DVer[database-verify-agent]
    DVer --> PD2["context-agent<br/>database-verify-report.md"]
    PD2 --> DApproved{"lastVerdict ==<br/>'Database approved.'?"}
    DApproved -->|No| CapD{"databaseVerifyIterations<br/>>= 5?"}
    CapD -->|No| DFix[database-fix-agent] --> PD3["context-agent<br/>database-fix-log.md"] --> DVer
    CapD -->|Yes| Attention

    DApproved -->|Yes| NGen[nginx-agent]
    NGen --> PN1["context-agent<br/>nginx-summary.md"]
    PN1 --> NVer[nginx-verify-agent]
    NVer --> PN2["context-agent<br/>nginx-verify-report.md"]
    PN2 --> NApproved{"lastVerdict ==<br/>'Nginx and SSL approved.'?"}
    NApproved -->|No| CapN{"nginxVerifyIterations<br/>>= 5?"}
    CapN -->|No| NFix[nginx-fix-agent] --> PN3["context-agent<br/>nginx-fix-log.md"] --> NVer
    CapN -->|Yes| Attention

    NApproved -->|Yes| BGen["backend test generation<br/>unit + integration + functional<br/>context-agent: backend-test-report.md"]
    BGen --> BLoop["Backend per-layer verify/fix loops<br/>(see Section 4)<br/>unit -> integration -> functional<br/>each: verify -> fix -> re-verify, cap 5"]
    BLoop --> BSat{"all 3 backend layers<br/>satisfied?"}
    BSat -->|No, any layer hit cap 5| Attention
    BSat -->|Yes| FGen

    FGen["frontend test generation<br/>unit + integration + functional<br/>context-agent: frontend-test-report.md"]
    FGen --> FLoop["Frontend per-layer verify/fix loops<br/>(see Section 5)<br/>unit -> integration -> functional<br/>each: verify -> fix -> re-verify, cap 5"]
    FLoop --> FSat{"all 3 frontend layers<br/>satisfied?"}
    FSat -->|No, any layer hit cap 5| Attention
    FSat -->|Yes| SIGen[system-integration-test-agent]

    SIGen --> PSI1["context-agent<br/>system-integration-test-report.md"]
    PSI1 --> SIVer[system-integration-test-verify-agent]
    SIVer --> PSI2["context-agent<br/>system-integration-test-verify-report.md"]
    PSI2 --> SISat{"lastVerdict ==<br/>'System integration testing<br/>requirements satisfied.'?"}
    SISat -->|No| CapSI{"systemIntegrationTestVerifyIterations<br/>>= 5?"}
    CapSI -->|No| SIFix[system-integration-test-fix-agent] --> PSI3["context-agent<br/>system-integration-test-fix-log.md"] --> SIVer
    CapSI -->|Yes| Attention
    SISat -->|Yes| DocAPI["Documentation & API stages (see Section 5.6)<br/>Swagger -> Javadoc -> API collection -> API tests -> API performance<br/>each: generate -> verify -> fix -> re-verify, cap 5"]
    DocAPI --> DocSat{"all 5 doc/API<br/>stages satisfied?"}
    DocSat -->|No, any stage hit cap 5| Attention
    DocSat -->|Yes| Prod["production-standards-agent<br/>audits ALL prior outputs + final report"]
    Prod --> P10["context-agent<br/>production-report.md"]
    P10 --> PSat{"lastVerdict ==<br/>'Final approval granted.<br/>System is production-ready.'?"}
    PSat -->|No| CapP{"productionVerifyIterations<br/>>= 5?"}
    CapP -->|No| PFix[production-fix-agent] --> P11["context-agent<br/>production-fix-log.md"] --> Prod
    CapP -->|Yes| Attention
    PSat -->|Yes| Final(["Final Approval<br/>System is production-ready."])
```

---

## 3. Code-level loops (detail)

Four generate → verify → fix loops run in order before backend generation: **frontend sanitization**, **architecture**, **backend code**, **database** (nginx and tests follow). Each has its own exit phrase and iteration counter.

### 3.0 Frontend sanitization loop

```mermaid
flowchart LR
    G[frontend-sanitize-agent] --> A[frontend-sanitize-verify-agent]
    A --> B["context-agent<br/>frontend-sanitize-verify-report.md"]
    B --> L[issues-log-agent if findings]
    B --> C{"Frontend sanitization complete?"}
    C -->|Yes| Exit([Exit to Architecture])
    C -->|No| D{frontendSanitizeVerifyIterations<br/>>= 5?}
    D -->|Yes| Stop([Needs attention<br/>continue if possible])
    D -->|No| E[frontend-sanitize-fix-agent]
    E --> F["context-agent<br/>frontend-sanitize-fix-log.md"]
    F --> A
```

### 3.1 Architecture loop

```mermaid
flowchart LR
    G[architecture-agent] --> A[architecture-verify-agent]
    A --> B["context-agent<br/>architecture-verify-report.md"]
    B --> C{"Architecture approved?"}
    C -->|Yes| Exit([Exit to Backend generation])
    C -->|No| D{architectureVerifyIterations<br/>>= 5?}
    D -->|Yes| Stop([Needs attention<br/>continue if possible])
    D -->|No| E[architecture-fix-agent]
    E --> F["context-agent<br/>architecture-fix-log.md"]
    F --> A
```

### 3.2 Backend code verification loop

```mermaid
flowchart LR
    A[jhipster-verify-agent] --> B["context-agent<br/>verify-report.md"]
    B --> C{Issues?}
    C -->|"No issues found.<br/>Backend approved."| Exit([Exit to Database])
    C -->|Issues found| D{backendVerifyIterations<br/>>= 5?}
    D -->|Yes| Stop([Needs attention<br/>continue if possible])
    D -->|No| E[issue-resolution-agent]
    E --> F["context-agent<br/>issue-resolution-log.md"]
    F --> A
```

### 3.3 Database loop

```mermaid
flowchart LR
    G[database-agent] --> A[database-verify-agent]
    A --> B["context-agent<br/>database-verify-report.md"]
    B --> C{"Database approved?"}
    C -->|Yes| Exit([Exit to Nginx & SSL])
    C -->|No| D{databaseVerifyIterations<br/>>= 5?}
    D -->|Yes| Stop([Needs attention<br/>continue if possible])
    D -->|No| E[database-fix-agent]
    E --> F["context-agent<br/>database-fix-log.md"]
    F --> A
```

### 3.4 Nginx & SSL edge loop

```mermaid
flowchart LR
    G[nginx-agent] --> A[nginx-verify-agent]
    A --> B["context-agent<br/>nginx-verify-report.md"]
    B --> C{"Nginx and SSL approved?"}
    C -->|Yes| Exit([Exit to Backend tests])
    C -->|No| D{nginxVerifyIterations<br/>>= 5?}
    D -->|Yes| Stop([Needs attention<br/>continue if possible])
    D -->|No| E[nginx-fix-agent]
    E --> F["context-agent<br/>nginx-fix-log.md"]
    F --> A
```

## 4. Backend testing loops (detail)

The three generation agents run **once** in order. Then each layer has its **own verify/fix loop** with its own exit phrase and counter, run in order: unit → integration → functional. Each layer's fix agent only touches that layer.

```mermaid
flowchart TB
    G1[backend-unit-test-agent] --> G2[backend-integration-test-agent] --> G3[backend-functional-test-agent]
    G3 --> P["context-agent<br/>backend-test-report.md"]

    P --> UA[backend-unit-test-verify-agent]
    UA --> UB{"unit satisfied?<br/>'Backend unit testing<br/>requirements satisfied.'"}
    UB -->|No| UD{backendUnitTestVerifyIterations >= 5?}
    UD -->|Yes| Stop([Needs attention<br/>continue if possible])
    UD -->|No| UE[backend-unit-test-fix-agent] --> UF["context-agent<br/>backend-unit-test-fix-log.md"] --> UA
    UB -->|Yes| IA[backend-integration-test-verify-agent]

    IA --> IB{"integration satisfied?<br/>'Backend integration testing<br/>requirements satisfied.'"}
    IB -->|No| ID{backendIntegrationTestVerifyIterations >= 5?}
    ID -->|Yes| Stop
    ID -->|No| IE[backend-integration-test-fix-agent] --> IF["context-agent<br/>backend-integration-test-fix-log.md"] --> IA
    IB -->|Yes| FA[backend-functional-test-verify-agent]

    FA --> FB{"functional satisfied?<br/>'Backend functional testing<br/>requirements satisfied.'"}
    FB -->|No| FD{backendFunctionalTestVerifyIterations >= 5?}
    FD -->|Yes| Stop
    FD -->|No| FE[backend-functional-test-fix-agent] --> FF["context-agent<br/>backend-functional-test-fix-log.md"] --> FA
    FB -->|Yes| Exit([Exit to Frontend tests])
```

## 5. Frontend testing loops (detail)

Same per-layer structure for the frontend: generate once, then unit → integration/component → functional/E2E, each with its own verify/fix loop, exit phrase, and counter.

```mermaid
flowchart TB
    G1[frontend-unit-test-agent] --> G2[frontend-integration-test-agent] --> G3[frontend-functional-test-agent]
    G3 --> P["context-agent<br/>frontend-test-report.md"]

    P --> UA[frontend-unit-test-verify-agent]
    UA --> UB{"unit satisfied?<br/>'Frontend unit testing<br/>requirements satisfied.'"}
    UB -->|No| UD{frontendUnitTestVerifyIterations >= 5?}
    UD -->|Yes| Stop([Needs attention<br/>continue if possible])
    UD -->|No| UE[frontend-unit-test-fix-agent] --> UF["context-agent<br/>frontend-unit-test-fix-log.md"] --> UA
    UB -->|Yes| IA[frontend-integration-test-verify-agent]

    IA --> IB{"integration satisfied?<br/>'Frontend integration testing<br/>requirements satisfied.'"}
    IB -->|No| ID{frontendIntegrationTestVerifyIterations >= 5?}
    ID -->|Yes| Stop
    ID -->|No| IE[frontend-integration-test-fix-agent] --> IF["context-agent<br/>frontend-integration-test-fix-log.md"] --> IA
    IB -->|Yes| FA[frontend-functional-test-verify-agent]

    FA --> FB{"functional satisfied?<br/>'Frontend functional testing<br/>requirements satisfied.'"}
    FB -->|No| FD{frontendFunctionalTestVerifyIterations >= 5?}
    FD -->|Yes| Stop
    FD -->|No| FE[frontend-functional-test-fix-agent] --> FF["context-agent<br/>frontend-functional-test-fix-log.md"] --> FA
    FB -->|Yes| Exit([Exit to System integration tests])
```

## 5.5 System integration testing loop (detail)

After both backend (§4) and frontend (§5) testing stages are satisfied, the collective full-stack loop runs the **whole system together** — the real frontend driving the real gateway + microservices, persisting to a real **PostgreSQL** database — to validate cross-tier journeys, auth propagation, and persistence. Generate once, then a single verify/fix loop.

```mermaid
flowchart LR
    G[system-integration-test-agent] --> A[system-integration-test-verify-agent]
    A --> B["context-agent<br/>system-integration-test-verify-report.md"]
    B --> C{"System integration testing<br/>requirements satisfied?"}
    C -->|Yes| Exit([Exit to Documentation & API stages])
    C -->|No| D{systemIntegrationTestVerifyIterations<br/>>= 5?}
    D -->|Yes| Stop([Needs attention<br/>continue if possible])
    D -->|No| E[system-integration-test-fix-agent]
    E --> F["context-agent<br/>system-integration-test-fix-log.md"]
    F --> A
```

## 5.6 Documentation & API loops (detail)

Five generate → verify → fix loops run **in order** after system integration testing and before production: **Swagger → Javadoc → API collection → API tests → API performance**. Swagger runs first because its exported OpenAPI spec feeds the API collection and API tests. Each loop has its own exit phrase and counter (cap 5).

```mermaid
flowchart TB
    SW[swagger-agent] --> SWV[swagger-verify-agent]
    SWV --> SWB{"Swagger documentation<br/>requirements satisfied?"}
    SWB -->|No| SWD{swaggerVerifyIterations >= 5?}
    SWD -->|Yes| Stop([Needs attention<br/>continue if possible])
    SWD -->|No| SWF[swagger-fix-agent] --> SWV
    SWB -->|Yes| JD[javadoc-agent]

    JD --> JDV[javadoc-verify-agent]
    JDV --> JDB{"Javadoc documentation<br/>requirements satisfied?"}
    JDB -->|No| JDD{javadocVerifyIterations >= 5?}
    JDD -->|Yes| Stop
    JDD -->|No| JDF[javadoc-fix-agent] --> JDV
    JDB -->|Yes| AC[api-collection-agent]

    AC --> ACV[api-collection-verify-agent]
    ACV --> ACB{"API collection<br/>requirements satisfied?"}
    ACB -->|No| ACD{apiCollectionVerifyIterations >= 5?}
    ACD -->|Yes| Stop
    ACD -->|No| ACF[api-collection-fix-agent] --> ACV
    ACB -->|Yes| AT[api-test-agent]

    AT --> ATV[api-test-verify-agent]
    ATV --> ATB{"API testing requirements satisfied?<br/>(every endpoint correct status)"}
    ATB -->|No| ATD{apiTestVerifyIterations >= 5?}
    ATD -->|Yes| Stop
    ATD -->|No| ATF[api-test-fix-agent] --> ATV
    ATB -->|Yes| AP[api-performance-test-agent]

    AP --> APV[api-performance-test-verify-agent]
    APV --> APB{"API performance satisfied?<br/>(1/10/20/30 thresholds met)"}
    APB -->|No| APD{apiPerformanceTestVerifyIterations >= 5?}
    APD -->|Yes| Stop
    APD -->|No| APF[api-performance-test-fix-agent] --> APV
    APB -->|Yes| Exit([Exit to Production])
```

## 6. Production loop (detail)

The production agent first runs a **completeness audit of every prior stage** (each stage's exact verdict present + artifacts on disk — a do's-and-don'ts checklist). If any stage is incomplete it emits `Final approval blocked.` with the gaps; otherwise it audits security/readiness/standards/performance and emits the comprehensive final report.

```mermaid
flowchart LR
    A["production-standards-agent<br/>audits ALL prior outputs<br/>+ comprehensive final report"] --> B["context-agent<br/>production-report.md"]
    B --> C{"lastVerdict ==<br/>'Final approval granted.<br/>System is production-ready.'?"}
    C -->|Yes| DEPLOY[Deployment tail #17-#22]
    C -->|No| D{productionVerifyIterations<br/>>= 5?}
    D -->|Yes| Stop([Needs attention<br/>continue if possible])
    D -->|No| E[production-fix-agent]
    E --> F["context-agent<br/>production-fix-log.md"]
    F --> A
```

On `Final approval granted.`, Sunny does **not** mark `phase: complete` — it advances into the **production deployment tail** (stages #17–#22) and only marks complete when Om emits `Production deployment verified. System is live.`

---

## 6.5 Production deployment tail (stages #17–#22)

After the production audit passes, Sunny automatically runs **six** deploy sub-stages on the VPS. Each follows the same generate → verify (readonly) → fix loop (cap 5) used by every other stage. The final stage (Om) is verify/fix only.

```mermaid
flowchart LR
    P["Prakash ✓<br/>'Final approval granted.'"] --> R["#17 Rajesh<br/>Minikube + Helm + Grafana + deploy/ scaffold"]
    R -->|issues| RFix[Rajesh Fix] --> R
    R -->|"Deployment platform approved."| Su["#18 Suresh<br/>VPS host deps (provision.sh)"]
    Su -->|issues| SuFix[Suresh Fix] --> Su
    Su -->|"Server provisioning approved."| L["#19 Lakshmi<br/>Production PostgreSQL + K8s secret"]
    L -->|issues| LFix[Lakshmi Fix] --> L
    L -->|"Deployment database approved."| M["#20 Manoj<br/>Minikube Deployments/Services/ServiceMonitors"]
    M -->|issues| MFix[Manoj Fix] --> M
    M -->|"Deployment backend approved."| As["#21 Asha<br/>Host Nginx TLS + PM2 + /api routing"]
    As -->|issues| AsFix[Asha Fix] --> As
    As -->|"Deployment edge approved."| O["#22 Om<br/>health-check.sh + port-map match"]
    O -->|issues| OFix[Om Fix] --> O
    O -->|"Production deployment verified. System is live."| Live([Live at https://project-domain/])
```

**Production topology** (deployed by the agents above; full spec in [`deploy/README.md`](../../deploy/README.md)):

```
Internet
   │
   ▼
Host Nginx (Certbot TLS, Asha) ──► PM2 frontend (static SPA)
   │                                   │
   │ /api                              └── VITE_API_URL → https://<domain>/api
   │ /grafana  ──► Grafana NodePort 30300
   │ /progress.json + /agentprogress.html ──► .sunny/web static mount
   ▼
Minikube NodePort (gateway :30080)
   │
   ├── JHipster Gateway pod
   ├── Microservice pods (ClusterIP, distinct ports, probes + limits, ServiceMonitor)
   ├── JHipster Registry pod
   │
   ▼
Host PostgreSQL  ◄── JDBC host.min.internal:5432 (Minikube docker driver)
                       ▲
                       └── SPRING_DATASOURCE_URL from sunny-postgres K8s secret (sync-secrets.sh)

Minikube observability namespace
   ├── Prometheus (kube-prometheus-stack; scrapes /management/prometheus)
   └── Grafana (Sunny deployment dashboard; Infinity datasource → /progress.json)
```

**Authoritative files** under `deploy/`:

- `deploy/README.md` — operator runbook.
- `deploy/port-map.md` — service → port → NodePort → health endpoint (Rajesh seeds, Manoj completes, Om verifies).
- `deploy/minikube/{namespace.yaml, resource-quota.yaml, kustomization.yaml}` — `sunny-prod` namespace + CPU/memory quotas.
- `deploy/helm/kube-prometheus-stack-values.yaml` — Grafana NodePort 30300, Infinity plugin, Prometheus retention, resource limits.
- `deploy/grafana/provisioning/dashboards/sunny/sunny-deployment.json` — provisioned dashboard.
- `deploy/grafana/provisioning/datasources/datasources.yaml` — Prometheus + Sunny progress.json.
- `deploy/scripts/{provision.sh, sync-secrets.sh, health-check.sh}` — Suresh's installer, Lakshmi/Manoj's K8s-secret writer, Om's verifier.

---

## 7. What happens when something fails (fix and re-verify)

Every stage uses the **same failure-handling mechanism**. When a verify/audit agent does not emit its exact exit phrase, the work goes to the matching fix agent, then back for a fresh re-audit — bounded by the 5-iteration cap.

```mermaid
flowchart TD
    V["verify / audit agent<br/>(readonly)"] --> R["Reports findings table<br/>ID, severity, category, location, fix"]
    R --> P["context-agent<br/>persist report<br/>set lastVerdict<br/>increment counter"]
    P --> Q{"exact exit<br/>phrase emitted?"}
    Q -->|Yes| Next([Advance to next stage])
    Q -->|No| Cap{"counter >= 5?"}
    Cap -->|Yes| Attention["stage = needs-attention<br/>dashboard notification<br/>continue if possible"]
    Attention --> Hard{"hard dependency<br/>blocks next stage?"}
    Hard -->|Yes| Blocked["phase = blocked<br/>Sunny stops with blockers"]
    Hard -->|No| Next
    Cap -->|No| Fix["fix agent<br/>• reads findings as work queue<br/>• fixes every item by severity<br/>• no control / gate weakening<br/>• rebuild + run affected tests"]
    Fix --> P2["context-agent<br/>append fix-log"]
    P2 --> V
```

### The rules that make this safe

1. **The fixer cannot mark its own homework.** Only the readonly verify/audit agent can emit the exit phrase. A fix is "accepted" only when an independent re-audit passes.
2. **Re-verification is from scratch.** The verify agent re-audits the real code with no memory of the fixes, so an incomplete fix is caught again.
3. **One round = one iteration.** Each verify run increments that loop's own counter (`architectureVerifyIterations`; `backendVerifyIterations`; `databaseVerifyIterations`; `nginxVerifyIterations`; the six per-layer test counters `backend/frontend{Unit,Integration,Functional}TestVerifyIterations`; `systemIntegrationTestVerifyIterations`; the five documentation/API counters `swaggerVerifyIterations` / `javadocVerifyIterations` / `apiCollectionVerifyIterations` / `apiTestVerifyIterations` / `apiPerformanceTestVerifyIterations`; `productionVerifyIterations`).
4. **The cap is checked before fixing again.** If the counter hits `maxIterations` (default 5) without the exit phrase, the loop stops iterating (never an infinite loop). By default the pipeline does **not** halt — the stage is marked `needs-attention`, remaining items become notifications on the local + fleet dashboards, and Sunny continues to the next stage wherever technically possible; only a hard technical dependency causes a real `blocked` stop.
5. **New findings are allowed.** A fix may surface fresh issues; they appear in the next report and are addressed in the next round (while under the cap).
6. **Fixers never weaken controls.** They do not disable auth, loosen CORS to `*`, remove validation, lower coverage thresholds, or introduce mock data to force a pass — they fix the root cause.
7. **Deadlock guard.** "Not satisfied" with an **empty findings table** never launches a fix agent (no work) — the stage is marked `needs-attention` and the run continues instead of looping uselessly.
8. **No-progress guard.** If two consecutive cycles show no net reduction in open findings (same/greater count or identical IDs persisting), Maya stops that loop early — catching oscillation (fix-A-breaks-B) before the cap — marks `needs-attention`, and continues.
9. **Counter-integrity backstop.** Maya increments the counter every verify run; Sunny independently counts launches, so a stuck/missing counter can never disable the cap.
10. **Exact phrase only.** Near-miss verdicts (typos, extra words) never advance; the verify agent is asked to re-emit the exact phrase.
11. **Resume-safe checkpointing.** Maya writes `state.json`/`progress.json` atomically (temp + rename) after every handoff, marking a stage `active` on entry and `done` only on its exit verdict. If the run is interrupted, Sunny's Phase −1 resume check re-enters the `active` stage with counters intact — so a crash/reboot resumes from the last checkpoint instead of restarting, and never loses a cap or an "action required" item.

### Same mechanism across all eighteen loops

| Loop | Verify / audit agent | Fix agent | Counter | Exit phrase |
|------|----------------------|-----------|---------|-------------|
| Frontend sanitization | `frontend-sanitize-verify-agent` | `frontend-sanitize-fix-agent` | `frontendSanitizeVerifyIterations` | `Frontend sanitization complete.` |
| Architecture | `architecture-verify-agent` | `architecture-fix-agent` | `architectureVerifyIterations` | `Architecture approved.` |
| Backend code | `jhipster-verify-agent` | `issue-resolution-agent` | `backendVerifyIterations` | `No issues found. Backend approved.` |
| Database | `database-verify-agent` | `database-fix-agent` | `databaseVerifyIterations` | `Database approved.` |
| Nginx & SSL | `nginx-verify-agent` | `nginx-fix-agent` | `nginxVerifyIterations` | `Nginx and SSL approved.` |
| Backend unit tests | `backend-unit-test-verify-agent` | `backend-unit-test-fix-agent` | `backendUnitTestVerifyIterations` | `Backend unit testing requirements satisfied.` |
| Backend integration tests | `backend-integration-test-verify-agent` | `backend-integration-test-fix-agent` | `backendIntegrationTestVerifyIterations` | `Backend integration testing requirements satisfied.` |
| Backend functional tests | `backend-functional-test-verify-agent` | `backend-functional-test-fix-agent` | `backendFunctionalTestVerifyIterations` | `Backend functional testing requirements satisfied.` |
| Frontend unit tests | `frontend-unit-test-verify-agent` | `frontend-unit-test-fix-agent` | `frontendUnitTestVerifyIterations` | `Frontend unit testing requirements satisfied.` |
| Frontend integration tests | `frontend-integration-test-verify-agent` | `frontend-integration-test-fix-agent` | `frontendIntegrationTestVerifyIterations` | `Frontend integration testing requirements satisfied.` |
| Frontend functional tests | `frontend-functional-test-verify-agent` | `frontend-functional-test-fix-agent` | `frontendFunctionalTestVerifyIterations` | `Frontend functional testing requirements satisfied.` |
| System integration tests | `system-integration-test-verify-agent` | `system-integration-test-fix-agent` | `systemIntegrationTestVerifyIterations` | `System integration testing requirements satisfied.` |
| Swagger / OpenAPI | `swagger-verify-agent` | `swagger-fix-agent` | `swaggerVerifyIterations` | `Swagger documentation requirements satisfied.` |
| Javadoc | `javadoc-verify-agent` | `javadoc-fix-agent` | `javadocVerifyIterations` | `Javadoc documentation requirements satisfied.` |
| API collection | `api-collection-verify-agent` | `api-collection-fix-agent` | `apiCollectionVerifyIterations` | `API collection requirements satisfied.` |
| API tests | `api-test-verify-agent` | `api-test-fix-agent` | `apiTestVerifyIterations` | `API testing requirements satisfied.` |
| API performance | `api-performance-test-verify-agent` | `api-performance-test-fix-agent` | `apiPerformanceTestVerifyIterations` | `API performance testing requirements satisfied.` |
| Production | `production-standards-agent` | `production-fix-agent` | `productionVerifyIterations` | `Final approval granted. System is production-ready.` |

> Each side's three generation agents (unit/integration/functional) run once at the start; then each layer has its own verify/fix loop. On failure the layer's fix agent adds or repairs that layer's tests, then the layer re-verifies — the generators are not re-run.

---

## 8. Phase sequence (who talks to whom, when)

```mermaid
sequenceDiagram
    autonumber
    participant U as User
    participant S as Sunny (driver)
    participant C as Context Agent
    participant L as Issues Log Agent
    participant ISH as Frontend Sanitize (gen+verify+fix)
    participant A as Architecture (gen+verify+fix)
    participant B as Backend Agent
    participant V as Verify Agent
    participant IR as Issue Resolution
    participant D as Database (gen+verify+fix)
    participant N as Nginx & SSL (gen+verify+fix)
    participant BT as Backend Test Gen+Fix (per layer)
    participant BTV as Backend Layer Verifiers
    participant FT as Frontend Test Gen+Fix (per layer)
    participant FTV as Frontend Layer Verifiers
    participant SI as System Integration Gen+Fix
    participant SIV as System Integration Verify
    participant DA as Doc/API Gen+Fix (5 stages)
    participant DAV as Doc/API Verifiers (5 stages)
    participant P as Production Standards
    participant PF as Production Fix

    U->>S: Frontend + requirements + project domain + fleet domain
    S->>C: Intake (project-context.md, state.json, seed .sunny/web dashboard, generate .env secrets)
    S->>U: Start early publisher -> http://server-ipv4:8787/agentprogress.html

    rect rgb(120,120,120)
    note right of S: Stage 1 - Frontend sanitization (max 5)
    S->>ISH: Strip Supabase/Lovable from frontend
    ISH-->>S: frontend-sanitize-summary
    S->>C: Persist frontend-sanitize-summary.md
    loop until "Frontend sanitization complete"
        S->>ISH: Verify sanitization (readonly)
        ISH-->>S: report + verdict
        S->>C: Persist frontend-sanitize-verify-report.md
        alt Findings present
            S->>L: Log issues to KNOWN_ISSUES.md
        end
        alt Not complete and iter < 5
            S->>ISH: frontend-sanitize-fix-agent closes findings
            S->>C: Persist frontend-sanitize-fix-log.md
        else Complete or max iterations
            note over S: break or needs-attention
        end
    end
    end

    rect rgb(120,120,120)
    note right of S: Stage 2 - Architecture (max 5)
    S->>A: Design blueprint + boilerplate
    A-->>S: architecture-summary
    S->>C: Persist architecture-summary.md
    loop until "Architecture approved"
        S->>A: Verify blueprint (readonly)
        A-->>S: report + verdict
        S->>C: Persist architecture-verify-report.md
        alt Not approved and iter < 5
            S->>A: architecture-fix-agent closes findings
            S->>C: Persist architecture-fix-log.md
        else Approved or max iterations
            note over S: break or needs-attention
        end
    end
    end

    rect rgb(120,120,120)
    note right of S: Stages 3-4 - Generate and verify backend
    S->>B: Generate JHipster microservices
    B-->>S: backend output
    S->>C: Persist backend-summary.md
    loop until "Backend approved"
        S->>V: Audit backend
        V-->>S: verify report + verdict
        S->>C: Persist verify-report.md
        alt Issues found and iter < 5
            S->>IR: Fix findings
            IR-->>S: fix summary
            S->>C: Persist issue-resolution-log.md
        else Approved or max iterations
            note over S: break or needs-attention
        end
    end
    end

    rect rgb(120,120,120)
    note right of S: Stage 5 - Database hardening (max 5)
    S->>D: Harden connections, schema, migrations
    D-->>S: database-summary
    S->>C: Persist database-summary.md
    loop until "Database approved"
        S->>D: Verify DB layer (readonly)
        D-->>S: report + verdict
        S->>C: Persist database-verify-report.md
        alt Not approved and iter < 5
            S->>D: database-fix-agent closes findings
            S->>C: Persist database-fix-log.md
        else Approved or max iterations
            note over S: break or needs-attention
        end
    end
    end

    rect rgb(120,120,120)
    note right of S: Stage 6 - Nginx & SSL edge (max 5)
    S->>N: Configure reverse proxy + domain + Certbot
    N-->>S: nginx-summary
    S->>C: Persist nginx-summary.md
    loop until "Nginx and SSL approved"
        S->>N: Verify edge layer (readonly)
        N-->>S: report + verdict
        S->>C: Persist nginx-verify-report.md
        alt Not approved and iter < 5
            S->>N: nginx-fix-agent closes findings
            S->>C: Persist nginx-fix-log.md
        else Approved or max iterations
            note over S: break or needs-attention
        end
    end
    end

    rect rgb(120,120,120)
    note right of S: Stage 7 - Backend tests (generate once, then per-layer loops)
    S->>BT: Generate unit, integration, functional
    BT-->>S: tests + coverage
    S->>C: Persist backend-test-report.md
    loop for each layer: unit -> integration -> functional (max 5 each)
        S->>BTV: Verify this layer's coverage/quality
        BTV-->>S: report + layer verdict
        S->>C: Persist backend-{layer}-test-verify-report.md
        alt Layer not satisfied and iter < 5
            S->>BT: backend-{layer}-test-fix-agent closes gaps
            BT-->>S: fix summary
            S->>C: Persist backend-{layer}-test-fix-log.md
        else Layer satisfied or max iterations
            note over S: next layer or needs-attention
        end
    end
    end

    rect rgb(120,120,120)
    note right of S: Stage 8 - Frontend tests (generate once, then per-layer loops)
    S->>FT: Generate unit, integration, functional
    FT-->>S: tests + coverage
    S->>C: Persist frontend-test-report.md
    loop for each layer: unit -> integration -> functional (max 5 each)
        S->>FTV: Verify this layer's coverage/quality
        FTV-->>S: report + layer verdict
        S->>C: Persist frontend-{layer}-test-verify-report.md
        alt Layer not satisfied and iter < 5
            S->>FT: frontend-{layer}-test-fix-agent closes gaps
            FT-->>S: fix summary
            S->>C: Persist frontend-{layer}-test-fix-log.md
        else Layer satisfied or max iterations
            note over S: next layer or needs-attention
        end
    end
    end

    rect rgb(120,120,120)
    note right of S: Stage 9 - System integration tests (collective, max 5)
    S->>SI: Generate full-stack tests (frontend + backend + PostgreSQL)
    SI-->>S: tests + run result
    S->>C: Persist system-integration-test-report.md
    loop until "System integration testing requirements satisfied"
        S->>SIV: Verify cross-tier journeys on real stack
        SIV-->>S: report + verdict
        S->>C: Persist system-integration-test-verify-report.md
        alt Not satisfied and iter < 5
            S->>SI: system-integration-test-fix-agent closes gaps
            SI-->>S: fix summary
            S->>C: Persist system-integration-test-fix-log.md
        else Satisfied or max iterations
            note over S: break or needs-attention
        end
    end
    end

    rect rgb(120,120,120)
    note right of S: Stages 10-14 - Documentation & API (in order, max 5 each)
    loop for each stage: swagger -> javadoc -> api-collection -> api-test -> api-performance
        S->>DA: Generate stage artifacts (spec / javadoc / postman / status tests / load scripts)
        DA-->>S: artifacts + run result
        S->>C: Persist {stage}-report.md
        loop until this stage's exit phrase
            S->>DAV: Verify this stage (readonly)
            DAV-->>S: report + verdict
            S->>C: Persist {stage}-verify-report.md
            alt Not satisfied and iter < 5
                S->>DA: {stage}-fix-agent closes gaps
                S->>C: Persist {stage}-fix-log.md
            else Satisfied or max iterations
                note over S: next stage or needs-attention
            end
        end
    end
    end

    rect rgb(120,120,120)
    note right of S: Stage 15 - Production (audits ALL prior outputs, max 5)
    loop until "Final approval granted"
        S->>P: Completeness audit of all stages + final audit
        P-->>S: comprehensive report + verdict
        S->>C: Persist production-report.md
        alt Blocked and iter < 5
            S->>PF: Remediate findings
            PF-->>S: fix summary
            S->>C: Persist production-fix-log.md
        else Approved or max iterations
            note over S: break or needs-attention
        end
    end
    end

    S->>U: Summary + run guide
```

---

## 9. Shared-memory data flow

Only the Context Agent writes the store; every other agent reads trimmed handoffs.

```mermaid
flowchart LR
    subgraph store [".sunny/context/"]
        PC[project-context.md]
        AS[architecture-summary.md]
        AVR[architecture-verify-report.md]
        AFL[architecture-fix-log.md]
        BS[backend-summary.md]
        VR[verify-report.md]
        IRL[issue-resolution-log.md]
        DS[database-summary.md]
        DVR[database-verify-report.md]
        DFL[database-fix-log.md]
        NS[nginx-summary.md]
        NVR[nginx-verify-report.md]
        NFL[nginx-fix-log.md]
        BTR[backend-test-report.md]
        BTV6["backend-{unit,integration,functional}-<br/>test-verify-report.md (x3)"]
        BTF6["backend-{unit,integration,functional}-<br/>test-fix-log.md (x3)"]
        FTR[frontend-test-report.md]
        FTV6["frontend-{unit,integration,functional}-<br/>test-verify-report.md (x3)"]
        FTF6["frontend-{unit,integration,functional}-<br/>test-fix-log.md (x3)"]
        SIR[system-integration-test-report.md]
        SIVR[system-integration-test-verify-report.md]
        SIFL[system-integration-test-fix-log.md]
        DOCV["swagger/javadoc/api-collection/<br/>api-test/api-performance -report.md (x5)"]
        DOCVR["...-verify-report.md (x5)"]
        DOCFL["...-fix-log.md (x5)"]
        PR[production-report.md]
        PFL[production-fix-log.md]
        ST[state.json]
    end

    subgraph web [".sunny/web/ (live dashboard)"]
        HTML[agentprogress.html]
        PJSON[progress.json]
        PUB[docker-compose.yml + nginx-progress.conf]
    end

    subgraph rootenv ["project root (gitignored)"]
        ENV[".env (auto-generated secrets)"]
    end

    Ctx[context-agent] -->|writes| store
    Ctx -->|"writes every handoff"| web
    Ctx -->|"generates at intake (no values logged)"| ENV
    ENV -->|"$VAR consumed by"| Stack["backend / nginx / tests<br/>(docker compose)"]
    PJSON -->|"early publisher / Naveen on domain"| Viewer["Browser<br/>agentprogress.html"]

    PC --> ARC[architecture-agent]
    AVR --> ARC
    AS --> ARCV[architecture-verify]
    PC --> ARCV
    AVR --> ARCF[architecture-fix]
    AS --> ARCF
    AFL --> ARCF

    PC --> BE[backend-agent]
    AS --> BE
    PC --> VER[verify-agent]
    BS --> VER
    AS --> VER
    VR --> FIX[issue-resolution]
    BS --> FIX
    IRL --> FIX

    BS --> DBA[database-agent]
    PC --> DBA
    DVR --> DBA
    DS --> DBV[database-verify]
    BS --> DBV
    DVR --> DBF[database-fix]
    DS --> DBF
    DFL --> DBF

    BS --> NGA[nginx-agent]
    DS --> NGA
    AS --> NGA
    PC --> NGA
    NVR --> NGA
    NS --> NGVA[nginx-verify]
    PC --> NGVA
    NVR --> NGFIX[nginx-fix]
    NS --> NGFIX
    NFL --> NGFIX

    BS --> BTEST[backend test gen agents x3]
    PC --> BTEST
    BTV6 --> BTEST
    BTR --> BTVA["backend layer verify agents x3"]
    BS --> BTVA
    BTV6 --> BTFIX["backend layer fix agents x3"]
    BTR --> BTFIX
    BTF6 --> BTFIX
    PC --> FTEST[frontend test gen agents x3]
    FTV6 --> FTEST
    FTR --> FTVA["frontend layer verify agents x3"]
    FTV6 --> FTFIX["frontend layer fix agents x3"]
    FTR --> FTFIX
    FTF6 --> FTFIX

    PC --> SIT[system-integration-test-agent]
    AS --> SIT
    BS --> SIT
    DS --> SIT
    SIVR --> SIT
    SIR --> SIV2[system-integration-verify]
    PC --> SIV2
    SIVR --> SIF2[system-integration-fix]
    SIR --> SIF2
    SIFL --> SIF2

    PC --> DOCGEN[doc/API gen agents x5]
    AS --> DOCGEN
    BS --> DOCGEN
    DOCVR --> DOCGEN
    DOCV --> DOCVA[doc/API verify agents x5]
    DOCVR --> DOCFIX[doc/API fix agents x5]
    DOCV --> DOCFIX
    DOCFL --> DOCFIX

    BTV6 --> PROD["production-standards<br/>(reads ALL files)"]
    FTV6 --> PROD
    SIVR --> PROD
    DOCVR --> PROD
    BS --> PROD
    PR --> PROD
    PR --> PFIX[production-fix]
    BS --> PFIX
    PC --> PFIX
    PFL --> PFIX
    ST -.drives loop decisions.-> Driver[Sunny driver]
```

---

## 10. Workflow state machine

`state.json.phase` transitions that the orchestrator follows.

```mermaid
stateDiagram-v2
    [*] --> intake
    intake --> frontend_sanitize
    frontend_sanitize --> frontend_sanitize_verify
    frontend_sanitize_verify --> frontend_sanitize_fix: not complete
    frontend_sanitize_fix --> frontend_sanitize_verify: re-review
    frontend_sanitize_verify --> architecture: Frontend sanitization complete

    architecture --> architecture_verify
    architecture_verify --> architecture_fix: not approved
    architecture_fix --> architecture_verify: re-review
    architecture_verify --> backend: Architecture approved

    backend --> backend_verify
    backend_verify --> issue_resolution: issues found
    issue_resolution --> backend_verify: re-audit
    backend_verify --> database: Backend approved

    database --> database_verify
    database_verify --> database_fix: not approved
    database_fix --> database_verify: re-audit
    database_verify --> nginx: Database approved

    nginx --> nginx_verify
    nginx_verify --> nginx_fix: not approved
    nginx_fix --> nginx_verify: re-audit
    nginx_verify --> testing_backend: Nginx and SSL approved

    testing_backend --> testing_backend: layer not satisfied (fix and re-verify)
    testing_backend --> testing_frontend: all 3 backend layers satisfied

    testing_frontend --> testing_frontend: layer not satisfied (fix and re-verify)
    testing_frontend --> testing_system: all 3 frontend layers satisfied

    testing_system --> testing_system: not satisfied (fix and re-verify)
    testing_system --> swagger: System integration testing satisfied

    swagger --> swagger: not satisfied (fix and re-verify)
    swagger --> javadoc: Swagger satisfied
    javadoc --> javadoc: not satisfied (fix and re-verify)
    javadoc --> api_collection: Javadoc satisfied
    api_collection --> api_collection: not satisfied (fix and re-verify)
    api_collection --> api_testing: API collection satisfied
    api_testing --> api_testing: not satisfied (fix and re-verify)
    api_testing --> api_performance: API testing satisfied
    api_performance --> api_performance: not satisfied (fix and re-verify)
    api_performance --> production: API performance satisfied

    production --> production_fix: findings
    production_fix --> production: re-audit
    production --> complete: Final approval granted
    complete --> [*]

    frontend_sanitize_verify --> architecture: max iterations, mark frontend_sanitize needs-attention if architecture can continue
    architecture_verify --> backend: max iterations, mark architecture needs-attention if backend can continue
    backend_verify --> database: max iterations, mark backend verification needs-attention if database can continue
    database_verify --> nginx: max iterations, mark database needs-attention if nginx can continue
    nginx_verify --> testing_backend: max iterations, mark nginx needs-attention if tests can continue
    testing_backend --> testing_frontend: max iterations, mark backend testing needs-attention if frontend can continue
    testing_frontend --> testing_system: max iterations, mark frontend testing needs-attention if system tests can continue
    testing_system --> swagger: max iterations, mark system testing needs-attention if docs can continue
    swagger --> javadoc: max iterations, mark swagger needs-attention
    javadoc --> api_collection: max iterations, mark javadoc needs-attention
    api_collection --> api_testing: max iterations, mark API collection needs-attention
    api_testing --> api_performance: max iterations, mark API testing needs-attention
    api_performance --> production: max iterations, mark API performance needs-attention
    production --> complete: max iterations, mark production needs-attention and report outstanding items
    architecture_verify --> blocked: hard dependency cannot continue
    frontend_sanitize_verify --> blocked: hard dependency cannot continue
    backend_verify --> blocked: hard dependency cannot continue
    database_verify --> blocked: hard dependency cannot continue
    nginx_verify --> blocked: hard dependency cannot continue
    testing_backend --> blocked: hard dependency cannot continue
    testing_frontend --> blocked: hard dependency cannot continue
    testing_system --> blocked: hard dependency cannot continue
    swagger --> blocked: hard dependency cannot continue
    javadoc --> blocked: hard dependency cannot continue
    api_collection --> blocked: hard dependency cannot continue
    api_testing --> blocked: hard dependency cannot continue
    api_performance --> blocked: hard dependency cannot continue
    production --> blocked: hard dependency cannot continue
    blocked --> [*]: user action required
```

> Within `testing_backend` and `testing_frontend`, the layers are verified/fixed in order — unit → integration → functional — each with its own exit phrase and iteration counter. The side advances only when all three layers are satisfied.

---

## Legend

| Concept | Meaning |
|---------|---------|
| **Driver** | Main chat agent that follows the playbook and launches sub-agents via the Task tool |
| **Solid arrow** | Control flow / Task launch |
| **Dotted arrow** | Data flow (persist / handoff) |
| **readonly agent** | Audits and reports only; makes no code changes (frontend-sanitize-verify, architecture-verify, jhipster-verify, database-verify, nginx-verify, the six per-layer test-verify agents, system-integration-test-verify, the five doc/API verify agents, production-standards) |
| **Issues log** | Leela (`issues-log-agent`) appends to `.sunny/KNOWN_ISSUES.md` when findings/blockers occur |
| **Exit phrase** | Exact string in `state.json.lastVerdict` that breaks a loop |
| **Frontend sanitization exit** | `Frontend sanitization complete.` |
| **Architecture exit** | `Architecture approved.` |
| **Backend code exit** | `No issues found. Backend approved.` |
| **Database exit** | `Database approved.` |
| **Nginx & SSL exit** | `Nginx and SSL approved.` |
| **Backend test exits** | `Backend unit testing requirements satisfied.` / `Backend integration testing requirements satisfied.` / `Backend functional testing requirements satisfied.` |
| **Frontend test exits** | `Frontend unit testing requirements satisfied.` / `Frontend integration testing requirements satisfied.` / `Frontend functional testing requirements satisfied.` |
| **System integration exit** | `System integration testing requirements satisfied.` |
| **Doc/API exits** | `Swagger documentation requirements satisfied.` / `Javadoc documentation requirements satisfied.` / `API collection requirements satisfied.` / `API testing requirements satisfied.` / `API performance testing requirements satisfied.` |
| **Production exit** | `Final approval granted. System is production-ready.` |
| **Deploy platform exit** | `Deployment platform approved.` |
| **Server provisioning exit** | `Server provisioning approved.` |
| **Deployment database exit** | `Deployment database approved.` |
| **Deployment backend exit** | `Deployment backend approved.` |
| **Deployment edge exit** | `Deployment edge approved.` |
| **Deployment final exit** | `Production deployment verified. System is live.` |
| **Max iterations** | Default 5 per loop; each loop has its own counter (`frontendSanitizeVerifyIterations`; `architectureVerifyIterations`; `supabaseRemovalVerifyIterations`; `backendVerifyIterations`; `databaseVerifyIterations`; `nginxVerifyIterations`; the six `backend/frontend{Unit,Integration,Functional}TestVerifyIterations`; `systemIntegrationTestVerifyIterations`; the five `swagger/javadoc/apiCollection/apiTest/apiPerformanceTestVerifyIterations`; `productionVerifyIterations`; the six `deploymentPlatformVerifyIterations` / `serverProvisionVerifyIterations` / `deploymentDatabaseVerifyIterations` / `deploymentBackendVerifyIterations` / `deploymentEdgeVerifyIterations` / `deploymentVerifyIterations`); exceeding it marks the stage `needs-attention` **before** launching the fix agent again and continues wherever technically possible. `phase = blocked` is reserved for a hard dependency that makes the next stage impossible. |
