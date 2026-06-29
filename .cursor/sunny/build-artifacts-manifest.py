#!/usr/bin/env python3
"""Symlink Postman, OpenAPI, and JaCoCo artifacts into .sunny/web/artifacts/."""
from __future__ import annotations

import json
import os
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB = Path(__file__).resolve().parent / "web"
ARTIFACTS = WEB / "artifacts"
MANIFEST = WEB / "artifacts-manifest.json"
PROGRESS_MODE = 0o644

BE_SERVICES = (
    "ascentaGateway",
    "administrationService",
    "accountingService",
    "billingService",
    "businessService",
    "customerportalService",
    "storeService",
)


def atomic_write_json(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(json.dumps(data, indent=2) + "\n")
        os.chmod(tmp, PROGRESS_MODE)
        os.replace(tmp, path)
        os.chmod(path, PROGRESS_MODE)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def link_or_copy(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() or dest.is_symlink():
        if dest.is_symlink() or dest.is_file():
            dest.unlink()
        elif dest.is_dir():
            shutil.rmtree(dest)
    try:
        os.symlink(src, dest)
    except OSError:
        if src.is_dir():
            shutil.copytree(src, dest, dirs_exist_ok=True)
        else:
            shutil.copy2(src, dest)
        os.chmod(dest, PROGRESS_MODE)


def build() -> dict:
    entries: list[dict] = []

    postman_col = ROOT / "postman" / "ascenta-core-hub.postman_collection.json"
    if postman_col.is_file():
        dest = ARTIFACTS / "postman" / "collection.json"
        link_or_copy(postman_col, dest)
        entries.append({
            "id": "postman-collection",
            "label": "Postman collection",
            "category": "Postman",
            "path": "/artifacts/postman/collection.json",
            "available": True,
        })

    env_dir = ROOT / "postman" / "environments"
    if env_dir.is_dir():
        dest_env = ARTIFACTS / "postman" / "environments"
        dest_env.mkdir(parents=True, exist_ok=True)
        for env in sorted(env_dir.glob("*.json")):
            dest = dest_env / env.name
            link_or_copy(env, dest)
            entries.append({
                "id": f"postman-env-{env.stem}",
                "label": f"Postman env: {env.stem}",
                "category": "Postman",
                "path": f"/artifacts/postman/environments/{env.name}",
                "available": True,
            })

    openapi_dir = ROOT / "openapi"
    if openapi_dir.is_dir():
        dest_openapi = ARTIFACTS / "openapi"
        dest_openapi.mkdir(parents=True, exist_ok=True)
        for spec in sorted(openapi_dir.glob("*-openapi.json")):
            dest = dest_openapi / spec.name
            link_or_copy(spec, dest)
            entries.append({
                "id": f"openapi-{spec.stem}",
                "label": spec.name.replace("-openapi.json", "").title() + " OpenAPI",
                "category": "OpenAPI",
                "path": f"/artifacts/openapi/{spec.name}",
                "available": True,
            })

    for svc in BE_SERVICES:
        jacoco = ROOT / svc / "target" / "site" / "jacoco"
        jacoco_ut = ROOT / svc / "target" / "site" / "jacoco-ut"
        picked = jacoco if jacoco.is_dir() else (jacoco_ut if jacoco_ut.is_dir() else None)
        rel_path = f"/artifacts/jacoco/{svc}/"
        if picked:
            dest = ARTIFACTS / "jacoco" / svc
            link_or_copy(picked, dest)
            index = rel_path + "index.html"
            entries.append({
                "id": f"jacoco-{svc}",
                "label": f"JaCoCo — {svc}",
                "category": "JaCoCo",
                "path": index,
                "available": True,
            })
        else:
            entries.append({
                "id": f"jacoco-{svc}",
                "label": f"JaCoCo — {svc}",
                "category": "JaCoCo",
                "path": rel_path + "index.html",
                "available": False,
                "note": "Run mvn verify to generate",
            })

    manifest = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "count": len(entries),
        "availableCount": sum(1 for e in entries if e.get("available")),
        "artifacts": entries,
    }
    atomic_write_json(MANIFEST, manifest)
    return manifest


def main() -> int:
    manifest = build()
    print(
        f"OK  {manifest['availableCount']}/{manifest['count']} artifacts available → "
        f"artifacts/ + artifacts-manifest.json"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
