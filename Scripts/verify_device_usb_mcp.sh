#!/usr/bin/env bash
# E2E verify: CollLayout demo on physical iPhone over USB (AppView :47192 MCP).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=appview_dismiss_dialogs.sh
source "$ROOT/AppView/Scripts/appview_dismiss_dialogs.sh"
DEVICE="${DEVICE_UDID:-00008030-001014891AE1802E}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-9938T969H4}"
DD_IOS="${DD_IOS:-$ROOT/appview-verify-logs/DerivedData-CollLayoutDevice}"
DD_MAC="${DD_MAC:-$ROOT/appview-verify-logs/DerivedData-AppViewRefactor}"
DEMO_WS="$ROOT/AppViewServer/AppViewDemo/AppViewCollectionLayoutDemo/AppViewCollectionLayoutDemo.xcworkspace"
MAC_WS="$ROOT/AppView/AppView.xcworkspace"
IOS_APP="$DD_IOS/Build/Products/Debug-iphoneos/AppViewCollectionLayoutDemo.app"
MAC_APP="$DD_MAC/Build/Products/Debug/AppView.app"
PORT=47192
STAMP="$(date +%Y%m%d-%H%M%S)"
RESULT="$ROOT/appview-verify-logs/device-usb-$STAMP.txt"

fail() { echo "RESULT: FAIL — $1" | tee -a "$RESULT"; exit 1; }
pass() { echo "RESULT: PASS — $1" | tee -a "$RESULT"; }

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

silence_simulator_demos() {
  local sim_udid
  sim_udid="$(xcrun simctl list devices booted 2>/dev/null | rg -o '[A-F0-9-]{36}' | head -1 || true)"
  if [[ -z "$sim_udid" ]]; then
    echo "  no booted simulator — skip sim demo terminate" | tee -a "$RESULT"
    return 0
  fi
  echo "  terminate AppView demos on simulator $sim_udid (USB-only discover)" | tee -a "$RESULT"
  for bid in \
    AppView.AppViewCustomInfoDemoSwift \
    AppView.AppViewMCPSample \
    AppView.AppViewCollectionLayoutDemo \
    AppView.AppViewCustomInfoDemo; do
    xcrun simctl terminate "$sim_udid" "$bid" 2>/dev/null || true
  done
}

enter_usb_inspector() {
  local max="${1:-45}"
  local i usable
  wait_mcp_port || fail "AppView MCP :$PORT not ready"
  for ((i = 1; i <= 25; i++)); do
    usable="$(curl -sf --max-time 5 "http://127.0.0.1:${PORT}/status" 2>/dev/null \
      | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('client',{}).get('lastDiscover',{}).get('usableAppCount',0))" 2>/dev/null || echo 0)"
    if [[ "${usable:-0}" -ge 1 ]]; then
      break
    fi
    sleep 1
  done
  appview_mac_select_inspect_channel "$PORT" usb
  sleep 2
  curl -sf --max-time 30 -X POST "http://127.0.0.1:${PORT}/ui/open-inspector" \
    -H "Content-Type: application/json" -d '{}' >/dev/null 2>&1 || true
  wait_inspector "$max" || return 1
  return 0
}

wait_inspector() {
  local max="$1"
  for _ in $(seq 1 "$max"); do
    local ui
    ui=$(curl -sf --max-time 3 "http://127.0.0.1:$PORT/status" 2>/dev/null \
      | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('client',{}).get('uiMode',''))" 2>/dev/null || echo "")
    [[ "$ui" == "inspector" ]] && return 0
    sleep 1
  done
  return 1
}

assert_usb_session() {
  curl -sf "http://127.0.0.1:$PORT/status" | python3 -c "
import json,sys
c=json.load(sys.stdin)['data']['client']
port=int(c.get('channelTargetPort') or 0)
assert c.get('uiMode')=='inspector', c.get('uiMode')
assert c.get('inspectingBundleId')=='AppView.AppViewCollectionLayoutDemo', c.get('inspectingBundleId')
assert 47175 <= port <= 47179, f'usb port {port} not in [47175,47179]'
print(f'usb session ok port={port}')
"
}

section() { echo ""; echo "======== $1 ========" | tee -a "$RESULT"; }

BUILD_IOS_DEMO="${BUILD_IOS_DEMO:-1}"
BUILD_MAC_CLIENT="${BUILD_MAC_CLIENT:-1}"

