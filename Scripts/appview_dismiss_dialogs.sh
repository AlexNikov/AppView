#!/usr/bin/env bash
# Dismiss macOS crash recovery / Problem Report / alert sheets blocking AppView automation.

appview_bundle_ids() {
  # ObjC and Swift builds share the same bundle id in this repo.
  echo "hughkli.AppView"
}

# Demo bundle IDs — keep in sync with AVDemoBundleID.swift.
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=appview_demo_bundle_ids.env
source "$_SCRIPT_DIR/appview_demo_bundle_ids.env"

appview_free_ios_mcp_port_47190() {
  local pids pid comm
  pids="$(lsof -ti tcp:47190 2>/dev/null || true)"
  if [[ -z "$pids" ]]; then
    return 0
  fi
  for pid in $pids; do
    comm="$(ps -p "$pid" -o comm= 2>/dev/null | tr -d ' ' || true)"
    case "$comm" in
      AppViewCustomInfoDemo|AppViewMCPSample|AppViewCollectionLayoutDemo*)
        continue
        ;;
    esac
    echo "  terminating stale listener on :47190 pid=$pid ($comm)" >&2
    kill -9 "$pid" 2>/dev/null || true
  done
  sleep 1
}

appview_prepare_mcp_sample_demo() {
  local sim_udid="$1"
  local mcp_app="$2"
  appview_free_ios_mcp_port_47190
  xcrun simctl install "$sim_udid" "$mcp_app"
  xcrun simctl terminate "$sim_udid" "$LEGACY_DEMO_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$DEMO_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$MCP_SAMPLE_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$COLLECTION_LAYOUT_SWIFT_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$COLLECTION_LAYOUT_OBJC_BUNDLE_ID" 2>/dev/null || true
  pkill -f AppViewMCPSample 2>/dev/null || true
  pkill -f AppViewCollectionLayoutDemo 2>/dev/null || true
  sleep 1
  xcrun simctl launch "$sim_udid" "$MCP_SAMPLE_BUNDLE_ID"
}

appview_relaunch_mcp_sample_demo() {
  local sim_udid="$1"
  xcrun simctl terminate "$sim_udid" "$LEGACY_DEMO_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$DEMO_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$MCP_SAMPLE_BUNDLE_ID" 2>/dev/null || true
  sleep 1
  xcrun simctl launch "$sim_udid" "$MCP_SAMPLE_BUNDLE_ID"
}

appview_prepare_collection_layout_demo() {
  local sim_udid="$1"
  local demo_app="$2"
  local bundle_id="$3"
  appview_free_ios_mcp_port_47190
  xcrun simctl install "$sim_udid" "$demo_app"
  xcrun simctl terminate "$sim_udid" "$LEGACY_DEMO_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$DEMO_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$MCP_SAMPLE_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$COLLECTION_LAYOUT_SWIFT_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$COLLECTION_LAYOUT_OBJC_BUNDLE_ID" 2>/dev/null || true
  pkill -f AppViewMCPSample 2>/dev/null || true
  pkill -f AppViewCollectionLayoutDemo 2>/dev/null || true
  sleep 1
  xcrun simctl launch "$sim_udid" "$bundle_id"
}

appview_ios_mcp_curl() {
  local path="$1" out="${2:-}"
  if [[ -n "$out" ]]; then
    curl -sf --max-time 15 "http://127.0.0.1:47190${path}" -o "$out" 2>/dev/null \
      || curl -g -sf --max-time 15 "http://[::1]:47190${path}" -o "$out" 2>/dev/null
  else
    curl -sf --max-time 15 "http://127.0.0.1:47190${path}" 2>/dev/null \
      || curl -g -sf --max-time 15 "http://[::1]:47190${path}" 2>/dev/null
  fi
}

