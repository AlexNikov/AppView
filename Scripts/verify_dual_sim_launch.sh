#!/usr/bin/env bash
# E2E verify: two booted Simulators with different demos — launch tiles + in-inspector sim↔sim switch.
#
#   bash AppView/Scripts/verify_dual_sim_launch.sh
#   SIM_A_UDID=... SIM_B_UDID=... bash AppView/Scripts/verify_dual_sim_launch.sh
#   BUILD_IOS_DEMO=0 bash AppView/Scripts/verify_dual_sim_launch.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$ROOT/appview-verify-logs"
export APPVIEW_VERIFY_LOG_DIR="$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$LOG_DIR/dual-sim-launch-$STAMP"
mkdir -p "$OUT_DIR"
RESULT="$OUT_DIR/RESULT-dual-sim-launch-$STAMP.txt"

SIM_A_UDID="${SIM_A_UDID:-5794C474-9C3D-4EDA-80BA-8E18C92A50AB}"
SIM_B_UDID="${SIM_B_UDID:-3967BCC4-7087-4567-BC8D-D58B1453086F}"
PORT="${PORT:-47192}"
BUILD_IOS_DEMO="${BUILD_IOS_DEMO:-1}"
DISCOVER_WAIT_SEC="${DISCOVER_WAIT_SEC:-90}"
INSPECTOR_WAIT_SEC="${INSPECTOR_WAIT_SEC:-60}"
MAX_SWAP_MS="${MAX_SWAP_MS:-60000}"

DD_MAC="${DD_MAC:-$LOG_DIR/DerivedData-AppViewRefactor}"
DD_CUSTOM="${DD_CUSTOM:-$LOG_DIR/DerivedData-CustomInfoDemo-Swift}"
DD_COLL="${DD_COLL:-$LOG_DIR/DerivedData-CollectionLayout-Swift}"
MAC_APP="${APPVIEW_APP:-$DD_MAC/Build/Products/Debug/AppView.app}"
APP_A="${APP_A:-$DD_CUSTOM/Build/Products/Debug-iphonesimulator/AppViewCustomInfoDemo.app}"
APP_B="${APP_B:-$DD_COLL/Build/Products/Debug-iphonesimulator/AppViewCollectionLayoutDemo.app}"
BUNDLE_A="${BUNDLE_A:-AppView.AppViewCustomInfoDemoSwift}"
BUNDLE_B="${BUNDLE_B:-AppView.AppViewCollectionLayoutDemo}"
A11Y_A="appview.launch.app.${BUNDLE_A}.sim"
A11Y_B="appview.launch.app.${BUNDLE_B}.sim"

# shellcheck source=appview_write_latest_summary.sh
source "$ROOT/AppView/Scripts/appview_write_latest_summary.sh"
# shellcheck source=appview_dismiss_dialogs.sh
source "$ROOT/AppView/Scripts/appview_dismiss_dialogs.sh"
# shellcheck source=appview_verify_ios_demo.sh
source "$ROOT/AppView/Scripts/appview_verify_ios_demo.sh"

section() { echo ""; echo "======== $1 ========" | tee -a "$RESULT"; }
fail() { echo "RESULT: FAIL — $1" | tee -a "$RESULT"; exit 1; }
pass() { echo "RESULT: PASS — $1" | tee -a "$RESULT"; }

_write_summary() {
  appview_write_latest_summary "verify_dual_sim_launch" "$RESULT" || true
}
trap _write_summary EXIT

