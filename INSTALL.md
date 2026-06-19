# Installation & VPS setup — Sunny multi-agent system

Everything you need to install **before** running Sunny on a VPS (or locally), how to **clone and wire GitHub repos**, and how to avoid the common edge cases.

**Stack:** React frontend · JHipster microservices backend (Java) · PostgreSQL · Docker Compose · Nginx + Certbot · Graphify · optional Newman / Playwright / k6.

---

## 1. What gets committed vs what stays on the server

| Track in Git | Ignore (see [`.gitignore`](.gitignore)) |
|--------------|----------------------------------------|
| `.cursor/` — agent definitions, orchestrator rules, dashboard templates | `.sunny/` — runtime context + live dashboard data |
| React frontend **source** (`src/`, `package.json`, …) | `node_modules/`, `dist/`, `build/` |
| JHipster backend **source** (services, gateway, JDL, `.jhipster/`) | `target/`, `build/`, `*.class` |
| `docker-compose*.yml`, Nginx configs (no secrets) | `.env`, `*.pem`, `*.key`, `letsencrypt/` |
| Docs (`README.md`, `INSTALL.md`, …) | `graphify-out/` (regenerated) |
| [`.env.example`](.env.example) (template only) | Real `.env` with passwords |

After clone on the VPS you run `graphify .` once; Sunny/Maya create `.sunny/` **and the root `.env` (with strong auto-generated secrets)** at runtime. You only pre-create `.env` if you want to **override** a value (e.g. supply your own DB password) — Maya never clobbers an existing `.env`, she only fills missing keys.

---

## 2. Repository layout on the VPS (recommended)

Two common patterns — pick one:

### Pattern A — Monorepo (simplest)

```
my-project/                 # one GitHub repo
├── .cursor/                # Sunny agent system (from this repo or submodule)
├── .gitignore              # use the root .gitignore from this repo
├── .env.example
├── frontend/               # React app
├── gateway/                # generated JHipster gateway
├── services/               # generated microservices
├── docker-compose.yml
└── ...
```

### Pattern B — Agents repo + project repo

```
/opt/sunny-agents/          # clone: github.com/you/sunny-agents (this repo)
└── .cursor/

/opt/my-app/                # clone: github.com/you/my-app
├── frontend/
├── (generated backend…)
└── .cursor/  → symlink or copy from /opt/sunny-agents/.cursor
```

```bash
# Example symlink on Linux VPS:
ln -s /opt/sunny-agents/.cursor /opt/my-app/.cursor
```

### Pattern C — Fleet (many VPSs, same agents, one global view)

> **Exact prompts, step by step:** see [`FLEET-QUICKSTART.md`](FLEET-QUICKSTART.md) — first VPS (fleet host + build) vs. later VPSs (build only).

Use the **same** `.cursor/` on every worker VPS (clone this repo or symlink). Each VPS runs Sunny **independently** for a different project/domain. Deploy the fleet collector **once** on a central host:

| Host | Role | What runs |
|------|------|-----------|
| **Central VPS** | Fleet dashboard only | `.cursor/central/` → `https://<fleet-domain>/` |
| **Worker VPS #1, #2, …** | Full Sunny pipeline | Same `.cursor/` agents + project frontend; pushes progress to central |

**On the central host (once — an agent does it):** invoke the **Fleet Host Agent (Hari)** — it writes `.env`, issues the cert, starts the stack, schedules renewal, and validates the board. You only ensure DNS + ports first.

```text
# In Cursor on the central host (repo cloned, Docker installed):
"Sunny, set up the fleet dashboard host. Fleet domain: fleet.example.com (admin@example.com)."
```

Prefer to do it by hand? The manual steps are below — token is still auto-generated.

```bash
cd /opt/sunny-agents/.cursor/central
cp .env.example .env   # CENTRAL_DOMAIN + ACME_EMAIL only; token auto-generated
# issue cert + docker compose up — see .cursor/central/README.md
```

**On every worker VPS:**

```bash
ln -s /opt/sunny-agents/.cursor /opt/my-app/.cursor
graphify .
# Sunny prompt — two domains only:
# "Sunny, build backend for ./frontend. Project domain: mememates.org. Fleet domain: fleet.example.com"
```

Maya auto-generates `RUN_ID`, all secrets, fetches the fleet push token, starts the local publisher, and pushes to the global board. **You never copy tokens or hand-write `.env`.**

**Fleet host scope:** the collector is **visibility only, not HA** — a single file-backed board. If it goes down, worker runs continue locally and retry pushes; nothing load-bearing depends on it. See [`.cursor/central/README.md`](.cursor/central/README.md) ("Scope: visibility only").

