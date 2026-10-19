#!/usr/bin/env bash
# E2E verify: CollLayout on Simulator + physical iPhone — dual launch tiles and in-inspector switch.
#
# Requires: booted Simulator with CollLayout demo, iPhone with CollLayout over USB, Swift AppView :47192.
#
#   bash AppView/Scripts/verify_dual_sim_usb_launch.sh
#   DEVICE_UDID=... SIM_UDID=... bash AppView/Scripts/verify_dual_sim_usb_launch.sh
#   BUILD_IOS_DEMO=0 bash AppView/Scripts/verify_dual_sim_usb_launch.sh   # reuse existing .app builds
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$ROOT/appview-verify-logs"
export APPVIEW_VERIFY_LOG_DIR="$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$LOG_DIR/dual-sim-usb-$STAMP"
mkdir -p "$OUT_DIR"
RESULT="$OUT_DIR/RESULT-dual-sim-usb-$STAMP.txt"

DEVICE="${DEVICE_UDID:-00008030-001014891AE1802E}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-9938T969H4}"
SIM_UDID="${SIM_UDID:-5794C474-9C3D-4EDA-80BA-8E18C92A50AB}"
SIM_NAME="${SIM_NAME:-iPhone 17 Pro}"
PORT="${PORT:-47192}"
BUILD_IOS_DEMO="${BUILD_IOS_DEMO:-1}"
DISCOVER_WAIT_SEC="${DISCOVER_WAIT_SEC:-90}"
INSPECTOR_WAIT_SEC="${INSPECTOR_WAIT_SEC:-45}"

DD_SIM="${DD_COLLAYOUT_SIM:-$LOG_DIR/DerivedData-CollLayoutSim}"
DD_DEVICE="${DD_COLLAYOUT_DEVICE:-$LOG_DIR/DerivedData-CollLayoutDevice}"
DD_MAC="${DD_MAC:-$LOG_DIR/DerivedData-AppViewRefactor}"
DEMO_WS="$ROOT/AppViewServer/AppViewDemo/AppViewCollectionLayoutDemo/AppViewCollectionLayoutDemo.xcworkspace"
MAC_WS="$ROOT/AppView/AppView.xcworkspace"
IOS_SIM_APP="$DD_SIM/Build/Products/Debug-iphonesimulator/AppViewCollectionLayoutDemo.app"
IOS_DEVICE_APP="$DD_DEVICE/Build/Products/Debug-iphoneos/AppViewCollectionLayoutDemo.app"
MAC_APP="$DD_MAC/Build/Products/Debug/AppView.app"
BUNDLE_ID="${COLLECTION_LAYOUT_SWIFT_BUNDLE_ID:-AppView.AppViewCollectionLayoutDemo}"
HIER_PY="$ROOT/AppView/Scripts/mcp_ui_helpers.py"

SIM_PORT_MIN=47164
SIM_PORT_MAX=47169
USB_PORT_MIN=47175
USB_PORT_MAX=47179

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
  appview_write_latest_summary "verify_dual_sim_usb_launch" "$RESULT" || true
}
trap _write_summary EXIT

wait_mcp_port() {
  local i
  for ((i = 1; i <= 60; i++)); do
    appview_pump_system_dialogs
    if curl -sf --max-time 3 "http://127.0.0.1:${PORT}/status" >/dev/null 2>&1; then
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
"
}

mcp_discover_usable_count() {
  curl -sf --max-time 5 "http://127.0.0.1:${PORT}/status" | python3 -c "
import json, sys
c = json.load(sys.stdin).get('data', {}).get('client', {})
print(int(c.get('lastDiscover', {}).get('usableAppCount', 0)))
" 2>/dev/null || echo 0
}

wait_usable_discover() {
  local min_count="${1:-2}"
  local max_wait="${2:-90}"
  local i usable
  echo "  waiting up to ${max_wait}s for usableAppCount>=${min_count}…" | tee -a "$RESULT"
  for ((i = 1; i <= max_wait; i++)); do
    usable="$(mcp_discover_usable_count)"
    if [[ "${usable:-0}" -ge "$min_count" ]]; then
      echo "  usableAppCount=$usable (ready after ${i}s)" | tee -a "$RESULT"
      return 0
    fi
    if (( i % 12 == 0 )); then
      mcp_force_discover_usable_count >/dev/null || true
      refresh_launch_targets 20
    fi
    sleep 1
  done
  echo "  usableAppCount=${usable:-0} < $min_count after ${max_wait}s" | tee -a "$RESULT"
  return 1
}