section "build iOS demo + Mac AppView"
if [[ "$BUILD_IOS_DEMO" == "1" ]]; then
  (cd "$ROOT/AppViewServer/AppViewDemo/AppViewCollectionLayoutDemo" && pod install --silent)
  xcodebuild -workspace "$DEMO_WS" -scheme AppViewCollectionLayoutDemo -configuration Debug \
    -destination "id=$DEVICE" -derivedDataPath "$DD_IOS" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    -allowProvisioningUpdates build -quiet
else
  echo "  BUILD_IOS_DEMO=0 — reuse $IOS_APP on device" | tee -a "$RESULT"
fi
if [[ "$BUILD_MAC_CLIENT" == "1" ]]; then
  xcodebuild -workspace "$MAC_WS" -scheme AppViewClient -configuration Debug \
    -derivedDataPath "$DD_MAC" build -quiet
else
  echo "  BUILD_MAC_CLIENT=0 — reuse $MAC_APP" | tee -a "$RESULT"
fi
[[ -d "$MAC_APP" ]] || fail "missing Mac AppView.app at $MAC_APP"
if [[ "$BUILD_IOS_DEMO" == "1" ]]; then
  [[ -d "$IOS_APP" ]] || fail "missing iOS app at $IOS_APP"
fi

section "install demo on device"
silence_simulator_demos
killall AppView 2>/dev/null || true; killall AppView 2>/dev/null || true
pid=$(xcrun devicectl device info processes --device "$DEVICE" 2>/dev/null \
  | rg AppViewCollectionLayoutDemo | awk '{print $1}' | head -1 || true)
[[ -n "${pid:-}" ]] && xcrun devicectl device process terminate --device "$DEVICE" --pid "$pid" 2>/dev/null || true
sleep 1
if [[ "$BUILD_IOS_DEMO" == "1" && -d "$IOS_APP" ]]; then
  xcrun devicectl device install app --device "$DEVICE" "$IOS_APP" >/dev/null
fi
xcrun devicectl device process launch --device "$DEVICE" AppView.AppViewCollectionLayoutDemo >/dev/null
sleep 3

section "auto-enter USB inspector"
appview_prepare_clean_launch
launchctl setenv APPVIEW_VERIFY 1
appview_activate_mac_client "$MAC_APP"
enter_usb_inspector 45 || fail "USB inspector enter timeout"
assert_usb_session || fail "not USB CollLayout session"
pass "auto-enter CollLayout on USB :47175"

section "cold start (AppView before demo)"
curl -sf -X POST "http://127.0.0.1:$PORT/action/end-inspect-session" -d '{}' >/dev/null 2>&1 || true
killall AppView 2>/dev/null || true; killall AppView 2>/dev/null || true
pid=$(xcrun devicectl device info processes --device "$DEVICE" 2>/dev/null \
  | rg AppViewCollectionLayoutDemo | awk '{print $1}' | head -1 || true)
[[ -n "${pid:-}" ]] && xcrun devicectl device process terminate --device "$DEVICE" --pid "$pid" 2>/dev/null || true
sleep 1
silence_simulator_demos
appview_activate_mac_client "$MAC_APP"
sleep 4
xcrun devicectl device process launch --device "$DEVICE" AppView.AppViewCollectionLayoutDemo >/dev/null
enter_usb_inspector 60 || fail "cold start timeout"
assert_usb_session || fail "cold start wrong session"
pass "cold start USB connect"

section "relaunch AppView (demo stays running)"
killall AppView 2>/dev/null || true; killall AppView 2>/dev/null || true
sleep 2
# Foreground demo so iOS Peertalk re-listens after Mac quit (watchdog / willEnterForeground).
xcrun devicectl device process launch --device "$DEVICE" AppView.AppViewCollectionLayoutDemo >/dev/null
sleep 3
silence_simulator_demos
appview_activate_mac_client "$MAC_APP"
enter_usb_inspector 40 || fail "relaunch AppView timeout"
assert_usb_session || fail "relaunch wrong session"
pass "AppView relaunch after killall"

section "reload hierarchy"
curl -sf -X POST "http://127.0.0.1:$PORT/action/reload-hierarchy" -d '{}' >/dev/null 2>&1 || true
sleep 8
assert_usb_session || fail "reload lost USB session"
curl -sf "http://127.0.0.1:$PORT/status" | python3 -c "
import json,sys
assert json.load(sys.stdin)['data']['client']['hasHierarchy']
print('hierarchy ok')
" || fail "no hierarchy after reload"
pass "reload keeps USB session"

launchctl unsetenv APPVIEW_VERIFY 2>/dev/null || true
pass "device USB E2E complete"
echo "log: $RESULT"
