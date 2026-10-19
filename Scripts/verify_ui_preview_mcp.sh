#!/usr/bin/env bash
# Compare iOS 3D preview (SceneKit) via GET /ui/preview/state and /ui/preview/screenshot.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$ROOT/appview-verify-logs"
export APPVIEW_VERIFY_LOG_DIR="$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OBJC_DIR="$LOG_DIR/objc-preview"
SWIFT_DIR="$LOG_DIR/swift-preview"
mkdir -p "$OBJC_DIR" "$SWIFT_DIR"
# shellcheck source=appview_write_latest_summary.sh
source "$ROOT/AppView/Scripts/appview_write_latest_summary.sh"
RESULT_FILE=""
SHOTS_DIFF_FILE=""

DD_SWIFT="$LOG_DIR/DerivedData-AppViewRefactor"
DD_OBJC="$LOG_DIR/DerivedData-AppViewBaseline"
SWIFT_APP="$DD_SWIFT/Build/Products/Debug/AppView.app"
OBJC_APP="$DD_OBJC/Build/Products/Debug/AppView.app"
COMPARE_PY="$ROOT/AppView/Scripts/compare_ui_preview.py"
PREVIEW_GOLDEN="$ROOT/AppView/Scripts/fixtures/ui-preview-state-golden.norm"
HIER_PY="$ROOT/AppView/Scripts/mcp_ui_helpers.py"
# shellcheck source=appview_dismiss_dialogs.sh
source "$ROOT/AppView/Scripts/appview_dismiss_dialogs.sh"
# shellcheck source=appview_verify_ios_demo.sh
source "$ROOT/AppView/Scripts/appview_verify_ios_demo.sh"
# shellcheck source=appview_verify_mcp_helpers.sh
source "$ROOT/AppView/Scripts/appview_verify_mcp_helpers.sh"

SKIP_OBJC_BASELINE="${SKIP_OBJC_BASELINE:-1}"
PREVIEW_WAIT_SEC="${PREVIEW_WAIT_SEC:-90}"

section() { echo ""; echo "======== $1 ========"; }

