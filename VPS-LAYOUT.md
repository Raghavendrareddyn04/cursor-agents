# VPS layout template

Copy to `/opt/LAYOUT.md` on your server after setup.

## `/opt` — application repos

| Path | Repo | Purpose |
|------|------|---------|
| `/opt/cursor-agents` | `Raghavendrareddyn04/cursor-agents` | Sunny agents + setup docs |
| `/opt/jarvis` | `eadmin2/jarvis_ai` | Jarvis voice + HUD |
| `/opt/your-project` | your app repo | Frontend + generated backend |

```bash
ln -sf /opt/cursor-agents/.cursor /opt/your-project/.cursor
```

## `/root/.hermes` — Hermes Agent

| Path | Purpose |
|------|---------|
| `/root/.hermes/hermes-agent` | Hermes git clone + venv |
| `/root/.hermes/config.yaml` | Model, tools, gateway |
| `/root/.hermes/.env` | API keys (never commit) |
| `/root/.hermes/skills/devops/sunny/SKILL.md` | Sunny bridge |

CLI: `/root/.local/bin/hermes`

## Services

```bash
systemctl status hermes-gateway jarvis-voice nginx
```

| Service | Port | Role |
|---------|------|------|
| `hermes-gateway` | 8642 loopback | Hermes API |
| `jarvis-voice` | 8765 | Voice + HUD |
| `nginx` | 443 | TLS proxy to HUD or app |

Full setup: `/opt/cursor-agents/HERMES-JARVIS-SETUP.md`
