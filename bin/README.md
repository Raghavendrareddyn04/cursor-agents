# `bin/` — Sunny bootstrap scripts

One-shot helpers that make "start Sunny" a single command.

| Script | Purpose | When to run |
|---|---|---|
| `start-sunny.sh` (or `.bat`) | Bootstrap a fresh Sunny repo: create `.env` from `.env.example`, prompt for `DOMAIN` / `ACME_EMAIL` / `FLEET_DOMAIN`, optionally `git clone` the frontend, run the Phase −2 self-test, print the kickoff command. | Once per project / per VPS. Idempotent. |
| `smoke-test-deploy.sh` | Phase 5.0 pre-flight: SSH handshake, DNS propagation, inbound ports 22/80/443, sudo NOPASSWD. | Immediately before `sunny deploy` / before launching Rajesh. Idempotent. |

## Usage

### Fresh project (Pattern A — monorepo, you commit the frontend)

```bash
# 1. Clone this repo
git clone <this repo> mememates-backend-agent && cd mememates-backend-agent

# 2. Drop your React/Vite frontend in ./frontend/
cp -r /path/to/your-frontend ./frontend
git add frontend && git commit -m "import frontend"

# 3. Bootstrap
./bin/start-sunny.sh --domain=app.example.com --fleet=fleet.example.com
#  → follow the prompts (or pass --non-interactive in CI)
#  → script prints the exact "start sunny with …" line to send to your AI

# 4. Tell your AI assistant:
#    "start sunny with domain app.example.com and fleet fleet.example.com"
```

### Fresh project (Pattern B — frontend stays in a separate repo)

```bash
# 1. Clone this repo and bootstrap (no frontend yet)
git clone <this repo> mememates-backend-agent && cd mememates-backend-agent

# 2. Tell start-sunny.sh where the frontend lives
./bin/start-sunny.sh --domain=app.example.com \
  --non-interactive \
  -- \
  FRONTEND_REPO_URL=git@github.com:you/your-frontend.git

# (or edit .env after bootstrap and set FRONTEND_REPO_URL, then re-run)

# 3. Script will git-clone the frontend into ./frontend/ on the next run
./bin/start-sunny.sh --no-preflight
```

### Deploy pre-flight

```bash
# Make sure VPS is reachable before launching Phase 5
./bin/smoke-test-deploy.sh --vps=1.2.3.4 --user=ubuntu --domain=app.example.com
#  → PASS: launch Rajesh
#  → FAIL: fix the items, re-run
```

## Flags

### `start-sunny.sh`

| Flag | Effect |
|---|---|
| `--domain=DOMAIN` | Skip the prompt for project domain |
| `--fleet=DOMAIN` | Skip the prompt for fleet domain |
| `--email=EMAIL` | Skip the prompt for Let's Encrypt email |
| `--frontend-path=PATH` | Where the frontend lives (default `./frontend`) |
| `--no-clone` | Skip the optional `git clone` of `FRONTEND_REPO_URL` |
| `--no-preflight` | Skip the Phase −2 self-test (use only if you trust your env) |
| `--non-interactive` | Never prompt; fail if required inputs are missing (CI mode) |
| `-h`, `--help` | Show help |

### `smoke-test-deploy.sh`

| Flag | Effect |
|---|---|
| `--vps=IP` | Override `VPS_IP` from `.env` |
| `--user=USER` | Override `VPS_USER` (default `root`) |
| `--domain=DOMAIN` | Override `DOMAIN` from `.env` |
| `--skip-ssh` | Skip the SSH handshake check |
| `--skip-dns` | Skip the DNS propagation check |
| `--skip-ports` | Skip the inbound-port check |
| `-h`, `--help` | Show help |

## Exit codes

Both scripts follow the standard convention:

- `0` — every check passed, proceed
- `1` — at least one check failed, do not proceed
- `2` — argument error (bad flag, missing value)

## Idempotency

Both scripts are safe to re-run any number of times:

- `start-sunny.sh` never clobbers an existing `.env` (Maya is the only writer, and she only fills missing keys).
- `smoke-test-deploy.sh` is read-only against the VPS — it never modifies state.

## Adding to the repo

These scripts are committed in `bin/`. To make them runnable from anywhere on the VPS, add `bin/` to `$PATH` or symlink:

```bash
ln -s "$(pwd)/bin/start-sunny.sh" /usr/local/bin/sunny
# then: sunny --domain=app.example.com
```
