#!/usr/bin/env python3
"""Build read-only HTML agent reports from .sunny/context/*.md for the demo dashboard.

Writes to .sunny/web/ only — never modifies context/ or disturbs the running pipeline.
Regenerate anytime: python3 .sunny/write-reports-html.py
"""
from __future__ import annotations

import html
import json
import os
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CONTEXT = ROOT / "context"
WEB = ROOT / "web"
REPORTS_DIR = WEB / "reports"
MANIFEST = WEB / "reports-manifest.json"
PROGRESS_MODE = 0o644

SKIP = {"state.json"}

CATEGORY_RULES: list[tuple[str, re.Pattern[str]]] = [
    ("Deployment", re.compile(r"^deployment-|^server-provision-", re.I)),
    ("Test reports", re.compile(r".*-test-report\.md$", re.I)),
    ("Verify reports", re.compile(r".*-verify-report\.md$", re.I)),
    ("Fix logs", re.compile(r".*-fix-log\.md$|issue-resolution-log\.md$", re.I)),
    ("Summaries", re.compile(r".*-summary\.md$", re.I)),
    ("Reference", re.compile(r"^(backend|database|nginx|project)-", re.I)),
    ("Operations", re.compile(r"KNOWN_ISSUES\.md$|verify-report\.md$", re.I)),
]

STAGE_RULES: list[tuple[str, re.Pattern[str]]] = [
    ("deployment_verify", re.compile(r"^deployment-verify", re.I)),
    ("deployment_edge", re.compile(r"^deployment-edge", re.I)),
    ("deployment_backend", re.compile(r"^deployment-backend", re.I)),
    ("deployment_database", re.compile(r"^deployment-database", re.I)),
    ("deployment_provision", re.compile(r"^server-provision-", re.I)),
    ("deployment_platform", re.compile(r"^deployment-platform|^deployment-fix", re.I)),
    ("production", re.compile(r"^production-", re.I)),
    ("api_performance", re.compile(r"^api-performance-", re.I)),
    ("api_testing", re.compile(r"^api-test-", re.I)),
    ("api_collection", re.compile(r"^api-collection-", re.I)),
    ("javadoc", re.compile(r"^javadoc-", re.I)),
    ("swagger", re.compile(r"^swagger-", re.I)),
    ("testing_system", re.compile(r"^system-integration-test-", re.I)),
    ("testing_frontend", re.compile(r"^frontend-(functional|integration|unit|test)-", re.I)),
    ("testing_backend", re.compile(r"^backend-(functional|integration|unit|test)-", re.I)),
    ("nginx", re.compile(r"^nginx-", re.I)),
    ("database", re.compile(r"^database-", re.I)),
    ("backend_verify", re.compile(r"^backend-(verify|summary)|^verify-report", re.I)),
    ("backend", re.compile(r"^backend-", re.I)),
    ("supabase_removal", re.compile(r"^supabase-removal-", re.I)),
    ("architecture", re.compile(r"^architecture-", re.I)),
    ("frontend_sanitize", re.compile(r"^frontend-sanitize-", re.I)),
]

VERDICT_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("live", re.compile(r"\bsystem is live\b|\bproduction deployment verified\b", re.I)),
    ("granted", re.compile(r"\bfinal approval granted\b|\bapproved\b|\bsatisfied\b", re.I)),
    ("blocked", re.compile(r"\bblocked\b|\bfailed\b|\brejected\b", re.I)),
]


def categorize(name: str) -> str:
    for label, pattern in CATEGORY_RULES:
        if pattern.search(name):
            return label
    return "Other"


def stage_for(name: str) -> str | None:
    for key, pattern in STAGE_RULES:
        if pattern.search(name):
            return key
    return None


def verdict_for(raw: str) -> str | None:
    final = re.search(r"##\s*Final verdict\s*\n+(.+?)(?:\n#|\n##|\Z)", raw, re.I | re.S)
    if final:
        section = final.group(1).strip().lower()
        if "final approval granted" in section or "production deployment verified" in section or "system is live" in section:
            return "granted"
        if "blocked" in section or "failed" in section:
            return "blocked"
    head = raw[:2000].lower()
    if "final approval granted" in head:
        return "granted"
    tail = raw[-800:].lower()
    if re.search(r"\bfinal approval granted\b|\bproduction deployment verified\b|\bsystem is live\b", tail):
        return "granted"
    if re.search(r"\bblocked\b|\bfailed\b|\brejected\b", head):
        return "blocked"
    for label, pattern in VERDICT_PATTERNS:
        if pattern.search(raw):
            return label
    return None


def slugify(name: str) -> str:
    return re.sub(r"\.md$", "", name, flags=re.I).lower().replace("_", "-")


