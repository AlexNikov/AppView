#!/usr/bin/env bash
# Verify AppViewOsAppMCP tap on macOS AppView client (Swift + optional ObjC baseline).
#
# Order (required):
#   1. Simulator + AppViewMCPSample (iOS)
#   2. AppView.app — macOS client (AppViewOsAppMCP :47192 Swift, :47191 ObjC)
#   3. AppViewOsAppMCP: GET /ui/tap-targets → POST /ui/tap → GET /ui/state
#
# Usage:
#   bash AppView/Scripts/verify_ui_tap_mcp.sh
#   SKIP_OBJC_BASELINE=0 bash AppView/Scripts/verify_ui_tap_mcp.sh  # ObjC vs Swift parity (baseline)
# Default: SKIP_OBJC_BASELINE=1 — Swift-only + golden invariants
#   BUILD_MCP_SAMPLE=1 bash AppView/Scripts/verify_ui_tap_mcp.sh  # force rebuild demo
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$ROOT/appview-verify-logs"
export APPVIEW_VERIFY_LOG_DIR="$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
TAP_COMPARE_FILE=""

# shellcheck source=appview_write_latest_summary.sh
source "$ROOT/AppView/Scripts/appview_write_latest_summary.sh"
# shellcheck source=appview_dismiss_dialogs.sh
source "$ROOT/AppView/Scripts/appview_dismiss_dialogs.sh"
# shellcheck source=appview_verify_ios_demo.sh
source "$ROOT/AppView/Scripts/appview_verify_ios_demo.sh"
# shellcheck source=appview_osapp_mcp_tap_lib.sh
source "$ROOT/AppView/Scripts/appview_osapp_mcp_tap_lib.sh"

DD_SWIFT="$LOG_DIR/DerivedData-AppViewRefactor"
DD_OBJC="$LOG_DIR/DerivedData-AppViewBaseline"
SWIFT_APP="$DD_SWIFT/Build/Products/Debug/AppView.app"
OBJC_APP="$DD_OBJC/Build/Products/Debug/AppView.app"
HIER_PY="$ROOT/AppView/Scripts/mcp_ui_helpers.py"

SKIP_OBJC_BASELINE="${SKIP_OBJC_BASELINE:-1}"
TAP_GOLDEN="$ROOT/AppView/Scripts/fixtures/tap-state-golden.txt"
BUILD_MCP_SAMPLE="${BUILD_MCP_SAMPLE:-0}"
MIN_HIERARCHY_ROWS="${MIN_HIERARCHY_ROWS:-5}"
TAP_ROW_INDEX="${TAP_ROW_INDEX:-3}"

section() { echo "" >&2; echo "======== $1 ========" >&2; }
_tap_write_summary() {
  [[ -n "$TAP_COMPARE_FILE" && -f "$TAP_COMPARE_FILE" ]] \
    && appview_write_latest_summary "verify_ui_tap_mcp" "$TAP_COMPARE_FILE" || true
}
trap _tap_write_summary EXIT

fail() { echo "verify_ui_tap_mcp: FAIL — $1" >&2; exit 1; }
pass() { echo "verify_ui_tap_mcp: PASS — $1"; }

