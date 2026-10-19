#!/usr/bin/env bash
# Classify @objc usage in AppViewClient (Phase F). Read-only inventory for cleanup PRs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/AppViewClient"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$REPO/appview-verify-logs"
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$LOG_DIR/client-objc-audit-${STAMP}.txt"

python3 - "$CLIENT" "$OUT" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

client = Path(sys.argv[1])
out_path = Path(sys.argv[2])

class_pat = re.compile(
    r"^@objc\(([^)]+)\)\s*\n((?:private |public |final |open )*)class (\w+)",
    re.M,
)
counts = {k: 0 for k in "ABCDEFG"}
samples = {k: [] for k in "ABCDEFG"}

for path in sorted(client.rglob("*.swift")):
    text = path.read_text()
    rel = path.relative_to(client.parent)
    for m in class_pat.finditer(text):
        objc_name, swift_name = m.group(1), m.group(3)
        cat = "A" if objc_name == swift_name else "B"
        counts[cat] += 1
        if len(samples[cat]) < 8:
            samples[cat].append(f"  {rel}: @objc({objc_name}) class {swift_name}")

    for m in re.finditer(r"^@objc\(([^)]+)\)\s*$", text, re.M):
        name = m.group(1)
        if "initWith" in name or (":" in name and not name.startswith("LK")):
            cat = "C"
            counts[cat] += 1
        elif name.startswith("AppView"):
            cat = "G"
            counts[cat] += 1

    counts["D"] += len(re.findall(r"^@objc protocol ", text, re.M))
    counts["G"] += len(re.findall(r"^@objc enum ", text, re.M))
    counts["E"] += len(
        re.findall(
            r"^\s*@objc(?:\([^)]+\))?\s+(?:private |public |fileprivate |override )?func ",
            text,
            re.M,
        )
    )

    if "/Connection/" in str(path) and "@objc" in text:
        counts["F"] += 1

r = subprocess.run(
    ["rg", "-c", r"@objc\(", str(client), "--glob", "*.swift"],
    capture_output=True,
    text=True,
)
total_atobjc = 0
rows = []
for line in r.stdout.splitlines():
    if ":" in line:
        p, c = line.rsplit(":", 1)
        c = int(c)
        total_atobjc += c
        rows.append((c, p))

with out_path.open("w") as f:
    f.write("RESULT: client_objc_audit\n")
    f.write(f"  AppViewClient @objc( total (rg): {total_atobjc}\n\n")
    f.write("Categories (heuristic; overlaps possible):\n")
    labels = {
        "A": "redundant @objc(Name) class Name — remove in Phase F3",
        "B": "@objc name != Swift class name — keep",
        "C": "legacy selector line @objc(foo:)",
        "D": "@objc protocol",
        "E": "@objc func (selectors / delegates)",
        "F": "Connection files with @objc",
        "G": "@objc enum / AppView* exports",
    }
    for cat in "ABCDEFG":
        f.write(f"  [{cat}] {labels[cat]}: {counts[cat]}\n")
        for s in samples.get(cat, []):
            f.write(s + "\n")
        f.write("\n")
    f.write("Top 15 files by @objc( count:\n")
    for c, p in sorted(rows, reverse=True)[:15]:
        f.write(f"  {c:3d}  {p}\n")

print(out_path.read_text())
PY

chmod +x "$ROOT/Scripts/audit_client_objc.sh" 2>/dev/null || chmod +x "$(dirname "$0")/audit_client_objc.sh"
echo ""
echo "audit_client_objc: wrote $OUT"
