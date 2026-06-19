#!/usr/bin/env bash
# ============================================================================
#  bin/smoke-test-deploy.sh — Phase 5.0 pre-flight check
# ----------------------------------------------------------------------------
#  Verifies the VPS deploy target is actually reachable BEFORE launching
#  Rajesh (#17). Catching a broken network here prevents burning 5 Rajesh
#  iterations on a server that will never respond.
#
#  Required inputs (from .env, or --flag overrides):
#    VPS_IP        — public IPv4 of the target VPS
#    VPS_USER      — SSH user (must have key-based, NOPASSWD sudo)
#    DOMAIN        — domain whose A record must point at VPS_IP
#    FLEET_DOMAIN  — (optional) fleet dashboard host
#
#  Required inbound ports: 22, 80, 443 (80 is for Let's Encrypt HTTP-01).
#
#  Exit codes:
#    0  — every check passed, Rajesh can launch
#    1  — one or more checks failed; emit a blocker, do NOT launch Rajesh
# ============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ROOT}/.env"

# ----- arg parsing ----------------------------------------------------------
VPS_IP_OVERRIDE=""
VPS_USER_OVERRIDE=""
DOMAIN_OVERRIDE=""
SKIP_SSH=0
SKIP_DNS=0
SKIP_PORTS=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --vps=IP              Override VPS_IP from .env
  --user=USER           Override VPS_USER from .env
  --domain=DOMAIN       Override DOMAIN from .env
  --skip-ssh            Skip the SSH handshake check
  --skip-dns            Skip the DNS propagation check
  --skip-ports          Skip the inbound-port check
  -h, --help            Show this help

Exit: 0 = all checks passed, 1 = at least one check failed.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --vps=*)            VPS_IP_OVERRIDE="${arg#*=}" ;;
    --user=*)           VPS_USER_OVERRIDE="${arg#*=}" ;;
    --domain=*)         DOMAIN_OVERRIDE="${arg#*=}" ;;
    --skip-ssh)         SKIP_SSH=1 ;;
    --skip-dns)         SKIP_DNS=1 ;;
    --skip-ports)       SKIP_PORTS=1 ;;
    -h|--help)          usage; exit 0 ;;
    *)                  echo "Unknown argument: $arg" >&2; usage; exit 2 ;;
  esac
done

# ----- load .env if present ------------------------------------------------
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

VPS_IP="${VPS_IP_OVERRIDE:-${VPS_IP:-}}"
VPS_USER="${VPS_USER_OVERRIDE:-${VPS_USER:-root}}"
DOMAIN="${DOMAIN_OVERRIDE:-${DOMAIN:-}}"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
say_ok()   { printf "${GREEN}PASS${NC} %s\n" "$*"; }
say_warn() { printf "${YELLOW}SKIP${NC} %s\n" "$*"; }
say_err()  { printf "${RED}FAIL${NC} %s\n" "$*" >&2; }
FAILED=0

mark_fail() { FAILED=1; }

# ----- required values ------------------------------------------------------
echo "============================================================"
echo "  Phase 5.0 pre-flight — ${VPS_USER}@${VPS_IP:-<unknown>} (${DOMAIN:-<no domain>})"
echo "============================================================"
echo

if [[ -z "$VPS_IP" ]]; then
  say_err "VPS_IP not set. Add to .env or pass --vps=1.2.3.4"
  exit 1
fi

# ----- 1. SSH handshake -----------------------------------------------------
if [[ $SKIP_SSH -eq 1 ]]; then
  say_warn "SSH handshake (--skip-ssh)"
else
  if command -v ssh >/dev/null 2>&1; then
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
           "${VPS_USER}@${VPS_IP}" 'true' </dev/null >/dev/null 2>&1; then
      say_ok "SSH handshake (${VPS_USER}@${VPS_IP})"
    else
      say_err "SSH handshake (${VPS_USER}@${VPS_IP})"
      say_err "  → add your public key to ~/.ssh/authorized_keys on the VPS, or"
      say_err "    run: ssh-copy-id ${VPS_USER}@${VPS_IP}"
      mark_fail
    fi
  else
    say_err "ssh binary not found"
    mark_fail
  fi
