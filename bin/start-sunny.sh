#!/usr/bin/env bash
# ============================================================================
#  bin/start-sunny.sh — Sunny bootstrap
# ----------------------------------------------------------------------------
#  One-shot setup so the user can type exactly ONE command to start Sunny.
#
#  What it does (in order, all idempotent / safe to re-run):
#    1. Sanity check: this is a Sunny repo (looks for .cursor/rules/ and
#       sunny-orchestrator.mdc) and required CLI tools are on PATH.
#    2. Create .env from .env.example if missing. NEVER clobber an existing
#       .env — Maya only fills missing keys at intake.
#    3. If .env is missing DOMAIN/ACME_EMAIL/FLEET_DOMAIN, prompt the user.
#       In non-interactive mode, fall back to env vars passed on the command
#       line (e.g. `start-sunny.sh --domain=foo.com --non-interactive`).
#    4. Optionally `git clone` the frontend into ./frontend/ if FRONTEND_REPO_URL
#       is set in .env (Pattern B in INSTALL.md). Default ./frontend/ path
#       matches Phase 0 intake.
#    5. Run the Phase −2 self-test from the orchestrator rule (CLI tools,
#       agent file inventory, .env present) and print a clear PASS/FAIL.
#    6. Print the kickoff command for the user's AI assistant: literally
#       "start sunny with domain <X> and fleet <Y>".
#
#  Re-running this script is safe — every step is idempotent. If anything
#  fails the script exits non-zero with a precise error.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ----- arg parsing ----------------------------------------------------------
DOMAIN_OVERRIDE=""
FLEET_OVERRIDE=""
ACME_EMAIL_OVERRIDE=""
FRONTEND_PATH_OVERRIDE=""
NON_INTERACTIVE=0
SKIP_CLONE=0
SKIP_PREFLIGHT=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --domain=DOMAIN          Override the project domain
  --fleet=FLEET_DOMAIN     Override the fleet dashboard domain
  --email=ACME_EMAIL       Override the Let's Encrypt email
  --frontend-path=PATH     Where the frontend lives (default: ./frontend)
  --no-clone               Skip FRONTEND_REPO_URL clone step
  --no-preflight           Skip the Phase −2 self-test
  --non-interactive        Never prompt; fail if required inputs are missing
  -h, --help               Show this help

After this script finishes, run your AI assistant and say:
  "start sunny with domain <DOMAIN> and fleet <FLEET_DOMAIN>"
EOF
}

for arg in "$@"; do
  case "$arg" in
    --domain=*)        DOMAIN_OVERRIDE="${arg#*=}" ;;
    --fleet=*)         FLEET_OVERRIDE="${arg#*=}" ;;
    --email=*)         ACME_EMAIL_OVERRIDE="${arg#*=}" ;;
    --frontend-path=*) FRONTEND_PATH_OVERRIDE="${arg#*=}" ;;
    --no-clone)        SKIP_CLONE=1 ;;
    --no-preflight)    SKIP_PREFLIGHT=1 ;;
    --non-interactive) NON_INTERACTIVE=1 ;;
    -h|--help)         usage; exit 0 ;;
    *)                 echo "Unknown argument: $arg" >&2; usage; exit 2 ;;
  esac
done

# ----- helpers --------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
say_ok()   { printf "${GREEN}OK${NC}   %s\n" "$*"; }
say_warn() { printf "${YELLOW}WARN${NC} %s\n" "$*"; }
say_err()  { printf "${RED}ERR${NC}  %s\n" "$*" >&2; }
say()      { printf "      %s\n" "$*"; }

# Idempotent .env writer (same contract as deploy/scripts/sync-secrets.sh):
# append only if the key is absent — never overwrite a user-set value.
set_env_var() {
  local key="$1" value="$2"
  [[ -f .env ]] || touch .env
  if grep -qE "^${key}=" .env 2>/dev/null; then
    return 0
  fi
  printf '\n%s=%s\n' "$key" "$value" >> .env
}

prompt() {
  # prompt "Label" "default-value" → echoes the value
  local label="$1" default="$2"
  if [[ $NON_INTERACTIVE -eq 1 ]]; then
    echo "$default"
    return
  fi
  local reply
  read -r -p "      ${label} [${default}]: " reply
  echo "${reply:-$default}"
}

# ----- 1. Sanity check ------------------------------------------------------
echo "============================================================"
echo "  Sunny bootstrap — ${ROOT}"
echo "============================================================"
echo

