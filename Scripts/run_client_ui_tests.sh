#!/usr/bin/env bash
# Boot iOS demo fixture, build AppView.app + UI tests, run XCUITest smoke suite.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$ROOT/appview-verify-logs"
export APPVIEW_VERIFY_LOG_DIR="$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
DD="$LOG_DIR/DerivedData-AppViewRefactor"
RESULT_DIR="$LOG_DIR/ui-tests-$STAMP"
SIM_NAME="${SIM_NAME:-iPhone 17 Pro}"
ONLY_TESTING="${ONLY_TESTING:-AppViewClientUITests}"
RUN_LEGACY_GATES="${RUN_LEGACY_GATES:-1}"

# shellcheck source=appview_write_latest_summary.sh
source "$ROOT/AppView/Scripts/appview_write_latest_summary.sh"
# shellcheck source=appview_dismiss_dialogs.sh
source "$ROOT/AppView/Scripts/appview_dismiss_dialogs.sh"
# shellcheck source=appview_verify_ios_demo.sh
source "$ROOT/AppView/Scripts/appview_verify_ios_demo.sh"

section() { echo ""; echo "======== $1 ========"; }
fail() { echo "run_client_ui_tests: FAIL — $1" >&2; exit 1; }
pass() { echo "run_client_ui_tests: PASS — $1"; }

_write_summary() {
  if [[ -n "${RESULT_FILE:-}" && -f "${RESULT_FILE}" ]]; then
    appview_write_latest_summary "run_client_ui_tests" "$RESULT_FILE" || true
  elif [[ -f "${RESULT_DIR:-}/xcodebuild.log" ]]; then
    appview_write_latest_summary "run_client_ui_tests" "$RESULT_DIR/xcodebuild.log" || true
  else
    appview_write_latest_summary "run_client_ui_tests" || true
  fi
}
trap _write_summary EXIT

resolve_sim_udid() {
  xcrun simctl list devices available -j | python3 -c "
import json, sys, os
name = os.environ.get('SIM_NAME', 'iPhone 17 Pro')
for devices in json.load(sys.stdin).get('devices', {}).values():
    for dev in devices:
        if dev.get('isAvailable') and name in dev.get('name', '') and 'iPhone' in dev.get('name', ''):
            print(dev['udid'])
            sys.exit(0)
sys.exit(1)
"
}

section "0. Optional legacy gates"
if [[ "$RUN_LEGACY_GATES" == "1" ]]; then
  bash "$ROOT/AppView/Scripts/run_legacy_gates.sh"
fi

section "1. iOS simulator + AppViewCustomInfoDemo fixture"
SIM_UDID="$(resolve_sim_udid)" || fail "Simulator not found: $SIM_NAME"
export SIM_NAME
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$SIM_UDID" 2>/dev/null || true
appview_build_ios_demo custom_info swift
appview_install_ios_demo "$SIM_UDID" custom_info swift
sleep 2

section "2. Generate Xcode project + pods"
cd "$ROOT/AppView"
if ! command -v xcodegen >/dev/null 2>&1; then
  fail "xcodegen is required (brew install xcodegen)"
fi
xcodegen generate
pod install --silent 2>/dev/null || pod install

section "3. Build AppView.app + AppViewClientUITests"
mkdir -p "$RESULT_DIR"
xcodebuild -workspace AppView.xcworkspace -scheme AppViewClient \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DD" \
  build-for-testing -quiet \
  2>&1 | tee "$RESULT_DIR/build-for-testing.log"

section "4. Clean AppView saved state (foreground launch for XCUITest)"
appview_prepare_clean_launch
launchctl unsetenv APPVIEW_VERIFY 2>/dev/null || true
pkill -9 -f "DerivedData-AppViewRefactor.*/AppView.app/Contents/MacOS/AppView" 2>/dev/null || true
pkill -9 -f "/Applications/AppView.app/Contents/MacOS/AppView" 2>/dev/null || true
killall -9 AppView 2>/dev/null || true; killall -9 AppView 2>/dev/null || true
killall -9 "Problem Reporter" 2>/dev/null || true
sleep 2

section "5. Run UI tests"
set +e
python3 -c "
import json, os
print(json.dumps({
  'recordPreviewFixtures': os.environ.get('APPVIEW_RECORD_PREVIEW_FIXTURE', '0') == '1',
}))
" > "$LOG_DIR/ui-test-config.json"

env APPVIEW_DEMO_FIXTURE_READY=1 \
  xcodebuild -workspace AppView.xcworkspace -scheme AppViewClient \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DD" \
    -resultBundlePath "$RESULT_DIR/TestResults.xcresult" \
    -only-testing:"$ONLY_TESTING" \
    test 2>&1 | tee "$RESULT_DIR/xcodebuild.log"
TEST_EXIT=${PIPESTATUS[0]}
set -e

echo ""
grep -E 'Test Case .* (passed|failed)|TEST (SUCCEEDED|FAILED)|error:' "$RESULT_DIR/xcodebuild.log" | tail -20 || true

if [[ "$TEST_EXIT" -eq 0 ]]; then
  pass "UI tests ($ONLY_TESTING)"
else
  fail "xcodebuild test exit $TEST_EXIT — see $RESULT_DIR/xcodebuild.log"
fi

if [[ "${APPVIEW_RECORD_PREVIEW_FIXTURE:-0}" == "1" ]]; then
  FIXTURE_DIR="$ROOT/AppView/AppViewClientUITests/Fixtures"
  mkdir -p "$FIXTURE_DIR"
  find "$HOME/Library/Containers" -path '*AppViewClientUITests*.xctrunner*/tmp/preview-structure*.norm' \
    -exec cp -f {} "$FIXTURE_DIR"/ \; 2>/dev/null || true
  echo "Preview fixtures copied to $FIXTURE_DIR"
  ls -la "$FIXTURE_DIR"/*.norm 2>/dev/null || true
fi
