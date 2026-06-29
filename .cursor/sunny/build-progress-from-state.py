#!/usr/bin/env python3
"""Rebuild .sunny/web/progress.json from state.json (read-only on state).

Safe to run from the watchdog while Sunny is active — only refreshes the
dashboard feed; never writes state.json or interrupts the pipeline.
"""
from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
STATE_PATH = ROOT / "context" / "state.json"
WRITE_HELPER = ROOT / "write-progress-json.py"

# Composite testing stages: sum per-layer verify counters for iteration display.
COMPOSITE_VERIFY_KEYS: dict[str, list[str]] = {
    "testing_backend": [
        "backendUnitTestVerifyIterations",
        "backendIntegrationTestVerifyIterations",
        "backendFunctionalTestVerifyIterations",
    ],
    "testing_frontend": [
        "frontendUnitTestVerifyIterations",
        "frontendIntegrationTestVerifyIterations",
        "frontendFunctionalTestVerifyIterations",
    ],
}

STAGE_VERIFY_KEYS: dict[str, str] = {
    "frontend_sanitize": "frontendSanitizeVerifyIterations",
    "architecture": "architectureVerifyIterations",
    "supabase_removal": "supabaseRemovalVerifyIterations",
    "backend_verify": "backendVerifyIterations",
    "database": "databaseVerifyIterations",
    "nginx": "nginxVerifyIterations",
    "testing_system": "systemIntegrationTestVerifyIterations",
    "swagger": "swaggerVerifyIterations",
    "javadoc": "javadocVerifyIterations",
    "api_collection": "apiCollectionVerifyIterations",
    "api_testing": "apiTestVerifyIterations",
    "api_performance": "apiPerformanceTestVerifyIterations",
    "production": "productionVerifyIterations",
    "deployment_platform": "deploymentPlatformVerifyIterations",
    "deployment_provision": "serverProvisionVerifyIterations",
    "deployment_database": "deploymentDatabaseVerifyIterations",
    "deployment_backend": "deploymentBackendVerifyIterations",
    "deployment_edge": "deploymentEdgeVerifyIterations",
    "deployment_verify": "deploymentVerifyIterations",
}


def parse_iso(value: str | None) -> datetime | None:
    if not value:
        return None
    text = value.replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def stage_duration_ms(stage: dict, now: datetime, prev_ended: datetime | None) -> int | None:
    if stage.get("durationMs") is not None:
        return int(stage["durationMs"])
    started = parse_iso(stage.get("startedAt")) or prev_ended
    ended = parse_iso(stage.get("endedAt"))
    status = stage.get("status", "pending")
    if status == "active" and started:
        return max(0, int((now - started).total_seconds() * 1000))
    if started and ended:
        return max(0, int((ended - started).total_seconds() * 1000))
    return None


def map_status(status: str) -> str:
    if status == "done":
        return "completed"
    return status or "pending"


def resolve_iterations(stage_key: str, stage: dict, state: dict) -> tuple[int, str | None]:
    if stage_key in COMPOSITE_VERIFY_KEYS:
        parts = [int(state.get(key, 0) or 0) for key in COMPOSITE_VERIFY_KEYS[stage_key]]
        total = sum(parts)
        if total <= 0:
            total = int(stage.get("iterations") or 0)
        detail = "+".join(str(p) for p in parts) if any(parts) else None
        return total, detail

    counter_key = STAGE_VERIFY_KEYS.get(stage_key)
    if counter_key:
        value = int(state.get(counter_key, 0) or 0)
        if value > 0:
            return value, None
    return int(stage.get("iterations") or 0), None


