#!/usr/bin/env bash
# Write appview-verify-logs/LATEST_SUMMARY.txt for agents (RESULT + narrow diff).
# shellcheck disable=SC2034
appview_write_latest_summary() {
  local label="$1"
  shift
  local summary="${APPVIEW_VERIFY_LOG_DIR:-}/LATEST_SUMMARY.txt"
  if [[ -z "${APPVIEW_VERIFY_LOG_DIR:-}" ]]; then
    echo "appview_write_latest_summary: APPVIEW_VERIFY_LOG_DIR not set" >&2
    return 1
  fi
  mkdir -p "$APPVIEW_VERIFY_LOG_DIR"
  {
    echo "verify: $label"
    echo "timestamp: $(date -Iseconds)"
    echo ""
    while [[ $# -gt 0 ]]; do
      local f="$1"
      shift
      [[ -f "$f" ]] || continue
      echo "--- $(basename "$f") ---"
      grep '^RESULT:' "$f" 2>/dev/null || true
      head -50 "$f" 2>/dev/null || true
      echo ""
    done
  } >"$summary"
  echo "Wrote $summary"
}
