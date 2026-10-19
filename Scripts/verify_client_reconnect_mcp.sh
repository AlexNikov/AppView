#!/usr/bin/env bash
# Verify repeated connect: demo stays running; only AppView.app restarts between rounds.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$ROOT/appview-verify-logs"
SIM_UDID="${SIM_UDID:-$(xcrun simctl list devices booted -j | python3 -c "
import json,sys
for d in json.load(sys.stdin).get('devices',{}).values():
  for x in d:
    if x.get('state')=='Booted':
      print(x['udid']); sys.exit(0)
sys.exit(1)
")}"
SIM_NAME="${SIM_NAME:-iPhone 17 Pro}"
DEMO_APP="${DEMO_APP:-$ROOT/appview-verify-logs/DerivedData-CustomInfoDemo-Swift/Build/Products/Debug-iphonesimulator/AppViewCustomInfoDemo.app}"
APPVIEW_APP="${APPVIEW_APP:-$ROOT/appview-verify-logs/DerivedData-AppViewRefactor/Build/Products/Debug/AppView.app}"
BUNDLE="${DEMO_BUNDLE:-AppView.AppViewCustomInfoDemoSwift}"
PORT=47192
ROUNDS="${RECONNECT_ROUNDS:-2}"
DISCOVER_WAIT_SEC="${DISCOVER_WAIT_SEC:-45}"
CONNECT_WAIT_SEC="${CONNECT_WAIT_SEC:-90}"
RESULT="$ROOT/appview-verify-logs/client-reconnect-$(date +%Y%m%d-%H%M%S).txt"

fail() { echo "RESULT: FAIL — $1" | tee -a "$RESULT"; exit 1; }
pass() { echo "RESULT: PASS — $1" | tee -a "$RESULT"; }

[[ -d "$DEMO_APP" ]] || fail "Missing demo app: $DEMO_APP"
[[ -d "$APPVIEW_APP" ]] || fail "Missing AppView.app: $APPVIEW_APP"

xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
# shellcheck source=appview_dismiss_dialogs.sh
source "$ROOT/AppView/Scripts/appview_dismiss_dialogs.sh"
# shellcheck source=appview_verify_ios_demo.sh
source "$ROOT/AppView/Scripts/appview_verify_ios_demo.sh"
HIER_PY="$ROOT/AppView/Scripts/mcp_ui_helpers.py"
appview_prepare_custom_info_demo "$SIM_UDID" "$DEMO_APP" "$BUNDLE"
osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
appview_wait_ios_mcp || fail "iOS MCP :47190 not up after demo launch"
sleep 2

wait_peertalk_listen() {
  local i
  for ((i=1; i<=60; i++)); do
    if /usr/sbin/lsof -nP -iTCP:47164-47169 -sTCP:LISTEN 2>/dev/null | grep -qE '127\.0\.0\.1:4716[0-9]'; then
      return 0
    fi
    if /usr/sbin/lsof -nP -iTCP:47164-47169 2>/dev/null | grep -qE 'AppViewCus.*4716[0-9].*ESTABLISHED'; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}
wait_peertalk_listen || fail "Demo Peertalk not listening (47164-47169)"

