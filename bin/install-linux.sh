#!/usr/bin/env bash
# ============================================================================
#  bin/install-linux.sh — Sunny prerequisite installer (Linux VPS)
#  Mirrors install.bat + INSTALL.md. Idempotent — safe to re-run.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${SUNNY_PROJECT:-/opt/ascenta-core-hub}"
FAILED=0

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
say_ok()   { printf "${GREEN}OK${NC}   %s\n" "$*"; }
say_skip() { printf "      skip %s\n" "$*"; }
say_warn() { printf "${YELLOW}WARN${NC} %s\n" "$*"; FAILED=1; }
say_err()  { printf "${RED}ERR${NC}  %s\n" "$*" >&2; FAILED=1; }
need_cmd() { command -v "$1" >/dev/null 2>&1; }

echo "============================================================"
echo "  Sunny Linux installer — $ROOT"
echo "  Project: $PROJECT"
echo "============================================================"
echo

# --- §4 Base system packages -------------------------------------------------
echo "---- Base packages (INSTALL.md §4) ----"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq \
  git curl wget ca-certificates gnupg lsb-release \
  build-essential unzip jq openssl \
  python3 python3-pip python3-venv \
  openjdk-17-jdk maven 2>/dev/null || true
say_ok "apt base packages"

# --- §5 Docker Compose plugin ------------------------------------------------
echo "---- Docker Compose (INSTALL.md §5) ----"
if docker compose version >/dev/null 2>&1; then
  say_skip "docker compose"
elif need_cmd docker-compose; then
  say_skip "docker-compose (legacy)"
else
  sudo apt-get install -y -qq docker-compose-v2 2>/dev/null || \
    sudo apt-get install -y -qq docker-compose-plugin 2>/dev/null || \
    say_warn "could not install docker compose plugin — install manually"
fi
need_cmd docker && say_ok "docker $(docker --version | awk '{print $3}' | tr -d ',')" || say_err "docker missing"

# --- §6 Git ------------------------------------------------------------------
need_cmd git && say_ok "git $(git --version | awk '{print $3}')" || say_err "git missing"

# --- §7 Java -----------------------------------------------------------------
if need_cmd java; then
  say_ok "java $(java -version 2>&1 | head -1)"
else
  say_err "java missing"
fi

# --- §8 Node.js --------------------------------------------------------------
if need_cmd node; then
  say_ok "node $(node -v)"
else
  say_warn "node missing — install Node 20 LTS (INSTALL.md §8)"
fi

# --- §8 uv + Graphify (§9) ---------------------------------------------------
echo "---- uv + Graphify (INSTALL.md §8–9) ----"
if ! need_cmd uv; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
if need_cmd uv; then
  say_ok "uv $(uv --version 2>/dev/null | awk '{print $2}')"
else
  say_err "uv not on PATH"
fi

if ! need_cmd graphify; then
  uv tool install "graphifyy[anthropic]"
  export PATH="$HOME/.local/bin:$PATH"
fi
if need_cmd graphify; then
  graphify install
  say_ok "graphify $(graphify --version 2>/dev/null || echo installed)"
else
  say_err "graphify not on PATH — re-run after shell restart"
fi

# --- §11b Minikube / kubectl / Helm ------------------------------------------
echo "---- K8s toolchain (INSTALL.md §11b) ----"
for t in kubectl minikube helm; do
  need_cmd "$t" && say_ok "$t" || say_warn "$t missing"
done

# --- Global Node tooling (install.bat) -----------------------------------------
echo "---- Node globals (Newman, JHipster, PM2) ----"
if need_cmd npm; then
  need_cmd newman    || { npm install -g newman && say_ok "newman installed"; }
  need_cmd newman    && say_skip "newman"
  need_cmd jhipster  || { npm install -g generator-jhipster && say_ok "jhipster installed"; }
  need_cmd jhipster  && say_skip "jhipster"
  need_cmd pm2       || { npm install -g pm2 && say_ok "pm2 installed"; }
  need_cmd pm2       && say_skip "pm2"
