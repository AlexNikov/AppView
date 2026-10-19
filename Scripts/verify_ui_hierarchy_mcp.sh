#!/usr/bin/env bash
# Compare mac AppView /ui/hierarchy (NSView tree) and per-view screenshots (ObjC vs Swift).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$ROOT/appview-verify-logs"
export APPVIEW_VERIFY_LOG_DIR="$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OBJC_DIR="$LOG_DIR/objc"
SWIFT_DIR="$LOG_DIR/swift"
mkdir -p "$OBJC_DIR" "$SWIFT_DIR"
# shellcheck source=appview_write_latest_summary.sh
source "$ROOT/AppView/Scripts/appview_write_latest_summary.sh"
RESULT_FILE=""
SHOTS_DIFF_FILE=""

DD_SWIFT="$LOG_DIR/DerivedData-AppViewRefactor"
DD_OBJC="$LOG_DIR/DerivedData-AppViewBaseline"
SWIFT_APP="$DD_SWIFT/Build/Products/Debug/AppView.app"
OBJC_APP="$DD_OBJC/Build/Products/Debug/AppView.app"
COMPARE_PY="$ROOT/AppView/Scripts/compare_ui_hierarchy.py"
HIER_GOLDEN="$ROOT/AppView/Scripts/fixtures/ui-hierarchy-inspector-golden.norm"
CAPTURE_SHOTS_PY="$ROOT/AppView/Scripts/capture_ui_screenshots.py"
COMPARE_SHOTS_PY="$ROOT/AppView/Scripts/compare_ui_screenshots.py"
HIER_PY="$ROOT/AppView/Scripts/mcp_ui_helpers.py"
# shellcheck source=appview_dismiss_dialogs.sh
source "$ROOT/AppView/Scripts/appview_dismiss_dialogs.sh"
# shellcheck source=appview_verify_ios_demo.sh
source "$ROOT/AppView/Scripts/appview_verify_ios_demo.sh"
# shellcheck source=appview_verify_mcp_helpers.sh
source "$ROOT/AppView/Scripts/appview_verify_mcp_helpers.sh"

HIER_MIN_ROWS="${HIER_MIN_ROWS:-5}"
HIER_MIN_FLAT="${HIER_MIN_FLAT:-5}"
HIER_MIN_CARDS="${HIER_MIN_CARDS:-1}"
HIER_MIN_INSPECTOR_PATHS="${HIER_MIN_INSPECTOR_PATHS:-80}"

section() { echo ""; echo "======== $1 ========"; }

_hierarchy_inspector_path_count() {
  local json_file="$1"
  python3 -c "
import json, sys
def walk(node, prefix=''):
    if not isinstance(node, dict):
        return 0
    cls = node.get('className') or node.get('class') or ''
    path = f'{prefix}/{cls}' if prefix else cls
    n = 1 if any(k in path for k in ('AVSplitView', 'AVHierarchyView', 'AVDashboard')) else 0
    for ch in node.get('children') or node.get('subviews') or []:
        n += walk(ch, path)
    return n
try:
    d = json.load(open(sys.argv[1]))
    data = d.get('data', d)
    total = 0
    for w in data.get('windows', []):
        root = w.get('contentView') or w.get('root') or w
        total += walk(root, '')
    print(total)
except Exception:
    print(0)
" "$json_file" 2>/dev/null || echo 0
}

