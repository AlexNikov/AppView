#!/usr/bin/env bash
# AppViewOsAppMCP (macOS AppView client HTTP) — shared tap verify helpers.
#
# Correct order (enforced by verify_ui_tap_mcp.sh):
#   1. Simulator + AppViewMCPSample (iOS, Peertalk target)
#   2. AppView.app (macOS client, AppViewOsAppMCP on 47191/47192)
#   3. GET /ui/tap-targets → POST /ui/tap → GET /ui/state
#
# Source from verify_ui_tap_mcp.sh — do not run directly.

: "${MIN_HIERARCHY_ROWS:=5}"
: "${TAP_ROW_INDEX:=3}"
: "${DEMO_SETTLE_SEC:=6}"
: "${CLIENT_CONNECT_SEC:=45}"

# Phase 1 — iOS demo only (no AppView.app yet).
appview_osapp_prepare_ios_demo() {
  local sim_udid="$1"
  local mcp_app="$2"

  echo "  [1/3] Simulator: install & launch AppViewMCPSample" >&2
  xcrun simctl boot "$sim_udid" 2>/dev/null || true
  open -a Simulator --args -CurrentDeviceUDID "$sim_udid" 2>/dev/null || true

  # Free :47190 only before installing — never kill the port after the demo is running.
  appview_free_ios_mcp_port_47190
  killall AppView 2>/dev/null || true; killall AppView 2>/dev/null || true

  xcrun simctl install "$sim_udid" "$mcp_app"
  xcrun simctl terminate "$sim_udid" "$LEGACY_DEMO_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$DEMO_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$MCP_SAMPLE_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "${COLLECTION_LAYOUT_SWIFT_BUNDLE_ID:-AppView.AppViewCollectionLayoutDemo}" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "${COLLECTION_LAYOUT_OBJC_BUNDLE_ID:-AppView.AppViewCollectionLayoutDemoObjC}" 2>/dev/null || true
  sleep 1
  xcrun simctl launch "$sim_udid" "$MCP_SAMPLE_BUNDLE_ID" >&2
  echo "  [1/3] waiting ${DEMO_SETTLE_SEC}s for demo to settle…" >&2
  sleep "$DEMO_SETTLE_SEC"

  if ! appview_wait_ios_mcp; then
    echo "FAIL: iOS app not serving AppViewServer MCP on :47190" >&2
    return 1
  fi
  echo "  [1/3] iOS MCP :47190 OK" >&2
  osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
  return 0
}

appview_osapp_fetch_tap_targets() {
  local port="$1" out="$2"
  curl -sf --max-time 15 "http://127.0.0.1:${port}/ui/tap-targets" -o "$out" 2>/dev/null
}

appview_osapp_wait_mac_connected() {
  local port="$1" status_json="$2"
  local connected=0 i

  echo "  [2/3] waiting for AppView mac /status connected=1 (max ${CLIENT_CONNECT_SEC}s)…" >&2
  for ((i=1; i<=CLIENT_CONNECT_SEC; i++)); do
    dismiss_appview_system_dialogs
    curl -sf --max-time 10 "http://127.0.0.1:${port}/status" -o "$status_json" 2>/dev/null || true
    connected="$(python3 -c "import json; d=json.load(open('$status_json')).get('data',{}); print(int(d.get('connected',0)))" 2>/dev/null || echo 0)"
    if [[ "$connected" == "1" ]]; then
      echo "  [2/3] connected=1 (poll $i)" >&2
      return 0
    fi
    if (( i % 15 == 0 )); then
      echo "  [2/3] still connected=0 (poll $i)…" >&2
    fi
    sleep 1
  done
  echo "FAIL: AppView client not connected to simulator app (connected=0)" >&2
  return 1
}

