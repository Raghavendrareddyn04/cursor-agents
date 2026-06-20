# Hermes Agent + Jarvis — Full VPS Setup From Scratch

**Purpose:** Reproduce the entire stack on a **new VPS** after cloning this repo. Covers Hermes (brain), Jarvis (voice HUD), Sunny bridge, systemd services, nginx, DNS, testing, and backup before a server shutdown.

**Companion docs in this repo:**

| Doc | When to read |
|-----|----------------|
| [HERMES-SUNNY-GUIDE.md](HERMES-SUNNY-GUIDE.md) | Running Sunny pipeline on Hermes |
| [HERMES-MAPPING.md](HERMES-MAPPING.md) | Cursor ↔ Hermes technical mapping |
| [INSTALL.md](INSTALL.md) | Sunny/JHipster/Docker prerequisites |
| [FLEET-QUICKSTART.md](FLEET-QUICKSTART.md) | Multi-VPS fleet dashboard |
| [deploy/](deploy/) | Copy-paste systemd + nginx + `.env` templates |

---

## 1. What you are building

Three separate git repos work together on one VPS:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  YOU                                                                     │
│  • Browser HUD (mic + voice)                                            │
│  • Hermes CLI: hermes                                                    │
│  • "Sunny, build the backend…"                                          │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
┌───────────────┐     ┌─────────────────┐     ┌─────────────────────┐
│ Jarvis        │     │ Hermes Gateway  │     │ cursor-agents       │
│ /opt/jarvis   │────▶│ /root/.hermes   │◀────│ /opt/cursor-agents  │
│ voice + HUD   │ API │ brain + tools   │reads│ 62 Sunny agents     │
└───────────────┘     └────────┬────────┘     └─────────────────────┘
                               │
                               ▼
                        Gemini / OpenRouter / etc.
```

| Piece | Repo | Path on VPS | Role |
|-------|------|-------------|------|
| **cursor-agents** | `Raghavendrareddyn04/cursor-agents` | `/opt/cursor-agents` | Sunny agent definitions (`.cursor/agents/`) |
| **Hermes Agent** | `NousResearch/hermes-agent` | `/root/.hermes/hermes-agent` | Runtime: terminal, files, web, `delegate_task` |
| **Jarvis** | `eadmin2/jarvis_ai` | `/opt/jarvis` | Voice STT + ElevenLabs TTS + browser HUD |

**Secrets live in one place only:** `~/.hermes/.env` — never in git repos.

---

## 2. Recommended VPS layout

```
/opt/
├── cursor-agents/          # this repo — Sunny agents
├── jarvis/                 # voice + HUD server
├── your-project/           # e.g. arcadian-wealth — app + .sunny/ runtime
└── LAYOUT.md               # optional path reference (create on server)

/root/.hermes/              # Hermes home (hidden)
├── hermes-agent/           # git clone + Python venv
├── config.yaml             # model, tools, TTS, gateway settings
├── .env                    # ALL API keys (gitignored)
├── skills/devops/sunny/    # Sunny bridge skill
└── plugins/hud_display/    # Jarvis HUD plugin for Hermes
```

Symlink agents into any project:

```bash
ln -sf /opt/cursor-agents/.cursor /opt/your-project/.cursor
```

---

## 3. VPS requirements

| Item | Minimum | Recommended |
|------|---------|-------------|
| OS | Ubuntu 22.04 | Ubuntu 24.04 |
| CPU | 4 vCPU | 8 vCPU |
| RAM | 8 GB | 16 GB (Whisper + Docker + Java) |
| Disk | 40 GB SSD | 80 GB SSD |

**Firewall ports:**

| Port | Service |
|------|---------|
| 22 | SSH |
| 80 | HTTP (Certbot) |
| 443 | HTTPS (nginx → app or Jarvis HUD) |
| 8765 | Jarvis (loopback; nginx proxies public HTTPS) |
| 8642 | Hermes API (loopback only — do not expose publicly) |
| 8787 | Early Sunny progress dashboard (optional) |

---

## 4. Base packages

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl wget ca-certificates build-essential \
  python3 python3-pip python3-venv jq openssl nginx certbot python3-certbot-nginx
```