wait_mcp_port() {
  local i
  for ((i=1; i<=60; i++)); do
    appview_pump_system_dialogs
    if curl -sf --max-time 2 "http://127.0.0.1:${PORT}/status" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

restart_appview_client() {
  local force_discover_once="${1:-0}"
  if curl -sf --max-time 5 -X POST "http://127.0.0.1:${PORT}/action/end-inspect-session" \
    -H 'Content-Type: application/json' -d '{}' >/dev/null 2>&1; then
    sleep 2
  fi
  killall AppView 2>/dev/null || true; killall AppView 2>/dev/null || true
  sleep 2
  osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
  sleep 2
  curl -sf --max-time 5 -X POST "http://127.0.0.1:47190/relisten-peertalk" >/dev/null 2>&1 || true
  sleep 3
  appview_prepare_clean_launch
  local exe="$APPVIEW_APP/Contents/MacOS/$(basename "$APPVIEW_APP" .app)"
  [[ -x "$exe" ]] || return 1
  local appview_env=(APPVIEW_VERIFY=1)
  if [[ "$force_discover_once" == "1" ]]; then
    appview_env+=(APPVIEW_FORCE_DISCOVER_ONCE=1)
  fi
  env "${appview_env[@]}" "$exe" >/dev/null 2>&1 &
  appview_activate_mac_client "$APPVIEW_APP"
  wait_mcp_port
  curl -sf --max-time 10 -X POST "http://127.0.0.1:${PORT}/action/end-inspect-session" \
    -H 'Content-Type: application/json' -d '{}' >/dev/null 2>&1 || true
  sleep 1
}

mcp_status_field() {
  local py_expr="$1"
  curl -sf --max-time 5 "http://127.0.0.1:${PORT}/status" | python3 -c "
import json, sys
c = json.load(sys.stdin).get('data', {}).get('client', {})
print($py_expr)
" 2>/dev/null || true
}

mcp_discover_usable_count() {
  mcp_status_field "int((c.get('lastDiscover') or {}).get('usableAppCount', 0))"
}

refresh_launch_targets() {
  local wait_sec="${1:-20}"
  curl -sf --max-time $((wait_sec + 30)) -X POST "http://127.0.0.1:${PORT}/action/refresh-launch-targets" \
    -H "Content-Type: application/json" \
    -d "{\"timeout\":${wait_sec}}" \
    | python3 -c "
import json, sys
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print('refresh count=', d.get('count', 0), 'ok=', d.get('ok'))
" 2>/dev/null || true
}

force_discover_apps() {
  local timeout="${1:-15}"
  curl -sf --max-time $((timeout + 20)) -X POST "http://127.0.0.1:${PORT}/action/discover-apps" \
    -H "Content-Type: application/json" -d "{\"timeout\":${timeout}}" >/dev/null 2>&1 || true
}

launch_target_count() {
  curl -sf --max-time 10 "http://127.0.0.1:${PORT}/ui/launch-targets" 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('count',0))" 2>/dev/null \
    || echo 0
}

peertalk_port_ready() {
  local port="$1"
  [[ "${port:-0}" -ge 47164 && "${port:-0}" -le 47171 ]]
}

select_inspect_sim() {
  local timeout="${1:-25}"
  local resp
  echo "  POST select-inspect-target channel=sim timeout=${timeout}" | tee -a "$RESULT"
  resp="$(curl -s --max-time $((timeout + 15)) -X POST "http://127.0.0.1:${PORT}/action/select-inspect-target" \
    -H "Content-Type: application/json" \
    -d "{\"channel\":\"sim\",\"timeout\":${timeout}}" 2>/dev/null || true)"
  if [[ -z "$resp" ]]; then
    echo "  select-inspect-target: empty response" | tee -a "$RESULT"
    return 1
  fi
  echo "  select-inspect-target: $(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin).get('data',{}); print('ok='+str(d.get('ok'))+', channel='+str(d.get('channel',''))+', error='+str(d.get('error','')))" 2>/dev/null || echo "$resp")" | tee -a "$RESULT"
  echo "$resp" | python3 -c "
import json, sys
doc = json.load(sys.stdin)
d = doc.get('data', doc)
assert d.get('ok'), d
" 2>/dev/null
}

nudge_custom_info_connect() {
  local mode bundle
  mode="$(mcp_status_field "c.get('uiMode', '')")"
  bundle="$(mcp_status_field "c.get('inspectingBundleId', '')")"
  if [[ "$mode" == "inspector" && -z "$bundle" ]]; then
    curl -sf --max-time 10 -X POST "http://127.0.0.1:${PORT}/action/end-inspect-session" \
      -H 'Content-Type: application/json' -d '{}' >/dev/null 2>&1 || true
    sleep 2
    mode="$(mcp_status_field "c.get('uiMode', '')")"
  fi
  if [[ "$mode" == "launch" || -z "$bundle" ]]; then
    appview_click_appview_launch_tile "AppViewCustomInfoDemo"
    sleep 3
  fi
}