wait_mcp_port() {
  local i
  export APPVIEW_APP="$MAC_APP"
  for ((i = 1; i <= 60; i++)); do
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

mcp_discover_usable_count() {
  mcp_status_field "int((c.get('lastDiscover') or {}).get('usableAppCount', 0))" 2>/dev/null || echo 0
}

wait_usable_discover() {
  local min_count="${1:-2}"
  local max_wait="${2:-90}"
  local i usable
  echo "  waiting up to ${max_wait}s for usableAppCount>=${min_count}…" | tee -a "$RESULT"
  for ((i = 1; i <= max_wait; i++)); do
    appview_pump_system_dialogs
    usable="$(mcp_discover_usable_count)"
    if [[ "${usable:-0}" -ge "$min_count" ]]; then
      echo "  usableAppCount=$usable (ready after ${i}s)" | tee -a "$RESULT"
      return 0
    fi
    if (( i % 12 == 0 )); then
      refresh_launch_targets 25
    fi
    sleep 1
  done
  echo "  usableAppCount=${usable:-0} < $min_count after ${max_wait}s" | tee -a "$RESULT"
  return 1
}

refresh_launch_targets() {
  local wait_sec="${1:-45}"
  curl -sf --max-time $((wait_sec + 30)) -X POST "http://127.0.0.1:${PORT}/action/refresh-launch-targets" \
    -H "Content-Type: application/json" -d "{\"timeout\":${wait_sec}}" >/dev/null 2>&1 || true
}

launch_tile_count() {
  curl -sf --max-time 10 "http://127.0.0.1:${PORT}/ui/launch-targets" | python3 -c "
import json, sys
d = json.load(sys.stdin).get('data', {})
print(int(d.get('count', 0)))
" 2>/dev/null || echo 0
}

sim_launch_tile_count() {
  curl -sf --max-time 10 "http://127.0.0.1:${PORT}/ui/launch-targets" | python3 -c "
import json, sys
d = json.load(sys.stdin).get('data', {})
print(sum(1 for t in (d.get('targets') or []) if t.get('channel') == 'sim'))
" 2>/dev/null || echo 0
}

build_appview_if_needed() {
  [[ -d "$MAC_APP" ]] || {
    echo "  building AppView.app…" | tee -a "$RESULT"
    xcodebuild -workspace "$ROOT/AppView/AppView.xcworkspace" -scheme AppViewClient \
      -derivedDataPath "$DD_MAC" build -quiet
  }
  [[ -d "$MAC_APP" ]] || fail "Missing AppView.app: $MAC_APP"
}

build_demos_if_needed() {
  if [[ "$BUILD_IOS_DEMO" == "1" ]]; then
    appview_build_ios_demo custom_info swift
    appview_build_ios_demo collection_layout swift
  fi
  APP_A="$(appview_ios_demo_app_path custom_info swift)"
  APP_B="$(appview_ios_demo_app_path collection_layout swift)"
  [[ -d "$APP_A" ]] || fail "Missing CustomInfo demo: $APP_A"
  [[ -d "$APP_B" ]] || fail "Missing CollLayout demo: $APP_B"
}

boot_and_launch_demos() {
  section "boot dual simulators + launch demos"
  xcrun simctl boot "$SIM_A_UDID" 2>/dev/null || true
  xcrun simctl boot "$SIM_B_UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$SIM_A_UDID" -b 2>/dev/null || true
  xcrun simctl bootstatus "$SIM_B_UDID" -b 2>/dev/null || true
  open -a Simulator 2>/dev/null || true

  xcrun simctl install "$SIM_A_UDID" "$APP_A"
  xcrun simctl terminate "$SIM_A_UDID" "$BUNDLE_B" 2>/dev/null || true
  xcrun simctl launch "$SIM_A_UDID" "$BUNDLE_A"
  sleep 3

  xcrun simctl install "$SIM_B_UDID" "$APP_B"
  xcrun simctl terminate "$SIM_B_UDID" "$BUNDLE_A" 2>/dev/null || true
  xcrun simctl launch "$SIM_B_UDID" "$BUNDLE_B"
  sleep 4

  echo "  Peertalk listeners:" | tee -a "$RESULT"
  /usr/sbin/lsof -nP -iTCP:47164-47169 -sTCP:LISTEN 2>/dev/null | tee -a "$RESULT" || true
}

launch_appview() {
  section "launch AppView (timing enabled)"
  killall AppView 2>/dev/null || true; killall AppView 2>/dev/null || true
  sleep 1
  appview_prepare_clean_launch
  export APPVIEW_APP="$MAC_APP"
  env APPVIEW_VERIFY=1 APPVIEW_CONN_TIMING=1 "$MAC_APP/Contents/MacOS/$(basename "$MAC_APP" .app)" >/dev/null 2>&1 &
  appview_activate_mac_client "$MAC_APP"
  wait_mcp_port || fail "AppView MCP :$PORT not up"
}

wait_inspector_bundle() {
  local want_bundle="$1"
  local max_wait="${2:-$INSPECTOR_WAIT_SEC}"
  local i bundle
  for ((i = 1; i <= max_wait; i++)); do
    appview_pump_system_dialogs
    bundle="$(mcp_status_field "c.get('inspectingBundleId','')")"
    if [[ "$bundle" == "$want_bundle" ]]; then
      echo "  inspector bundle=$bundle (${i}s)" | tee -a "$RESULT"
      return 0
    fi
    sleep 1
  done
  fail "inspector bundle not $want_bundle (last=${bundle:-none})"
}

select_launch_tile() {
  local a11y="$1"
  local t0 ms body ok
  t0=$(python3 -c "import time; print(int(time.time()*1000))")
  body="$(curl -s --max-time $((INSPECTOR_WAIT_SEC + 30)) -X POST "http://127.0.0.1:${PORT}/action/select-inspect-target" \
    -H "Content-Type: application/json" \
    -d "{\"accessibilityIdentifier\":\"${a11y}\",\"timeout\":${INSPECTOR_WAIT_SEC}}")"
  ok="$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print('1' if (d.get('data') or d).get('ok') else '0')" "$body" 2>/dev/null || echo 0)"
  ms=$(python3 -c "import time; print(int(time.time()*1000)-$t0)")
  echo "  select $a11y ${ms}ms ok=$ok" | tee -a "$RESULT"
  [[ "$ok" == "1" ]] || { echo "  response: $body" | tee -a "$RESULT"; fail "select-inspect-target $a11y failed"; }
  if [[ "$ms" -gt "$MAX_SWAP_MS" ]]; then
    fail "select $a11y took ${ms}ms > MAX_SWAP_MS=$MAX_SWAP_MS"
  fi
}

