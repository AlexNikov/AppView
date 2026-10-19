#!/usr/bin/env bash
# Pretty-print iOS 3D preview JSON from AppView MCP (structure = ObjC-comparable tree).
# Usage:
#   bash AppView/Scripts/print_preview_state_json.sh [port]
#   bash AppView/Scripts/print_preview_state_json.sh 47192 structure
#   bash AppView/Scripts/print_preview_state_json.sh 47191 full
set -euo pipefail

PORT="${1:-47192}"
MODE="${2:-structure}"
BASE="http://127.0.0.1:${PORT}"

case "$MODE" in
  structure)
    PATH_SUFFIX="/ui/preview/structure"
    ;;
  full | state)
    PATH_SUFFIX="/ui/preview/state"
    ;;
  *)
    echo "Mode: structure | full" >&2
    exit 2
    ;;
esac

RAW="$(curl -sf --max-time 15 "${BASE}${PATH_SUFFIX}")" || {
  echo "curl failed — is AppView running on port ${PORT} with inspector open?" >&2
  exit 1
}

python3 -c "
import json, sys
doc = json.loads(sys.argv[1])
print(json.dumps(doc, indent=2, ensure_ascii=False))
" "$RAW"