_hierarchy_write_summary() {
  local files=()
  [[ -n "$RESULT_FILE" && -f "$RESULT_FILE" ]] && files+=("$RESULT_FILE")
  [[ -n "$SHOTS_DIFF_FILE" && -f "$SHOTS_DIFF_FILE" ]] && files+=("$SHOTS_DIFF_FILE")
  [[ -f "$LOG_DIR/comparison.md" ]] && files+=("$LOG_DIR/comparison.md")
  if ((${#files[@]} > 0)); then
    appview_write_latest_summary "verify_ui_hierarchy_mcp" "${files[@]}" || true
  fi
}
trap _hierarchy_write_summary EXIT

fail() { echo "verify_ui_hierarchy_mcp: FAIL — $1" >&2; exit 1; }
pass() { echo "verify_ui_hierarchy_mcp: PASS — $1"; }

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

build_appview_clients() {
  section "0a. Build ObjC baseline (Lookin-baseline+mcp)"
  cd "$ROOT/Lookin-baseline+mcp"
  pod install --silent 2>/dev/null || pod install
  xcodebuild -workspace AppView.xcworkspace -scheme AppViewClient -configuration Debug \
    -derivedDataPath "$DD_OBJC" build -quiet

  section "0b. Build Swift AppView"
  cd "$ROOT/AppView"
  pod install --silent 2>/dev/null || pod install
  xcodebuild -workspace AppView.xcworkspace -scheme AppViewClient -configuration Debug \
    -derivedDataPath "$DD_SWIFT" build -quiet

}

SKIP_OBJC_BASELINE="${SKIP_OBJC_BASELINE:-1}"

if [[ "${RUN_LEGACY_GATES:-1}" == "1" ]]; then
  bash "$ROOT/AppView/Scripts/run_legacy_gates.sh"
fi

section "0. Preconditions"
# MCP needs com.apple.security.network.server (embedded with normal codesign, not CODE_SIGNING_ALLOWED=NO).
if [[ ! -d "$SWIFT_APP" ]]; then
  section "0b. Build Swift AppView"
  cd "$ROOT/AppView"
  pod install --silent 2>/dev/null || pod install
  xcodebuild -workspace AppView.xcworkspace -scheme AppViewClient -configuration Debug \
    -derivedDataPath "$DD_SWIFT" build -quiet
fi
[[ -d "$SWIFT_APP" ]] || fail "Missing Swift AppView.app after build"
if [[ "$SKIP_OBJC_BASELINE" != "1" ]]; then
  if [[ ! -d "$OBJC_APP" ]]; then
    build_appview_clients
  fi
  [[ -d "$OBJC_APP" ]] || fail "Missing ObjC AppView.app after build"
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

dashboard_metrics() {
  local json_file="$1"
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
def walk(node):
    cards = 0
    sections = 0
    max_card_h = 0
    max_section_h = 0
    cn = node.get('className', '')
    if cn.endswith('AVDashboardCardView'):
        cards += 1
        max_card_h = max(max_card_h, int(node.get('frame', {}).get('height', 0)))
    if cn.endswith('AVDashboardSectionView'):
        sections += 1
        max_section_h = max(max_section_h, int(node.get('frame', {}).get('height', 0)))
    for c in node.get('children', []):
        c1, s1, ch, sh = walk(c)
        cards += c1
        sections += s1
        max_card_h = max(max_card_h, ch)
        max_section_h = max(max_section_h, sh)
    if 'contentView' in node:
        c1, s1, ch, sh = walk(node['contentView'])
        cards += c1
        sections += s1
        max_card_h = max(max_card_h, ch)
        max_section_h = max(max_section_h, sh)
    return cards, sections, max_card_h, max_section_h
for w in d.get('data', {}).get('windows', []):
    cn = w.get('contentView', {}).get('className', '')
    if cn == 'AVSplitView' or cn.endswith('.AVSplitView'):
        c, s, h, sh = walk(w)
        print(f'{c},{s},{h},{sh}')
        sys.exit(0)
print('0,0,0,0')
" "$json_file"
}

mcp_open_inspector() {
  local port="$1"
  echo "  POST /ui/open-inspector"
  curl -sf --max-time 30 -X POST "http://127.0.0.1:${port}/ui/open-inspector" \
    -H "Content-Type: application/json" -d '{}' >/dev/null || true
  sleep 1
}

open_inspector_if_needed() {
  local port="$1"
  local state_file="$2"
  curl -sf --max-time 10 "http://127.0.0.1:${port}/ui/state" -o "$state_file" 2>/dev/null || true
  local ui_mode
  ui_mode="$(python3 -c "import json; print(json.load(open('$state_file')).get('data',{}).get('uiMode',''))" 2>/dev/null || echo "")"
  if [[ "$ui_mode" == "inspector" ]]; then
    echo "  already in inspector"
    return 0
  fi
  # ObjC baseline AppViewOsAppMCP has no POST /ui/open-inspector; use hierarchy/tap like tap-verify.
  if [[ "$port" == "47191" ]]; then
    appview_enter_mac_inspector "$port" "$HIER_PY"
    appview_click_appview_launch_tile "AppViewMCPSample"
    return 0
  fi
  mcp_open_inspector "$port"
  appview_click_appview_launch_tile "AppViewMCPSample"
}

try_capture_inspector_hierarchy() {
  local port="$1" out_file="$2"
  local state_file="${out_file%.json}-state.json"
  local probe_file="${out_file%.json}-probe.json"
  curl -sf --max-time 10 "http://127.0.0.1:${port}/ui/state" -o "$state_file" 2>/dev/null || true
  if [[ -f "$HIER_GOLDEN" && "$port" == "47192" ]]; then
    appview_ensure_mcp_sample_root_view "$port" || true
    curl -sf --max-time 10 "http://127.0.0.1:${port}/ui/state" -o "$state_file" 2>/dev/null || true
  fi
  if ! curl -sf --max-time 30 "http://127.0.0.1:${port}/ui/hierarchy" -o "$probe_file" 2>/dev/null; then
    return 1
  fi
  if [[ -f "$HIER_GOLDEN" && "$port" == "47192" ]]; then
    if python3 "$COMPARE_PY" golden compare "$probe_file" "$HIER_GOLDEN" >/dev/null 2>&1; then
      mv -f "$probe_file" "$out_file"
      echo "  hierarchy matches golden fixture"
      return 0
    fi
    local inspector_paths
    inspector_paths="$(_hierarchy_inspector_path_count "$probe_file")"
    if [[ "${inspector_paths:-0}" -ge "$HIER_MIN_INSPECTOR_PATHS" ]]; then
      mv -f "$probe_file" "$out_file"
      echo "  hierarchy ready (${inspector_paths} inspector paths, UIView selection)"
      return 0
    fi
    rm -f "$probe_file"
    return 1
  fi
  local inspector_paths
  inspector_paths="$(_hierarchy_inspector_path_count "$probe_file")"
  if [[ "${inspector_paths:-0}" -ge "$HIER_MIN_INSPECTOR_PATHS" ]]; then
    mv -f "$probe_file" "$out_file"
    return 0
  fi
  rm -f "$probe_file"
  return 1
}

wait_for_inspector_dashboard() {
  local port="$1"
  local out_file="$2"
  local max_wait="${3:-60}"
  max_wait="${HIER_ASYNC_MAX_WAIT:-120}"
  local state_file="${out_file%.json}-state.json"
  local i
  for ((i=1; i<=max_wait; i++)); do
    dismiss_appview_system_dialogs
    if (( i == 1 || i % 8 == 0 )); then
      open_inspector_if_needed "$port" "$state_file"
    fi
    if (( i % 16 == 0 )) && [[ "$mode" == "inspector" && "${cards:-0}" -lt "$HIER_MIN_CARDS" ]]; then
      curl -sf --max-time 15 -X POST "http://127.0.0.1:${port}/action/reload" \
        -H "Content-Type: application/json" -d '{}' >/dev/null || true
    fi
    curl -sf --max-time 10 "http://127.0.0.1:${port}/ui/state" -o "$state_file" 2>/dev/null || true
    local mode cards rows
    mode="$(python3 -c "import json; print(json.load(open('$state_file')).get('data',{}).get('uiMode',''))" 2>/dev/null || echo "")"
    cards="$(python3 -c "import json; print(json.load(open('$state_file')).get('data',{}).get('dashboardCards',0))" 2>/dev/null || echo 0)"
    rows="$(python3 -c "import json; print(json.load(open('$state_file')).get('data',{}).get('hierarchyRows',0))" 2>/dev/null || echo 0)"
    shell="$(python3 -c "import json; print(json.load(open('$state_file')).get('data',{}).get('hasInspectorShell',False))" 2>/dev/null || echo False)"
    flat_items="$(appview_mcp_client_flat_count "$port")"
    if [[ -f "$HIER_GOLDEN" && "$port" == "47192" ]] && ! appview_mcp_client_has_subtitle "$port" "SampleViewController.view" && (( i == 1 || i % 8 == 0 )); then
      appview_ensure_mcp_sample_inspector "$port" || true
      flat_items="$(appview_mcp_client_flat_count "$port")"
    fi
    echo "  poll ${i}/${max_wait}s: uiMode=${mode} cards=${cards} rows=${rows} flat=${flat_items} shell=${shell}"
    if [[ "$mode" == "inspector" ]]; then
      local flat_ok=0
      if [[ -f "$HIER_GOLDEN" && "$port" == "47192" ]]; then
        appview_mcp_client_has_subtitle "$port" "SampleViewController.view" && flat_ok=1
      else
        [[ "${flat_items:-0}" -ge "$HIER_MIN_FLAT" ]] && flat_ok=1
      fi
      [[ "$port" == "47191" && "${rows:-0}" -ge "$HIER_MIN_ROWS" ]] && flat_ok=1
      if [[ "$flat_ok" == "1" ]]; then
        if [[ -f "$HIER_GOLDEN" && "$port" == "47192" ]]; then
          appview_ensure_mcp_sample_root_view "$port" || true
        fi
        if try_capture_inspector_hierarchy "$port" "$out_file"; then
          return 0
        fi
      fi
    fi
    sleep 1
  done
  return 1
}

capture_client() {
  local label="$1"
  local app_path="$2"
  local port="$3"
  local out_dir="$4"
  local wait_sec="${5:-20}"
  local ios_flavor=swift
  [[ "$port" == "47191" ]] && ios_flavor=baseline

  section "Capture $label (port $port, iOS demo $ios_flavor AppViewMCPSample)"
  appview_terminate_all_ios_demos "$SIM_UDID"
  appview_uninstall_collection_layout_demos "$SIM_UDID"
  appview_install_ios_demo "$SIM_UDID" mcp_sample "$ios_flavor" \
    || fail "Install AppViewMCPSample ($ios_flavor) failed"
  sleep 5

  appview_prepare_clean_launch
  launchctl setenv APPVIEW_VERIFY 1
  sleep 3
  export APPVIEW_APP="$app_path"
  local dismiss_pid
  dismiss_pid="$(dismiss_appview_dialogs_watch_start 120)"
  local exe="$app_path/Contents/MacOS/$(basename "$app_path" .app)"
  [[ -x "$exe" ]] || fail "Missing AppView executable at $exe"
  "$exe" >/dev/null 2>&1 &
  sleep 2
  dismiss_appview_system_dialogs
  appview_activate_mac_client "$app_path"
  wait_mcp_port "$port" || {
    dismiss_appview_dialogs_watch_stop "$dismiss_pid"
    fail "MCP port $port not ready ($label)"
  }
  sleep 2
  appview_click_appview_launch_tile "AppViewMCPSample"
  appview_ensure_mcp_sample_inspector "$port" || true
  echo "Waiting ${wait_sec}s for iOS connection..."
  sleep "$wait_sec"
  appview_ensure_mcp_sample_inspector "$port" || true

  local status_file="$out_dir/status-$STAMP.json"
  local hierarchy_file="$out_dir/ui_hierarchy-$STAMP.json"
  curl -sf --max-time 10 "http://127.0.0.1:${port}/status" -o "$status_file" \
    || echo '{"success":false,"error":"status curl failed"}' > "$status_file"

  open_inspector_if_needed "$port" "${hierarchy_file%.json}-state.json"

  if ! wait_for_inspector_dashboard "$port" "$hierarchy_file" 90; then
    dismiss_appview_dialogs_watch_stop "$dismiss_pid"
    fail "Inspector hierarchy capture timed out on port $port ($label) — check selection SampleViewController.view / UIView and /ui/hierarchy"
  fi

  local alert_views
  alert_views="$(appview_count_alert_views "$hierarchy_file")"
  if [[ "${alert_views:-0}" -gt 0 ]]; then
    echo "  warning: ${alert_views} NSAlertContentView in hierarchy — retrying dismiss"
    dismiss_appview_system_dialogs
    curl -sf --max-time 30 "http://127.0.0.1:${port}/ui/hierarchy" -o "$hierarchy_file" || true
  fi

  cp "$hierarchy_file" "$out_dir/ui_hierarchy.json"
  echo "Saved: $hierarchy_file"
  python3 -c "import json; d=json.load(open('$hierarchy_file')); print('windows:', len(d.get('data',{}).get('windows',[])))"

  local shots_dir="$out_dir/screenshots-$STAMP"
  section "Capture view screenshots ($label)"
  python3 "$CAPTURE_SHOTS_PY" --port "$port" --hierarchy "$hierarchy_file" --out "$shots_dir" \
    || echo "  warning: screenshot capture had errors"

  dismiss_appview_dialogs_watch_stop "$dismiss_pid"
  launchctl unsetenv APPVIEW_VERIFY 2>/dev/null || true
  killall AppView 2>/dev/null || true; killall AppView 2>/dev/null || true
  killall "Problem Reporter" 2>/dev/null || true
  # Same bundle id — wait until MCP port is free before launching the other build.
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
  echo "  SKIP_OBJC_BASELINE=1 — Swift-only capture + golden fixture check"
  [[ -f "$HIER_GOLDEN" ]] || fail "Missing golden fixture: $HIER_GOLDEN"
  capture_client "Swift refactor" "$SWIFT_APP" 47192 "$SWIFT_DIR"
  RESULT_FILE="$LOG_DIR/ui_hierarchy-golden-diff-$STAMP.txt"
  python3 "$COMPARE_PY" golden compare \
    "$SWIFT_DIR/ui_hierarchy-$STAMP.json" "$HIER_GOLDEN" \
    | tee "$RESULT_FILE" || fail "Swift hierarchy differs from golden — see $RESULT_FILE"
  grep -q '^RESULT: PASS' "$RESULT_FILE" || fail "Golden hierarchy compare failed — see $RESULT_FILE"
  pass "Swift inspector hierarchy matches golden fixture"
  echo "PASS" > "$LOG_DIR/ui_hierarchy-result-$STAMP.txt"
  exit 0
fi

capture_client "ObjC baseline" "$OBJC_APP" 47191 "$OBJC_DIR"
capture_client "Swift refactor" "$SWIFT_APP" 47192 "$SWIFT_DIR"

section "3. Compare normalized trees"
RESULT_FILE="$LOG_DIR/ui_hierarchy-diff-$STAMP.txt"
SHOTS_DIFF_FILE="$LOG_DIR/ui_screenshots-diff-$STAMP.txt"
HIER_OK=1
python3 "$COMPARE_PY" \
  "$OBJC_DIR/ui_hierarchy-$STAMP.json" \
  "$SWIFT_DIR/ui_hierarchy-$STAMP.json" \
  | tee "$RESULT_FILE" || HIER_OK=0
grep -q '^RESULT: PASS' "$RESULT_FILE" || HIER_OK=0

section "4. Compare view screenshots"
SHOTS_REPORT="$LOG_DIR/ui_screenshots-diff-$STAMP.md"
SHOTS_OK=1
python3 "$COMPARE_SHOTS_PY" \
  "$OBJC_DIR/screenshots-$STAMP" \
  "$SWIFT_DIR/screenshots-$STAMP" \
  --threshold 0.08 \
  --report "$SHOTS_REPORT" \
  | tee "$SHOTS_DIFF_FILE" || SHOTS_OK=0
grep -q '^RESULT: PASS' "$SHOTS_DIFF_FILE" || SHOTS_OK=0

if [[ "$HIER_OK" -eq 1 && "$SHOTS_OK" -eq 1 ]]; then
  pass "UI hierarchy + screenshots parity (inspector)"
  echo "PASS" > "$LOG_DIR/ui_hierarchy-result-$STAMP.txt"
  {
    echo "# UI hierarchy ObjC vs Swift ($STAMP)"
    echo ""
    echo "## Tree"
    cat "$RESULT_FILE"
    echo ""
    echo "## Screenshots"
    cat "$LOG_DIR/ui_screenshots-diff-$STAMP.txt"
  } > "$LOG_DIR/comparison.md"
  exit 0
fi

echo "FAIL" > "$LOG_DIR/ui_hierarchy-result-$STAMP.txt"
[[ "$HIER_OK" -eq 0 ]] && fail "UI hierarchy mismatch — see $RESULT_FILE"
fail "UI screenshot mismatch — see $SHOTS_REPORT"