switch_inspector_app() {
  local a11y="$1"
  local t0 ms body ok
  t0=$(python3 -c "import time; print(int(time.time()*1000))")
  body="$(curl -s --max-time $((INSPECTOR_WAIT_SEC + 30)) -X POST "http://127.0.0.1:${PORT}/action/select-inspect-target" \
    -H "Content-Type: application/json" \
    -d "{\"accessibilityIdentifier\":\"${a11y}\",\"timeout\":${INSPECTOR_WAIT_SEC}}")"
  ok="$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print('1' if (d.get('data') or d).get('ok') else '0')" "$body" 2>/dev/null || echo 0)"
  ms=$(python3 -c "import time; print(int(time.time()*1000)-$t0)")
  echo "  switch $a11y ${ms}ms ok=$ok" | tee -a "$RESULT"
  [[ "$ok" == "1" ]] || { echo "  response: $body" | tee -a "$RESULT"; fail "inspector switch $a11y failed"; }
  if [[ "$ms" -gt "$MAX_SWAP_MS" ]]; then
    fail "switch $a11y took ${ms}ms > MAX_SWAP_MS=$MAX_SWAP_MS"
  fi
}

section "verify_dual_sim_launch setup"
echo "SIM_A=$SIM_A_UDID SIM_B=$SIM_B_UDID MAX_SWAP_MS=$MAX_SWAP_MS" | tee -a "$RESULT"

appview_verify_preflight_clean

build_appview_if_needed
build_demos_if_needed
boot_and_launch_demos
launch_appview

section "launch screen — 2 sim tiles"
refresh_launch_targets 45
wait_usable_discover 2 "$DISCOVER_WAIT_SEC" || fail "discover < 2 usable apps"

tile_count="$(launch_tile_count)"
sim_tiles="$(sim_launch_tile_count)"
echo "  launchTargets=$tile_count simTiles=$sim_tiles" | tee -a "$RESULT"
[[ "${sim_tiles:-0}" -ge 2 ]] || fail "expected >=2 sim launch tiles, got $sim_tiles"

curl -sf "http://127.0.0.1:${PORT}/status" | python3 -c "
import json, sys
c = json.load(sys.stdin).get('data', {}).get('client', {})
ld = c.get('lastDiscover') or {}
print('  discover:', ld.get('usableAppCount'), ld.get('appNames'), ld.get('channels'), file=open('$RESULT','a'))
lt = c.get('lastTiming') or {}
print('  timing maxMs:', lt.get('maxMs'), file=open('$RESULT','a'))
" 2>/dev/null || true

section "enter inspector — CustomInfo (sim A)"
select_launch_tile "$A11Y_A"
wait_inspector_bundle "$BUNDLE_A"

section "switch inspector — CollLayout (sim B)"
switch_inspector_app "$A11Y_B"
wait_inspector_bundle "$BUNDLE_B"

section "round-trip — CustomInfo (sim A)"
switch_inspector_app "$A11Y_A"
wait_inspector_bundle "$BUNDLE_A"

section "timing summary"
curl -sf "http://127.0.0.1:${PORT}/status" | python3 -c "
import json, sys
c = json.load(sys.stdin).get('data', {}).get('client', {})
lt = c.get('lastTiming') or {}
for phase in ('connect.listeningPorts', 'discover.fetchAppInfos', 'discover.appRequest.port', 'switch.simToSim', 'preview.launchTile', 'launch.discover'):
    if phase in (lt.get('maxMs') or {}):
        print(f'  {phase}: max={(lt.get(\"maxMs\") or {}).get(phase)}ms count={(lt.get(\"counts\") or {}).get(phase)}')
" 2>/dev/null | tee -a "$RESULT" || true

pass "dual sim launch + sim↔sim switch complete"