wait_mcp_port() {
  local port="$1"
  local i
  for ((i=1; i<=60; i++)); do
    appview_pump_system_dialogs
    if curl -sf --max-time 2 "http://127.0.0.1:${port}/status" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

mcp_get() {
  local port="$1" path="$2" out="$3"
  curl -sf --max-time 30 "http://127.0.0.1:${port}${path}" -o "$out" \
    || fail "GET ${path} failed on port ${port}"
}

mcp_post_tap() {
  local port="$1" body="$2" out="$3"
  curl -sf --max-time 30 -X POST "http://127.0.0.1:${port}/ui/tap" \
    -H "Content-Type: application/json" \
    -d "$body" -o "$out" \
    || fail "POST /ui/tap failed on port ${port}"
}

if [[ "${RUN_LEGACY_GATES:-1}" == "1" ]]; then
  bash "$ROOT/AppView/Scripts/run_legacy_gates.sh"
fi

section "0. Preconditions"
[[ -d "$SWIFT_APP" ]] || fail "Missing Swift AppView.app"
[[ -f "$HIER_PY" ]] || fail "Missing $HIER_PY"
if [[ "$SKIP_OBJC_BASELINE" != "1" ]]; then
  [[ -d "$OBJC_APP" ]] || fail "Missing ObjC AppView.app"
fi

SIM_NAME="${SIM_NAME:-iPhone 17 Pro}"
SIM_UDID="$(xcrun simctl list devices available -j | python3 -c "
import json,sys,os
name=os.environ.get('SIM_NAME','iPhone 17 Pro')
for d in json.load(sys.stdin).get('devices',{}).values():
  for dev in d:
    if dev.get('isAvailable') and name in dev.get('name','') and 'iPhone' in dev.get('name',''):
      print(dev['udid']); sys.exit(0)
sys.exit(1)
" 2>/dev/null || true)"
[[ -n "$SIM_UDID" ]] || fail "Simulator not found: $SIM_NAME"

section "1. iOS — Simulator + AppViewMCPSample (Swift, before AppView client)"
SWIFT_MCP_APP="$(appview_ios_demo_app_path mcp_sample swift)"
appview_build_ios_demo mcp_sample swift || fail "Build Swift AppViewMCPSample failed"
SWIFT_MCP_APP="$(appview_ios_demo_app_path mcp_sample swift)"
[[ -d "$SWIFT_MCP_APP" ]] || fail "Missing Swift AppViewMCPSample.app"
appview_osapp_prepare_ios_demo "$SIM_UDID" "$SWIFT_MCP_APP" \
  || fail "Phase 1 failed: launch Swift AppViewMCPSample on simulator"

run_one_client() {
  local label="$1" app="$2" port="$3"
  local out_dir="$LOG_DIR/tap-${label}-${STAMP}"
  section "2–3. macOS AppView client + AppViewOsAppMCP tap — $label (:$port)"
  appview_osapp_run_client_tap_verify "$label" "$app" "$port" "$out_dir" "$HIER_PY" \
    || fail "$label: AppViewOsAppMCP tap verify failed"
  python3 "$HIER_PY" assert_osapp_mcp_tap "$out_dir" "$MIN_HIERARCHY_ROWS" >&2 \
    || fail "$label: tap assertions failed"
  printf '%s' "$out_dir"
}

SWIFT_OUT="$(run_one_client "swift" "$SWIFT_APP" 47192)"
SWIFT_OUT="${SWIFT_OUT##*$'\n'}"

if [[ "$SKIP_OBJC_BASELINE" == "1" ]]; then
  [[ -f "$TAP_GOLDEN" ]] || fail "Missing golden fixture: $TAP_GOLDEN"
  TAP_COMPARE_FILE="$LOG_DIR/tap-golden-diff-$STAMP.txt"
  python3 "$HIER_PY" compare_tap_golden "$SWIFT_OUT/final_state.json" "$TAP_GOLDEN" \
    | tee "$TAP_COMPARE_FILE" || fail "Tap state differs from golden — see $TAP_COMPARE_FILE"
  grep -q '^RESULT: PASS' "$TAP_COMPARE_FILE" || fail "Golden tap compare failed — see $TAP_COMPARE_FILE"
  pass "Swift AppViewOsAppMCP /ui/tap OK (golden invariants)"
  exit 0
fi

section "1b. iOS — baseline AppViewMCPSample (before ObjC client)"
appview_install_ios_demo_for_mac_client "$SIM_UDID" objc mcp_sample || fail "Install baseline AppViewMCPSample failed"
sleep "$DEMO_SETTLE_SEC"
appview_wait_ios_mcp || fail "iOS MCP lost before ObjC client run"

OBJC_OUT="$(run_one_client "objc" "$OBJC_APP" 47191)"
OBJC_OUT="${OBJC_OUT##*$'\n'}"

section "4. Compare ObjC vs Swift (AppViewOsAppMCP /ui/state after tap)"
TAP_COMPARE_FILE="$LOG_DIR/tap-compare-${STAMP}.txt"
python3 "$HIER_PY" compare_tap_states \
  "$OBJC_OUT/final_state.json" \
  "$SWIFT_OUT/final_state.json" \
  | tee "$TAP_COMPARE_FILE"

grep -q '^RESULT: PASS' "$TAP_COMPARE_FILE" \
  && pass "ObjC and Swift AppViewOsAppMCP taps match" \
  || fail "tap mismatch — see $TAP_COMPARE_FILE"