For full Sunny pipeline also install Docker, Node 20, JDK 17 — see [INSTALL.md](INSTALL.md).

---

## 5. Clone repos

```bash
sudo mkdir -p /opt && cd /opt

# 1) Sunny agents (this repo)
git clone https://github.com/Raghavendrareddyn04/cursor-agents.git

# 2) Jarvis voice server
git clone https://github.com/eadmin2/jarvis_ai.git jarvis
```

Hermes is installed in the next step (installer clones into `~/.hermes/hermes-agent`).

---

## 6. Install Hermes Agent

Official one-liner (installs Python 3.11, Node, venv, `hermes` CLI):

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
source ~/.bashrc
hermes --version    # expect v0.16+
```

**Manual equivalent** (if installer fails):

```bash
git clone https://github.com/NousResearch/hermes-agent.git ~/.hermes/hermes-agent
cd ~/.hermes/hermes-agent
# install uv first: curl -LsSf https://astral.sh/uv/install.sh | sh
uv venv --python 3.11 venv
source venv/bin/activate && uv pip install -e .
ln -sf ~/.hermes/hermes-agent/venv/bin/hermes ~/.local/bin/hermes
```

### 6.1 Configure LLM provider

```bash
hermes setup          # interactive — pick provider + model
# OR non-interactive example for Gemini:
hermes auth add gemini
```

**Critical:** In `~/.hermes/config.yaml`, the model field must be **`default`**, not `name`:

```yaml
model:
  provider: gemini
  default: gemini-2.0-flash    # ← correct key (NOT "name:")
```

Wrong key → gateway logs show `model=` empty → Gemini HTTP **404**.

Verify:

```bash
hermes doctor
```

### 6.2 Create secrets file

```bash
cp /opt/cursor-agents/deploy/hermes.env.example ~/.hermes/.env
chmod 600 ~/.hermes/.env
nano ~/.hermes/.env
```

Generate API server key:

```bash
echo "API_SERVER_KEY=$(openssl rand -hex 32)" >> ~/.hermes/.env
echo "JARVIS_HUD_TOKEN=jarvis-$(openssl rand -hex 3)" >> ~/.hermes/.env
```

| Variable | Required for | Notes |
|----------|--------------|-------|
| `GEMINI_API_KEY` or `GOOGLE_API_KEY` | Hermes brain | From [AI Studio](https://aistudio.google.com/apikey); enable billing for agent workloads |
| `API_SERVER_ENABLED=true` | Jarvis | Must be `true` |
| `API_SERVER_KEY` | Jarvis → Hermes | Bearer token for loopback `:8642` |
| `JARVIS_HUD_TOKEN` | Browser HUD | Password prompt in browser |
| `ELEVENLABS_API_KEY` | Jarvis voice | TTS only |

### 6.3 Enable Hermes API + gateway settings

In `~/.hermes/config.yaml` ensure these exist (installer may add them):

```yaml
API_SERVER_ENABLED: true
API_SERVER_HOST: 127.0.0.1
API_SERVER_PORT: 8642
# API_SERVER_KEY: set in .env, not yaml
```

Enable HUD plugin:

```yaml
plugins:
  enabled:
    - hud_display
```

### 6.4 Install Sunny bridge skill

Hermes needs a skill that tells it how to act as Sunny:

```bash
mkdir -p ~/.hermes/skills/devops/sunny
cp /opt/cursor-agents/deploy/sunny-bridge-SKILL.md \
   ~/.hermes/skills/devops/sunny/SKILL.md
```

Or symlink (updates when you `git pull` cursor-agents):

```bash
mkdir -p ~/.hermes/skills/devops
ln -sf /opt/cursor-agents/deploy/sunny-bridge-SKILL.md \
       ~/.hermes/skills/devops/sunny/SKILL.md