mcp_force_discover_usable_count() {
  curl -sf --max-time 35 -X POST "http://127.0.0.1:${PORT}/action/discover-apps" \
    -H "Content-Type: application/json" -d '{"timeout":20}' \
    | python3 -c "
import json, sys
doc = json.load(sys.stdin)
d = doc.get('data', doc) if isinstance(doc, dict) else {}
print(int(d.get('usableAppCount', 0)))
" 2>/dev/null || echo 0
}

refresh_launch_targets() {
  local wait_sec="${1:-25}"
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

mcp_launch_freeze_reasons() {
  curl -sf --max-time 5 "http://127.0.0.1:${PORT}/ui/launch-health" 2>/dev/null \
    | python3 -c "
import json, sys
d = json.load(sys.stdin).get('data', {})
if not d.get('isFrozen'):
    print('')
else:
    print(','.join(d.get('freezeReasons') or [d.get('freezeReason','frozen')]))
" 2>/dev/null || echo ""
}

wait_dual_on_launch() {
  local i usable ui tile_count freeze frozen_streak=0
  echo "  waiting up to ${DISCOVER_WAIT_SEC}s for 2 apps on launch screen…" | tee -a "$RESULT"
  refresh_launch_targets 25
  for ((i = 1; i <= DISCOVER_WAIT_SEC; i++)); do
    dismiss_appview_system_dialogs
    ui="$(mcp_status_field "c.get('uiMode', '')" 2>/dev/null || echo "")"
    usable="$(mcp_discover_usable_count)"
    tile_count="$(curl -sf --max-time 10 "http://127.0.0.1:${PORT}/ui/launch-targets" 2>/dev/null \
      | python3 -c "import json,sys; d=json.load(sys.stdin).get('data',{}); print(d.get('count',0))" 2>/dev/null || echo 0)"
    freeze="$(mcp_launch_freeze_reasons)"
    if [[ -n "$freeze" ]]; then
      frozen_streak=$((frozen_streak + 1))
    else
      frozen_streak=0
    fi
    echo "  poll $i: uiMode=$ui usableAppCount=$usable launchTargets=$tile_count frozen=${freeze:-no}" | tee -a "$RESULT"
    if [[ "$ui" == "launch" && "${tile_count:-0}" -ge 2 ]]; then
      return 0
    fi
    # Only abort early for frozen state if we have seen at least some apps before
    # (i.e., we regressed from discovered → stuck), not during initial cold start.
    # After AppView restart, polling_stopped_empty/discover_no_progress fire immediately
    # even though apps just need time to reconnect — give them 60s before aborting.
    if [[ "$frozen_streak" -ge 60 && -n "$freeze" && "${usable:-0}" -eq 0 ]]; then
      echo "  launch screen frozen for ${frozen_streak}s with no apps: $freeze" | tee -a "$RESULT"
      return 1
    fi
    if (( i % 15 == 0 )); then
      refresh_launch_targets 20
      mcp_force_discover_usable_count >/dev/null || true
    fi
    sleep 1
  done
  return 1
}

assert_channel_range() {
  local label="$1" min_port="$2" max_port="$3"
  curl -sf --max-time 5 "http://127.0.0.1:${PORT}/status" | python3 -c "
import json, sys
c = json.load(sys.stdin)['data']['client']
port = int(c.get('channelTargetPort') or 0)
assert c.get('uiMode') == 'inspector', c.get('uiMode')
assert c.get('inspectingBundleId') == '$BUNDLE_ID', c.get('inspectingBundleId')
assert $min_port <= port <= $max_port, f'port {port} not in [$min_port,$max_port] ($label)'
assert c.get('hasHierarchy'), 'no hierarchy'
print(f'$label ok port={port}')
" || return 1
}

select_inspect_target_channel() {
  local channel="$1" resp
  wait_usable_discover 2 90 || true
  echo "  POST /action/select-inspect-target channel=$channel" | tee -a "$RESULT"
  resp="$(curl -s --max-time 150 -X POST "http://127.0.0.1:${PORT}/action/select-inspect-target" \
    -H "Content-Type: application/json" \
    -d "{\"channel\":\"$channel\",\"timeout\":90}" 2>/dev/null || true)"
  if [[ -z "$resp" ]]; then
    echo "  select-inspect-target: empty response (MCP timeout?)" | tee -a "$RESULT"
    return 1
  fi
  echo "$resp" | python3 -c "
