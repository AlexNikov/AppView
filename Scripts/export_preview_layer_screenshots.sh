#!/usr/bin/env bash
# Export per-layer preview PNGs via AppView MCP into a directory.
# Usage:
#   bash AppView/Scripts/export_preview_layer_screenshots.sh [port] [output_dir]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${1:-47192}"
OUT="${2:-$ROOT/appview-verify-logs/preview-layers-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$(dirname "$OUT")"

BODY=$(OUT="$OUT" python3 -c 'import json, os; print(json.dumps({"directory": os.environ["OUT"]}))')

echo "POST http://127.0.0.1:${PORT}/ui/preview/export-screenshots"
echo "  directory: $OUT"
RESP=$(curl -sf --max-time 120 -X POST "http://127.0.0.1:${PORT}/ui/preview/export-screenshots" \
  -H "Content-Type: application/json" \
  -d "$BODY") || {
  echo "FAIL: MCP request failed (is AppView in inspector with iOS connected?)" >&2
  exit 1
}

echo "$RESP" | python3 -m json.tool
EXPORTED=$(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin).get('data',{}); print(d.get('exportedCount',0))")
echo ""
echo "Exported $EXPORTED layer file(s) to: $OUT"
ls -la "$OUT" 2>/dev/null | head -30