appview_wait_ios_mcp() {
  local i tmp
  tmp="$(mktemp -t appview-ios-mcp-status.XXXXXX.json)"
  for ((i=1; i<=60; i++)); do
    if appview_ios_mcp_curl "/status" "$tmp"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

appview_mac_ui_tap_oid() {
  local port="$1" oid="$2"
  curl -sf --max-time 10 -X POST "http://127.0.0.1:${port}/ui/tap" \
    -H "Content-Type: application/json" -d "{\"oid\": ${oid}}" >/dev/null 2>&1 || true
}

appview_mac_select_inspect_channel() {
  local port="$1" channel="$2"
  curl -sf --max-time 90 -X POST "http://127.0.0.1:${port}/action/select-inspect-target" \
    -H "Content-Type: application/json" \
    -d "{\"channel\":\"${channel}\",\"timeout\":45}" >/dev/null 2>&1 || true
}

appview_mac_ui_tap_channel() {
  local port="$1" channel="$2"
  curl -sf --max-time 90 -X POST "http://127.0.0.1:${port}/ui/tap" \
    -H "Content-Type: application/json" \
    -d "{\"channel\":\"${channel}\",\"timeout\":45}" >/dev/null 2>&1 || true
}

# Enter inspector from launch screen (tap-targets openInspector, launch card, or POST /ui/open-inspector).
appview_enter_mac_inspector() {
  local port="$1" helpers_py="$2"
  local tt hier launch_oid
  tt="$(mktemp -t appview-mac-tap-targets-enter.XXXXXX.json)"
  hier="$(mktemp -t appview-mac-hierarchy-enter.XXXXXX.json)"
  if curl -sf --max-time 10 "http://127.0.0.1:${port}/ui/tap-targets" -o "$tt" 2>/dev/null; then
    launch_oid="$(python3 "$helpers_py" tap_target_oid_by_action "$tt" openInspector 0 2>/dev/null || true)"
    echo "  enter inspector: openInspector oid=$launch_oid" >&2
    if [[ -n "$launch_oid" && "$launch_oid" != "0" ]]; then
      appview_mac_ui_tap_oid "$port" "$launch_oid"
      sleep 3
      return 0
    fi
  fi
  if curl -sf --max-time 10 "http://127.0.0.1:${port}/ui/hierarchy" -o "$hier" 2>/dev/null; then
    launch_oid="$(python3 "$helpers_py" launch_app_view_oid "$hier" 2>/dev/null || true)"
    echo "  enter inspector: AVLaunchAppView oid=$launch_oid" >&2
    if [[ -n "$launch_oid" && "$launch_oid" != "0" ]]; then
      appview_mac_ui_tap_oid "$port" "$launch_oid"
      sleep 3
      return 0
    fi
  fi
  curl -sf --max-time 30 -X POST "http://127.0.0.1:${port}/ui/open-inspector" \
    -H "Content-Type: application/json" -d '{}' >/dev/null 2>&1 || true
  sleep 2
}

# Poll GET /hierarchy (iOS tree in mac inspector) and /ui/state until loaded.
# ObjC baseline has no /ui/client-state; use this for port 47191 automation.
wait_for_mac_ios_hierarchy() {
  local port="$1" out_file="$2" helpers_py="$3"
  local min_items="${4:-20}" max_wait="${5:-90}"
  local tile_label="${6:-${SIM_NAME:-AppViewMCPSample}}"
  local i state_file item_count rows ui_mode
  state_file="${out_file%.json}-ui-state.json"
  for ((i=1; i<=max_wait; i++)); do
    dismiss_appview_system_dialogs
    if (( i == 1 || i % 8 == 0 )); then
      appview_enter_mac_inspector "$port" "$helpers_py"
      appview_click_appview_launch_tile "$tile_label"
      curl -sf --max-time 30 -X POST "http://127.0.0.1:${port}/ui/open-inspector" \
        -H "Content-Type: application/json" -d '{}' >/dev/null 2>&1 || true
    fi
    if (( i % 16 == 0 )); then
      curl -sf --max-time 15 -X POST "http://127.0.0.1:${port}/action/reload" \
        -H "Content-Type: application/json" -d '{}' >/dev/null 2>&1 || true
    fi
    if curl -sf --max-time 15 "http://127.0.0.1:${port}/hierarchy" -o "$out_file" 2>/dev/null; then
      item_count="$(python3 -c "
import json, sys

def count_nodes(items):
    n = 0
    for it in items or []:
        n += 1
        n += count_nodes(it.get('children') or it.get('subitems') or [])
    return n

d = json.load(open(sys.argv[1]))
items = (d.get('data') or {}).get('items') or []
print(count_nodes(items))
" "$out_file" 2>/dev/null || echo 0)"
      if [[ "${item_count:-0}" -ge "$min_items" ]]; then
        echo "  iOS hierarchy ready: ${item_count} root items (poll ${i}/${max_wait}s)" >&2
        return 0
      fi
    fi
    curl -sf --max-time 10 "http://127.0.0.1:${port}/ui/state" -o "$state_file" 2>/dev/null || true
    ui_mode="$(python3 -c "import json; print(json.load(open('$state_file')).get('data',{}).get('uiMode',''))" 2>/dev/null || echo "")"
    rows="$(python3 -c "import json; print(json.load(open('$state_file')).get('data',{}).get('hierarchyRows',0))" 2>/dev/null || echo 0)"
    echo "  poll ${i}/${max_wait}s: uiMode=${ui_mode} hierarchyRows=${rows} iosItems=${item_count:-0}" >&2
    if [[ "$ui_mode" == "inspector" && "${rows:-0}" -ge "$min_items" ]]; then
      curl -sf --max-time 15 "http://127.0.0.1:${port}/hierarchy" -o "$out_file" 2>/dev/null || true
      return 0
    fi
    sleep 1
  done
  return 1
}

appview_prepare_custom_info_demo() {
  local sim_udid="$1"
  local demo_app="$2"
  local launch_bundle="${3:-$DEMO_BUNDLE_ID}"
  xcrun simctl terminate "$sim_udid" "$MCP_SAMPLE_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "${COLLECTION_LAYOUT_SWIFT_BUNDLE_ID:-AppView.AppViewCollectionLayoutDemo}" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "${COLLECTION_LAYOUT_OBJC_BUNDLE_ID:-AppView.AppViewCollectionLayoutDemoObjC}" 2>/dev/null || true
  xcrun simctl install "$sim_udid" "$demo_app"
  xcrun simctl terminate "$sim_udid" "$LEGACY_DEMO_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$DEMO_BUNDLE_ID" 2>/dev/null || true
  if [[ "$launch_bundle" != "$LEGACY_DEMO_BUNDLE_ID" ]]; then
    xcrun simctl terminate "$sim_udid" "$LEGACY_DEMO_BUNDLE_ID" 2>/dev/null || true
  fi
  if [[ "$launch_bundle" != "$DEMO_BUNDLE_ID" ]]; then
    xcrun simctl terminate "$sim_udid" "$DEMO_BUNDLE_ID" 2>/dev/null || true
  fi
  xcrun simctl uninstall "$sim_udid" "$LEGACY_DEMO_BUNDLE_ID" 2>/dev/null || true
  sleep 1
  appview_free_ios_mcp_port_47190
  APPVIEW_LAST_CUSTOM_INFO_BUNDLE="$launch_bundle"
  xcrun simctl launch "$sim_udid" "$launch_bundle"
}

appview_relaunch_custom_info_demo() {
  local sim_udid="$1"
  local launch_bundle="${2:-${APPVIEW_LAST_CUSTOM_INFO_BUNDLE:-$DEMO_BUNDLE_ID}}"
  xcrun simctl terminate "$sim_udid" "$LEGACY_DEMO_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$DEMO_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$MCP_SAMPLE_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "${COLLECTION_LAYOUT_SWIFT_BUNDLE_ID:-AppView.AppViewCollectionLayoutDemo}" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "${COLLECTION_LAYOUT_OBJC_BUNDLE_ID:-AppView.AppViewCollectionLayoutDemoObjC}" 2>/dev/null || true
  sleep 1
  xcrun simctl launch "$sim_udid" "$launch_bundle"
}

# Activate the verify/refactor AppView.app (not /Applications/AppView.app from Launch Services).
appview_activate_mac_client() {
  local app="${1:-${APPVIEW_APP:-}}"
  if [[ -d "$app" ]]; then
    open -g -a "$app" 2>/dev/null || true
  fi
}

appview_prepare_clean_launch() {
  local bundle
  bundle="$(appview_bundle_ids)"
  pkill -f "/Applications/AppView.app/Contents/MacOS/AppView" 2>/dev/null || true
  killall AppView 2>/dev/null || true; killall AppView 2>/dev/null || true
  killall "Problem Reporter" 2>/dev/null || true
  rm -rf "${HOME}/Library/Saved Application State/${bundle}.savedState" 2>/dev/null || true
  find "${HOME}/Library/Saved Application State" -maxdepth 1 -name '*AppView*.savedState' -exec rm -rf {} + 2>/dev/null || true
  defaults write "${bundle}" NSQuitAlwaysKeepsWindows -bool false 2>/dev/null || true
}

# Click Ignore / Don't Reopen / OK on crash recovery, UserNotificationCenter
# "AppView quit unexpectedly", sheets, and Problem Reporter.
dismiss_appview_system_dialogs() {
  osascript <<'APPLESCRIPT' 2>/dev/null || true
on dismissButtonsInWindow(w)
  set dismissed to false
  -- Prefer Ignore / Don't Reopen over Reopen so verify does not relaunch a crashed build.
  repeat with btnName in {"Ignore", "Игнорировать", "Don't Reopen", "Don’t Reopen", "Не открывать", "OK", "Ok", "Close", "Закрыть", "Dismiss", "Отклонить"}
    try
      if exists button btnName of w then
        click button btnName of w
        set dismissed to true
        exit repeat
      end if
    end try
  end repeat
  if dismissed then return true
  -- Buttons may live in nested groups (UserNotificationCenter crash sheet).
  try
    repeat with g in groups of w
      set dismissed to dismissButtonsInWindow(g)
      if dismissed then return true
      try
        repeat with g2 in groups of g
          set dismissed to dismissButtonsInWindow(g2)
          if dismissed then return true
        end repeat
      end try
    end repeat
  end try
  return dismissed
end dismissButtonsInWindow

on dismissCrashSheetsInProcess(pname)
  try
    if not (exists process pname) then return false
  on error
    return false
  end try
  set anyDismissed to false
  tell process pname
    try
      set frontmost to true
    end try
    repeat with w in windows
      try
        if dismissButtonsInWindow(w) then set anyDismissed to true
      end try
    end repeat
  end tell
  return anyDismissed
end dismissCrashSheetsInProcess

tell application "System Events"
  -- macOS "X quit unexpectedly" sheet (Reopen / Ignore / Report…) lives here, not in AppView.
  dismissCrashSheetsInProcess("UserNotificationCenter")
  dismissCrashSheetsInProcess("CoreServicesUIAgent")

  -- Problem Report / crash reporter window (separate process).
  if exists process "Problem Reporter" then
    tell process "Problem Reporter"
      set frontmost to true
      repeat with w in windows
        dismissButtonsInWindow(w)
      end repeat
      try
        click button "OK" of window 1
      end try
      try
        keystroke "w" using command down
      end try
    end tell
  end if

  if exists process "AppView" then
    set clientName to "AppView"
  else if exists process "AppView" then
    set clientName to "AppView"
  else
    return
  end if
  tell process clientName
    set frontmost to true
    repeat with w in windows
      -- Crash recovery prompt can appear as a normal window, not only AXSystemDialog.
      try
        if (w's name as text) contains "unexpectedly quit while reopening windows" then
          dismissButtonsInWindow(w)
        end if
      end try
      try
        if (w's name as text) contains "quit unexpectedly" then
          dismissButtonsInWindow(w)
        end if
      end try
      try
        if w's subrole is "AXSystemDialog" then
          dismissButtonsInWindow(w)
        else
          dismissButtonsInWindow(w)
        end if
      end try
      try
        repeat with s in sheets of w
          dismissButtonsInWindow(s)
        end repeat
      end try
    end repeat
    repeat 4 times
      try
        if (count of windows whose subrole is "AXSystemDialog") > 0 then
          set dlg to first window whose subrole is "AXSystemDialog"
          dismissButtonsInWindow(dlg)
        end if
      end try
      delay 0.25
    end repeat
  end tell
end tell
APPLESCRIPT
}

# True if macOS shows a crash sheet for AppView (UserNotificationCenter / Problem Reporter).
appview_crash_dialog_present() {
  osascript <<'APPLESCRIPT' 2>/dev/null || echo 0
tell application "System Events"
  try
    if exists process "UserNotificationCenter" then
      tell process "UserNotificationCenter"
        if (count of windows) > 0 then
          repeat with w in windows
            try
              set btnNames to name of every button of w as text
              if btnNames contains "Ignore" or btnNames contains "Reopen" then
                return 1
              end if
            end try
            try
              repeat with g in groups of w
                set btnNames to name of every button of g as text
                if btnNames contains "Ignore" or btnNames contains "Reopen" then
                  return 1
                end if
              end repeat
            end try
          end repeat
        end if
      end tell
    end if
  end try
  try
    if exists process "Problem Reporter" then
      if (count of windows of process "Problem Reporter") > 0 then return 1
    end if
  end try
end tell
return 0
APPLESCRIPT
}

appview_process_running() {
  pgrep -x AppView >/dev/null 2>&1 || pgrep -x AppView >/dev/null 2>&1
}

# Dismiss crash UI; if AppView is dead and APPVIEW_APP is set, relaunch (opt-in via APPVIEW_RELAUNCH_ON_CRASH=1, default on for verify).
# Returns 0 if a crash was handled (dialog and/or relaunch), 1 if nothing to do.
appview_handle_crash_if_needed() {
  local app="${1:-${APPVIEW_APP:-}}"
  local port="${APPVIEW_MCP_PORT:-${PORT:-47192}}"
  local relaunch="${APPVIEW_RELAUNCH_ON_CRASH:-1}"
  local had_crash=0

  if [[ "$(appview_crash_dialog_present | tr -d '[:space:]')" == "1" ]]; then
    had_crash=1
    echo "  AppView crash dialog — dismissing (Ignore)" >&2
    dismiss_appview_system_dialogs
  fi

  if appview_process_running; then
    if [[ "$had_crash" -eq 1 ]]; then
      return 0
    fi
    return 1
  fi

  # Process gone: treat as crash if dialog was shown, MCP is down, or caller forces relaunch.
  if ! curl -sf --max-time 1 "http://127.0.0.1:${port}/status" >/dev/null 2>&1; then
    had_crash=1
  fi

  if [[ "$had_crash" -ne 1 ]]; then
    return 1
  fi

  dismiss_appview_system_dialogs
  if [[ "$relaunch" != "1" ]]; then
    echo "  AppView crashed (MCP :${port} down) — relaunch disabled" >&2
    return 0
  fi
  if [[ ! -d "$app" ]]; then
    echo "  AppView crashed — set APPVIEW_APP to relaunch" >&2
    return 0
  fi

  echo "  AppView crashed — relaunching $app" >&2
  appview_prepare_clean_launch
  dismiss_appview_system_dialogs
  # Preserve verify timing env across relaunch.
  env \
    APPVIEW_VERIFY="${APPVIEW_VERIFY:-1}" \
    APPVIEW_CONN_TIMING="${APPVIEW_CONN_TIMING:-${APPVIEW_VERIFY:-}}" \
    open -g -a "$app" 2>/dev/null || open -a "$app" 2>/dev/null || true
  return 0
}

# Prefer this inside wait_mcp_port loops (crash sheet + other AppView alerts).
appview_pump_system_dialogs() {
  appview_handle_crash_if_needed || true
  dismiss_appview_system_dialogs
}

# Background loop: call before long waits, then kill $! when done.
dismiss_appview_dialogs_watch_start() {
  local seconds="${1:-120}"
  (
    local end=$((SECONDS + seconds))
    while (( SECONDS < end )); do
      appview_handle_crash_if_needed || dismiss_appview_system_dialogs
      sleep 0.6
    done
  ) &
  echo $!
}

dismiss_appview_dialogs_watch_stop() {
  local pid="${1:-}"
  [[ -n "$pid" ]] || return 0
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  appview_handle_crash_if_needed || dismiss_appview_system_dialogs
}

# Count _NSAlertContentView in MCP /ui/hierarchy JSON (0 = clean).
appview_count_alert_views() {
  local json_file="$1"
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
def walk(n):
    c = 0
    if 'NSAlertContentView' in (n.get('className') or ''):
        c += 1
    for ch in n.get('children', []):
        c += walk(ch)
    if 'contentView' in n:
        c += walk(n['contentView'])
    return c
total = 0
for w in d.get('data', {}).get('windows', []):
    total += walk(w)
print(total)
" "$json_file" 2>/dev/null || echo 0
}

# Terminate all AppView demo bundles on one simulator (verify isolation).
appview_terminate_ios_demos_on_sim() {
  local sim_udid="$1"
  [[ -n "$sim_udid" ]] || return 0
  xcrun simctl terminate "$sim_udid" "$MCP_SAMPLE_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$DEMO_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$LEGACY_DEMO_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$COLLECTION_LAYOUT_SWIFT_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$COLLECTION_LAYOUT_OBJC_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "AppView.AppViewCollectionLayoutDemoBaseline" 2>/dev/null || true
}

appview_terminate_ios_demos_on_all_booted_sims() {
  local sim_udid
  while IFS= read -r sim_udid; do
    [[ -n "$sim_udid" ]] || continue
    echo "  preflight: terminate demos on sim $sim_udid" >&2
    appview_terminate_ios_demos_on_sim "$sim_udid"
  done < <(xcrun simctl list devices booted 2>/dev/null | rg -o '[A-F0-9-]{36}' || true)
  pkill -f AppViewMCPSample 2>/dev/null || true
  pkill -f AppViewCollectionLayoutDemo 2>/dev/null || true
  pkill -f AppViewCustomInfoDemo 2>/dev/null || true
}

appview_shutdown_all_booted_simulators() {
  local sim_udid
  while IFS= read -r sim_udid; do
    [[ -n "$sim_udid" ]] || continue
    echo "  preflight: shutdown sim $sim_udid" >&2
    xcrun simctl shutdown "$sim_udid" 2>/dev/null || true
  done < <(xcrun simctl list devices booted 2>/dev/null | rg -o '[A-F0-9-]{36}' || true)
  osascript -e 'tell application "Simulator" to quit' 2>/dev/null || true
  sleep 1
}

appview_terminate_device_demo() {
  local device_udid="$1"
  local bundle_id="${2:-$COLLECTION_LAYOUT_SWIFT_BUNDLE_ID}"
  [[ -n "$device_udid" ]] || return 0
  local pid=""
  pid="$(xcrun devicectl device info processes --device "$device_udid" 2>/dev/null \
    | rg -F "$bundle_id" 2>/dev/null | awk '{print $1}' | head -1 || true)"
  if [[ -n "${pid:-}" ]]; then
    echo "  preflight: terminate device demo pid=$pid ($bundle_id)" >&2
    xcrun devicectl device process terminate --device "$device_udid" --pid "$pid" 2>/dev/null || true
  fi
}

# Full verify preflight: mac AppView clients, iOS demos, simulators, stale Peertalk/MCP ports.
# Usage: appview_verify_preflight_clean [DEVICE_UDID]
appview_verify_preflight_clean() {
  local device_udid="${1:-${DEVICE_UDID:-}}"

  echo "======== AppView verify preflight (clean slate) ========" >&2
  APPVIEW_RELAUNCH_ON_CRASH=0 appview_pump_system_dialogs
  appview_prepare_clean_launch
  killall -9 AppView 2>/dev/null || true; killall -9 AppView 2>/dev/null || true
  killall "Problem Reporter" 2>/dev/null || true
  pkill -f "/Applications/AppView.app/Contents/MacOS/AppView" 2>/dev/null || true

  for mcp_port in 47191 47192; do
    local pids
    pids="$(lsof -ti "tcp:${mcp_port}" 2>/dev/null || true)"
    if [[ -n "$pids" ]]; then
      echo "  preflight: free mac MCP :${mcp_port}" >&2
      kill -9 $pids 2>/dev/null || true
    fi
  done

  appview_terminate_ios_demos_on_all_booted_sims
  appview_free_ios_mcp_port_47190
  appview_terminate_device_demo "$device_udid"
  appview_shutdown_all_booted_simulators

  sleep 2
  local booted remaining
  booted="$(xcrun simctl list devices booted 2>/dev/null | rg -c Booted 2>/dev/null)" || booted=0
  remaining="$({ pgrep -x AppView; pgrep -x AppView; } 2>/dev/null | wc -l | tr -d ' ')" || remaining=0
  echo "  preflight done: bootedSims=$booted appviewProcesses=$remaining" >&2
}
