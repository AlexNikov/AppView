#!/usr/bin/env bash
# Simulator kill + app swap timing: CustomInfo → CollLayout, action permutations.
#
#   SWAP_SCENARIO=both bash AppView/Scripts/verify_simulator_swap_timing.sh
#   ACTION_PERM=reload,select,fast SWAP_SCENARIO=inspector bash ...
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$ROOT/appview-verify-logs"
export APPVIEW_VERIFY_LOG_DIR="$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$LOG_DIR/sim-swap-timing-$STAMP"
mkdir -p "$OUT_DIR"
RESULT="$OUT_DIR/RESULT-sim-swap-timing-$STAMP.txt"

SIM_UDID="${SIM_UDID:-$(xcrun simctl list devices booted -j | python3 -c "
import json,sys
for d in json.load(sys.stdin).get('devices',{}).values():
  for x in d:
    if x.get('state')=='Booted':
      print(x['udid']); sys.exit(0)
print('')
" 2>/dev/null || true)}"
SIM_NAME="${SIM_NAME:-iPhone 17 Pro}"
PORT="${PORT:-47192}"
DD_MAC="${DD_MAC:-$LOG_DIR/DerivedData-AppViewRefactor}"
DD_CUSTOM="${DD_CUSTOM:-$LOG_DIR/DerivedData-CustomInfoDemo-Swift}"
DD_COLL="${DD_COLL:-$LOG_DIR/DerivedData-CollectionLayout-Swift}"
MAC_APP="${APPVIEW_APP:-$DD_MAC/Build/Products/Debug/AppView.app}"
APP_A="${APP_A:-$DD_CUSTOM/Build/Products/Debug-iphonesimulator/AppViewCustomInfoDemo.app}"
APP_B="${APP_B:-$DD_COLL/Build/Products/Debug-iphonesimulator/AppViewCollectionLayoutDemo.app}"
BUNDLE_A="${BUNDLE_A:-AppView.AppViewCustomInfoDemoSwift}"
BUNDLE_B="${BUNDLE_B:-AppView.AppViewCollectionLayoutDemo}"
SWAP_SCENARIO="${SWAP_SCENARIO:-both}"
ACTION_PERM="${ACTION_PERM:-}"
DISCOVER_WAIT_SEC="${DISCOVER_WAIT_SEC:-60}"
CONNECT_WAIT_SEC="${CONNECT_WAIT_SEC:-75}"
BUILD_IOS_DEMO="${BUILD_IOS_DEMO:-1}"
MAX_SWAP_MS="${MAX_SWAP_MS:-45000}"

# shellcheck source=appview_write_latest_summary.sh
source "$ROOT/AppView/Scripts/appview_write_latest_summary.sh"
# shellcheck source=appview_dismiss_dialogs.sh
source "$ROOT/AppView/Scripts/appview_dismiss_dialogs.sh"
# shellcheck source=appview_verify_ios_demo.sh
source "$ROOT/AppView/Scripts/appview_verify_ios_demo.sh"

LAST_WAIT_ELAPSED_SEC=0

fail() { echo "RESULT: FAIL — $1" | tee -a "$RESULT"; exit 1; }
pass() { echo "RESULT: PASS — $1" | tee -a "$RESULT"; }
section() { echo ""; echo "======== $1 ========" | tee -a "$RESULT"; }

_write_summary() {
  appview_write_latest_summary "verify_simulator_swap_timing" "$RESULT" || true
}
trap _write_summary EXIT

PERMS=(
  "reload,select,fast"
  "reload,fast,select"
  "select,reload,fast"
  "select,fast,reload"
  "fast,reload,select"
  "fast,select,reload"
)

[[ -n "$SIM_UDID" ]] || SIM_UDID="$(xcrun simctl list devices available -j | python3 -c "
import json,sys
for runtime, devices in json.load(sys.stdin).get('devices',{}).items():
  if 'iOS' not in runtime: continue
  for d in devices:
    if d.get('isAvailable') and 'iPhone' in d.get('name',''):
      print(d['udid']); sys.exit(0)
sys.exit(1)
")"

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

mcp_status_field() {
  local py_expr="$1"
  curl -sf --max-time 5 "http://127.0.0.1:${PORT}/status" | python3 -c "
import json, sys
c = json.load(sys.stdin).get('data', {}).get('client', {})
print($py_expr)
" 2>/dev/null || true
}