def build_progress(state: dict) -> dict:
    now = datetime.now(timezone.utc)
    stages_in = state.get("stages") or []
    prev_ended = parse_iso(state.get("workflowStartedAt"))

    stages_out: list[dict] = []
    done_count = 0
    time_consumed_ms = 0
    done_estimate_min = 0
    done_actual_min = 0.0
    remaining_estimate_min = 0
    current_stage = None
    current_stage_label = None

    for stage in stages_in:
        key = stage.get("key", "")
        status = stage.get("status", "pending")
        mapped = map_status(status)
        dur = stage_duration_ms(stage, now, prev_ended)
        if dur is not None:
            time_consumed_ms += dur
            if mapped == "completed":
                done_actual_min += dur / 60000.0
            elif mapped == "active":
                done_actual_min += dur / 60000.0

        iterations, iteration_detail = resolve_iterations(key, stage, state)

        row: dict = {
            "key": key,
            "label": stage.get("label", key),
            "status": mapped,
            "estimateMin": stage.get("estimateMin", 0),
            "iterations": iterations,
        }
        if iteration_detail:
            row["iterationDetail"] = iteration_detail
        if stage.get("startedAt"):
            row["startedAt"] = stage["startedAt"]
        elif prev_ended and mapped in ("completed", "active"):
            row["startedAt"] = prev_ended.isoformat().replace("+00:00", "Z")
        if stage.get("endedAt"):
            row["endedAt"] = stage["endedAt"]
        if dur is not None:
            row["durationMs"] = dur
        if stage.get("verdict"):
            row["verdict"] = stage["verdict"]

        stages_out.append(row)

        if mapped == "completed":
            done_count += 1
            done_estimate_min += int(stage.get("estimateMin") or 0)
        elif mapped in ("active", "pending", "needs-attention", "blocked"):
            remaining_estimate_min += int(stage.get("estimateMin") or 0)

        if mapped == "active":
            current_stage = key
            current_stage_label = stage.get("label", key)

        ended = parse_iso(stage.get("endedAt"))
        if ended:
            prev_ended = ended
        elif parse_iso(stage.get("startedAt")):
            prev_ended = parse_iso(stage.get("startedAt"))

    phase = state.get("phase", "running")
    top_status = "running"
    if phase == "complete":
        top_status = "complete"
    elif phase == "blocked":
        top_status = "blocked"
    elif any(s.get("status") in ("needs-attention",) for s in stages_in):
        top_status = "needs-attention"

    pace = done_actual_min / done_estimate_min if done_estimate_min > 0 else 1.0
    pace = max(0.5, min(3.0, pace))
    remaining_min = remaining_estimate_min * pace
    estimated_remaining_ms = int(remaining_min * 60000)
    estimated_total_ms = time_consumed_ms + estimated_remaining_ms
    eta = (now.timestamp() + estimated_remaining_ms / 1000.0)
    eta_iso = datetime.fromtimestamp(eta, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    project = state.get("project") or {}
    out = {
        "runId": state.get("runId", ""),
        "project": project,
        "vps": state.get("vps", ""),
        "localDashboardUrl": state.get("localDashboardUrl", ""),
        "generatedAt": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "workflowStartedAt": state.get("workflowStartedAt"),
        "status": top_status,
        "phase": phase,
        "currentStage": current_stage,
        "currentStageLabel": current_stage_label,
        "counts": {"done": done_count, "total": len(stages_in) or 23},
        "timeConsumedMs": time_consumed_ms,
        "estimatedTotalMs": estimated_total_ms,
        "estimatedRemainingMs": estimated_remaining_ms,
        "eta": eta_iso,
        "viewUrl": state.get("localDashboardUrl", ""),
        "actionRequired": [
            b for b in (state.get("blockers") or [])
            if isinstance(b, dict) and (b.get("kind") == "needs-input" or b.get("key"))
        ],
        "blockers": state.get("blockers") or [],
        "stages": stages_out,
    }
    if state.get("reportsUrls"):
        out["reportsUrls"] = state["reportsUrls"]
    if state.get("reportsStats"):
        out["reportsStats"] = state["reportsStats"]
    if state.get("reportsPublishedAt"):
        out["reportsPublishedAt"] = state["reportsPublishedAt"]
    return out


def main() -> int:
    state_path = Path(sys.argv[1]) if len(sys.argv) > 1 else STATE_PATH
    state = json.loads(state_path.read_text(encoding="utf-8"))
    progress = build_progress(state)
    proc = subprocess.run(
        [sys.executable, str(WRITE_HELPER)],
        input=json.dumps(progress, indent=2) + "\n",
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        print(proc.stderr or proc.stdout, file=sys.stderr)
        return proc.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