if [[ ! -f .cursor/rules/sunny-orchestrator.mdc ]]; then
  say_err ".cursor/rules/sunny-orchestrator.mdc not found"
  say_err "  Run this script from the Sunny repo root, not a subfolder."
  exit 1
fi
say_ok "Sunny repo detected"

# Required CLI tools (subset of the Phase −2 self-test — only the ones that
# matter for the LOCAL operator host, not the VPS).
MISSING=()
for t in git curl jq openssl; do
  if ! command -v "$t" >/dev/null 2>&1; then
    MISSING+=("$t")
  fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  say_err "Missing CLI tools: ${MISSING[*]}"
  say_err "  Install them (Ubuntu: apt-get install -y ${MISSING[*]})."
  exit 1
fi
say_ok "Core CLI tools present (git, curl, jq, openssl)"

# ----- 2. .env from template ------------------------------------------------
if [[ ! -f .env ]]; then
  if [[ ! -f .env.example ]]; then
    say_err ".env.example missing — repo is incomplete."
    exit 1
  fi
  cp .env.example .env
  say_ok "Created .env from .env.example (Maya will fill secrets at intake)"
else
  say_ok ".env already present — leaving it untouched (Maya will only fill missing keys)"
fi

# ----- 3. Capture kickoff inputs -------------------------------------------
echo
echo "---- Project inputs ----"

DOMAIN="${DOMAIN_OVERRIDE:-$(prompt 'Project domain (e.g. app.example.com)' '')}"
if [[ -z "$DOMAIN" ]]; then
  say_err "DOMAIN is required. Re-run with --domain=app.example.com (or answer the prompt)."
  exit 1
fi
set_env_var "DOMAIN" "$DOMAIN"
say_ok "DOMAIN=${DOMAIN}"

FLEET="${FLEET_OVERRIDE:-$(prompt 'Fleet dashboard domain (blank to skip global dashboard)' '')}"
if [[ -n "$FLEET" ]]; then
  set_env_var "FLEET_DOMAIN" "$FLEET"
  say_ok "FLEET_DOMAIN=${FLEET}"
else
  say_warn "FLEET_DOMAIN not set — global dashboard disabled (single-VPS mode)"
fi

EMAIL="${ACME_EMAIL_OVERRIDE:-$(prompt 'ACME email for Let'\''s Encrypt (blank → admin@<DOMAIN>)' '')}"
EMAIL="${EMAIL:-admin@${DOMAIN}}"
set_env_var "ACME_EMAIL" "$EMAIL"
say_ok "ACME_EMAIL=${EMAIL}"

FRONTEND_PATH="${FRONTEND_PATH_OVERRIDE:-${FRONTEND_PATH:-./frontend}}"
set_env_var "FRONTEND_PATH" "${FRONTEND_PATH}"
say_ok "FRONTEND_PATH=${FRONTEND_PATH}"

# Generate a deterministic RUN_ID now so the dashboard has it from minute 0.
# Maya will respect it (only generates one if absent).
if ! grep -qE "^RUN_ID=" .env; then
  RUN_ID="run-$(date -u +%Y%m%dT%H%M%SZ)-$(openssl rand -hex 4)"
  set_env_var "RUN_ID" "$RUN_ID"
  say_ok "RUN_ID=${RUN_ID}"
else
  say_ok "RUN_ID already in .env (keeping existing)"
fi

# ----- 4. Optional frontend clone (Pattern B) --------------------------------
echo
echo "---- Frontend ----"

if [[ $SKIP_CLONE -eq 1 ]]; then
  say_warn "Skipping FRONTEND_REPO_URL clone (--no-clone)"
elif grep -qE "^FRONTEND_REPO_URL=.+" .env 2>/dev/null; then
  REPO_URL=$(grep -E "^FRONTEND_REPO_URL=" .env | head -1 | cut -d= -f2-)
  if [[ -d "${FRONTEND_PATH}/.git" ]] || [[ -d "${FRONTEND_PATH}/package.json" ]]; then
    say_ok "Frontend already at ${FRONTEND_PATH} — skipping clone"
  else
    say "Cloning ${REPO_URL} → ${FRONTEND_PATH}"
    if ! git clone --depth 1 "$REPO_URL" "$FRONTEND_PATH"; then
      say_err "git clone failed. Check FRONTEND_REPO_URL and credentials."
      exit 1
    fi
    say_ok "Frontend cloned to ${FRONTEND_PATH}"
  fi