_preview_write_summary() {
  local files=()
  [[ -n "$RESULT_FILE" && -f "$RESULT_FILE" ]] && files+=("$RESULT_FILE")
  [[ -n "$SHOTS_DIFF_FILE" && -f "$SHOTS_DIFF_FILE" ]] && files+=("$SHOTS_DIFF_FILE")
  if [[ ${#files[@]} -gt 0 ]]; then
    appview_write_latest_summary "verify_ui_preview_mcp" "${files[@]}" || true
  else
    appview_write_latest_summary "verify_ui_preview_mcp" || true
  fi
}
trap _preview_write_summary EXIT

fail() { echo "verify_ui_preview_mcp: FAIL — $1" >&2; exit 1; }
pass() { echo "verify_ui_preview_mcp: PASS — $1"; }

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

SIM_NAME="${SIM_NAME:-iPhone 17 Pro}"

if [[ "${RUN_LEGACY_GATES:-1}" == "1" ]]; then
  bash "$ROOT/AppView/Scripts/run_legacy_gates.sh"
fi

section "0. Preconditions"
if [[ ! -d "$SWIFT_APP" ]]; then
  cd "$ROOT/AppView"
  pod install --silent 2>/dev/null || pod install
  xcodebuild -workspace AppView.xcworkspace -scheme AppViewClient -configuration Debug \
    -derivedDataPath "$DD_SWIFT" build -quiet
fi
[[ -d "$SWIFT_APP" ]] || fail "Missing Swift AppView.app"
if [[ "$SKIP_OBJC_BASELINE" != "1" ]]; then
  if [[ ! -d "$OBJC_APP" ]]; then
    cd "$ROOT/Lookin-baseline+mcp"
    pod install --silent 2>/dev/null || pod install
    xcodebuild -workspace AppView.xcworkspace -scheme AppViewClient -configuration Debug \
      -derivedDataPath "$DD_OBJC" build -quiet
  fi
  [[ -d "$OBJC_APP" ]] || fail "Missing ObjC AppView.app"
fi

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
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$SIM_UDID" 2>/dev/null || true

mcp_open_inspector() {
  curl -sf --max-time 30 -X POST "http://127.0.0.1:$1/ui/open-inspector" \
    -H "Content-Type: application/json" -d '{}' >/dev/null || true
  sleep 1
}

open_inspector_if_needed() {
  local port="$1" state_file="$2"
  curl -sf --max-time 10 "http://127.0.0.1:${port}/ui/state" -o "$state_file" 2>/dev/null || true
  local ui_mode
  ui_mode="$(python3 -c "import json; print(json.load(open('$state_file')).get('data',{}).get('uiMode',''))" 2>/dev/null || echo "")"
  [[ "$ui_mode" == "inspector" ]] && return 0
  if [[ "$port" == "47191" ]]; then
    appview_enter_mac_inspector "$port" "$HIER_PY"
    appview_click_appview_launch_tile "AppViewMCPSample"
    return 0
  fi
  mcp_open_inspector "$port"
  appview_click_appview_launch_tile "AppViewMCPSample"
}

wait_for_mcp_sample_hierarchy() {
  local port="$1"
  local max_wait="${2:-90}"
  local i
  for ((i=1; i<=max_wait; i++)); do
    dismiss_appview_system_dialogs
    if appview_mcp_client_has_subtitle "$port" "SampleViewController.view"; then
      return 0
    fi
    if (( i == 1 || i % 8 == 0 )); then
      open_inspector_if_needed "$port" "${APPVIEW_VERIFY_LOG_DIR:-/tmp}/preview-ui-state.json"
      appview_ensure_mcp_sample_inspector "$port" || true
    fi
    sleep 1
  done
  return 1
}

wait_for_preview_ready() {
  local port="$1" state_file="$2" max_wait="${3:-120}"
  local i
  for ((i=1; i<=max_wait; i++)); do
    dismiss_appview_system_dialogs
    local cs
    cs="$(curl -sf --max-time 10 "http://127.0.0.1:${port}/ui/client-state" 2>/dev/null || echo '{}')"
    local fetching nodes preview_ep
    fetching="$(echo "$cs" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('isFetchingDetails',True))" 2>/dev/null || echo True)"
    nodes="$(echo "$cs" | python3 -c "import json,sys; d=json.load(sys.stdin).get('data',{}); print((d.get('preview') or {}).get('displayItemNodesCount',0))" 2>/dev/null || echo 0)"
    if (( i == 1 || i % 8 == 0 )); then
      open_inspector_if_needed "$port" "${state_file%.json}-ui.json"
      if [[ "${nodes:-0}" -eq 0 ]] || [[ -f "$PREVIEW_GOLDEN" && "$port" == "47192" ]]; then
        appview_ensure_mcp_sample_inspector "$port" || true
      fi
    fi
    preview_ep="$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/ui/preview/state" 2>/dev/null || true)"
    preview_ep="${preview_ep:-000}"
    echo "  preview poll ${i}/${max_wait}s: fetching=${fetching} nodes=${nodes} preview_http=${preview_ep}"
    if [[ "$preview_ep" == "200" && "$fetching" == "False" && "${nodes:-0}" -gt 0 ]]; then
      if [[ -f "$PREVIEW_GOLDEN" && "$port" == "47192" && "${nodes:-0}" -gt 15 ]]; then
        appview_ensure_mcp_sample_root_view "$port" || true
        sleep 1
      fi
      return 0
    fi
    sleep 1
  done
  return 1
}

capture_preview_client() {
  local label="$1" app_path="$2" port="$3" out_dir="$4"
  local ios_flavor=swift
  [[ "$port" == "47191" ]] && ios_flavor=baseline

  section "Capture preview $label (port $port)"
  appview_terminate_all_ios_demos "$SIM_UDID"
  appview_uninstall_collection_layout_demos "$SIM_UDID"
  xcrun simctl terminate "$SIM_UDID" "$DEMO_BUNDLE_ID" 2>/dev/null || true
  appview_install_ios_demo "$SIM_UDID" mcp_sample "$ios_flavor" \
    || fail "Install AppViewMCPSample ($ios_flavor) failed"
  sleep 5
  appview_prepare_clean_launch
  launchctl setenv APPVIEW_VERIFY 1
  sleep 2
  local dismiss_pid
  dismiss_pid="$(dismiss_appview_dialogs_watch_start 120)"
  "$app_path/Contents/MacOS/$(basename "$app_path" .app)" >/dev/null 2>&1 &
  sleep 2
  dismiss_appview_system_dialogs
  export APPVIEW_APP="$app_path"
  appview_activate_mac_client "$app_path"
  wait_mcp_port "$port" || {
    dismiss_appview_dialogs_watch_stop "$dismiss_pid"
    fail "MCP port $port not ready"
  }
  sleep 2
  appview_click_appview_launch_tile "AppViewMCPSample"
  appview_ensure_mcp_sample_inspector "$port" || true
  if ! wait_for_mcp_sample_hierarchy "$port" 90; then
    dismiss_appview_dialogs_watch_stop "$dismiss_pid"
    fail "MCPSample hierarchy not ready on port $port ($label)"
  fi
  sleep 5

  local state_file="$out_dir/preview_state-$STAMP.json"
  local shot_file="$out_dir/preview_screenshot-$STAMP.json"
  if ! wait_for_preview_ready "$port" "$state_file" 120; then
    dismiss_appview_dialogs_watch_stop "$dismiss_pid"
    fail "Preview not ready on port $port ($label)"
  fi

  if [[ -f "$PREVIEW_GOLDEN" && "$port" == "47192" ]]; then
    appview_ensure_mcp_sample_root_view "$port" || true
    sleep 1
  fi

  curl -sf --max-time 30 "http://127.0.0.1:${port}/ui/preview/state" -o "$state_file" \
    || fail "GET /ui/preview/state failed ($label)"
  if ! curl -sf --max-time 60 "http://127.0.0.1:${port}/ui/preview/screenshot" -o "$shot_file"; then
    echo "  warning: GET /ui/preview/screenshot failed ($label) — state-only compare"
    echo '{"success":false,"error":"screenshot unavailable"}' >"$shot_file"
  fi
  cp "$state_file" "$out_dir/preview_state.json"
  cp "$shot_file" "$out_dir/preview_screenshot.json"
  python3 -c "import json; d=json.load(open('$state_file')); print('planes:', len(d.get('data',{}).get('planes',[])))"

  local layers_dir="$out_dir/preview-layers-$STAMP"
  section "Export per-layer screenshots ($label)"
  EXPORT_BODY=$(OUT="$layers_dir" python3 -c 'import json, os; print(json.dumps({"directory": os.environ["OUT"]}))')
  if curl -sf --max-time 120 -X POST "http://127.0.0.1:${port}/ui/preview/export-screenshots" \
    -H "Content-Type: application/json" -d "$EXPORT_BODY" -o "$out_dir/export-layers-$STAMP.json"; then
    python3 -c "import json; d=json.load(open('$out_dir/export-layers-$STAMP.json')); print('  exported:', d.get('data',{}).get('exportedCount',0), 'dir:', d.get('data',{}).get('directory',''))"
  else
    echo "  warning: POST /ui/preview/export-screenshots failed ($label)"
  fi

  dismiss_appview_dialogs_watch_stop "$dismiss_pid"
  launchctl unsetenv APPVIEW_VERIFY 2>/dev/null || true
  killall AppView 2>/dev/null || true; killall AppView 2>/dev/null || true
  for ((k=1; k<=15; k++)); do
    if ! curl -sf --max-time 1 "http://127.0.0.1:${port}/status" >/dev/null 2>&1; then
      break
    fi
    killall AppView 2>/dev/null || true; killall AppView 2>/dev/null || true
    sleep 1
  done
  sleep 2
}

if [[ "$SKIP_OBJC_BASELINE" == "1" ]]; then
  echo "  SKIP_OBJC_BASELINE=1 — Swift preview vs golden"
  if [[ ! -f "$PREVIEW_GOLDEN" ]]; then
    echo "  No golden fixture — capturing bootstrap for $PREVIEW_GOLDEN"
    capture_preview_client "Swift" "$SWIFT_APP" 47192 "$SWIFT_DIR"
    mkdir -p "$(dirname "$PREVIEW_GOLDEN")"
    python3 "$COMPARE_PY" golden export "$SWIFT_DIR/preview_state.json" > "$PREVIEW_GOLDEN"
    pass "Bootstrapped preview golden ($(wc -l < "$PREVIEW_GOLDEN" | tr -d ' ') lines) — commit $PREVIEW_GOLDEN"
    exit 0
  fi
  capture_preview_client "Swift" "$SWIFT_APP" 47192 "$SWIFT_DIR"
  RESULT_FILE="$LOG_DIR/ui_preview-golden-diff-$STAMP.txt"
  python3 "$COMPARE_PY" golden compare \
    "$SWIFT_DIR/preview_state.json" "$PREVIEW_GOLDEN" \
    | tee "$RESULT_FILE" || fail "Swift preview state differs from golden"
  grep -q '^RESULT: PASS' "$RESULT_FILE" || fail "Golden preview compare failed"
  pass "Swift iOS preview state matches golden"
  exit 0
fi

capture_preview_client "ObjC" "$OBJC_APP" 47191 "$OBJC_DIR"
capture_preview_client "Swift" "$SWIFT_APP" 47192 "$SWIFT_DIR"

RESULT_FILE="$LOG_DIR/ui_preview-diff-$STAMP.txt"
SHOTS_DIFF_FILE="$LOG_DIR/ui_preview-screenshots-diff-$STAMP.txt"
ST_OK=1
SH_OK=1
python3 "$COMPARE_PY" compare \
  "$OBJC_DIR/preview_state.json" "$SWIFT_DIR/preview_state.json" \
  "$OBJC_DIR/preview_screenshot.json" "$SWIFT_DIR/preview_screenshot.json" \
  --threshold 0.12 \
  | tee "$RESULT_FILE" || ST_OK=0
grep -q '^RESULT: PASS — preview state and screenshots match' "$RESULT_FILE" || ST_OK=0

if [[ "$ST_OK" -eq 1 ]]; then
  pass "iOS 3D preview ObjC vs Swift parity"
  exit 0
fi
fail "Preview parity failed — see $RESULT_FILE"