# Phase 2 — launch macOS AppView client (demo must already be running).
appview_osapp_launch_mac_client() {
  local label="$1"
  local app_path="$2"
  local port="$3"
  local out_dir="$4"

  mkdir -p "$out_dir"
  echo "  [2/3] Launch AppView mac client ($label, AppViewOsAppMCP :$port)" >&2

  appview_prepare_clean_launch
  launchctl setenv APPVIEW_VERIFY 1
  sleep 1

  local dismiss_pid
  dismiss_pid="$(dismiss_appview_dialogs_watch_start 120)"
  APPVIEW_OSAPP_DISMISS_PID="$dismiss_pid"
  APPVIEW_OSAPP_LAST_PORT="$port"

  local exe="$app_path/Contents/MacOS/$(basename "$app_path" .app)"
  [[ -x "$exe" ]] || { echo "FAIL $label: missing $exe" >&2; return 1; }
  "$exe" >/dev/null 2>&1 &
  dismiss_appview_system_dialogs

  if ! wait_mcp_port "$port"; then
    dismiss_appview_dialogs_watch_stop "$dismiss_pid"
    echo "FAIL $label: AppViewOsAppMCP port $port not listening" >&2
    return 1
  fi
  sleep 2

  local status_json="$out_dir/mac_status.json"
  if ! appview_osapp_wait_mac_connected "$port" "$status_json"; then
    echo "  WARN: /status connected=0 — will try inspector + /ui/tap anyway (single-app auto-enter)" >&2
  fi
  return 0
}

appview_osapp_stop_mac_client() {
  local dismiss_pid="${APPVIEW_OSAPP_DISMISS_PID:-}"
  local port="${APPVIEW_OSAPP_LAST_PORT:-}"
  if [[ -n "$port" ]]; then
    curl -sf --max-time 5 -X POST "http://127.0.0.1:${port}/action/end-inspect-session" \
      -H "Content-Type: application/json" -d '{}' >/dev/null 2>&1 || true
  fi
  curl -sf --max-time 3 -X POST "http://127.0.0.1:47190/relisten-peertalk" >/dev/null 2>&1 \
    || curl -sf --max-time 3 "http://127.0.0.1:47190/status" >/dev/null 2>&1 || true
  dismiss_appview_dialogs_watch_stop "$dismiss_pid"
  launchctl unsetenv APPVIEW_VERIFY 2>/dev/null || true
  killall AppView 2>/dev/null || true; killall AppView 2>/dev/null || true
  killall "Problem Reporter" 2>/dev/null || true
  APPVIEW_OSAPP_DISMISS_PID=""
  sleep 2
}