fi

# ----- 2. DNS propagation ---------------------------------------------------
if [[ $SKIP_DNS -eq 1 ]]; then
  say_warn "DNS check (--skip-dns)"
elif [[ -z "$DOMAIN" ]]; then
  say_err "DOMAIN not set — DNS check skipped (add DOMAIN to .env)"
  mark_fail
elif command -v dig >/dev/null 2>&1; then
  RESOLVED=$(dig +short "$DOMAIN" 2>/dev/null | head -1)
  if [[ -z "$RESOLVED" ]]; then
    say_err "DNS: ${DOMAIN} does not resolve"
    say_err "  → add an A record: ${DOMAIN}. IN A ${VPS_IP}, wait 5 min for propagation"
    mark_fail
  elif [[ "$RESOLVED" != "$VPS_IP" ]]; then
    say_err "DNS: ${DOMAIN} → ${RESOLVED}, expected ${VPS_IP}"
    say_err "  → update the A record and wait for TTL expiry"
    mark_fail
  else
    say_ok "DNS: ${DOMAIN} → ${VPS_IP}"
  fi
else
  # Fallback: use getent (works without dig)
  RESOLVED=$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -1)
  if [[ "$RESOLVED" == "$VPS_IP" ]]; then
    say_ok "DNS: ${DOMAIN} → ${VPS_IP} (via getent)"
  else
    say_err "DNS: cannot verify (dig not installed). Install bind-utils/dnsutils."
    mark_fail
  fi
fi

# ----- 3. Inbound ports -----------------------------------------------------
port_check() {
  local port="$1" name="$2"
  if command -v nc >/dev/null 2>&1; then
    if nc -z -w5 "$VPS_IP" "$port" 2>/dev/null; then
      say_ok "Port ${port}/${name} open"
    else
      say_err "Port ${port}/${name} closed or filtered"
      say_err "  → open ${port}/${name} in the VPS firewall (ufw allow ${port}/${name})"
      mark_fail
    fi
  elif command -v bash >/dev/null 2>&1 && bash -c "</dev/tcp/${VPS_IP}/${port}" 2>/dev/null; then
    say_ok "Port ${port}/${name} open (via /dev/tcp)"
  else
    say_err "Neither nc nor /dev/tcp usable — install netcat"
    mark_fail
  fi
}

if [[ $SKIP_PORTS -eq 1 ]]; then
  say_warn "Port checks (--skip-ports)"
else
  port_check 22  "ssh"
  port_check 80  "http"
  port_check 443 "https"
fi

# ----- 4. Optional: sudo NOPASSWD ------------------------------------------
if [[ $SKIP_SSH -eq 0 ]]; then
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "${VPS_USER}@${VPS_IP}" \
        'sudo -n true 2>&1' </dev/null >/dev/null 2>&1; then
    say_ok "sudo NOPASSWD on ${VPS_USER}@${VPS_IP}"
  else
    say_err "sudo NOPASSWD: ${VPS_USER} cannot run passwordless sudo"
    say_err "  → on the VPS run: echo '${VPS_USER} ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/90-${VPS_USER}"
    mark_fail
  fi
fi

# ----- summary --------------------------------------------------------------
echo
if [[ $FAILED -eq 0 ]]; then
  echo "============================================================"
  echo "  Phase 5.0 pre-flight: PASS — Rajesh can launch."
  echo "============================================================"
  exit 0
else
  echo "============================================================"
  echo "  Phase 5.0 pre-flight: FAIL — do NOT launch Rajesh."
  echo "  Fix the FAIL items above, then re-run $(basename "$0")."
  echo "============================================================"
  exit 1
fi