```

After editing paths inside the skill for your VPS, restart gateway.

### 6.5 Install Hermes gateway as systemd service

```bash
sudo cp /opt/cursor-agents/deploy/hermes-gateway.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hermes-gateway
```

Verify:

```bash
KEY=$(grep '^API_SERVER_KEY=' ~/.hermes/.env | cut -d= -f2)
curl -s -H "Authorization: Bearer $KEY" http://127.0.0.1:8642/health
# expect JSON with "ok"
journalctl -u hermes-gateway -n 20 --no-pager
```

---

## 7. Install Jarvis voice + HUD

```bash
cd /opt/jarvis/server
python3 -m venv .venv
.venv/bin/pip install fastapi uvicorn requests pyyaml numpy anthropic \
    RealtimeSTT faster-whisper silero-vad websockets psutil

cp config/server.example.yaml config/server.yaml
```

Edit `/opt/jarvis/server/config/server.yaml`:

```yaml
hermes:
  base_url: http://127.0.0.1:8642
  api_key_env: API_SERVER_KEY
  conversation: jarvis-main
  session_key: jarvis:user:main

voice:
  provider: elevenlabs
  model: eleven_flash_v2_5
  voice_id: pNInz6obpgDQGcFmaJgB   # premade "Adam" — safe on free plans
  # Do NOT use instant voice clones unless your ElevenLabs plan allows ivc

server:
  host: 0.0.0.0
  port: 8765
  tls_ports: [8766]                # drop 443 if nginx uses it

security:
  hud_token_env: JARVIS_HUD_TOKEN
  extra_origin_hosts: ["YOUR.VPS.IP", "your-hud-domain.example.com"]
```

**First start downloads Whisper ~460 MB** — allow 60–90 seconds.

### 7.1 TLS for direct IP access (optional)

If you open HUD on `:8766` without nginx:

```bash
cd /opt/jarvis/server
scripts/make-certs.sh
```

Browsers need HTTPS for microphone access.

### 7.2 Install Jarvis systemd service

```bash
sudo cp /opt/cursor-agents/deploy/jarvis-voice.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now jarvis-voice
```

Health check:

```bash
/opt/jarvis/server/scripts/jarvis-health.sh
```

All five lines should show **OK**.

---

## 8. Public HTTPS for Jarvis HUD (nginx)

Browsers require HTTPS for the microphone. Point a DNS **A record** at your VPS IP.

```bash
sudo mkdir -p /var/www/acme
sudo cp /opt/cursor-agents/deploy/nginx-jarvis-hud.conf \
        /etc/nginx/sites-available/jarvis-hud
# Edit server_name + cert paths inside the file
sudo ln -sf /etc/nginx/sites-available/jarvis-hud /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d your-hud-domain.example.com
```

**Example from production VPS:**

- HUD URL: `https://agentprogress.qualityoutsidethebox.org/hud/`
- Jarvis listens on `127.0.0.1:8765`; nginx terminates TLS on 443

Open HUD → enter `JARVIS_HUD_TOKEN` from `~/.hermes/.env` → click ring → speak.

---

## 9. Wire Sunny to Hermes + your project

```bash
# Project workspace
git clone <your-app-repo> /opt/your-project
ln -sf /opt/cursor-agents/.cursor /opt/your-project/.cursor

# Point Hermes shell at project
hermes config set terminal.cwd /opt/your-project

# Codebase graph (once per project)
curl -LsSf https://astral.sh/uv/install.sh | sh && source ~/.local/bin/env
uv tool install graphifyy && graphify install
cd /opt/your-project && graphify .
```

**Invoke Sunny** (CLI or Jarvis voice):

```text
Sunny, build the backend for ./frontend.
Project domain: your-app.example.com
Fleet domain: fleet.example.com
```

Resume after disconnect:

```text
Sunny, resume
```