**Internet-facing fleet domain?** By default the dashboard and `/api/fleet-config` are public (workers need the latter for zero-config). If the fleet domain is on the public internet, enable **Basic-Auth on the human routes** (`/` + `/api/runs` index) per `nginx-central.conf` — workers stay zero-config. See README "Exposure model".

**Windows → Linux:** [`.gitattributes`](.gitattributes) forces LF for shell scripts and Docker files so `mvnw` / `gradlew` work after clone on the VPS.

---

## 3. VPS requirements

| Item | Minimum | Recommended |
|------|---------|-------------|
| OS | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS |
| CPU | 4 vCPU | 8 vCPU (JHipster + tests + load tests) |
| RAM | 8 GB | 16 GB |
| Disk | 40 GB SSD | 80 GB SSD |
| Network | Public IPv4 | + DNS A record → VPS IP |

Open firewall ports:

| Port | Purpose |
|------|---------|
| **22** | SSH |
| **80** | HTTP (Certbot ACME + redirect to HTTPS) |
| **443** | HTTPS (frontend + `/api` + `/agentprogress.html`) |
| **8787** | Early progress dashboard (until Nginx stage; then close if you want) |

```bash
# UFW example (Ubuntu):
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8787/tcp   # optional: early dashboard only
sudo ufw enable
```

**DNS:** create an **A record** for your domain → VPS public IP **before** the Nginx/Certbot stage.

---

## 4. Base system packages (Ubuntu)

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
  git curl wget ca-certificates gnupg lsb-release \
  build-essential unzip jq openssl \
  python3 python3-pip python3-venv
```

---

## 5. Docker & Docker Compose (required)

The whole stack runs in containers: PostgreSQL, JHipster services, React frontend (build or serve), Nginx, Certbot, early progress publisher.

```bash
# Official Docker CE install (Ubuntu):
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Run docker without sudo (log out/in after):
sudo usermod -aG docker $USER

# Verify:
docker --version
docker compose version
```

**Edge case:** if `docker compose` is missing, install the `docker-compose-plugin` package above — do not use the legacy standalone `docker-compose` v1 unless you have no choice.

---

## 6. Git (required)

```bash
git --version   # 2.x+

# First-time identity (for commits on VPS if needed):
git config --global user.name "Your Name"
git config --global user.email "you@example.com"

# Optional: reuse GitHub deploy key or PAT for private repos
```

### Clone workflow on the VPS

```bash
# 1) Clone your project (and/or agents repo)
git clone git@github.com:you/my-project.git
cd my-project

# 2) If agents live in a separate repo, link .cursor:
#    ln -s /path/to/sunny-agents/.cursor .cursor

# 3) Environment — OPTIONAL. Maya auto-generates .env + secrets at intake.
#    Only do this if you want to override values (e.g. your own DB password):
# cp .env.example .env
# nano .env    # set DOMAIN, ACME_EMAIL, POSTGRES_PASSWORD, JWT secret, etc.
#    Otherwise just provide DOMAIN + Certbot email in the Sunny prompt.

# 4) Bootstrap Graphify (once per project root)
uv tool install graphifyy    # see section 8 if uv not installed yet
graphify install
graphify .                   # initial graph; agents use `graphify update` after that

# 5) Invoke Sunny in Cursor (or your orchestrator) pointing at ./frontend
```

### Push workflow (dev machine → GitHub → VPS)

```bash
# On your machine: commit source + .cursor, never secrets/runtime
git add .
git status    # confirm NO .env, .sunny/, node_modules/, target/, graphify-out/, *.pem

git commit -m "feat: ..."
git push origin main

# On VPS:
cd /opt/my-project
git pull origin main
# Rebuild/restart only what changed:
docker compose up -d --build <service>
```

---

## 7. Java JDK (required for JHipster backend)

JHipster generates **Java** (Spring Boot). Use **JDK 17** (JHipster 8 default) or **21** if your generated apps target it.

```bash
# Ubuntu — Eclipse Temurin 17 (recommended):
sudo apt install -y temurin-17-jdk

java -version   # should show 17.x
```

**Also needed on the VPS (inside Docker builds too):** Maven or Gradle — generated projects include `./mvnw` / `./gradlew` wrappers; **commit those wrappers** (`.gitignore` keeps them).

**Edge case:** do not install only JRE — you need the full JDK for compilation and Javadoc.

---

## 8. Node.js (required for React frontend + tooling)

React frontend needs Node for `npm ci` / `npm run build`. Agents also use Node for **Newman** (API collection), **Playwright** (E2E), and often **Vitest/Jest**.

```bash
# Node 20 LTS via NodeSource (Ubuntu):
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

