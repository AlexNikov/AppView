#!/usr/bin/env bash
# Compare saved ObjC vs Swift inspector captures (tree + optional screenshot dirs).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OBJC_HIER="${1:-}"
SWIFT_HIER="${2:-}"
OBJC_SHOTS="${3:-}"
SWIFT_SHOTS="${4:-}"

if [[ -z "$OBJC_HIER" || -z "$SWIFT_HIER" ]]; then
  echo "Usage: $0 <objc/ui_hierarchy.json> <swift/ui_hierarchy.json> [objc/screenshots] [swift/screenshots]"
  exit 2
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="$ROOT/appview-verify-logs"
mkdir -p "$LOG_DIR"

HIER_OK=0
SHOTS_OK=0

echo "======== Tree structure ========"
python3 "$ROOT/AppView/Scripts/compare_ui_hierarchy.py" "$OBJC_HIER" "$SWIFT_HIER" | tee "$LOG_DIR/ui_hierarchy-diff-$STAMP.txt"
grep -q '^RESULT: PASS' "$LOG_DIR/ui_hierarchy-diff-$STAMP.txt" && HIER_OK=1

if [[ -n "$OBJC_SHOTS" && -n "$SWIFT_SHOTS" && -d "$OBJC_SHOTS" && -d "$SWIFT_SHOTS" ]]; then
  echo ""
  echo "======== View screenshots ========"
  python3 "$ROOT/AppView/Scripts/compare_ui_screenshots.py" \
    "$OBJC_SHOTS" "$SWIFT_SHOTS" \
    --report "$LOG_DIR/ui_screenshots-diff-$STAMP.md" \
    | tee "$LOG_DIR/ui_screenshots-diff-$STAMP.txt"
  grep -q '^RESULT: PASS' "$LOG_DIR/ui_screenshots-diff-$STAMP.txt" && SHOTS_OK=1
else
  echo "Skipping screenshots (pass screenshot directories as args 3 and 4)."
  SHOTS_OK=1
fi

if [[ "$HIER_OK" -eq 1 && "$SHOTS_OK" -eq 1 ]]; then
  echo "RESULT: PASS — tree and screenshots"
  exit 0
fi
echo "RESULT: FAIL"
exit 1
