#!/usr/bin/env bash
# Run after changes to AppViewShared wire models or AppViewClient connection layer.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
bash "$ROOT/AppView/Scripts/verify_appview_client_migration.sh"
bash "$ROOT/AppViewServer/Scripts/verify_appview_integration.sh"