Full pipeline details: [HERMES-SUNNY-GUIDE.md](HERMES-SUNNY-GUIDE.md).

---

## 10. How everything connects (checklist)

Use this order on a fresh VPS:

| Step | Command / check |
|------|-----------------|
| 1 | `hermes doctor` — LLM key OK |
| 2 | `systemctl is-active hermes-gateway` |
| 3 | `curl -H "Authorization: Bearer $KEY" http://127.0.0.1:8642/health` |
| 4 | `systemctl is-active jarvis-voice` |
| 5 | `curl -s http://127.0.0.1:8765/docs` — Jarvis up |
| 6 | ElevenLabs test (see §11) |
| 7 | Gemini test via Hermes (see §11) |
| 8 | Browser HUD on HTTPS URL + `JARVIS_HUD_TOKEN` |
| 9 | `ln -sf /opt/cursor-agents/.cursor /opt/your-project/.cursor` |
| 10 | `ls ~/.hermes/skills/devops/sunny/SKILL.md` — Sunny bridge present |

**Data flow for voice chat:**

```
Browser mic → nginx:443 → Jarvis:8765 → Whisper STT
  → Hermes API :8642 → Gemini LLM + tools
  → text reply → ElevenLabs TTS → browser speaker
```

Jarvis and CLI share the same Hermes session (`jarvis-main` / `jarvis:user:main` in `server.yaml`).

---

## 11. Testing commands

### ElevenLabs (voice only)

```bash
source ~/.hermes/.env
curl -s -w "\nHTTP %{http_code}\n" -o /tmp/el-test.mp3 \
  -X POST "https://api.elevenlabs.io/v1/text-to-speech/pNInz6obpgDQGcFmaJgB" \
  -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"text":"Jarvis online.","model_id":"eleven_flash_v2_5"}'
file /tmp/el-test.mp3   # expect: Audio file
```

### Gemini (direct API)

```bash
source ~/.hermes/.env
curl -s -o /tmp/gemini.json -w "HTTP %{http_code}\n" \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}" \
  -H 'Content-Type: application/json' \
  -d '{"contents":[{"parts":[{"text":"Say OK"}]}]}'
```

- **200** = working  
- **429** = key valid but quota/billing exhausted — add credits at AI Studio  
- **404** = wrong model name in URL  

### Hermes one-shot

```bash
hermes -p "Reply with exactly: HERMES_OK"
```

### Full Jarvis stack

```bash
/opt/jarvis/server/scripts/jarvis-health.sh
```

---