def md_to_html(text: str) -> str:
  """Minimal markdown → HTML (headers, tables, lists, code, emphasis)."""
  lines = text.replace("\r\n", "\n").split("\n")
  out: list[str] = []
  i = 0
  in_code = False
  code_lang = ""
  in_table = False
  table_rows: list[str] = []

  def flush_table() -> None:
    nonlocal in_table, table_rows
    if not table_rows:
      return
    out.append('<table class="md-table">')
    for ri, row in enumerate(table_rows):
      cells = [c.strip() for c in row.strip().strip("|").split("|")]
      if ri == 1 and all(re.match(r"^:?-+:?$", c) for c in cells):
        continue
      tag = "th" if ri == 0 else "td"
      out.append("<tr>" + "".join(f"<{tag}>{inline_md(c)}</{tag}>" for c in cells) + "</tr>")
    out.append("</table>")
    table_rows = []
    in_table = False

  def inline_md(s: str) -> str:
    s = html.escape(s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", s)
    s = re.sub(
      r"\[([^\]]+)\]\(([^)]+)\)",
      lambda m: f'<a href="{html.escape(m.group(2))}" rel="noopener">{html.escape(m.group(1))}</a>',
      s,
    )
    return s

  while i < len(lines):
    line = lines[i]
    if line.strip().startswith("```"):
      flush_table()
      if in_code:
        out.append("</code></pre>")
        in_code = False
        code_lang = ""
      else:
        code_lang = line.strip()[3:].strip()
        cls = f' class="lang-{html.escape(code_lang)}"' if code_lang else ""
        out.append(f"<pre><code{cls}>")
        in_code = True
      i += 1
      continue
    if in_code:
      out.append(html.escape(line) + "\n")
      i += 1
      continue

    if "|" in line and line.strip().startswith("|"):
      in_table = True
      table_rows.append(line)
      i += 1
      continue
    flush_table()

    if re.match(r"^#{1,6}\s", line):
      level = len(line) - len(line.lstrip("#"))
      level = min(max(level, 1), 6)
      content = inline_md(line.lstrip("#").strip())
      out.append(f"<h{level}>{content}</h{level}>")
    elif re.match(r"^[-*]\s+", line):
      items = []
      while i < len(lines) and re.match(r"^[-*]\s+", lines[i]):
        items.append(f"<li>{inline_md(lines[i][2:].strip())}</li>")
        i += 1
      out.append("<ul>" + "".join(items) + "</ul>")
      continue
    elif re.match(r"^\d+\.\s+", line):
      items = []
      while i < len(lines) and re.match(r"^\d+\.\s+", lines[i]):
        item_text = re.sub(r"^\d+\.\s+", "", lines[i]).strip()
        items.append(f"<li>{inline_md(item_text)}</li>")
        i += 1
      out.append("<ol>" + "".join(items) + "</ol>")
      continue
    elif line.strip() in ("---", "***", "___"):
      out.append("<hr>")
    elif line.strip() == "":
      out.append("")
    else:
      out.append(f"<p>{inline_md(line)}</p>")
    i += 1

  flush_table()
  if in_code:
    out.append("</code></pre>")
  return "\n".join(out)


def atomic_write(path: Path, content: str) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
  try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
      handle.write(content)
    os.chmod(tmp, PROGRESS_MODE)
    os.replace(tmp, path)
    os.chmod(path, PROGRESS_MODE)
  except Exception:
    try:
      os.unlink(tmp)
    except OSError:
      pass
    raise


def atomic_write_json(path: Path, data: object) -> None:
  atomic_write(path, json.dumps(data, indent=2) + "\n")


def collect_sources() -> list[Path]:
  sources: list[Path] = []
  if CONTEXT.is_dir():
    sources.extend(sorted(CONTEXT.glob("*.md")))
  known = ROOT / "KNOWN_ISSUES.md"
  if known.is_file():
    sources.append(known)
  return sources


def build() -> dict:
  entries: list[dict] = []
  REPORTS_DIR.mkdir(parents=True, exist_ok=True)

  for src in collect_sources():
    name = src.name
    if name in SKIP:
      continue
    slug = slugify(name)
    raw = src.read_text(encoding="utf-8", errors="replace")
    mtime = datetime.fromtimestamp(src.stat().st_mtime, tz=timezone.utc).isoformat()
    mtime_ts = src.stat().st_mtime
    title_match = re.search(r"^#\s+(.+)$", raw, re.M)
    title = title_match.group(1).strip() if title_match else name.replace(".md", "").replace("-", " ").title()
    body = md_to_html(raw)
    fragment = (
      f'<article class="report-body" id="{slug}">\n'
      f'<header class="report-head"><h1>{html.escape(title)}</h1>'
      f'<p class="report-meta"><span class="file">{html.escape(name)}</span>'
      f'<span class="mtime">Updated {html.escape(mtime)}</span></p></header>\n'
      f"{body}\n</article>"
    )
    out_path = REPORTS_DIR / f"{slug}.html"
    atomic_write(out_path, fragment)
    entry: dict = {
        "id": slug,
        "title": title,
        "file": name,
        "category": categorize(name),
        "path": f"reports/{slug}.html",
        "mtime": mtime,
        "_mtime_ts": mtime_ts,
        "size": src.stat().st_size,
    }
    stage = stage_for(name)
    if stage:
      entry["stage"] = stage
    verdict = verdict_for(raw)
    if verdict:
      entry["verdict"] = verdict
    entries.append(entry)

  entries.sort(key=lambda e: (e["category"], -e.get("_mtime_ts", 0), e["title"].lower()))
  for e in entries:
    e.pop("_mtime_ts", None)
  manifest = {
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "count": len(entries),
    "reports": entries,
  }
  atomic_write_json(MANIFEST, manifest)
  return manifest


def main() -> int:
  manifest = build()
  print(f"OK  {manifest['count']} reports → {WEB}/reports/ + reports-manifest.json")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