# Phase 3 — AppViewOsAppMCP tap verify (client must be running and connected).
appview_osapp_verify_tap() {
  local label="$1"
  local port="$2"
  local out_dir="$3"
  local hier_py="$4"

  echo "  [3/3] AppViewOsAppMCP tap verify ($label)" >&2

  local hier="$out_dir/ui_hierarchy.json"
  local state="$out_dir/ui_state.json"
  local tap_targets="$out_dir/ui_tap_targets.json"
  local tap_res="$out_dir/tap_result.json"

  dismiss_appview_system_dialogs
  mcp_get "$port" "/ui/hierarchy" "$hier"
  mcp_get "$port" "/ui/state" "$state"

  local ui_mode
  ui_mode="$(python3 -c "import json; print(json.load(open('$state'))['data'].get('uiMode',''))")"

  local tile_label="${SIM_NAME:-AppViewMCPSample}"
  if [[ "$ui_mode" != "inspector" ]]; then
    echo "  $label: enter inspector via AppViewOsAppMCP" >&2
    appview_enter_mac_inspector "$port" "$hier_py"
    appview_click_appview_launch_tile "$tile_label"
    curl -sf --max-time 30 -X POST "http://127.0.0.1:${port}/ui/open-inspector" \
      -H "Content-Type: application/json" -d '{}' -o "$tap_res" 2>/dev/null || true
    sleep 3
    mcp_get "$port" "/ui/state" "$state"
    ui_mode="$(python3 -c "import json; print(json.load(open('$state'))['data'].get('uiMode',''))")"
  fi

  local i mode rows
  for ((i=1; i<=90; i++)); do
    dismiss_appview_system_dialogs
    if (( i == 1 || i % 8 == 0 )); then
      appview_enter_mac_inspector "$port" "$hier_py"
      appview_click_appview_launch_tile "$tile_label"
      curl -sf --max-time 30 -X POST "http://127.0.0.1:${port}/ui/open-inspector" \
        -H "Content-Type: application/json" -d '{}' >/dev/null 2>&1 || true
    fi
    if (( i % 16 == 0 )); then
      curl -sf --max-time 15 -X POST "http://127.0.0.1:${port}/action/reload" \
        -H "Content-Type: application/json" -d '{}' >/dev/null 2>&1 || true
    fi
    mcp_get "$port" "/ui/state" "$state"
    mode="$(python3 -c "import json; print(json.load(open('$state'))['data'].get('uiMode',''))")"
    rows="$(python3 -c "import json; print(json.load(open('$state'))['data'].get('hierarchyRows',0))")"
    echo "  poll $i: uiMode=$mode hierarchyRows=$rows" >&2
    if [[ "$mode" == "inspector" && "${rows:-0}" -ge "$MIN_HIERARCHY_ROWS" ]]; then
      break
    fi
    sleep 1
  done

  mode="$(python3 -c "import json; print(json.load(open('$state'))['data'].get('uiMode',''))")"
  rows="$(python3 -c "import json; print(json.load(open('$state'))['data'].get('hierarchyRows',0))")"
  if [[ "$mode" != "inspector" || "${rows:-0}" -lt "$MIN_HIERARCHY_ROWS" ]]; then
    echo "FAIL $label: inspector not ready (uiMode=$mode hierarchyRows=$rows); need demo running before client" >&2
    return 1
  fi

  mcp_get "$port" "/ui/hierarchy" "$hier"
  mcp_get "$port" "/ui/state" "$out_dir/ui_state_after_inspector.json"
  cp "$out_dir/ui_state_after_inspector.json" "$out_dir/ui_state_before_tap.json"

  local tt_arg="-"
  if appview_osapp_fetch_tap_targets "$port" "$tap_targets"; then
    local n
    n="$(python3 -c "import json; print(len(json.load(open('$tap_targets')).get('data',{}).get('targets',[])))")"
    echo "  $label: GET /ui/tap-targets → $n targets" >&2
    tt_arg="$tap_targets"
  else
    echo "  $label: /ui/tap-targets missing (legacy client) — use /ui/hierarchy" >&2
  fi

  local row_oid row_count hs_count
  row_oid="$(python3 "$hier_py" pick_hierarchy_tap_oid "$tt_arg" "$hier" "$TAP_ROW_INDEX")"
  row_count="$(python3 "$hier_py" hierarchy_row_count "$hier")"
  if [[ -f "$tap_targets" ]]; then
    hs_count="$(python3 -c "import json; t=json.load(open('$tap_targets')).get('data',{}).get('targets',[]); print(sum(1 for x in t if x.get('action')=='hierarchySelect'))")"
  else
    hs_count="n/a"
  fi
  [[ -n "$row_oid" && "$row_oid" != "0" ]] || {
    echo "FAIL $label: no hierarchy row at index $TAP_ROW_INDEX (hierarchy_rows=$row_count tap_targets_hierarchySelect=$hs_count)" >&2
    return 1
  }

  echo "  $label: POST /ui/tap oid=$row_oid" >&2
  mcp_post_tap "$port" "{\"oid\": $row_oid}" "$tap_res"
  sleep 1
  mcp_get "$port" "/ui/state" "$out_dir/ui_state_after_row_tap.json"
  cp "$out_dir/ui_state_after_row_tap.json" "$out_dir/final_state.json"
  return 0
}

appview_osapp_run_client_tap_verify() {
  local label="$1"
  local app_path="$2"
  local port="$3"
  local out_dir="$4"
  local hier_py="$5"

  appview_osapp_launch_mac_client "$label" "$app_path" "$port" "$out_dir" || return 1
  appview_osapp_verify_tap "$label" "$port" "$out_dir" "$hier_py" || {
    appview_osapp_stop_mac_client
    return 1
  }
  appview_osapp_stop_mac_client
  return 0
}