node -v    # v20.x
npm -v
```

Install frontend deps after clone:

```bash
cd frontend
npm ci          # prefer ci over install for reproducible VPS builds
```

**Global / project tooling** (install as agents need them — can be project devDependencies):

```bash
# Newman — API collection CI (Chetan agent)
npm install -g newman

# Playwright — E2E (Anika agent); also installs browser deps:
cd frontend && npm install -D @playwright/test
npx playwright install --with-deps chromium

# Optional: k6 for API performance (Pawan agent)
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | \
  sudo tee /etc/apt/sources.list.d/k6.list
sudo apt update && sudo apt install -y k6
```

---

## 9. Graphify (required — token-efficient context)

Pre-install **before** Sunny runs. Operators install; agents run `graphify update` after code changes.

```bash
# Install uv (Python package manager) if you don't have it:
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env   # or restart shell

# Install Graphify CLI (PyPI package name: graphifyy)
uv tool install graphifyy
graphify install

# Optional project-scoped skill:
graphify install --project

# Bootstrap knowledge graph once per project (after clone):
cd /opt/my-project
graphify .
# Thereafter agents only need:  graphify update .
```

Output: `graphify-out/` — **gitignored**, regenerated on each machine.

---

## 10. JHipster CLI (optional on VPS)

Sunny's **Vikram** agent generates the backend; you do **not** have to install JHipster globally on the VPS unless you want manual CLI access.

```bash
# Optional — only if you want the CLI locally:
npm install -g generator-jhipster
jhipster --version
```

Generation typically happens inside the agent workflow; Docker builds use the committed source.

---

## 11. Cursor / IDE (where Sunny runs)

Sunny orchestration runs from **Cursor** (or any environment that can launch the Task subagents defined in `.cursor/agents/`).

- **Development:** Cursor on your machine, repo cloned, `.cursor/` present.
- **VPS:** clone repo, edit/run via Cursor SSH Remote, or run agents from your machine against a synced clone.

The VPS must have everything in sections 4–9 so agents can **build, test, and deploy** what they generate.

---

## 11b. Production deployment prerequisites (Minikube / Helm / Grafana)

Suresh (`server-provision-agent`) installs these automatically during the production deployment stage, but pre-installing them on the VPS speeds up the first run. The full runbook lives in [`deploy/README.md`](deploy/README.md).

```bash
# Minikube + kubectl + a container runtime (docker driver)
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Helm 3
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Kubernetes CLI
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/kubectl

# PM2 (for frontend hosting on the host)
npm install -g pm2
```

Verify the host is ready:

```bash
minikube version    # >= 1.32
helm version        # >= 3.13
kubectl version --client
pm2 --version
docker --version    # already in section 5
```

If the host has fewer than **4 CPU / 8 GB RAM** available to Minikube, lower the profile in `.env`:

```bash
MINIKUBE_CPUS=2
MINIKUBE_MEMORY=4096
```

---

## 12. First-time checklist (copy/paste)

```bash
# --- On VPS after git clone ---
cd /opt/my-project

# .env is auto-generated by Maya at intake (DOMAIN/email come from the Sunny prompt).
# OPTIONAL override only: cp .env.example .env && nano .env

# Graphify
uv tool install graphifyy && graphify install && graphify .

# Frontend
cd frontend && npm ci && cd ..

# Docker stack (after Sunny generates backend — or if already present):
docker compose up -d --build

# Early progress dashboard (Sunny/Maya also document this):
docker compose -f .sunny/web/docker-compose.yml up -d
# Open: http://<server-ip>:8787/agentprogress.html

