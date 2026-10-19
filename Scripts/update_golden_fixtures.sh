#!/usr/bin/env bash
# Regenerate swift-only golden fixtures from a successful verify capture.
# Usage:
#   bash AppView/Scripts/update_golden_fixtures.sh [capture_dir]
# If capture_dir omitted, uses latest tap-swift-* under appview-verify-logs/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURES="$ROOT/AppView/Scripts/fixtures"
COMPARE_PY="$ROOT/AppView/Scripts/compare_ui_hierarchy.py"
PREVIEW_COMPARE_PY="$ROOT/AppView/Scripts/compare_ui_preview.py"
HIER_PY="$ROOT/AppView/Scripts/mcp_ui_helpers.py"
LOG_DIR="$ROOT/appview-verify-logs"

fail() { echo "update_golden_fixtures: FAIL — $1" >&2; exit 1; }

CAPTURE_DIR="${1:-}"
if [[ -z "$CAPTURE_DIR" ]]; then
  CAPTURE_DIR="$(ls -td "$LOG_DIR"/tap-swift-* 2>/dev/null | head -1 || true)"
fi
[[ -n "$CAPTURE_DIR" && -d "$CAPTURE_DIR" ]] || fail "No capture dir (pass path or run verify_ui_tap_mcp.sh first)"

HIER_JSON="$CAPTURE_DIR/ui_hierarchy.json"
[[ -f "$HIER_JSON" ]] || HIER_JSON="$(ls "$CAPTURE_DIR"/ui_hierarchy*.json 2>/dev/null | head -1)"
[[ -f "$HIER_JSON" ]] || fail "No ui_hierarchy.json in $CAPTURE_DIR"

TAP_STATE="$CAPTURE_DIR/final_state.json"
[[ -f "$TAP_STATE" ]] || fail "No final_state.json in $CAPTURE_DIR"

mkdir -p "$FIXTURES"
python3 "$COMPARE_PY" golden export "$HIER_JSON" > "$FIXTURES/ui-hierarchy-inspector-golden.norm"
python3 "$HIER_PY" export_tap_golden "$TAP_STATE" > "$FIXTURES/tap-state-golden.txt"

PREVIEW_STATE="$CAPTURE_DIR/preview_state.json"
if [[ -f "$PREVIEW_STATE" ]]; then
  python3 "$PREVIEW_COMPARE_PY" golden export "$PREVIEW_STATE" > "$FIXTURES/ui-preview-state-golden.norm"
  echo "  $FIXTURES/ui-preview-state-golden.norm ($(wc -l < "$FIXTURES/ui-preview-state-golden.norm" | tr -d ' ') lines)"
fi

echo "update_golden_fixtures: updated"
echo "  $FIXTURES/ui-hierarchy-inspector-golden.norm ($(wc -l < "$FIXTURES/ui-hierarchy-inspector-golden.norm" | tr -d ' ') lines)"
echo "  $FIXTURES/tap-state-golden.txt"