wait_custom_info_on_launch() {
  local i usable tiles mode bundle
  echo "  waiting up to ${DISCOVER_WAIT_SEC}s for CustomInfo on launch…" | tee -a "$RESULT"
  refresh_launch_targets 15
  force_discover_apps 20
  for ((i=1; i<=DISCOVER_WAIT_SEC; i++)); do
    dismiss_appview_system_dialogs
    mode="$(mcp_status_field "c.get('uiMode', '')")"
    bundle="$(mcp_status_field "c.get('inspectingBundleId', '')")"
    usable="$(mcp_discover_usable_count)"
    tiles="$(launch_target_count)"
    if [[ "$mode" == "inspector" && -z "$bundle" ]]; then
      curl -sf --max-time 10 -X POST "http://127.0.0.1:${PORT}/action/end-inspect-session" \
        -H 'Content-Type: application/json' -d '{}' >/dev/null 2>&1 || true
      mode="launch"
    fi
    if (( i == 1 || i % 10 == 0 )); then
      echo "  discover poll $i/${DISCOVER_WAIT_SEC}: uiMode=$mode usable=$usable tiles=$tiles" | tee -a "$RESULT"
    fi
    if (( i == 20 || (i > 20 && i % 15 == 0) )) && [[ "${usable:-0}" -eq 0 && "${tiles:-0}" -eq 0 ]]; then
      curl -sf --max-time 5 -X POST "http://127.0.0.1:47190/relisten-peertalk" >/dev/null 2>&1 || true
      sleep 1
      force_discover_apps
      refresh_launch_targets 10
    fi
    if [[ "${usable:-0}" -ge 1 ]]; then
      return 0
    fi
    if (( i % 12 == 0 )); then
      nudge_custom_info_connect
      force_discover_apps
      refresh_launch_targets 10
    fi
    sleep 1
  done
  usable="$(mcp_discover_usable_count)"
  tiles="$(launch_target_count)"
  echo "  discover: timeout (usable=$usable tiles=$tiles)" | tee -a "$RESULT"
  [[ "${usable:-0}" -ge 1 || "${tiles:-0}" -ge 1 ]]
}

inspector_session_ready() {
  local mode bundle port
  mode="$(mcp_status_field "c.get('uiMode', '')")"
  bundle="$(mcp_status_field "c.get('inspectingBundleId', '')")"
  port="$(mcp_status_field "int(c.get('channelTargetPort') or 0)")"
  [[ "$mode" == "inspector" ]] || return 1
  [[ "$bundle" == "$BUNDLE" ]] || return 1
  [[ "$(mcp_status_field "bool(c.get('channelIsConnected'))")" == "True" ]] \
    || peertalk_port_ready "$port" || return 1
  return 0
}

wait_inspecting_custom_info() {
  local i
  for ((i=1; i<=CONNECT_WAIT_SEC; i++)); do
    dismiss_appview_system_dialogs
    if inspector_session_ready; then
      echo "  connect poll $i/${CONNECT_WAIT_SEC}: inspector session ready" | tee -a "$RESULT"
      return 0
    fi
    if [[ "$(mcp_status_field "c.get('uiMode', '')")" == "inspector" \
      && -z "$(mcp_status_field "c.get('inspectingBundleId', '')")" ]]; then
      curl -sf --max-time 10 -X POST "http://127.0.0.1:${PORT}/action/end-inspect-session" \
        -H 'Content-Type: application/json' -d '{}' >/dev/null 2>&1 || true
    fi
    if (( i == 1 || i % 8 == 0 )); then
      if [[ "$(mcp_status_field "c.get('uiMode', '')")" == "launch" \
        || "$(mcp_status_field "bool(c.get('channelIsConnected'))")" != "True" ]]; then
        nudge_custom_info_connect
      fi
    fi
    if (( i % 20 == 0 )); then
      refresh_launch_targets 15
      force_discover_apps
    fi
    if (( i == 1 || i % 10 == 0 )); then
      echo "  connect poll $i/${CONNECT_WAIT_SEC}: mode=$(mcp_status_field "c.get('uiMode', '')") bundle=$(mcp_status_field "c.get('inspectingBundleId', '')") port=$(mcp_status_field "int(c.get('channelTargetPort') or 0)") channel=$(mcp_status_field "bool(c.get('channelIsConnected'))")" | tee -a "$RESULT"
    fi
    sleep 1
  done
  return 1
}