else
  if [[ -d "${FRONTEND_PATH}" ]]; then
    say_ok "Frontend present at ${FRONTEND_PATH} (committed directly — Pattern A)"
  else
    say_warn "No frontend at ${FRONTEND_PATH} and FRONTEND_REPO_URL not set."
    say_warn "  Drop your frontend in there, or set FRONTEND_REPO_URL=git@github.com:you/repo.git"
  fi
fi

# ----- 5. Phase −2 self-test (subset) ---------------------------------------
if [[ $SKIP_PREFLIGHT -eq 1 ]]; then
  echo
  say_warn "Skipping Phase −2 self-test (--no-preflight)"
else
  echo
  echo "---- Phase −2 self-test ----"
  PREFLIGHT_FAILED=0

  # (1) CLI tools the LOCAL host needs to drive Sunny (Rajesh etc. need the rest
  # on the VPS — that's checked by Phase 5.0 pre-flight at deploy time).
  for t in graphify; do
    if ! command -v "$t" >/dev/null 2>&1; then
      say_warn "MISSING: $t — install with: uv tool install graphifyy && graphify install"
      PREFLIGHT_FAILED=1
    else
      say_ok "$t"
    fi
  done

  # (2) .sunny/ is writable
  mkdir -p .sunny/context .sunny/web .sunny/scripts
  if [[ -w .sunny ]]; then
    say_ok ".sunny/ writable"
  else
    say_err ".sunny/ not writable — fix permissions"
    PREFLIGHT_FAILED=1
  fi

  # (3) Agent files (generate-agents are required; fix-agents are nice-to-have)
  REQUIRED_AGENTS=(
    "supabase-removal-agent" "jhipster-backend-agent" "database-agent" "nginx-agent"
    "backend-unit-test-agent" "backend-integration-test-agent" "backend-functional-test-agent"
    "frontend-unit-test-agent" "frontend-integration-test-agent" "frontend-functional-test-agent"
    "system-integration-test-agent" "swagger-agent" "javadoc-agent"
    "api-collection-agent" "api-test-agent" "api-performance-test-agent" "production-standards-agent"
    "deployment-platform-agent" "server-provision-agent" "deployment-database-agent"
    "deployment-backend-agent" "deployment-edge-agent" "om-fix-agent"
  )
  for slug in "${REQUIRED_AGENTS[@]}"; do
    if [[ ! -f ".cursor/agents/${slug}.md" ]]; then
      say_err "MISSING: .cursor/agents/${slug}.md"
      PREFLIGHT_FAILED=1
    fi
  done
  [[ $PREFLIGHT_FAILED -eq 0 ]] && say_ok "all required agent files present"

  # (4) Rule file readable
  if [[ -r .cursor/rules/sunny-orchestrator.mdc ]]; then
    say_ok "sunny-orchestrator.mdc readable"
  fi

  # (5) .env has the three required kickoff fields
  for key in DOMAIN ACME_EMAIL FRONTEND_PATH; do
    if grep -qE "^${key}=" .env; then
      say_ok ".env has ${key}"
    else
      say_err ".env missing ${key}"
      PREFLIGHT_FAILED=1
    fi
  done

  if [[ $PREFLIGHT_FAILED -eq 0 ]]; then
    echo
    say_ok "Phase −2 self-test: PASS"
  else
    echo
    say_err "Phase −2 self-test: FAIL — fix the items above and re-run"
    exit 1
  fi
fi

# ----- 6. Kickoff prompt ----------------------------------------------------
echo
echo "============================================================"
echo "  Ready to start Sunny"
echo "============================================================"
echo
say "  Project domain:    ${DOMAIN}"
say "  Fleet domain:      ${FLEET:-<none — single VPS mode>}"
say "  ACME email:        ${EMAIL}"
say "  Frontend path:     ${FRONTEND_PATH}"
say "  RUN_ID:            ${RUN_ID:-<Maya will generate>}"
echo
echo "  Open your AI assistant (Cursor / Claude Code / etc.) and say:"
echo
if [[ -n "$FLEET" ]]; then
  echo "    \"start sunny with domain ${DOMAIN} and fleet ${FLEET}\""
else
  echo "    \"start sunny with domain ${DOMAIN}\""
fi
echo
say "  (Sunny will read .env and FRONTEND_PATH, then run Phases 0 → 22.)"
echo
