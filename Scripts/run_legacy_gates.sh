#!/usr/bin/env bash
# Static legacy-removal gates (run before verify or in CI).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

section() { echo ""; echo "======== $1 ========"; }

section "AppView XcodeGen (project.yml)"
bash "$ROOT/AppView/Scripts/verify_xcodegen_project.sh"

section "AppViewClient migration gates"
bash "$ROOT/AppView/Scripts/verify_appview_client_migration.sh"

section "AppViewServer ObjC exception catch manifest"
bash "$ROOT/AppViewServer/Scripts/verify_src_manifest.sh"

section "AppViewServer ObjC inventory"
bash "$ROOT/AppViewServer/Scripts/count_objc_legacy.sh"

section "Swift @objc / .h inventory (G6/G7)"
bash "$ROOT/AppViewServer/Scripts/count_swift_objc.sh"

echo ""
echo "run_legacy_gates: all gates passed"
