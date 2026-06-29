#!/usr/bin/env bash
# Copy fleet reports-publish toolchain from cursor-agents into a project .sunny/
# Idempotent — safe to re-run after git pull in /opt/cursor-agents.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${1:-${SUNNY_PROJECT:-$(pwd)}}"
PROJECT="$(cd "$PROJECT" && pwd)"

SRC_SUNNY="$ROOT/.cursor/sunny"
SRC_WEB="$ROOT/.cursor/web"

if [[ ! -d "$SRC_SUNNY" ]]; then
  echo "ERR: missing $SRC_SUNNY — git pull cursor-agents" >&2
  exit 1
fi

mkdir -p "$PROJECT/.sunny/web/reports" "$PROJECT/.sunny/context" "$PROJECT/.sunny/logs"

for f in publish-reports.sh write-reports-html.py build-test-catalog.py build-artifacts-manifest.py build-progress-from-state.py; do
  install -m 644 "$SRC_SUNNY/$f" "$PROJECT/.sunny/$f"
done
chmod +x "$PROJECT/.sunny/publish-reports.sh"

for f in reports.html reports-shared.css; do
  if [[ -f "$SRC_WEB/$f" ]]; then
    install -m 644 "$SRC_WEB/$f" "$PROJECT/.sunny/web/$f"
  fi
done

if [[ -x "$ROOT/.cursor/bin/sunny-cursor-run.sh" && ! -e "$PROJECT/.cursor/bin/sunny-cursor-run.sh" ]]; then
  mkdir -p "$PROJECT/.cursor/bin"
  install -m 755 "$ROOT/.cursor/bin/sunny-cursor-run.sh" "$PROJECT/.cursor/bin/sunny-cursor-run.sh"
fi

echo "OK  seeded reports toolchain → $PROJECT/.sunny/"
echo "    run: bash $PROJECT/.sunny/publish-reports.sh --verify"
