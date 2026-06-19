#!/usr/bin/env bash
# Om / operators — quick production deployment health check. Exit non-zero on critical failure.
set -euo pipefail

DOMAIN="${DOMAIN:-}"
GRAFANA_URL="${GRAFANA_URL:-}"
FAILED=0

fail() { echo "FAIL: $*"; FAILED=1; }
ok()   { echo "OK:   $*"; }

command -v kubectl >/dev/null || fail "kubectl missing"
command -v minikube >/dev/null || fail "minikube missing"

minikube status >/dev/null 2>&1 || fail "minikube not running"
ok "minikube running"

# App pods — ignore Init:*/Pending for the grace window (rollout in progress) and Completed jobs.
# Count pods whose phase is NOT Running/Completed AND not in a benign transitional state.
NOT_READY=$(kubectl get pods -n sunny-prod --no-headers 2>/dev/null \
  | awk '$3 !~ /^(Running|Completed|Succeeded)$/ && $3 !~ /^Init:/ {print}' | wc -l || true)
[[ "$NOT_READY" -eq 0 ]] && ok "sunny-prod pods Running" || fail "sunny-prod has $NOT_READY non-Running pods (excluding Init/Completed)"

# Observability — ALL pods must be Running (not just one).
OBS_NOT_RUNNING=$(kubectl get pods -n observability --no-headers 2>/dev/null \
  | awk '$3 !~ /^(Running|Completed|Succeeded)$/' | wc -l || true)
[[ "$OBS_NOT_RUNNING" -eq 0 ]] && ok "observability pods Running" || fail "observability has $OBS_NOT_RUNNING non-Running pods"

# Gateway health via minikube service (if configured)
if kubectl get svc -n sunny-prod gateway 2>/dev/null | grep -q NodePort; then
  GW_PORT=$(kubectl get svc -n sunny-prod gateway -o jsonpath='{.spec.ports[0].nodePort}')
  MINIKUBE_IP=$(minikube ip)
  if curl -fsS "http://${MINIKUBE_IP}:${GW_PORT}/management/health" | grep -q UP; then
    ok "gateway health UP"
  else
    fail "gateway health check"
  fi
fi

# Public edge (when DOMAIN set). Retry progress.json a few times — Maya may be mid-write.
if [[ -n "$DOMAIN" ]]; then
  if curl -fsS --retry 3 --retry-delay 1 "https://${DOMAIN}/api/management/health" | grep -q UP; then
    ok "public /api health"
  else
    fail "public API health"
  fi
  if curl -fsS --retry 3 --retry-delay 1 "https://${DOMAIN}/progress.json" | grep -q runId; then
    ok "progress.json live"
  else
    fail "progress.json"
  fi
fi

# Grafana reachability
if [[ -n "$GRAFANA_URL" ]]; then
  if curl -fsS -o /dev/null -w "%{http_code}" "${GRAFANA_URL}/api/health" | grep -q 200; then
    ok "Grafana health"
  else
    fail "Grafana unreachable"
  fi
fi

if [[ "$FAILED" -eq 0 ]]; then
  echo "Health check: PASS"
else
  echo "Health check: FAIL ($FAILED issue(s))"
fi

exit "$FAILED"