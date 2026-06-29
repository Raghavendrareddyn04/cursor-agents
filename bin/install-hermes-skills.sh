#!/usr/bin/env bash
# ============================================================================
#  bin/install-hermes-skills.sh — Wire cursor-agents Sunny bridge into Hermes
# ----------------------------------------------------------------------------
#  Idempotent. Safe to re-run after `git pull` in cursor-agents.
#
#  Installs:
#    ~/.hermes/skills/devops/sunny/SKILL.md           (copy, not symlink)
#    ~/.hermes/skills/devops/sunny-agents/<slug>/     (Hermes persona skills)
#
#  Personas are converted from .cursor/agents/*.md so Hermes loads trusted
#  skills under ~/.hermes/skills/ (symlinks outside that tree trigger security
#  warnings and subagents may not get persona context). See HERMES-MAPPING.md.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
SKILL_SRC="$ROOT/deploy/sunny-bridge-SKILL.md"
SKILL_DST="$HERMES_HOME/skills/devops/sunny/SKILL.md"
PERSONAS_DST="$HERMES_HOME/skills/devops/sunny-agents"
CONVERT="$ROOT/bin/convert-cursor-to-hermes-personas.py"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
say_ok()  { printf "${GREEN}OK${NC}   %s\n" "$*"; }
say_err() { printf "${RED}ERR${NC}  %s\n" "$*" >&2; }

echo "============================================================"
echo "  Hermes Sunny bridge install"
echo "  Repo: $ROOT"
echo "  Hermes: $HERMES_HOME"
echo "============================================================"
echo

if [[ ! -f "$SKILL_SRC" ]]; then
  say_err "Missing $SKILL_SRC"
  exit 1
fi

if ! command -v hermes >/dev/null 2>&1; then
  say_err "hermes CLI not found — install first:"
  echo "  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"
  exit 1
fi
say_ok "hermes $(hermes --version 2>/dev/null | head -1 || echo 'present')"

mkdir -p "$(dirname "$SKILL_DST")"
if [[ -L "$SKILL_DST" ]]; then
  rm -f "$SKILL_DST"
fi
cp -f "$SKILL_SRC" "$SKILL_DST"
say_ok "Copied sunny bridge → $SKILL_DST"

if [[ ! -f "$CONVERT" ]]; then
  say_err "Missing $CONVERT"
  exit 1
fi
python3 "$CONVERT" "$PERSONAS_DST"
PERSONA_COUNT=$(find "$PERSONAS_DST" -mindepth 2 -name 'SKILL.md' 2>/dev/null | wc -l)
say_ok "Hermes persona skills: $PERSONA_COUNT under $PERSONAS_DST"

# Agent inventory (informational — not copied into Hermes)
AGENT_COUNT=$(find "$ROOT/.cursor/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)
CANONICAL_COUNT=$(find "$ROOT/.cursor/agents" -maxdepth 1 -name '*-agent.md' 2>/dev/null | wc -l)
say_ok "cursor-agents: $AGENT_COUNT agent .md files ($CANONICAL_COUNT canonical *-agent.md slugs)"

MISSING=0
REQUIRED=(
  frontend-sanitize-agent supabase-removal-agent architecture-agent
  jhipster-backend-agent database-agent nginx-agent
  production-standards-agent deployment-platform-agent server-provision-agent
  deployment-database-agent deployment-backend-agent deployment-edge-agent
  deployment-verify-agent om-fix-agent reports-publish-agent context-agent
)
for slug in "${REQUIRED[@]}"; do
  if [[ ! -f "$ROOT/.cursor/agents/${slug}.md" ]]; then
    say_err "MISSING: .cursor/agents/${slug}.md"
    MISSING=1
  fi
done
[[ $MISSING -eq 0 ]] && say_ok "required pipeline agent files present"

if [[ ! -f "$ROOT/.cursor/rules/sunny-orchestrator.mdc" ]]; then
  say_err "MISSING: .cursor/rules/sunny-orchestrator.mdc"
  exit 1
fi
say_ok "sunny-orchestrator.mdc present"

if rg -q 'counts.total: 23|total: 23' "$ROOT/.cursor/agents/context-agent.md" 2>/dev/null; then
  say_ok "Maya context-agent: 23-stage contract"
else
  say_err "context-agent.md may be stale — expected counts.total: 23"
fi

echo
echo "---- Next steps ----"
echo "  1. Point Hermes at your project:"
echo "       hermes config set terminal.cwd /opt/your-project"
echo "  2. Symlink agents into the project:"
echo "       ln -sf $ROOT/.cursor /opt/your-project/.cursor"
echo "  3. Restart gateway if running:"
echo "       sudo systemctl restart hermes-gateway"
echo "  4. Invoke:"
echo '       Sunny, build the backend for ./frontend. Project domain: example.com'
echo
say_ok "Hermes Sunny bridge installed"
