#!/usr/bin/env python3
"""
Convert cursor-agents/.cursor/agents/*.md personas into Hermes SKILL.md files.

Output: ~/.hermes/skills/devops/sunny-agents/<slug>/SKILL.md
Also writes MANIFEST.json with slug → toolsets, readonly, codename aliases.

Real files (not symlinks) so Hermes trusts them under ~/.hermes/skills/.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AGENTS_DIR = ROOT / ".cursor" / "agents"
DEFAULT_OUT = Path.home() / ".hermes" / "skills" / "devops" / "sunny-agents"

SKIP_FILES = {
    "README.md",
    "AGENT-GUIDE.md",
    "ARCHITECTURE.md",
}

CODENAME_CANONICAL = {
    "maya": "context-agent",
    "rajesh": "deployment-platform-agent",
    "rajesh-verify": "deployment-platform-verify-agent",
    "rajesh-fix": "deployment-platform-fix-agent",
    "suresh": "server-provision-agent",
    "suresh-verify": "server-provision-verify-agent",
    "suresh-fix": "server-provision-fix-agent",
    "lakshmi": "deployment-database-agent",
    "lakshmi-verify": "deployment-database-verify-agent",
    "lakshmi-fix": "deployment-database-fix-agent",
    "manoj": "deployment-backend-agent",
    "manoj-verify": "deployment-backend-verify-agent",
    "manoj-fix": "deployment-backend-fix-agent",
    "asha": "deployment-edge-agent",
    "asha-verify": "deployment-edge-verify-agent",
    "asha-fix": "deployment-edge-fix-agent",
    "om": "deployment-verify-agent",
    "om-fix": "om-fix-agent",
    "neel": "reports-publish-agent",
    "prakash": "production-standards-agent",
    "prakash-fix": "production-fix-agent",
}

HERMES_PREAMBLE = """## Hermes runtime (required)

You are a **Sunny pipeline specialist** running inside **Hermes Agent**. Execute work directly with your tools — do not ask the parent to run commands for you.

| Setting | Value |
|---------|-------|
| Toolsets | `{toolsets}` |
| Readonly | `{readonly}` |
| Persona slug | `{slug}` |
| Skill path | `~/.hermes/skills/devops/sunny-agents/{slug}/SKILL.md` |

**Rules:**
- Use `terminal` for builds, tests, docker, kubectl, graphify, npm, mvn, etc.
- Use `file` / `code` tools to read and edit project files.
- Return **structured output** exactly as your persona specifies (for Maya / context-agent).
- Do **not** write to `.sunny/context/` unless you are `context-agent`.
- After code changes, run `graphify update <project-root>` before handing off (except readonly verify agents).

---

