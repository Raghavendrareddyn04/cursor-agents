# Fleet quickstart — first VPS vs. later VPSs

How to bring up the **global dashboard** and run backend builds across many VPSs,
using the same `.cursor/` agents on every machine. You only ever provide **two
domains** (project + fleet) and an optional Certbot email — agents generate all
secrets, tokens, and `RUN_ID`s.

- **Fleet host** = the one machine that owns the **fleet domain** and runs the global board (`.cursor/central/`, deployed by the **Fleet Host Agent — Hari**).
- **Worker** = any machine that builds a backend with Sunny and **pushes** its progress to the fleet host.
- The fleet host can be a dedicated box **or** one of your workers — see below.

---

## TL;DR

| Situation | What you do |
|-----------|-------------|
| **First VPS** (also the fleet host) | Set DNS for both domains → ask Sunny to **set up the fleet dashboard host** (Hari) → then ask Sunny to **build and deploy the backend**. |
| **Later VPS** (fleet already up) | Set DNS for the project domain → ask Sunny to **build and deploy the backend**, giving the **same fleet domain**. Do **not** redeploy the fleet host. |

You never copy or type the push token anywhere. Agents fetch it from `https://<fleet-domain>/api/fleet-config`.

"Build and deploy" is a single Sunny invocation — after the production audit (#17), Sunny automatically runs the **Rajesh → Suresh → Lakshmi → Manoj → Asha → Om** deploy tail (dashboard **#18–#23**) and brings the system live on the project domain. See [`deploy/README.md`](deploy/README.md) for the operator runbook.

---

## Prerequisites (every VPS)

1. Docker + Docker Compose installed, and everything from [`INSTALL.md`](INSTALL.md).
2. This agents repo cloned (or `.cursor/` symlinked) **next to / into** your project, so the same agents are available.
3. Graphify bootstrapped once in the project (`graphify .`).
4. DNS A-records pointing at the VPS public IP, with ports **80 + 443** open (see each section).

---

## First VPS — fleet host **and** first backend build

On your first machine you usually want both the global board *and* a backend. Do them as **two prompts, in order**.

### 1. DNS first (you, not the agent)

Point both A-records at this VPS's public IP and open 80/443:

| Record | Points to | Purpose |
|--------|-----------|---------|
| `mememates.org` | this VPS IP | project (frontend + API) |
| `global.mememates.org` | this VPS IP | fleet dashboard |

> Use your own names. The fleet domain **must be different** from the project domain.

### 2. Deploy the fleet dashboard (run-once, Hari)

In Cursor on this VPS:

```text
Sunny, set up the fleet dashboard host.
Fleet domain: global.mememates.org
Certbot email: admin@mememates.org
```

Hari will: write the central `.env`, **auto-generate** the push token, issue the
Let's Encrypt cert, start the collector + Nginx stack, schedule renewal, and
validate `https://global.mememates.org/`. It's idempotent — safe to re-run.

> If `global.mememates.org` isn't resolving yet, Hari says so and can bring up an
> **HTTP-only** board temporarily; re-run the same prompt after DNS propagates to
> get HTTPS. Hari preserves the fallback push token during that cutover so workers
> that already fetched it keep reporting to the same board.

### 3. Build the backend (normal pipeline)

```text
Sunny, build the backend for ./frontend.
Project domain: mememates.org
Fleet domain: global.mememates.org
```

Maya fetches the token from the fleet host and pushes progress after every
handoff. This run appears as the first card on `https://global.mememates.org/`.

### One-message alternative

Sunny will sequence both jobs if you prefer:

```text
Sunny, this VPS is also my fleet host.
First set up the fleet dashboard on global.mememates.org (email admin@mememates.org),
then build the backend for ./frontend on mememates.org and push progress to that fleet board.
```

### Fleet host shares the box with a project?

Hari handles it: the fleet board uses the **different** domain
(`global.…`), shares the Certbot tooling, and **never** overwrites the project's
`.env`, certs, or compose stack. If the project's Nginx already owns 80/443,
Hari adds the fleet domain as another server name through that Nginx instead of
a competing bind, and reports the choice.

---

## Later VPS — fleet domain already active

The fleet host already exists, so you **skip Hari entirely**. Just build, and
hand Sunny the **same** fleet domain so this run reports to the same board.

### 1. DNS (project only)

| Record | Points to | Purpose |
|--------|-----------|---------|
| `app2.com` | this VPS IP | project (frontend + API) |

(The fleet domain still points at the **fleet host**, not this machine.)

### 2. Build the backend

```text
Sunny, build the backend for ./frontend.
Project domain: app2.com
Fleet domain: global.mememates.org
```

That's it. Maya auto-fetches the push token from
`https://global.mememates.org/api/fleet-config`, generates this run's `RUN_ID`
and secrets, and starts pushing. A new card appears on the global board.

Repeat for VPS #3, #4, … — each independent, same fleet domain.

---

## What each command does (under the hood)

| Prompt | Agent | Result |
|--------|-------|--------|
| "set up the fleet dashboard host" | **Hari** (`fleet-host-agent`) | Deploys `.cursor/central/` collector + TLS on the fleet domain. Run **once**. |
| "build the backend … fleet domain: …" | **Sunny** pipeline + **Maya** | Builds/tests/documents the backend; Maya fetches the token and pushes `progress.json` to the fleet host after every handoff. |

The `fleet-host-agent` file ships on **every** VPS (it's in the shared `.cursor/`)
but is **inert** — it only runs when you explicitly ask for the fleet dashboard.
Sunny never auto-launches it during a backend build.

---

## Verify it's working

- **Fleet board:** open `https://<fleet-domain>/` — one card per run.
- **Health:** `curl -fsS https://<fleet-domain>/healthz` → `{"ok": true}`.
- **Local board (each worker):** `https://<project-domain>/agentprogress.html`.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|--------|--------------|-----|
| Hari: cert step failed | Fleet DNS not pointing here yet | Add/fix the A-record, re-run the Hari prompt (it reuses everything, only repairs the cert). |
| No card appears on the board | Worker pushed before fleet host was up, or wrong fleet domain | Confirm the fleet host is live; ensure the build prompt used the exact fleet domain. Pushes retry on the next handoff. |
| Ports 80/443 in use on fleet host | Another stack bound them | Hari reports the conflict; stop the stale stack or let Hari attach the fleet domain to the existing Nginx. |
| "Do I rerun Hari on VPS #2?" | — | **No.** Hari runs once on the fleet host only. Workers just pass the fleet domain. |

See also: [`.cursor/central/README.md`](.cursor/central/README.md),
[`INSTALL.md`](INSTALL.md) (Pattern C), and
[`.cursor/agents/fleet-host-agent.md`](.cursor/agents/fleet-host-agent.md).

## Production notes

- **Visibility only, not HA.** The fleet host is a progress board — single container, file-backed, no clustering. Worker runs never depend on it; they retry pushes if it's down.
- **Internet-facing?** If `global.…` is on the public internet, turn on **Basic-Auth for the dashboard** (`/` + `/api/runs` feed) using the commented lines in `nginx-central.conf` — workers still auto-fetch the push token from `/api/fleet-config`. Details: central README **"Exposure model"**.
