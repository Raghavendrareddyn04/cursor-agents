#!/usr/bin/env bash
# Regenerate all Sunny web reports, test catalog, and artifact links.
# Usage: publish-reports.sh [--verify]
#   --verify  curl-check key URLs; write publish-status.json; exit non-zero on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERIFY=false
for arg in "$@"; do
  case "$arg" in
    --verify) VERIFY=true ;;
    -h|--help)
      echo "Usage: publish-reports.sh [--verify]"
      exit 0
      ;;
  esac
done

resolve_domain() {
  local domain=""
  if [[ -f "${ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${ROOT}/.env"
    domain="${DOMAIN:-}"
  fi
  if [[ -z "$domain" && -f "${ROOT}/.sunny/context/state.json" ]]; then
    domain="$(python3 -c "
import json
s = json.load(open('${ROOT}/.sunny/context/state.json'))
print((s.get('project') or {}).get('domain', ''))
" 2>/dev/null || true)"
  fi
  if [[ -z "$domain" ]]; then
    echo "ERROR: could not resolve DOMAIN from .env or state.json" >&2
    return 1
  fi
  printf '%s' "$domain"
}

ensure_sunny_symlink() {
  local web="${ROOT}/.sunny/web"
  mkdir -p "$web"
  if [[ ! -L /var/www/sunny ]] || [[ "$(readlink -f /var/www/sunny)" != "$(readlink -f "$web")" ]]; then
    rm -rf /var/www/sunny
    ln -sfn "$web" /var/www/sunny
    echo "Linked /var/www/sunny -> $web"
  fi
}

run_build() {
  python3 .sunny/write-reports-html.py
  python3 .sunny/build-test-catalog.py
  python3 .sunny/build-artifacts-manifest.py
}

write_publish_status() {
  local domain="$1"
  ROOT="$ROOT" DOMAIN="$domain" python3 <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

root = Path(os.environ["ROOT"])
domain = os.environ["DOMAIN"]
web = root / ".sunny" / "web"

def load_json(path: Path) -> dict:
    if path.is_file():
        return json.loads(path.read_text(encoding="utf-8"))
    return {}

manifest = load_json(web / "reports-manifest.json")
catalog = load_json(web / "test-catalog.json")
artifacts = load_json(web / "artifacts-manifest.json")

base = f"https://{domain}"
status = {
    "publishedAt": datetime.now(timezone.utc).isoformat(),
    "domain": domain,
    "reportCount": manifest.get("count", 0),
    "testCount": catalog.get("totalTests", 0),
    "artifactCount": artifacts.get("availableCount", 0),
    "artifactTotal": artifacts.get("count", 0),
    "urls": {
        "hub": f"{base}/reports.html",
        "catalog": f"{base}/test-catalog.html",
        "artifacts": f"{base}/artifacts/postman/collection.json",
        "progress": f"{base}/agentprogress.html",
    },
}
out = web / "publish-status.json"
tmp = web / ".publish-status.json.tmp"
tmp.write_text(json.dumps(status, indent=2) + "\n", encoding="utf-8")
tmp.replace(out)
print(json.dumps(status, indent=2))
PY
}

merge_state_reports() {
  ROOT="$ROOT" python3 <<'PY'
import json
import os
from pathlib import Path

root = Path(os.environ["ROOT"])
state_path = root / ".sunny" / "context" / "state.json"
status_path = root / ".sunny" / "web" / "publish-status.json"
if not status_path.is_file() or not state_path.is_file():
    raise SystemExit(0)

status = json.loads(status_path.read_text(encoding="utf-8"))
state = json.loads(state_path.read_text(encoding="utf-8"))
state["reportsPublishedAt"] = status["publishedAt"]
state["reportsUrls"] = status["urls"]
state["reportsStats"] = {
    "reportCount": status.get("reportCount", 0),
    "testCount": status.get("testCount", 0),
    "artifactCount": status.get("artifactCount", 0),
}
tmp = state_path.with_suffix(".json.tmp")
tmp.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
tmp.replace(state_path)
PY
}

curl_check() {
  local url="$1"
  local host="$2"
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout 10 --max-time 30 \
    -H "Host: ${host}" \
    "http://127.0.0.1${url}" 2>/dev/null || echo "000")"
  if [[ "$code" == "301" || "$code" == "302" ]]; then
    code="$(curl -sS -o /dev/null -w '%{http_code}' \
      --connect-timeout 10 --max-time 30 \
      -H "Host: ${host}" \
      -L "http://127.0.0.1${url}" 2>/dev/null || echo "000")"
  fi
  printf '%s' "$code"
}

verify_urls() {
  local domain="$1"
  local failed=0
  local paths=("/reports.html" "/test-catalog.html" "/artifacts/postman/collection.json")
  for path in "${paths[@]}"; do
    local code
    code="$(curl_check "$path" "$domain")"
    if [[ "$code" != "200" ]]; then
      echo "VERIFY FAIL  ${path}  HTTP ${code}  (Host: ${domain})" >&2
      failed=1
    else
      echo "VERIFY OK    ${path}  HTTP 200"
    fi
  done
  return "$failed"
}

DOMAIN="$(resolve_domain)"
ensure_sunny_symlink
run_build
write_publish_status "$DOMAIN" >"${ROOT}/.sunny/web/.publish-status-last.json"

echo "Published to ${ROOT}/.sunny/web (live at /var/www/sunny when symlinked)"

if [[ "$VERIFY" == true ]]; then
  if ! verify_urls "$DOMAIN"; then
    echo "ERROR: URL verification failed — check nginx config and reload if needed" >&2
    exit 1
  fi
  merge_state_reports
  python3 .sunny/build-progress-from-state.py || true
  ROOT="$ROOT" python3 <<'PY'
import json, os
from pathlib import Path

root = Path(os.environ["ROOT"])
status = json.loads((root / ".sunny/web/publish-status.json").read_text(encoding="utf-8"))
domain = status["domain"]
urls = status["urls"]
md = f"""# Reports Publish Summary

**Updated:** {status["publishedAt"]}
**Agent:** reports-publish-agent (Neel)
**Domain:** {domain}

## Verdict
Reports published and verified.

## Published URLs
| Resource | URL |
|----------|-----|
| Reports hub | {urls["hub"]} |
| Test catalog | {urls["catalog"]} |
| Artifacts (Postman) | {urls["artifacts"]} |
| Progress dashboard | {urls["progress"]} |

## Stats
| Metric | Count |
|--------|-------|
| Agent reports | {status.get("reportCount", 0)} |
| Test methods | {status.get("testCount", 0)} |
| Artifacts available | {status.get("artifactCount", 0)}/{status.get("artifactTotal", 0)} |
"""
out = root / ".sunny/context/reports-publish-summary.md"
tmp = out.with_suffix(".md.tmp")
tmp.write_text(md, encoding="utf-8")
tmp.replace(out)
PY
  echo "All report URLs verified for https://${DOMAIN}/"
fi