"""


def parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    block = text[3:end].strip()
    body = text[end + 4 :].lstrip("\n")
    meta: dict[str, str] = {}
    for line in block.splitlines():
        if ":" not in line:
            continue
        key, val = line.split(":", 1)
        meta[key.strip()] = val.strip().strip('"').strip("'")
    return meta, body


def infer_toolsets(slug: str, readonly: bool) -> list[str]:
    if readonly:
        return ["terminal", "file"]
    if slug in {"context-agent", "issues-log-agent", "fleet-host-agent"}:
        return ["file", "terminal"]
    return ["terminal", "file", "code", "web"]


def infer_readonly(slug: str, meta: dict[str, str]) -> bool:
    raw = meta.get("readonly", "").lower()
    if raw in {"true", "yes", "1"}:
        return True
    if raw in {"false", "no", "0"}:
        return False
    if slug.endswith("-verify-agent") or slug in {
        "production-standards-agent",
        "deployment-verify-agent",
        "jhipster-verify-agent",
    }:
        return True
    return False


def infer_tags(slug: str) -> list[str]:
    tags = ["sunny", "agent"]
    if slug.endswith("-verify-agent"):
        tags.append("verify")
    elif slug.endswith("-fix-agent"):
        tags.append("fix")
    else:
        tags.append("generate")
    base = slug.replace("-agent", "").replace("-verify", "").replace("-fix", "")
    if base:
        tags.append(base.split("-")[0])
    return tags


def truncate_description(desc: str, max_len: int = 1020) -> str:
    desc = re.sub(r"\s+", " ", desc.strip())
    if len(desc) <= max_len:
        return desc
    return desc[: max_len - 3] + "..."


def build_skill_md(
    slug: str,
    meta: dict[str, str],
    body: str,
    *,
    codename: str | None = None,
    canonical_slug: str | None = None,
) -> str:
    readonly = infer_readonly(slug, meta)
    toolsets = infer_toolsets(slug, readonly)
    desc = meta.get("description") or f"Sunny pipeline agent: {slug}"
    desc = truncate_description(
        f"Sunny/Hermes persona ({slug}). {desc} Invoke via /{slug} or delegate_task."
    )
    name = slug[:64]
    preamble = HERMES_PREAMBLE.format(
        toolsets=", ".join(toolsets),
        readonly=str(readonly).lower(),
        slug=slug,
    )
    if codename and canonical_slug and canonical_slug != slug:
        alias_note = (
            f"> **Codename alias:** {codename} → canonical `{canonical_slug}`. "
            f"Follow the canonical persona below.\n\n"
        )
        body = alias_note + body

    tags = infer_tags(slug)
    frontmatter = (
        "---\n"
        f"name: {name}\n"
        f'description: "{desc.replace(chr(34), chr(39))}"\n'
        "version: 1.0.0\n"
        "author: cursor-agents\n"
        "license: MIT\n"
        "platforms: [linux, macos, windows]\n"
        "metadata:\n"
        "  hermes:\n"
        f"    tags: {json.dumps(tags)}\n"
        "    related_skills: [sunny]\n"
        "    sunny:\n"
        f"      slug: {slug}\n"
        f"      readonly: {str(readonly).lower()}\n"
        f"      toolsets: {json.dumps(toolsets)}\n"
    )
    if codename:
        frontmatter += f"      codename: {codename}\n"
    if canonical_slug:
        frontmatter += f"      canonical_slug: {canonical_slug}\n"
    frontmatter += "---\n\n"
    return frontmatter + preamble + body


def collect_canonical_slugs() -> list[str]:
    slugs: list[str] = []
    for path in sorted(AGENTS_DIR.glob("*.md")):
        if path.name in SKIP_FILES:
            continue
        if (
            path.name.endswith("-agent.md")
            or path.name in {"documentation.md"}
        ):
            slugs.append(path.stem)
    return slugs


def convert_all(out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    canonical_slugs = collect_canonical_slugs()
    canonical_bodies: dict[str, tuple[dict[str, str], str]] = {}

    for slug in canonical_slugs:
        src = AGENTS_DIR / f"{slug}.md"
        meta, body = parse_frontmatter(src.read_text(encoding="utf-8"))
        canonical_bodies[slug] = (meta, body)
        skill_text = build_skill_md(slug, meta, body, canonical_slug=slug)
        skill_dir = out_dir / slug
        skill_dir.mkdir(parents=True, exist_ok=True)
        (skill_dir / "SKILL.md").write_text(skill_text, encoding="utf-8")

    # Codename alias skills (thin wrappers pointing at canonical body)
    for alias, canonical in CODENAME_CANONICAL.items():
        if canonical not in canonical_bodies:
            print(f"WARN: canonical missing for alias {alias} -> {canonical}", file=sys.stderr)
            continue
        alias_src = AGENTS_DIR / f"{alias}.md"
        if alias_src.exists():
            alias_meta, _ = parse_frontmatter(alias_src.read_text(encoding="utf-8"))
        else:
            alias_meta = {"description": f"Codename alias for {canonical}"}
        can_meta, can_body = canonical_bodies[canonical]
        skill_text = build_skill_md(
            alias,
            {**can_meta, **alias_meta, "name": alias},
            can_body,
            codename=alias,
            canonical_slug=canonical,
        )
        skill_dir = out_dir / alias
        skill_dir.mkdir(parents=True, exist_ok=True)
        (skill_dir / "SKILL.md").write_text(skill_text, encoding="utf-8")

    manifest: dict = {
        "version": 1,
        "source": str(AGENTS_DIR),
        "output": str(out_dir),
        "canonical_count": len(canonical_slugs),
        "alias_count": len(CODENAME_CANONICAL),
        "agents": {},
        "aliases": CODENAME_CANONICAL,
    }

    for skill_dir in sorted(out_dir.iterdir()):
        if not skill_dir.is_dir():
            continue
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.exists():
            continue
        slug = skill_dir.name
        meta, _ = parse_frontmatter(skill_md.read_text(encoding="utf-8"))
        readonly = infer_readonly(slug, meta)
        manifest["agents"][slug] = {
            "skill": f"devops/sunny-agents/{slug}",
            "skill_path": str(skill_md),
            "readonly": readonly,
            "toolsets": infer_toolsets(slug, readonly),
            "slash_command": f"/{slug}",
        }

    (out_dir / "MANIFEST.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest


def main() -> int:
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    if not AGENTS_DIR.is_dir():
        print(f"ERR: agents dir not found: {AGENTS_DIR}", file=sys.stderr)
        return 1
    manifest = convert_all(out_dir)
    total = len(manifest["agents"])
    print(f"OK  Wrote {total} Hermes persona skills to {out_dir}")
    print(f"    Canonical: {manifest['canonical_count']}  Aliases: {manifest['alias_count']}")
    print(f"    Manifest: {out_dir / 'MANIFEST.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
