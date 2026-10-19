#!/usr/bin/env bash
# Build demo, run MCP setHidden on oid 17, grep AppViewDiag lines from simulator log.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$ROOT/appview-verify-logs"
STAMP="$(date +%Y%m%d-%H%M%S)"
DIAG_LOG="$LOG_DIR/modification-diag-$STAMP.log"
RESULT_FILE="$LOG_DIR/modification-diag-result-$STAMP.txt"
source "$ROOT/AppView/Scripts/appview_dismiss_dialogs.sh"

DD_DEMO="${DD_DEMO:-$LOG_DIR/DerivedData-CustomInfoDemo-Swift}"
SIM_NAME="${SIM_NAME:-iPhone 17 Pro}"
OID="${1:-17}"

fail() { echo "RESULT: FAIL — $1" | tee -a "$RESULT_FILE"; exit 1; }
pass() { echo "RESULT: PASS — $1" | tee -a "$RESULT_FILE"; }

SIM_UDID="$(xcrun simctl list devices available -j | python3 -c "
import json,sys,os
name=os.environ.get('SIM_NAME','iPhone 17 Pro')
for d in json.load(sys.stdin).get('devices',{}).values():
  for dev in d:
    if dev.get('isAvailable') and name in dev.get('name','') and 'iPhone' in dev.get('name',''):
      print(dev['udid']); sys.exit(0)
sys.exit(1)
")"

echo "=== verify_modification_diag_logs oid=$OID ===" | tee "$DIAG_LOG"
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true

cd "$ROOT/AppViewServer/AppViewDemo/AppViewCustomInfoDemo"
pod install --silent 2>/dev/null || pod install
DEMO_APP="$(find "$DD_DEMO" -name 'AppViewCustomInfoDemo.app' -type d 2>/dev/null | head -1)"
if [[ ! -d "$DEMO_APP" ]]; then
  echo "Building AppViewCustomInfoDemo..." >>"$DIAG_LOG"
  xcodebuild -workspace AppViewCustomInfoDemo.xcworkspace -scheme AppViewCustomInfoDemo \
    -configuration Debug -destination "platform=iOS Simulator,name=${SIM_NAME}" \
    -derivedDataPath "$DD_DEMO" build -quiet
  DEMO_APP="$(find "$DD_DEMO" -name 'AppViewCustomInfoDemo.app' -type d | head -1)"
fi
[[ -d "$DEMO_APP" ]] || fail "Missing AppViewCustomInfoDemo.app"

appview_free_ios_mcp_port_47190
xcrun simctl terminate "$SIM_UDID" "$DEMO_BUNDLE_ID" 2>/dev/null || true
appview_prepare_custom_info_demo "$SIM_UDID" "$DEMO_APP"
sleep 5
appview_wait_ios_mcp || fail "MCP :47190 not up"

DIAG_STREAM="$LOG_DIR/modification-diag-stream-$STAMP.log"
LOG_PID=""
xcrun simctl spawn "$SIM_UDID" log stream --style compact \
  --predicate 'process == "AppViewCustomInfoDemo"' \
  >"$DIAG_STREAM" 2>/dev/null &
LOG_PID=$!
sleep 2

bash "$ROOT/AppView/Scripts/verify_hidden_ios_mcp.sh" "$OID" >>"$DIAG_LOG" 2>&1 || fail "verify_hidden_ios_mcp.sh $OID"

sleep 2
if [[ -n "$LOG_PID" ]]; then
  kill "$LOG_PID" 2>/dev/null || true
  wait "$LOG_PID" 2>/dev/null || true
fi

if [[ -f "$DIAG_STREAM" ]]; then
  rg 'AppViewDiag' "$DIAG_STREAM" >>"$DIAG_LOG" 2>/dev/null || true
fi

echo "--- AppViewDiag (grep) ---" | tee -a "$RESULT_FILE"
rg 'AppViewDiag' "$DIAG_LOG" | tail -20 | tee -a "$RESULT_FILE" || true

rg -q "inbuilt recv oid=${OID}.*visibilityOnly=true" "$DIAG_LOG" \
  || fail "missing server visibility fast-path log for oid $OID"
rg -q "inbuilt OK visibility.*detailOid=${OID}" "$DIAG_LOG" \
  || fail "missing server visibility OK log"
rg -q "MCP modify OK oid=${OID}" "$DIAG_LOG" \
  || fail "missing MCP modify OK log"

pass "AppViewDiag server logs for MCP hidden oid=$OID (see $DIAG_LOG)"
