# VPS backup — Agentstest (77.107.95.63)

Sanitized snapshot of this server's Hermes + Jarvis + nginx config so you can restore on a new VPS after `git pull`.

**Restore guide:** run `./backup/restore.sh` on the new server (as root), or follow steps below.

---

## What's in this folder

| File | Restore to |
|------|------------|
| `hermes.config.yaml` | `~/.hermes/config.yaml` |
| `vps-agentstest-secrets.env` | `~/.hermes/.env` (merge or replace) |
| `jarvis.server.yaml` | `/opt/jarvis/server/config/server.yaml` |
| `hermes-gateway.service` | `/etc/systemd/system/hermes-gateway.service` |
| `jarvis-voice.service` | `/etc/systemd/system/jarvis-voice.service` |
| `sunny-bridge-SKILL.md` | `~/.hermes/skills/devops/sunny/SKILL.md` |
| `nginx/agentprogress-jarvis.conf` | `/etc/nginx/sites-available/agentprogress-jarvis` |
| `nginx/unitedfinance-reports.conf` | `/etc/nginx/sites-available/unitedfinance-reports` |

## Domains on this VPS

| Domain | Purpose |
|--------|---------|
| `agentprogress.qualityoutsidethebox.org` | Jarvis HUD (`/hud/`) |
| `unitedfinance.qualityoutsidethebox.org` | Static reports only (`.sunny/web`) |

## Quick restore (new VPS)

```bash
cd /opt/cursor-agents
git pull

# 1) Install Hermes + Jarvis first (see HERMES-JARVIS-SETUP.md), then:
sudo ./backup/restore.sh

# 2) Re-issue TLS certs (DNS must point to new IP first)
sudo certbot --nginx -d agentprogress.qualityoutsidethebox.org
sudo certbot --nginx -d unitedfinance.qualityoutsidethebox.org

# 3) Verify
systemctl status hermes-gateway jarvis-voice nginx
/opt/jarvis/server/scripts/jarvis-health.sh
```

## Manual restore

```bash
REPO=/opt/cursor-agents

mkdir -p ~/.hermes/skills/devops/sunny
cp "$REPO/backup/hermes.config.yaml" ~/.hermes/config.yaml
cp "$REPO/backup/vps-agentstest-secrets.env" ~/.hermes/.env
chmod 600 ~/.hermes/.env
cp "$REPO/backup/sunny-bridge-SKILL.md" ~/.hermes/skills/devops/sunny/SKILL.md

cp "$REPO/backup/jarvis.server.yaml" /opt/jarvis/server/config/server.yaml

sudo cp "$REPO/backup/hermes-gateway.service" /etc/systemd/system/
sudo cp "$REPO/backup/jarvis-voice.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hermes-gateway jarvis-voice

sudo cp "$REPO/backup/nginx/agentprogress-jarvis.conf" /etc/nginx/sites-available/agentprogress-jarvis
sudo cp "$REPO/backup/nginx/unitedfinance-reports.conf" /etc/nginx/sites-available/unitedfinance-reports
sudo ln -sf /etc/nginx/sites-available/agentprogress-jarvis /etc/nginx/sites-enabled/
sudo ln -sf /etc/nginx/sites-available/unitedfinance-reports /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

## Security

`vps-agentstest-secrets.env` is a **template only** — fill in all values on the new VPS after restore. No API keys or tokens are stored in git.

```bash
openssl rand -hex 32   # for API_SERVER_KEY
echo "jarvis-$(openssl rand -hex 3)"   # for JARVIS_HUD_TOKEN
```

## Not included (regenerate on new VPS)

- Let's Encrypt certificates (`certbot` re-issue)
- Python venvs (`hermes` installer + Jarvis `pip install`)
- Whisper model cache
- `/opt/arcadian-wealth/.sunny/web/` report artifacts (rsync separately if needed)
