#!/usr/bin/env python3
"""Parse test sources and emit test-catalog.json + test-catalog.html for the reports hub."""
from __future__ import annotations

import json
import os
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB = Path(__file__).resolve().parent / "web"
OUT_JSON = WEB / "test-catalog.json"
OUT_HTML = WEB / "test-catalog.html"
PROGRESS_MODE = 0o644

FE_UNIT_GLOB = ("src", "**", "*.test.ts")
FE_UNIT_GLOB_TSX = ("src", "**", "*.test.tsx")
FE_INT_GLOB = ("src", "**", "*.integration.test.ts")
FE_INT_GLOB_TSX = ("src", "**", "*.integration.test.tsx")
E2E_GLOB = ("e2e", "*.spec.ts")

BE_SERVICES = (
    "ascentaGateway",
    "administrationService",
    "accountingService",
    "billingService",
    "businessService",
    "customerportalService",
    "storeService",
)

RE_DESCRIBE = re.compile(
    r"""(?:describe|test\.describe)\s*\(\s*(['"`])(.+?)\1""",
    re.DOTALL,
)
RE_IT = re.compile(
    r"""(?:^|\s)(?:it|test)\s*\(\s*(['"`])(.+?)\1""",
    re.DOTALL,
)
RE_JAVA_TEST = re.compile(
    r"@(?:Test|ParameterizedTest)(?:\([^)]*\))?"
    r"(?:\s*@[\w.]+(?:\([^)]*\))?)*\s*"
    r"(?:public\s+|private\s+|protected\s+)?void\s+(\w+)\s*\(",
    re.MULTILINE,
)


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


def parse_ts_tests(text: str) -> list[str]:
    names: list[str] = []
    for m in RE_IT.finditer(text):
        name = m.group(2).strip()
        if name and name not in names:
            names.append(name)
    return names


def parse_java_tests(text: str) -> list[str]:
    return [m.group(1) for m in RE_JAVA_TEST.finditer(text)]


def be_module(path: Path) -> str:
    parts = path.parts
    for svc in BE_SERVICES:
        if svc in parts:
            return svc
    for part in parts:
        if part.endswith("Service") or part == "ascentaGateway":
            return part
    return "backend"


def classify_java_file(path: Path) -> str | None:
    name = path.name
    if not name.endswith(".java"):
        return None
    rel = str(path)
    if "/src/test/java/" not in rel.replace("\\", "/"):
        return None
    if name.endswith("IT.java"):
        if re.search(r"(ResourceIT|FunctionalIT|CoverageIT)\.java$", name):
            return "backend-functional"
        return "backend-integration"
    if name.endswith("Test.java"):
        return "backend-unit"
    return None


def add_entry(
    catalog: dict[str, dict[str, list[dict]]],
    layer: str,
    module: str,
    rel_path: str,
    tests: list[str],
) -> None:
    if not tests:
        return
    catalog.setdefault(layer, {}).setdefault(module, []).append(
        {"file": rel_path, "count": len(tests), "tests": tests}
    )


def scan_frontend(catalog: dict) -> None:
    seen: set[Path] = set()
    for pattern in (FE_UNIT_GLOB, FE_UNIT_GLOB_TSX):
        for path in sorted(ROOT.glob("/".join(pattern))):
            if ".integration.test." in path.name:
                continue
            seen.add(path)
            rel = path.relative_to(ROOT).as_posix()
            tests = parse_ts_tests(path.read_text(encoding="utf-8", errors="replace"))
            module = path.parts[1] if len(path.parts) > 2 else "frontend"
            add_entry(catalog, "frontend-unit", module, rel, tests)

    for pattern in (FE_INT_GLOB, FE_INT_GLOB_TSX):
        for path in sorted(ROOT.glob("/".join(pattern))):
            rel = path.relative_to(ROOT).as_posix()
            tests = parse_ts_tests(path.read_text(encoding="utf-8", errors="replace"))
            module = path.parts[1] if len(path.parts) > 2 else "frontend"
            add_entry(catalog, "frontend-integration", module, rel, tests)

    for path in sorted(ROOT.glob("/".join(E2E_GLOB))):
        rel = path.relative_to(ROOT).as_posix()
        tests = parse_ts_tests(path.read_text(encoding="utf-8", errors="replace"))
        add_entry(catalog, "e2e", "e2e", rel, tests)


