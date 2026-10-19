#!/usr/bin/env bash
# Print agent-facing verify summary (for narrow shell output).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SUMMARY="$ROOT/appview-verify-logs/LATEST_SUMMARY.txt"
if [[ -f "$SUMMARY" ]]; then
  cat "$SUMMARY"
  exit 0
fi
echo "LATEST_SUMMARY.txt not found. Run a verify_ui_*.sh or verify_custom_info_client.sh first." >&2
exit 1
