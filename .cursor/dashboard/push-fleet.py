#!/usr/bin/env python3
"""Push Sunny progress snapshot to the fleet central collector.

Reads .sunny/web/progress.json and POSTs to the collector. Uses
COLLECTOR_DIRECT_IP when set (bypasses Cloudflare ASN blocks on worker VPSs).

Usage (from project root):
  python3 .sunny/push-fleet.py
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


def _load_dotenv(project_root: Path) -> None:
    env_path = project_root / ".env"
    if not env_path.is_file():
        return
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def _stage_counts(stages: list) -> dict:
    done = sum(
        1
        for s in stages
        if isinstance(s, dict) and s.get("status") in ("done", "completed")
    )
    total = len(stages)
    return {"done": done, "total": total}


def _normalize_stages(raw) -> list:
    if isinstance(raw, list):
        stages = raw
    elif isinstance(raw, dict):
        stages = [
            {"key": k, **(v if isinstance(v, dict) else {"label": str(v)})}
            for k, v in raw.items()
        ]
    else:
        stages = []
    out = []
    for s in stages:
        if not isinstance(s, dict):
            continue
        st = s.get("status", "pending")
        if st == "done":
            st = "completed"
        out.append({**s, "status": st})
    return out


def main() -> int:
    project_root = Path(__file__).resolve().parent.parent
    _load_dotenv(project_root)

    progress_path = project_root / ".sunny" / "web" / "progress.json"
    state_path = project_root / ".sunny" / "context" / "state.json"

    if not progress_path.is_file():
        print("push-fleet: missing progress.json", file=sys.stderr)
        return 1

    progress = json.loads(progress_path.read_text(encoding="utf-8"))
    state = {}
    if state_path.is_file():
        state = json.loads(state_path.read_text(encoding="utf-8"))

    run_id = progress.get("runId") or state.get("runId") or os.environ.get("RUN_ID", "")
    if not run_id or run_id in ("<runId>", "undefined"):
        print("push-fleet: runId missing — Maya must set runId at intake", file=sys.stderr)
        return 1

    token = os.environ.get("CENTRAL_PUSH_TOKEN", "").strip()
    if not token:
        print("push-fleet: CENTRAL_PUSH_TOKEN not set — skipping", file=sys.stderr)
        return 0

    fleet_domain = (
        os.environ.get("FLEET_DOMAIN", "").strip()
        or (state.get("project") or {}).get("fleetDomain", "")
        or progress.get("project", {}).get("fleetDomain", "")
    )
    central_url = os.environ.get("CENTRAL_DASHBOARD_URL", "").strip().rstrip("/")
    direct_ip = os.environ.get("COLLECTOR_DIRECT_IP", "").strip()

    stages = _normalize_stages(progress.get("stages"))
    counts = progress.get("counts") or _stage_counts(stages)
    if not counts.get("total"):
        counts["total"] = len(stages) or 23

    payload = {
        **progress,
        "runId": run_id,
        "stages": stages,
        "counts": counts,
        "domain": (progress.get("project") or {}).get("domain")
        or (state.get("project") or {}).get("domain")
        or "",
        "currentStageLabel": progress.get("currentStageLabel")
        or progress.get("currentStage")
        or "",
        "actionRequired": progress.get("actionRequired") or [],
    }

    body = json.dumps(payload).encode("utf-8")
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }

    if direct_ip:
        url = f"http://{direct_ip}:8080/api/runs/{run_id}"
        if fleet_domain:
            headers["Host"] = fleet_domain
    elif central_url:
        url = f"{central_url}/api/runs/{run_id}"
    else:
        print("push-fleet: no COLLECTOR_DIRECT_IP or CENTRAL_DASHBOARD_URL — skipping", file=sys.stderr)
        return 0

    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            print(f"push-fleet: OK {resp.status} runId={run_id}")
            return 0
    except urllib.error.HTTPError as e:
        print(f"push-fleet: HTTP {e.code} {e.reason}", file=sys.stderr)
        return 0
    except urllib.error.URLError as e:
        print(f"push-fleet: {e.reason}", file=sys.stderr)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
