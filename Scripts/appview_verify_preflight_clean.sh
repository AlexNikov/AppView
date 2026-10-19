#!/usr/bin/env bash
# Kill mac AppView clients, terminate iOS demos, shutdown booted simulators before verify.
#
#   bash AppView/Scripts/appview_verify_preflight_clean.sh
#   DEVICE_UDID=00008030-... bash AppView/Scripts/appview_verify_preflight_clean.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=appview_dismiss_dialogs.sh
source "$ROOT/AppView/Scripts/appview_dismiss_dialogs.sh"

appview_verify_preflight_clean "${DEVICE_UDID:-${1:-}}"