import json, sys
doc = json.load(sys.stdin)
d = doc.get('data', doc)
assert d.get('ok'), d
print(d.get('channel', '$channel'))
" || return 1
  sleep 2
}

tap_open_inspector_tile() {
  local index="$1"
  local lt="$OUT_DIR/launch_targets.json"
  curl -sf --max-time 10 "http://127.0.0.1:${PORT}/ui/launch-targets" -o "$lt" \
    || fail "GET /ui/launch-targets failed"
  local channel
  channel="$(python3 -c "
import json, sys
doc = json.load(open('$lt'))
d = doc.get('data', doc)
targets = d.get('targets', [])
idx = int('$index')
assert 0 <= idx < len(targets), f'index $index out of range ({len(targets)} targets)'
print(targets[idx]['channel'])
")" || fail "no launch target at index $index"
  select_inspect_target_channel "$channel" || fail "select-inspect-target channel=$channel failed"
}

restart_appview_on_launch() {
  curl -sf --max-time 5 -X POST "http://127.0.0.1:${PORT}/action/end-inspect-session" \
    -H "Content-Type: application/json" -d '{}' >/dev/null 2>&1 || true
  sleep 2
  killall AppView 2>/dev/null || true; killall AppView 2>/dev/null || true
  sleep 1
  xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
  sleep 2
  appview_prepare_clean_launch
  appview_activate_mac_client "$MAC_APP"
  wait_mcp_port || fail "AppView MCP :$PORT not ready after restart"
  wait_dual_on_launch || fail "expected 2 apps on launch after restart"
}

wait_inspector_ready() {
  local max="$1"
  local i mode port hung_streak=0
  for ((i = 1; i <= max; i++)); do
    mode="$(mcp_status_field "c.get('uiMode', '')" 2>/dev/null || echo "")"
    port="$(mcp_status_field "int(c.get('channelTargetPort') or 0)" 2>/dev/null || echo 0)"
    if [[ "$mode" == "inspector" && "${port:-0}" -gt 0 ]]; then
      return 0
    fi
    if [[ -z "$mode" ]]; then
      hung_streak=$((hung_streak + 1))
    else
      hung_streak=0
    fi
    # MCP unresponsive for 10s — kill AppView so caller can handle the failure cleanly.
    if [[ "$hung_streak" -ge 10 ]]; then
      echo "  MCP unresponsive for ${hung_streak}s in wait_inspector_ready — killing AppView" | tee -a "$RESULT"
      killall -9 AppView 2>/dev/null || true; killall -9 AppView 2>/dev/null || true
      return 1
    fi
    sleep 1
  done
  return 1
}

# Kill AppView if MCP is unresponsive, then restart to launch screen.
# Does NOT restore inspector state — caller must re-enter inspector if needed.
appview_kill_if_hung() {
  local label="${1:-hung check}"
  if curl -sf --max-time 5 "http://127.0.0.1:${PORT}/status" >/dev/null 2>&1; then
    return 0
  fi
  echo "  MCP unresponsive ($label) — force-killing AppView" | tee -a "$RESULT"
  killall -9 AppView 2>/dev/null || true; killall -9 AppView 2>/dev/null || true
  sleep 2
  return 1
}

# Sync: POST /action/open-app-switcher, wait until the server returns tile list (up to 45s).
# Prints tile count and returns 0 if count >= min_count, 1 otherwise.
# Kills AppView if MCP is completely unresponsive before the call.
# Stores JSON response in $OUT_DIR/open_app_switcher.json for debugging.
open_app_switcher_sync() {
  local min_count="${1:-2}"
  local resp count ok
  if ! curl -sf --max-time 5 "http://127.0.0.1:${PORT}/status" >/dev/null 2>&1; then
    echo "  MCP unresponsive before open-app-switcher — killing AppView" | tee -a "$RESULT"
    killall -9 AppView 2>/dev/null || true; killall -9 AppView 2>/dev/null || true
    return 1
  fi
  echo "  POST /action/open-app-switcher (sync, min_tiles=$min_count)" | tee -a "$RESULT"
  resp="$(curl -s --max-time 90 -X POST "http://127.0.0.1:${PORT}/action/open-app-switcher" \
    -H "Content-Type: application/json" -d '{}' 2>/dev/null || true)"
  if [[ -z "$resp" ]]; then
    echo "  open-app-switcher: empty response — killing AppView" | tee -a "$RESULT"
    killall -9 AppView 2>/dev/null || true; killall -9 AppView 2>/dev/null || true
    return 1
  fi
  echo "$resp" > "$OUT_DIR/open_app_switcher.json"
  count="$(echo "$resp" | python3 -c "
