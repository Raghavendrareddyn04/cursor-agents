#!/usr/bin/env bash
# Suresh — host provisioning installer for Sunny (Ubuntu/Debian-first).
# Idempotent: re-runs skip tools already at required versions.
# Other OS families (RHEL/Alpine): Suresh extends with conditional branches.

set -euo pipefail

# Required versions — pin for reproducibility
JAVA_MIN=17
NODE_MIN=18
DOCKER_MIN=24
KUBECTL_MIN=1.29
MINIKUBE_MIN=1.32
HELM_MIN=3.14

# Detect OS family
. /etc/os-release
OS_FAMILY="unknown"
case "${ID:-${ID_LIKE:-}}" in
  ubuntu|debian) OS_FAMILY="debian" ;;
  rhel|centos|rocky|almalinux|fedora) OS_FAMILY="rhel" ;;
  alpine) OS_FAMILY="alpine" ;;
  *) OS_FAMILY="unknown" ;;
esac

if [[ "$OS_FAMILY" != "debian" ]]; then
  echo "WARNING: provision.sh is optimized for Ubuntu/Debian. Detected: ${PRETTY_NAME:-unknown}."
  echo "         Suresh must extend this script with ${OS_FAMILY}-specific install branches."
fi

if [[ "$OS_FAMILY" == "debian" ]] && ! command -v sudo >/dev/null; then
  echo "ERROR: sudo not found. Install sudo first or re-run as root." >&2
  exit 1
fi

# Helper: run with sudo only if not root, never prompt
SUDO=""
if [[ $EUID -ne 0 ]]; then
  SUDO="sudo -n"
  if ! $SUDO true 2>/dev/null; then
    echo "ERROR: passwordless sudo required (deployment stage #18 is pre-authorized). Run as root or grant NOPASSWD." >&2
    exit 1
  fi
fi

ver_ge() { # ver_ge INSTALLED MIN   "true" if installed >= min
  local inst="$1" min="$2"
  [[ "$inst" == "$min" || "$(printf '%s\n%s\n' "$min" "$inst" | sort -V | tail -n1)" == "$inst" ]]
}

# JAVA
if command -v java >/dev/null; then
  JAVA_VER=$(java -version 2>&1 | head -1 | awk -F'"' '{print $2}' | awk -F. '{print $1}')
  if ver_ge "${JAVA_VER:-0}" "$JAVA_MIN"; then
    echo "OK: java ${JAVA_VER} (>= ${JAVA_MIN})"
  else
    echo "INSTALL: java ${JAVA_VER} < ${JAVA_MIN}"
    [[ "$OS_FAMILY" == "debian" ]] && $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-${JAVA_MIN}-jdk-headless
  fi
else
  echo "INSTALL: java"
  [[ "$OS_FAMILY" == "debian" ]] && $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-${JAVA_MIN}-jdk-headless
fi

# NODE
if command -v node >/dev/null; then
  NODE_VER=$(node -v | tr -d 'v')
  NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
  if ver_ge "${NODE_MAJOR:-0}" "$NODE_MIN"; then
    echo "OK: node ${NODE_VER} (>= ${NODE_MIN})"
  else
    echo "INSTALL: node ${NODE_VER} < ${NODE_MIN} — Suresh must add NodeSource repo upgrade"
  fi
else
  echo "INSTALL: node (Suresh: add NodeSource setup_${NODE_MIN}.x)"
fi

# DOCKER
if command -v docker >/dev/null; then
  DOCKER_VER=$(docker -v | awk '{print $3}' | tr -d ',' | cut -d. -f1)
  if ver_ge "${DOCKER_VER:-0}" "$DOCKER_MIN"; then
    echo "OK: docker ${DOCKER_VER} (>= ${DOCKER_MIN})"
  else
    echo "INSTALL: docker ${DOCKER_VER} < ${DOCKER_MIN} — Suresh: upgrade via official script"
  fi
else
  echo "INSTALL: docker (Suresh: official install script)"
fi

# KUBECTL
if command -v kubectl >/dev/null; then
  K_VER=$(kubectl version --client 2>/dev/null | awk '/Client Version/ {print $3}' | tr -d 'v' | cut -d. -f1,2)
  if ver_ge "${K_VER:-0}" "$KUBECTL_MIN"; then
    echo "OK: kubectl ${K_VER} (>= ${KUBECTL_MIN})"
  else
    echo "INSTALL: kubectl ${K_VER} < ${KUBECTL_MIN} — Suresh: refresh k8s apt repo"
  fi
else
  echo "INSTALL: kubectl (Suresh: k8s.io/apt repo)"
fi

# MINIKUBE
if command -v minikube >/dev/null; then
  M_VER=$(minikube version --short 2>/dev/null | tr -d 'v')
  M_MAJOR=$(echo "$M_VER" | cut -d. -f1)
  if ver_ge "${M_MAJOR:-0}" "$MINIKUBE_MIN"; then
    echo "OK: minikube ${M_VER} (>= ${MINIKUBE_MIN})"
  else
    echo "INSTALL: minikube ${M_VER} < ${MINIKUBE_MIN} — Suresh: refresh download"
  fi
else
  echo "INSTALL: minikube (Rajesh owns platform tools; Suresh may pre-stage)"
fi

# HELM
if command -v helm >/dev/null; then
  H_VER=$(helm version --short 2>/dev/null | tr -d 'v' | cut -d+ -f1)
  H_MAJOR=$(echo "$H_VER" | cut -d. -f1)
  if ver_ge "${H_MAJOR:-0}" "$HELM_MIN"; then
    echo "OK: helm ${H_VER} (>= ${HELM_MIN})"
  else
    echo "INSTALL: helm ${H_VER} < ${HELM_MIN} — Suresh: refresh install"
  fi
else
  echo "INSTALL: helm"
fi

# Always-present basics (debian)
if [[ "$OS_FAMILY" == "debian" ]]; then
  echo "Refreshing apt cache and installing baseline utilities..."
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
    nginx postgresql postgresql-client certbot python3-certbot-nginx \
    curl jq openssl ca-certificates gnupg lsb-release \
    build-essential git unzip
fi

# NGINX
command -v nginx >/dev/null && nginx -v 2>&1 | head -1 || echo "MISSING: nginx"

# POSTGRESQL
command -v psql >/dev/null && psql --version || echo "MISSING: psql"

# CERTBOT — snap vs apt differ; snap needs /snap/bin on PATH
if ! command -v certbot >/dev/null; then
  echo "INSTALL: certbot (apt or snap)"
  if [[ "$OS_FAMILY" == "debian" ]] && ! command -v snap >/dev/null; then
    $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y certbot python3-certbot-nginx
  fi
fi
command -v certbot >/dev/null && certbot --version || echo "MISSING: certbot (try: snap install --classic certbot)"

# PM2
if command -v npm >/dev/null; then
  if ! command -v pm2 >/dev/null; then
    echo "INSTALL: pm2 (npm i -g pm2)"
    $SUDO npm install -g pm2
  fi
else
  echo "SKIP: pm2 (node missing)"
fi

echo "=== provision.sh done ==="