# Invoke Sunny with domain at intake, e.g.:
# "Sunny, build the backend for ./frontend using domain example.com (admin@example.com)"
```

---

## 13. Edge cases & how we handle them

| Edge case | Resolution |
|-----------|------------|
| **Secrets in Git** | `.env`, `*.pem`, `*.key`, `letsencrypt/` in [`.gitignore`](.gitignore). Only [`.env.example`](.env.example) is tracked. |
| **`.sunny/` committed by mistake** | Gitignored. Contains run-specific context + `progress.json`. Regenerated each Sunny run. |
| **`graphify-out/` huge / stale** | Gitignored. Run `graphify .` after clone, then agents run `graphify update`. |
| **CRLF breaks `mvnw` on Linux** | [`.gitattributes`](.gitattributes) forces LF for shell scripts and YAML. |
| **`node_modules/` or `target/` pushed** | Gitignored. On VPS: `npm ci` and `docker compose build`. |
| **Port 8787 blocked** | Open in UFW/security group, or set `PROGRESS_PORT` in `.env`. |
| **Certbot fails** | DNS A record must point to VPS **before** Nginx stage; ports 80/443 open. |
| **Frontend still calls localhost API** | Naveen sets `VITE_API_URL` / `REACT_APP_API_URL` to `https://<domain>/api` and **rebuilds** the frontend container. |
| **Code changed but tests see old behavior** | Agents rebuild + restart affected services (`docker compose up -d --build <service>`). See README "Restarts". |
| **Dashboard disappears during restart** | Early publisher is separate; Nginx uses graceful reload; `.sunny/web` is static — progress stays visible. |
| **Private GitHub repo on VPS** | Use deploy key or `gh auth login` / PAT; `git pull` in deploy script. |
| **Two repos (agents + app)** | Symlink or copy `.cursor/` into project root; keep agents repo pull separate. |
| **JDK / Node version drift** | Pin Node 20 + JDK 17 in this doc; match in Docker base images. |
| **Wrapper jars missing after clone** | `.gitignore` explicitly **keeps** `maven-wrapper.jar` / `gradle-wrapper.jar`. |
| **JHipster `.jhipster/*.json` ignored** | `.gitignore` keeps `!**/.jhipster/` — entity JSON is source. |
| **Accidentally committed `.env`** | `git rm --cached .env`, rotate all secrets, ensure `.gitignore` is in place. |
| **An agent needs a new secret mid-run** | Internal secrets (passwords, signing keys) are **self-service**: the agent appends them to `.env` with `openssl rand` and registers the key name with Maya — no blocking. |
| **A third-party provider key is required** | The agent can't mint it: it adds a `__set-me__` placeholder, flags the integration off, and surfaces an **"Action required"** item (dashboard + final report). The run continues; you supply the real key in `.env` and that stage picks it up. |
| **A loop can't reach a clean pass** | The iteration cap stops the loop; the pipeline **does not halt** — the stage is marked `needs-attention`, items become notifications, and the run continues. Only a hard technical dependency (won't build) stops it. |
| **Watch many VPS runs at once** | Deploy `.cursor/central/` on fleet domain via the **Fleet Host Agent (Hari)** (domain + email only). Each worker gives Sunny **project + fleet domain**; agents fetch token and push. |
| **Central collector unreachable** | Pushes are best-effort; the local dashboard keeps working and the next handoff retries — the run is never blocked. |
| **`.env.example` missing after clone** | Fixed in repo: templates are tracked (`!.env.example`, `!**/.env.example`). If you have an older clone, pull latest or copy templates manually from the repo. |
| **Fleet board on the public internet** | Enable Basic-Auth on dashboard routes (`/` + `/api/runs` index) in `nginx-central.conf` — see central README "Exposure model". Workers still fetch `/api/fleet-config` without Basic-Auth. |
| **VPS reboots / Cursor session closes / agent crashes mid-run** | The run is checkpointed to `.sunny/context/state.json` after every handoff. Re-invoke **"Sunny, resume"** (or the original prompt) in the project — Sunny skips completed stages, re-enters the interrupted one (agents are idempotent), and continues with counters intact. Docker services auto-restart (`restart: unless-stopped`). |
| **Disk full from Docker** | Periodic `docker system prune -af` (careful) + adequate disk per §3. |

---

## 14. Quick reference — install commands only

```bash
# Base
sudo apt update && sudo apt install -y git curl build-essential python3 python3-pip jq openssl temurin-17-jdk

# Docker (see section 5 for full official install)
# Node 20 (see section 7)
# uv + Graphify
curl -LsSf https://astral.sh/uv/install.sh | sh && source $HOME/.local/bin/env
uv tool install graphifyy && graphify install

# Optional globals
npm install -g newman
sudo apt install -y k6   # after k6 apt repo setup in section 7

# Project
git clone <your-repo> && cd <your-repo>
# .env is auto-generated by Maya at intake (override: cp .env.example .env)
graphify .
cd frontend && npm ci
```

---

## 15. Related docs

- [README.md](README.md) — what Sunny is and how to invoke it
- [`.cursor/agents/README.md`](.cursor/agents/README.md) — phase-by-phase workflow
- [`.cursor/agents/ARCHITECTURE.md`](.cursor/agents/ARCHITECTURE.md) — diagrams
- [`.cursor/rules/sunny-orchestrator.mdc`](.cursor/rules/sunny-orchestrator.mdc) — orchestration playbook
- [`.cursor/rules/graphify.mdc`](.cursor/rules/graphify.mdc) — Graphify protocol
- [`.gitignore`](.gitignore) — what never to push