import json, sys
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(int(d.get('count', 0)))
" 2>/dev/null || echo 0)"
  ok="$(echo "$resp" | python3 -c "
import json, sys
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print('true' if d.get('ok') else 'false')
" 2>/dev/null || echo false)"
  echo "  app-switcher tiles=$count ok=$ok" | tee -a "$RESULT"
  if [[ "${count:-0}" -ge "$min_count" ]]; then
    return 0
  fi
  refresh_launch_targets 25
  sleep 3
  echo "  POST /action/open-app-switcher (retry after refresh)" | tee -a "$RESULT"
  resp="$(curl -s --max-time 90 -X POST "http://127.0.0.1:${PORT}/action/open-app-switcher" \
    -H "Content-Type: application/json" -d '{}' 2>/dev/null || true)"
  count="$(echo "$resp" | python3 -c "
import json, sys
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(int(d.get('count', 0)))
" 2>/dev/null || echo 0)"
  echo "  app-switcher tiles=$count (retry)" | tee -a "$RESULT"
  [[ "${count:-0}" -ge "$min_count" ]]
}

section "preflight"
appview_verify_preflight_clean "$DEVICE"
if ! xcrun simctl boot "$SIM_UDID" 2>/dev/null; then
  xcrun simctl bootstatus "$SIM_UDID" -b 2>/dev/null || true
fi
open -a Simulator --args -CurrentDeviceUDID "$SIM_UDID" 2>/dev/null || true
launchctl unsetenv APPVIEW_VERIFY 2>/dev/null || true

section "build (optional)"
if [[ "$BUILD_IOS_DEMO" == "1" ]]; then
  (cd "$ROOT/AppViewServer/AppViewDemo/AppViewCollectionLayoutDemo" && pod install --silent)
  xcodebuild -workspace "$DEMO_WS" -scheme AppViewCollectionLayoutDemo -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIM_UDID" -derivedDataPath "$DD_SIM" build -quiet
  xcodebuild -workspace "$DEMO_WS" -scheme AppViewCollectionLayoutDemo -configuration Debug \
    -destination "id=$DEVICE" -derivedDataPath "$DD_DEVICE" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" -allowProvisioningUpdates build -quiet
  xcodebuild -workspace "$MAC_WS" -scheme AppViewClient -configuration Debug \
    -derivedDataPath "$DD_MAC" build -quiet
fi
[[ -d "$IOS_SIM_APP" && -d "$IOS_DEVICE_APP" && -d "$MAC_APP" ]] \
  || fail "missing build products (set BUILD_IOS_DEMO=1)"

section "install + launch CollLayout (sim + device)"
appview_prepare_collection_layout_demo "$SIM_UDID" "$IOS_SIM_APP" "$BUNDLE_ID"
osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
sleep 2

killall AppView 2>/dev/null || true; killall AppView 2>/dev/null || true
pid=$(xcrun devicectl device info processes --device "$DEVICE" 2>/dev/null \
  | rg AppViewCollectionLayoutDemo | awk '{print $1}' | head -1 || true)
[[ -n "${pid:-}" ]] && xcrun devicectl device process terminate --device "$DEVICE" --pid "$pid" 2>/dev/null || true
sleep 1
xcrun devicectl device install app --device "$DEVICE" "$IOS_DEVICE_APP" >/dev/null 2>&1 || true
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" >/dev/null \
  || fail "could not launch CollLayout on device $DEVICE"
sleep 5
osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
sleep 2

section "start AppView on launch screen (no auto-enter)"
appview_prepare_clean_launch
killall AppView 2>/dev/null || true; killall AppView 2>/dev/null || true
sleep 1
appview_activate_mac_client "$MAC_APP"
wait_mcp_port || fail "AppView MCP :$PORT not ready"

wait_dual_on_launch || fail "expected 2 apps on launch (sim+USB); see $RESULT"
pass "launch screen shows 2 discoverable apps"

section "launch targets (MCP)"
lt="$OUT_DIR/launch_targets_launch.json"
curl -sf --max-time 10 "http://127.0.0.1:${PORT}/ui/launch-targets" -o "$lt" \
  || fail "GET /ui/launch-targets on launch failed"