wait_peertalk_listen() {
  local i
  for ((i=1; i<=80; i++)); do
    if /usr/sbin/lsof -nP -iTCP:47164-47169 -sTCP:LISTEN 2>/dev/null | grep -qE '127\.0\.0\.0\.1:4716[0-9]|127\.0\.0\.1:4716[0-9]'; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

build_appview_if_needed() {
  [[ -d "$MAC_APP" ]] || {
    echo "  building AppView.app…" | tee -a "$RESULT"
    xcodebuild -workspace "$ROOT/AppView/AppView.xcworkspace" -scheme AppViewClient \
      -derivedDataPath "$DD_MAC" build -quiet 2>/dev/null \
      || xcodebuild -workspace "$ROOT/AppView/AppView.xcworkspace" -scheme AppViewClient \
        -derivedDataPath "$DD_MAC" build -quiet
  }
  [[ -d "$MAC_APP" ]] || fail "Missing AppView.app: $MAC_APP"
}

launch_appview() {
  killall AppView 2>/dev/null || true; killall AppView 2>/dev/null || true
  sleep 1
  appview_prepare_clean_launch
  local exe="$MAC_APP/Contents/MacOS/$(basename "$MAC_APP" .app)"
  env APPVIEW_VERIFY=1 APPVIEW_CONN_TIMING=1 "$exe" >/dev/null 2>&1 &
  appview_activate_mac_client "$MAC_APP"
  wait_mcp_port || fail "AppView MCP :$PORT not up"
}

install_demo() {
  local kind="$1"
  appview_install_ios_demo "$SIM_UDID" "$kind" swift
}

sim_swap_shutdown() {
  section "simulator shutdown"
  curl -sf --max-time 10 -X POST "http://127.0.0.1:${PORT}/action/end-inspect-session" \
    -H 'Content-Type: application/json' -d '{}' >/dev/null 2>&1 || true
  sleep 1
  xcrun simctl shutdown "$SIM_UDID" 2>/dev/null || true
  sleep 2
  AVConnectionTiming_clear=1
}

sim_boot_and_install_b() {
  section "simulator boot + demo B (CollLayout)"
  xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
  sleep 2
  install_demo collection_layout
  osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
  sleep 4
  appview_wait_ios_mcp || {
    curl -sf --max-time 5 -X POST "http://127.0.0.1:47190/relisten-peertalk" >/dev/null 2>&1 || true
    sleep 2
    appview_wait_ios_mcp || fail "iOS MCP :47190 not up after CollLayout launch"
  }
  curl -sf --max-time 5 -X POST "http://127.0.0.1:47190/relisten-peertalk" >/dev/null 2>&1 || true
  sleep 2
  wait_peertalk_listen || fail "CollLayout Peertalk not listening"
}

mcp_action_reload() {
  curl -sf --max-time 30 -X POST "http://127.0.0.1:${PORT}/action/reload" >/dev/null 2>&1 || true
  sleep 2
}

mcp_action_select() {
  curl -sf --max-time $((CONNECT_WAIT_SEC + 15)) -X POST "http://127.0.0.1:${PORT}/action/select-inspect-target" \
    -H "Content-Type: application/json" \
    -d "{\"channel\":\"sim\",\"timeout\":${CONNECT_WAIT_SEC}}" >/dev/null 2>&1 || true
  sleep 1
}

mcp_action_fast() {
  curl -sf --max-time 10 -X POST "http://127.0.0.1:${PORT}/action/toggle-fast-mode" >/dev/null 2>&1 || true
  sleep 0.5
}

mcp_action_discover() {
  curl -sf --max-time 25 -X POST "http://127.0.0.1:${PORT}/action/discover-apps" \
    -H "Content-Type: application/json" -d '{"timeout":18}' >/dev/null 2>&1 || true
  curl -sf --max-time 25 -X POST "http://127.0.0.1:${PORT}/action/refresh-launch-targets" \
    -H "Content-Type: application/json" -d '{"timeout":15}' >/dev/null 2>&1 || true
}

run_perm() {
  local perm="$1"
  IFS=',' read -r a b c <<< "$perm"
  mcp_action_discover
  for step in "$a" "$b" "$c"; do
    case "$step" in
      reload) mcp_action_reload ;;
      select) mcp_action_select ;;
      fast) mcp_action_fast ;;
      *) echo "  unknown step: $step" | tee -a "$RESULT" ;;
    esac
  done
}

