#!/usr/bin/env bash
# After: agent login (Cursor CLI) — use Rukmini voice for Sunny via Hermes.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"
PROJECT="${PROJECT:-/opt/ascenta-core-hub}"

echo "=== Rukmini + Hermes Sunny readiness ==="
echo

# Cursor CLI
if agent --version &>/dev/null; then
  echo "OK  Cursor agent: $(agent --version 2>/dev/null | head -1)"
else
  echo "ERR Cursor agent not in PATH — run: curl -fsSL https://cursor.com/install | bash"
  exit 1
fi

if agent -p --trust "Reply OK" &>/dev/null 2>&1; then
  echo "OK  Cursor CLI authenticated"
elif [[ -n "${CURSOR_API_KEY:-}" ]]; then
  echo "OK  CURSOR_API_KEY set"
else
  echo "!!  Cursor not authenticated yet — run: agent login"
  echo "    (or export CURSOR_API_KEY=... in ~/.hermes/.env)"
fi

# Hermes + Rukmini
if systemctl is-active --quiet hermes-gateway; then
  echo "OK  hermes-gateway active"
else
  echo "ERR hermes-gateway not running — sudo systemctl start hermes-gateway"
fi

if systemctl is-active --quiet jarvis-voice; then
  echo "OK  jarvis-voice (Rukmini) active"
else
  echo "ERR jarvis-voice not running — sudo systemctl start jarvis-voice"
fi

KEY=$(grep '^API_SERVER_KEY=' ~/.hermes/.env 2>/dev/null | cut -d= -f2- || true)
if [[ -n "$KEY" ]] && curl -sf -H "Authorization: Bearer $KEY" http://127.0.0.1:8642/health >/dev/null; then
  echo "OK  Hermes API :8642 healthy"
else
  echo "ERR Hermes API health check failed"
fi

if [[ -f ~/.hermes/skills/devops/sunny/SKILL.md ]]; then
  echo "OK  Sunny skill installed"
else
  echo "ERR Run: /opt/cursor-agents/bin/install-hermes-skills.sh"
fi

hermes config set terminal.cwd "$PROJECT" 2>/dev/null || true
echo "OK  project cwd: $PROJECT"

if [[ -f "$PROJECT/.sunny/context/state.json" ]]; then
  python3 -c "
import json
s=json.load(open('$PROJECT/.sunny/context/state.json'))
active=[x for x in s.get('stages',[]) if x.get('status')=='active']
print('OK  Sunny state: phase=%s active=%s' % (
  s.get('phase'),
  active[0].get('label') if active else 'none'))
" 2>/dev/null || true
fi

echo
echo "=== Use Rukmini (voice) — say in ENGLISH ==="
echo '  "Sunny, resume"'
echo
echo "Or open HUD in browser (HTTPS), enter JARVIS_HUD_TOKEN from ~/.hermes/.env"
echo "Dashboard: http://$(curl -s ifconfig.me 2>/dev/null || echo SERVER_IP):8787/agentprogress.html"
echo
echo "CLI fallback (keep terminal OPEN — do NOT use -q):"
echo "  cd $PROJECT && hermes chat -s sunny"
echo "  then type: Sunny, resume"