## 12. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `HTTP 404: Gemini` in HUD | `config.yaml` must use `model.default`, not `model.name`; restart `hermes-gateway` |
| `HTTP 429` / quota | Enable billing on Google AI Studio project; agent uses many calls per turn |
| `model=` empty in gateway logs | Same as 404 — wrong config key |
| HUD 401 / auth loop | `JARVIS_HUD_TOKEN` in browser must match `~/.hermes/.env` |
| Mic blocked | Must use HTTPS (nginx + Let's Encrypt) |
| "Thinking" forever | `systemctl start hermes-gateway`; check `:8642/health` |
| No speech / robotic fallback | Check `ELEVENLABS_API_KEY` and `voice.voice_id` |
| `ivc_not_permitted` (ElevenLabs) | Use a **library/premade** voice ID, not a clone |
| Sunny not recognized | Install bridge skill at `~/.hermes/skills/devops/sunny/SKILL.md` |
| Hermes denies all users | Set platform allowlists or `GATEWAY_ALLOW_ALL_USERS=true` in `.env` (dev only) |
| Port 443 conflict | Jarvis `tls_ports: [8766]` only; let nginx own 443 |

---

## 13. Backup before VPS shutdown

**Tracked in this repo:** [`backup/`](backup/) — configs + secrets from VPS Agentstest (`77.107.95.63`).

```bash
cd /opt/cursor-agents
git pull
sudo ./backup/restore.sh    # on new VPS after Hermes + Jarvis installed
```

See [`backup/README.md`](backup/README.md) for file list and manual steps.

**Also back up separately** (not in git — large/runtime):

```bash
# Report artifacts if you need the HTML reports site
rsync -avz /opt/arcadian-wealth/.sunny/web/ user@new-vps:/opt/arcadian-wealth/.sunny/web/
```

**Regenerate on new VPS** (don't bother backing up):

- Let's Encrypt certs (`certbot` re-issue)
- `~/.hermes/hermes-agent/venv` (reinstall Hermes)
- `/opt/jarvis/server/.venv`
- Whisper model cache

---

## 14. Quick reinstall script (new VPS)

Run as `root` after DNS points to the new IP:

```bash
#!/bin/bash
set -euo pipefail

# Base
apt update && apt install -y git curl nginx certbot python3-certbot-nginx

# Repos
mkdir -p /opt && cd /opt
git clone https://github.com/Raghavendrareddyn04/cursor-agents.git
git clone https://github.com/eadmin2/jarvis_ai.git jarvis

# Hermes
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
source ~/.bashrc

# Restore secrets from backup BEFORE continuing:
#   scp hermes-backup.tar.gz new-vps:/root/ && tar xzf hermes-backup.tar.gz -C /
# OR create fresh:
cp /opt/cursor-agents/deploy/hermes.env.example ~/.hermes/.env
chmod 600 ~/.hermes/.env && nano ~/.hermes/.env

# Fix model key if needed
grep -q 'default:' ~/.hermes/config.yaml || \
  sed -i 's/^  name:/  default:/' ~/.hermes/config.yaml

# Sunny skill
mkdir -p ~/.hermes/skills/devops/sunny
ln -sf /opt/cursor-agents/deploy/sunny-bridge-SKILL.md \
       ~/.hermes/skills/devops/sunny/SKILL.md

# Services
cp /opt/cursor-agents/deploy/hermes-gateway.service /etc/systemd/system/
cp /opt/cursor-agents/deploy/jarvis-voice.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now hermes-gateway

# Jarvis venv
cd /opt/jarvis/server
python3 -m venv .venv
.venv/bin/pip install fastapi uvicorn requests pyyaml numpy anthropic \
    RealtimeSTT faster-whisper silero-vad websockets psutil
cp config/server.example.yaml config/server.yaml
# EDIT server.yaml before starting:
nano config/server.yaml
systemctl enable --now jarvis-voice

echo "Done. Run jarvis-health.sh and configure nginx + certbot."
```

---

## 15. Git remotes reference

| Repo | Remote |
|------|--------|
| cursor-agents | `https://github.com/Raghavendrareddyn04/cursor-agents.git` |
| Hermes Agent | `https://github.com/NousResearch/hermes-agent.git` |
| Jarvis | `https://github.com/eadmin2/jarvis_ai.git` |

---

## 16. What NOT to commit

| Never in git | Where it lives |
|--------------|----------------|
| API keys | `~/.hermes/.env` |
| Project secrets | `<project>/.env` |
| Runtime state | `<project>/.sunny/` |
| TLS private keys | `/etc/letsencrypt/` |
| Whisper / venv | local caches |

Only commit **templates**: `deploy/hermes.env.example`, `.env.example` in projects.

---

## 17. Cursor agent on new VPS

Give any Cursor agent this single file plus:

```text
Read /opt/cursor-agents/HERMES-JARVIS-SETUP.md and set up Hermes + Jarvis from scratch.
Repos are at /opt/cursor-agents and /opt/jarvis.
Secrets go in ~/.hermes/.env only.
```

For Sunny backend builds, also point it at [INSTALL.md](INSTALL.md) and [HERMES-SUNNY-GUIDE.md](HERMES-SUNNY-GUIDE.md).

---

*Last updated from VPS Agentstest (77.107.95.63) — Hermes v0.16, Jarvis + ElevenLabs + Gemini stack.*