else
  say_warn "npm missing — skipping global node tools"
fi

# --- k6 (optional, install.bat) ----------------------------------------------
echo "---- k6 (API performance) ----"
if need_cmd k6; then
  say_skip "k6"
else
  if [[ ! -f /usr/share/keyrings/k6-archive-keyring.gpg ]]; then
    sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
      --keyserver hkp://keyserver.ubuntu.com:80 \
      --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69 2>/dev/null || true
    echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | \
      sudo tee /etc/apt/sources.list.d/k6.list >/dev/null
    sudo apt-get update -qq
  fi
  sudo apt-get install -y -qq k6 2>/dev/null && say_ok "k6" || say_warn "k6 install failed"
fi

# --- Hermes Sunny bridge -------------------------------------------------------
echo "---- Hermes Sunny bridge ----"
if [[ -x "$ROOT/bin/install-hermes-skills.sh" ]]; then
  "$ROOT/bin/install-hermes-skills.sh" || say_warn "Hermes skills install had warnings"
fi

# --- Project wiring -----------------------------------------------------------
echo "---- Project bootstrap: $PROJECT ----"
if [[ -d "$PROJECT" ]]; then
  if [[ ! -e "$PROJECT/.cursor" ]]; then
    ln -sf "$ROOT/.cursor" "$PROJECT/.cursor"
    say_ok "symlinked .cursor → $ROOT/.cursor"
  else
    say_skip ".cursor already present"
  fi

  if [[ -f "$PROJECT/package.json" ]]; then
    if [[ ! -d "$PROJECT/node_modules" ]]; then
      echo "      npm ci in $PROJECT ..."
      (cd "$PROJECT" && npm ci 2>/dev/null || npm install)
      say_ok "frontend deps installed"
    else
      say_skip "node_modules"
    fi
  elif [[ -f "$PROJECT/frontend/package.json" ]]; then
    if [[ ! -d "$PROJECT/frontend/node_modules" ]]; then
      (cd "$PROJECT/frontend" && npm ci 2>/dev/null || npm install)
      say_ok "frontend/ deps installed"
    else
      say_skip "frontend/node_modules"
    fi
  else
    say_warn "no package.json at project root or frontend/"
  fi

  if need_cmd graphify; then
    if [[ -f "$PROJECT/graphify-out/graph.json" ]]; then
      (cd "$PROJECT" && graphify update .) && say_ok "graphify update"
    else
      (cd "$PROJECT" && graphify .) && say_ok "graphify bootstrap"
    fi
  fi

  if [[ -x "$ROOT/bin/seed-sunny-reports.sh" ]]; then
    "$ROOT/bin/seed-sunny-reports.sh" "$PROJECT" && say_ok "reports toolchain seeded" || say_warn "seed-sunny-reports.sh failed"
  fi
else
  say_warn "project dir $PROJECT not found — skip npm/graphify"
fi

# --- Summary -----------------------------------------------------------------
echo
echo "============================================================"
echo "  Tool versions"
echo "============================================================"
for cmd in git docker java node npm python3 uv graphify kubectl minikube helm pm2 newman k6; do
  if need_cmd "$cmd"; then
    v=$($cmd --version 2>&1 | head -1 || $cmd -v 2>&1 | head -1 || echo ok)
    printf "  %-12s %s\n" "$cmd" "$v"
  else
    printf "  %-12s NOT FOUND\n" "$cmd"
  fi
done
docker compose version 2>/dev/null | sed 's/^/  compose      /' || true

echo
if [[ $FAILED -eq 0 ]]; then
  say_ok "Sunny Linux install complete"
  echo "  Invoke: Sunny, build the backend for ./  (frontend at repo root)"
  echo "  Hermes: hermes config set terminal.cwd $PROJECT"
else
  say_warn "Done with warnings — review output above"
fi

exit $FAILED