tile_count="$(python3 "$HIER_PY" launch_target_count "$lt")"
[[ "${tile_count:-0}" -ge 2 ]] || fail "expected >=2 launch targets, got $tile_count"
python3 -c "
import json
doc = json.load(open('$lt'))
targets = doc.get('data', doc).get('targets', [])
channels = {t.get('channel') for t in targets}
assert 'sim' in channels and 'usb' in channels, channels
for t in targets:
    assert t.get('accessibilityIdentifier'), t
    assert t.get('channel') in ('sim', 'usb'), t
print('channels', sorted(channels))
" || fail "launch-targets missing sim/usb or accessibilityIdentifier"
tt="$OUT_DIR/tap_targets_launch.json"
curl -sf --max-time 10 "http://127.0.0.1:${PORT}/ui/tap-targets" -o "$tt" \
  || fail "GET /ui/tap-targets on launch failed"
pass "launch has $tile_count targets (sim+usb) with channel + a11y ids"

section "enter inspector via simulator tile (index 0)"
wait_usable_discover 2 120 || fail "Peertalk discover not ready before sim entry"
tap_open_inspector_tile 0
wait_inspector_ready "$INSPECTOR_WAIT_SEC" || fail "simulator inspector timeout"
assert_channel_range "simulator session" "$SIM_PORT_MIN" "$SIM_PORT_MAX" \
  || fail "not connected via simulator Peertalk port"
pass "entered inspector on simulator channel"

section "switch to USB via toolbar App popover"
open_app_switcher_sync 2 || fail "app popover did not show 2 tiles"
select_inspect_target_channel usb || fail "select usb in popover failed"
wait_inspector_ready "$INSPECTOR_WAIT_SEC" || fail "USB inspector timeout after switch"
assert_channel_range "usb session" "$USB_PORT_MIN" "$USB_PORT_MAX" \
  || fail "not connected via USB Peertalk port after switch"
pass "switched inspector to USB device"

section "switch back to simulator"
open_app_switcher_sync 2 || fail "app popover missing on second switch"
select_inspect_target_channel sim || fail "select sim in popover failed"
wait_inspector_ready "$INSPECTOR_WAIT_SEC" || fail "simulator re-switch timeout"
assert_channel_range "simulator session (again)" "$SIM_PORT_MIN" "$SIM_PORT_MAX" \
  || fail "simulator channel not restored"
pass "switched back to simulator"

section "scenario B — restart launch, enter via USB device tile (index 1)"
restart_appview_on_launch
pass "launch screen ready (scenario B)"
tap_open_inspector_tile 1
wait_inspector_ready "$INSPECTOR_WAIT_SEC" || fail "USB launch entry timeout"
assert_channel_range "usb launch entry" "$USB_PORT_MIN" "$USB_PORT_MAX" \
  || fail "launch USB tile did not open USB session"
pass "entered inspector via USB device tile on launch"

section "scenario B — switch USB session to simulator via toolbar"
open_app_switcher_sync 2 || fail "popover missing after USB launch entry"
select_inspect_target_channel sim || fail "scenario B sim switch failed"
wait_inspector_ready "$INSPECTOR_WAIT_SEC" || fail "sim switch after USB launch timeout"
assert_channel_range "sim after USB launch" "$SIM_PORT_MIN" "$SIM_PORT_MAX" \
  || fail "toolbar switch to sim failed after USB launch"
pass "switched from USB launch to simulator"

section "scenario C — restart launch, enter USB, switch sim, switch USB again"
restart_appview_on_launch
tap_open_inspector_tile 1
wait_inspector_ready "$INSPECTOR_WAIT_SEC" || fail "scenario C USB entry timeout"
assert_channel_range "scenario C usb" "$USB_PORT_MIN" "$USB_PORT_MAX" \
  || fail "scenario C USB entry"
open_app_switcher_sync 2 || fail "scenario C popover 1"
select_inspect_target_channel sim || fail "scenario C sim switch failed"
wait_inspector_ready "$INSPECTOR_WAIT_SEC" || fail "scenario C sim switch"
assert_channel_range "scenario C sim" "$SIM_PORT_MIN" "$SIM_PORT_MAX" \
  || fail "scenario C sim channel"
open_app_switcher_sync 2 || fail "scenario C popover 2"
select_inspect_target_channel usb || fail "scenario C usb re-switch failed"
wait_inspector_ready "$INSPECTOR_WAIT_SEC" || fail "scenario C usb re-switch"
assert_channel_range "scenario C usb again" "$USB_PORT_MIN" "$USB_PORT_MAX" \
  || fail "scenario C USB re-switch"
pass "scenario C round-trip USB → sim → USB"

pass "dual sim+USB launch and all switch variants complete"
echo "log: $RESULT"