inspector_ready_b() {
  local mode bundle
  mode="$(mcp_status_field "c.get('uiMode', '')")"
  bundle="$(mcp_status_field "c.get('inspectingBundleId', '')")"
  [[ "$mode" == "inspector" && "$bundle" == "$BUNDLE_B" ]]
}

launch_ready_b() {
  local usable tiles bundle
  usable="$(mcp_status_field "int((c.get('lastDiscover') or {}).get('usableAppCount', 0))")"
  tiles="$(curl -sf --max-time 10 "http://127.0.0.1:${PORT}/ui/launch-targets" 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('count',0))" 2>/dev/null || echo 0)"
  bundle="$(mcp_status_field "c.get('inspectingBundleId', '')")"
  [[ "${usable:-0}" -ge 1 || "${tiles:-0}" -ge 1 || "$bundle" == "$BUNDLE_B" ]]
}

wait_ready() {
  local scenario="$1"
  local t0="$2"
  local i elapsed
  for ((i=1; i<=DISCOVER_WAIT_SEC; i++)); do
    dismiss_appview_system_dialogs
    if [[ "$scenario" == "inspector" ]]; then
      if inspector_ready_b; then
        elapsed=$(( $(date +%s) - t0 ))
        echo "  ready inspector B in ${elapsed}s (poll $i)" | tee -a "$RESULT" >&2
        LAST_WAIT_ELAPSED_SEC=$elapsed
        return 0
      fi
      if (( i % 6 == 0 )); then
        mcp_action_select
        curl -sf --max-time 25 -X POST "http://127.0.0.1:${PORT}/action/discover-apps" \
          -H "Content-Type: application/json" -d '{"timeout":15}' >/dev/null 2>&1 || true
      fi
    else
      if launch_ready_b; then
        elapsed=$(( $(date +%s) - t0 ))
        echo "  ready launch B in ${elapsed}s (poll $i)" | tee -a "$RESULT" >&2
        LAST_WAIT_ELAPSED_SEC=$elapsed
        return 0
      fi
      if (( i % 4 == 0 )); then
        mcp_action_discover
        if (( i % 8 == 0 )); then
          curl -sf --max-time 5 -X POST "http://127.0.0.1:47190/relisten-peertalk" >/dev/null 2>&1 || true
        fi
      fi
    fi
    if (( i % 10 == 0 )); then
      echo "  wait poll $i: mode=$(mcp_status_field "c.get('uiMode','')") bundle=$(mcp_status_field "c.get('inspectingBundleId','')") usable=$(mcp_status_field "int((c.get('lastDiscover') or {}).get('usableAppCount',0))")" | tee -a "$RESULT"
    fi
    sleep 1
  done
  LAST_WAIT_ELAPSED_SEC=-1
  return 1
}

log_timing_tail() {
  curl -sf --max-time 10 "http://127.0.0.1:${PORT}/status" | python3 -c "
import json,sys
c=json.load(sys.stdin).get('data',{}).get('client',{})
t=c.get('lastTiming') or {}
print('timing phases=', t.get('phaseCount',0))
for p in (t.get('recent') or [])[-8:]:
  print(' ', p.get('phase'), p.get('durationMs'), p.get('fresh', p.get('ok','')))
" 2>/dev/null | tee -a "$RESULT" || true
}

