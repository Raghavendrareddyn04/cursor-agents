#!/usr/bin/env bash
# Sync secrets from project .env into Kubernetes (observability + sunny-prod).
# Rajesh runs before helm install (grafana-admin); Manoj re-runs for app secrets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${ROOT}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found at ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# Validate sourced values — fail loud if .env has malformed lines
if [[ -n "${GRAFANA_ADMIN_PASSWORD:-}" ]] && [[ "$GRAFANA_ADMIN_PASSWORD" == *"="* ]]; then
  echo "ERROR: GRAFANA_ADMIN_PASSWORD in .env is malformed (contains '=')" >&2
  exit 1
fi

# Idempotent .env writer — append only if the key is absent (re-runs must not duplicate)
set_env_var() {
  local key="$1" value="$2"
  if grep -qE "^${key}=" "$ENV_FILE" 2>/dev/null; then
    return 0
  fi
  printf '\n%s=%s\n' "$key" "$value" >> "$ENV_FILE"
}

ensure_ns() {
  kubectl get namespace "$1" >/dev/null 2>&1 || kubectl create namespace "$1" --save-config 2>/dev/null \
    || kubectl get namespace "$1" >/dev/null
}

# --- Grafana admin (kube-prometheus-stack existingSecret: grafana-admin) ---
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
if [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
  GRAFANA_ADMIN_PASSWORD="$(openssl rand -base64 24)"
  set_env_var "GRAFANA_ADMIN_PASSWORD" "$GRAFANA_ADMIN_PASSWORD"
  echo "Generated GRAFANA_ADMIN_PASSWORD in .env (value not printed)"
fi

ensure_ns observability
kubectl create secret generic grafana-admin -n observability \
  --from-literal=admin-user="${GRAFANA_ADMIN_USER}" \
  --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "OK: secret/grafana-admin (observability)"

# --- App namespace ---
ensure_ns sunny-prod

# Host PostgreSQL defaults for Minikube pods (Lakshmi may override in .env)
POSTGRES_HOST="${POSTGRES_HOST:-host.min.internal}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-sunny}"

if [[ -n "${POSTGRES_PASSWORD:-}" ]]; then
  kubectl create secret generic sunny-postgres -n sunny-prod \
    --from-literal=POSTGRES_HOST="${POSTGRES_HOST}" \
    --from-literal=POSTGRES_PORT="${POSTGRES_PORT}" \
    --from-literal=POSTGRES_USER="${POSTGRES_USER}" \
    --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
    --from-literal=SPRING_DATASOURCE_URL="jdbc:postgresql://${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB:-sunny}" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "OK: secret/sunny-postgres (sunny-prod)"
else
  echo "SKIP: sunny-postgres — POSTGRES_PASSWORD not in .env yet (Lakshmi stage)"
fi

# JWT / registry secrets — Manoj extends: add keys from .env as needed
if [[ -n "${JHIPSTER_SECURITY_AUTHENTICATION_JWT_BASE64_SECRET:-}" ]]; then
  kubectl create secret generic jhipster-jwt -n sunny-prod \
    --from-literal=secret="${JHIPSTER_SECURITY_AUTHENTICATION_JWT_BASE64_SECRET}" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "OK: secret/jhipster-jwt (sunny-prod)"
fi

# Final summary
echo "sync-secrets.sh complete"