connect_custom_info_round() {
  for (( _ei=1; _ei<=6; _ei++ )); do
    [[ "$(mcp_status_field "c.get('uiMode', '')")" == "inspector" \
      && -z "$(mcp_status_field "c.get('inspectingBundleId', '')")" ]] || break
    curl -sf --max-time 10 -X POST "http://127.0.0.1:${PORT}/action/end-inspect-session" \
      -H 'Content-Type: application/json' -d '{}' >/dev/null 2>&1 || true
    sleep 1
  done
  wait_custom_info_on_launch || true
  if [[ "$(mcp_discover_usable_count)" -ge 1 || "$(launch_target_count)" -ge 1 ]]; then
    select_inspect_sim 45 || true
  fi
  if ! inspector_session_ready; then
    nudge_custom_info_connect
    if [[ "$(mcp_discover_usable_count)" -ge 1 || "$(launch_target_count)" -ge 1 ]]; then
      select_inspect_sim 30 || true
    fi
  fi
  wait_inspecting_custom_info
}

echo "======== client reconnect (demo once, restart AppView) ========" | tee "$RESULT"

restart_appview_client || fail "AppView MCP :$PORT not up (initial)"
appview_activate_mac_client "$APPVIEW_APP"
sleep 3
wait_peertalk_listen || fail "demo not listening before round 1"
refresh_launch_targets 15
force_discover_apps 20

for round in $(seq 1 "$ROUNDS"); do
  echo "--- round $round (demo not restarted) ---" | tee -a "$RESULT"
  osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
  wait_peertalk_listen || fail "round $round: demo not listening"
  connect_custom_info_round || fail "round $round: inspector connect timeout"
  echo "status: mode=$(mcp_status_field "c.get('uiMode', '')") bundle=$(mcp_status_field "c.get('inspectingBundleId', '')") port=$(mcp_status_field "int(c.get('channelTargetPort') or 0)") hierarchy=$(mcp_status_field "bool(c.get('hasHierarchy'))")" | tee -a "$RESULT"
  inspector_session_ready || fail "round $round: session not ready after connect"
  if [[ "$round" -lt "$ROUNDS" ]]; then
    restart_appview_client 1 || fail "round $round: AppView MCP down after client restart"
    osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
    wait_peertalk_listen || fail "round $round: demo not listening after AppView quit (iOS must re-listen)"
    for (( _i=1; _i<=8; _i++ )); do
      [[ "$(mcp_status_field "c.get('uiMode', '')")" == "launch" ]] && break
      curl -sf --max-time 10 -X POST "http://127.0.0.1:${PORT}/action/end-inspect-session" \
        -H 'Content-Type: application/json' -d '{}' >/dev/null 2>&1 || true
      sleep 1
    done
    curl -sf --max-time 5 -X POST "http://127.0.0.1:47190/relisten-peertalk" >/dev/null 2>&1 || true
    sleep 5
    force_discover_apps 25
    refresh_launch_targets 20
    for (( _i=1; _i<=12; _i++ )); do
      [[ "$(mcp_status_field "c.get('uiMode', '')")" == "launch" ]] && break
      curl -sf --max-time 10 -X POST "http://127.0.0.1:${PORT}/action/end-inspect-session" \
        -H 'Content-Type: application/json' -d '{}' >/dev/null 2>&1 || true
      sleep 1
    done
    sleep 2
  fi
done

DIAG="$(curl -sf --max-time 10 "http://127.0.0.1:${PORT}/ui/diag-log?tail=12")"
echo "diag tail: $DIAG" | tee -a "$RESULT"
pass "${ROUNDS}x connect after AppView client restart only (demo kept running)"