def scan_backend(catalog: dict) -> None:
    for path in sorted(ROOT.rglob("*.java")):
        layer = classify_java_file(path)
        if not layer:
            continue
        rel = path.relative_to(ROOT).as_posix()
        tests = parse_java_tests(path.read_text(encoding="utf-8", errors="replace"))
        add_entry(catalog, layer, be_module(path), rel, tests)


def layer_totals(catalog: dict) -> dict[str, int]:
    totals: dict[str, int] = {}
    for layer, modules in catalog.items():
        total = 0
        for files in modules.values():
            for f in files:
                total += f["count"]
        totals[layer] = total
    return totals


def build_catalog() -> dict:
    catalog: dict[str, dict[str, list[dict]]] = {}
    scan_frontend(catalog)
    scan_backend(catalog)
    totals = layer_totals(catalog)
    file_count = sum(len(files) for modules in catalog.values() for files in modules.values())
    return {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "totals": totals,
        "totalTests": sum(totals.values()),
        "totalFiles": file_count,
        "layers": catalog,
    }


def build_html(data: dict) -> str:
    payload = json.dumps(data)
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Sunny — Test Catalog</title>
  <link rel="stylesheet" href="reports-shared.css" />
</head>
<body class="catalog-page">
  <header class="site-header">
    <h1><span class="sun">&#9728;</span> Sunny — Test Catalog</h1>
    <nav class="top-nav">
      <a href="/reports.html">Overview</a>
      <a href="/reports.html#all">All reports</a>
      <a href="/test-catalog.html" class="active">Test catalog</a>
      <a href="/reports.html#artifacts">Artifacts</a>
      <a href="/agentprogress.html">Progress</a>
    </nav>
    <span class="pill" id="countPill">—</span>
  </header>

  <aside class="sidebar">
    <div class="search sticky-search"><input id="q" type="search" placeholder="Search tests…" autocomplete="off" /></div>
    <div class="filter-row">
      <label>Layer <select id="layerFilter"><option value="">All layers</option></select></label>
      <label>Module <select id="moduleFilter"><option value="">All modules</option></select></label>
    </div>
    <div id="summaryCards" class="summary-cards"></div>
    <div id="fileList" class="file-list"></div>
  </aside>

  <main id="content">
    <p class="empty">Select a file or search for a test method.</p>
  </main>

  <footer class="site-footer">
    <span id="gen">Generated: —</span>
    <span id="stats">—</span>
    <a href="/reports.html">← Reports hub</a>
  </footer>

  <script>
    const DATA = {payload};
    const $ = (id) => document.getElementById(id);
    let activeFile = null;

    function esc(s) {{
      return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
    }}

    function layerLabel(k) {{
      return ({{"frontend-unit":"FE unit","frontend-integration":"FE integration","e2e":"E2E",
        "backend-unit":"BE unit","backend-integration":"BE integration","backend-functional":"BE functional"}})[k] || k;
    }}

    function allFiles() {{
      const out = [];
      Object.entries(DATA.layers || {{}}).forEach(([layer, modules]) => {{
        Object.entries(modules).forEach(([module, files]) => {{
          files.forEach((f) => out.push({{ ...f, layer, module }}));
        }});
      }});
      return out;
    }}

    function renderSummary() {{
      const cards = $("summaryCards");
      const totals = DATA.totals || {{}};
      cards.innerHTML = Object.keys(totals).sort().map((k) =>
        `<button type="button" class="summary-card" data-layer="${{esc(k)}}"><span class="n">${{totals[k]}}</span><span class="l">${{esc(layerLabel(k))}}</span></button>`
      ).join("");
      cards.querySelectorAll(".summary-card").forEach((btn) => {{
        btn.addEventListener("click", () => {{
          $("layerFilter").value = btn.dataset.layer;
          $("moduleFilter").value = "";
          populateModules();
          renderList();
        }});
      }});
    }}

    function populateLayers() {{
      const sel = $("layerFilter");
      Object.keys(DATA.totals || {{}}).sort().forEach((k) => {{
        const o = document.createElement("option");
        o.value = k; o.textContent = layerLabel(k);
        sel.appendChild(o);
      }});
    }}

    function populateModules() {{
      const layer = $("layerFilter").value;
      const sel = $("moduleFilter");
      sel.innerHTML = '<option value="">All modules</option>';
      const mods = new Set();
      allFiles().forEach((f) => {{
        if (!layer || f.layer === layer) mods.add(f.module);
      }});
      [...mods].sort().forEach((m) => {{
        const o = document.createElement("option");
        o.value = m; o.textContent = m;
        sel.appendChild(o);
      }});
    }}

    function renderList() {{
      const q = ($("q").value || "").trim().toLowerCase();
      const layer = $("layerFilter").value;
      const module = $("moduleFilter").value;
      const list = $("fileList");
      let html = "";
      allFiles().filter((f) => {{
        if (layer && f.layer !== layer) return false;
        if (module && f.module !== module) return false;
        if (!q) return true;
        const hay = (f.file + " " + f.tests.join(" ")).toLowerCase();
        return hay.includes(q);
      }}).forEach((f) => {{
        const id = f.layer + "::" + f.file;
        html += `<a href="#" class="file-row${{activeFile === id ? " active" : ""}}" data-id="${{esc(id)}}">`
          + `<span class="badge">${{esc(layerLabel(f.layer))}}</span>`
          + `<span class="fname">${{esc(f.file)}}</span>`
          + `<span class="cnt">${{f.count}}</span></a>`;
      }});
      list.innerHTML = html || "<p class='empty'>No matches</p>";
      list.querySelectorAll(".file-row").forEach((el) => {{
        el.addEventListener("click", (e) => {{
          e.preventDefault();
          showFile(el.dataset.id);
        }});
      }});
    }}

    function showFile(id) {{
      activeFile = id;
      const [layer, ...rest] = id.split("::");
      const file = rest.join("::");
      const entry = allFiles().find((f) => f.layer === layer && f.file === file);
      if (!entry) return;
      renderList();
      $("content").innerHTML = `<article class="report-body"><header class="report-head"><h1>${{esc(entry.file)}}</h1>`
        + `<p class="report-meta"><span>${{esc(layerLabel(entry.layer))}}</span><span>${{esc(entry.module)}}</span>`
        + `<span>${{entry.count}} tests</span></p></header><ul class="test-names">`
        + entry.tests.map((t) => `<li>${{esc(t)}}</li>`).join("") + "</ul></article>";
    }}

    $("q").addEventListener("input", renderList);
    $("layerFilter").addEventListener("change", () => {{ populateModules(); renderList(); }});
    $("moduleFilter").addEventListener("change", renderList);

    $("countPill").textContent = (DATA.totalTests || 0) + " tests";
    $("gen").textContent = "Generated: " + (DATA.generatedAt || "—");
    $("stats").textContent = (DATA.totalFiles || 0) + " files · " + Object.keys(DATA.totals || {{}}).length + " layers";
    populateLayers();
    populateModules();
    renderSummary();
    renderList();
  </script>
</body>
</html>
"""


def main() -> int:
    data = build_catalog()
    atomic_write(OUT_JSON, json.dumps(data, indent=2) + "\n")
    atomic_write(OUT_HTML, build_html(data))
    print(
        f"OK  {data['totalTests']} tests in {data['totalFiles']} files → "
        f"{OUT_JSON.name} + {OUT_HTML.name}"
    )
    for layer, count in sorted(data["totals"].items()):
        print(f"    {layer}: {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
