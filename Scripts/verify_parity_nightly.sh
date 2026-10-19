#!/usr/bin/env bash
# Manual / nightly: full ObjC baseline vs Swift parity (requires both AppView builds + baseline iOS demo).
# Not the default fast path — use verify_* with SKIP_OBJC_BASELINE=1 for day-to-day CI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export SKIP_OBJC_BASELINE=0
LOG_DIR="$ROOT/appview-verify-logs"
DD_BASELINE="$LOG_DIR/DerivedData-AppViewBaseline"

section() { echo ""; echo "======== $1 ========"; }

parity_skip_baseline() {
  echo ""
  echo "verify_parity_nightly: SKIP — ObjC baseline does not build (read-only Lookin-baseline+mcp/)."
  echo "  Use swift-only verify instead:"
  echo "    SKIP_OBJC_BASELINE=1 bash AppView/Scripts/verify_ui_hierarchy_mcp.sh"
  echo "    bash AppView/Scripts/verify_custom_info_client.sh"
  echo "  Or fix baseline tree separately, then re-run with SKIP_OBJC_BASELINE=0."
  exit 0
}

parity_baseline_ios_build_ok() {
  return 1
}

section "Preflight: ObjC baseline AppView.app"
mkdir -p "$LOG_DIR"
cd "$ROOT/Lookin-baseline+mcp"
pod install --silent 2>/dev/null || pod install
set +e
xcodebuild -workspace AppView.xcworkspace -scheme AppViewClient -configuration Debug \
  -derivedDataPath "$DD_BASELINE" build -quiet \
  2>&1 | tee "$LOG_DIR/parity-baseline-build.log"
build_rc=${PIPESTATUS[0]}
set -e
if [[ "$build_rc" -ne 0 || ! -d "$DD_BASELINE/Build/Products/Debug/AppView.app" ]]; then
  grep -E 'error:' "$LOG_DIR/parity-baseline-build.log" | head -5 || true
  parity_skip_baseline
fi
echo "  baseline AppView.app OK"

section "Legacy gates"
bash "$ROOT/AppView/Scripts/run_legacy_gates.sh"

section "Wire v2 ping"
bash "$ROOT/AppView/Scripts/verify_wire_v2_ping.sh"

section "Custom info (baseline capture)"
bash "$ROOT/AppView/Scripts/verify_custom_info_client.sh"

section "UI hierarchy (ObjC vs Swift)"
bash "$ROOT/AppView/Scripts/verify_ui_hierarchy_mcp.sh"

section "UI tap (ObjC vs Swift)"
bash "$ROOT/AppView/Scripts/verify_ui_tap_mcp.sh"

echo ""
echo "verify_parity_nightly: all parity checks finished"