connect_to_a_inspector() {
  curl -sf --max-time 25 -X POST "http://127.0.0.1:${PORT}/action/discover-apps" \
    -H "Content-Type: application/json" -d "{\"timeout\":20}" >/dev/null 2>&1 || true
  curl -sf --max-time 25 -X POST "http://127.0.0.1:${PORT}/action/refresh-launch-targets" \
    -H "Content-Type: application/json" -d "{\"timeout\":15}" >/dev/null 2>&1 || true
  appview_click_appview_launch_tile "AppViewCustomInfoDemo" 2>/dev/null || true
  sleep 2
  curl -sf --max-time $((CONNECT_WAIT_SEC + 15)) -X POST "http://127.0.0.1:${PORT}/action/select-inspect-target" \
    -H "Content-Type: application/json" \
    -d "{\"channel\":\"sim\",\"timeout\":${CONNECT_WAIT_SEC}}" >/dev/null 2>&1 || true
  local i
  for ((i=1; i<=CONNECT_WAIT_SEC; i++)); do
    dismiss_appview_system_dialogs
    if [[ "$(mcp_status_field "c.get('inspectingBundleId', '')")" == "$BUNDLE_A" ]]; then
      echo "  connected to A in ${i}s" | tee -a "$RESULT"
      return 0
    fi
    if (( i % 8 == 0 )); then
      appview_click_appview_launch_tile "AppViewCustomInfoDemo" 2>/dev/null || true
      curl -sf --max-time 20 -X POST "http://127.0.0.1:${PORT}/action/select-inspect-target" \
        -H "Content-Type: application/json" \
        -d "{\"channel\":\"sim\",\"timeout\":30}" >/dev/null 2>&1 || true
    fi
    sleep 1
  done
  return 1
}

setup_initial_a() {
  section "setup demo A (CustomInfo)"
  xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
  install_demo custom_info
  osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
  sleep 4
  appview_wait_ios_mcp || {
    curl -sf --max-time 5 -X POST "http://127.0.0.1:47190/relisten-peertalk" >/dev/null 2>&1 || true
    sleep 2
    appview_wait_ios_mcp || fail "iOS MCP not up for CustomInfo"
  }
  wait_peertalk_listen || fail "CustomInfo Peertalk not listening"
  launch_appview
  curl -sf --max-time 20 -X POST "http://127.0.0.1:${PORT}/action/discover-apps" \
    -H "Content-Type: application/json" -d '{"timeout":20}' >/dev/null 2>&1 || true
}

run_scenario() {
  local scenario="$1"
  section "scenario=$scenario"
  setup_initial_a
  wait_mcp_port || launch_appview

  if [[ "$scenario" == "inspector" ]]; then
    connect_to_a_inspector || fail "could not connect to CustomInfo in inspector"
    echo "  connected to A bundle=$BUNDLE_A" | tee -a "$RESULT"
  else
    curl -sf --max-time 10 -X POST "http://127.0.0.1:${PORT}/action/end-inspect-session" \
      -H 'Content-Type: application/json' -d '{}' >/dev/null 2>&1 || true
    sleep 1
    wait_mcp_port || launch_appview
    echo "  staying on launch screen" | tee -a "$RESULT"
  fi

  sim_swap_shutdown
  sim_boot_and_install_b

  local perms_to_run=("${PERMS[@]}")
  if [[ -n "$ACTION_PERM" ]]; then
    perms_to_run=("$ACTION_PERM")
  fi

  local worst_ms=0
  for perm in "${perms_to_run[@]}"; do
    section "perm=$perm scenario=$scenario"
    sim_swap_shutdown
    sim_boot_and_install_b

    local t0
    t0=$(date +%s)
    echo "  T0=$t0 perm=$perm" | tee -a "$RESULT"
    run_perm "$perm"
    if ! wait_ready "$scenario" "$t0"; then
      log_timing_tail
      fail "timeout scenario=$scenario perm=$perm"
    fi
    local elapsed=$LAST_WAIT_ELAPSED_SEC
    log_timing_tail
    if (( elapsed < 0 )); then
      fail "timeout scenario=$scenario perm=$perm"
    fi
    if (( elapsed > worst_ms )); then worst_ms=$elapsed; fi
    if (( elapsed * 1000 > MAX_SWAP_MS )); then
      fail "slow swap $((elapsed * 1000))ms > ${MAX_SWAP_MS}ms scenario=$scenario perm=$perm"
    fi
    echo "  elapsed_ms=$(( elapsed * 1000 )) perm=$perm" | tee -a "$RESULT"
  done
  echo "  worst_elapsed_s=$worst_ms scenario=$scenario" | tee -a "$RESULT"
}

echo "======== simulator swap timing ========" | tee "$RESULT"
build_appview_if_needed

case "$SWAP_SCENARIO" in
  inspector) run_scenario inspector ;;
  launch) run_scenario launch ;;
  both)
    run_scenario inspector
    run_scenario launch
    ;;
  *) fail "unknown SWAP_SCENARIO=$SWAP_SCENARIO" ;;
esac

pass "simulator swap timing scenarios=$SWAP_SCENARIO"
