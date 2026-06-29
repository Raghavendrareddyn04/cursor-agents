#!/bin/bash
# Restore Hermes + Jarvis config from cursor-agents/backup/ on a new VPS.
# Run as root after: Hermes installed, /opt/jarvis cloned, venv created.
set -euo pipefail

REPO="${REPO:-/opt/cursor-agents}"
BACKUP="$REPO/backup"

if [[ ! -d "$BACKUP" ]]; then
  echo "Missing $BACKUP — clone cursor-agents first." >&2
  exit 1
fi

echo "==> Restoring Hermes config"
mkdir -p ~/.hermes/skills/devops/sunny
cp "$BACKUP/hermes.config.yaml" ~/.hermes/config.yaml
cp "$BACKUP/vps-agentstest-secrets.env" ~/.hermes/.env
chmod 600 ~/.hermes/.env
"$REPO/bin/install-hermes-skills.sh"

if [[ -f /opt/jarvis/server/config/server.yaml ]]; then
  echo "==> Restoring Jarvis server.yaml"
  cp "$BACKUP/jarvis.server.yaml" /opt/jarvis/server/config/server.yaml
else
  echo "WARN: /opt/jarvis/server not found — skip jarvis.server.yaml" >&2
fi

echo "==> Installing systemd units"
cp "$BACKUP/hermes-gateway.service" /etc/systemd/system/
cp "$BACKUP/jarvis-voice.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable hermes-gateway jarvis-voice
systemctl restart hermes-gateway || true
systemctl restart jarvis-voice || true

if command -v nginx >/dev/null 2>&1; then
  echo "==> Installing nginx site configs"
  mkdir -p /var/www/acme
  cp "$BACKUP/nginx/agentprogress-jarvis.conf" /etc/nginx/sites-available/agentprogress-jarvis
  cp "$BACKUP/nginx/unitedfinance-reports.conf" /etc/nginx/sites-available/unitedfinance-reports
  ln -sf /etc/nginx/sites-available/agentprogress-jarvis /etc/nginx/sites-enabled/
  ln -sf /etc/nginx/sites-available/unitedfinance-reports /etc/nginx/sites-enabled/
  nginx -t && systemctl reload nginx
else
  echo "WARN: nginx not installed — skip site configs" >&2
fi

echo ""
echo "Restore complete. Next steps:"
echo "  1. Point DNS A records to this server's IP"
echo "  2. sudo certbot --nginx -d agentprogress.qualityoutsidethebox.org"
echo "  3. sudo certbot --nginx -d unitedfinance.qualityoutsidethebox.org"
echo "  4. /opt/jarvis/server/scripts/jarvis-health.sh"
echo "  5. Open https://agentprogress.qualityoutsidethebox.org/hud/ (token in ~/.hermes/.env)"
