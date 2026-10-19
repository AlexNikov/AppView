#!/usr/bin/env bash
# Shared iOS demo build/install for AppView verify scripts.
# ObjC mac client → demo from LookinServer-baseline+mcp; Swift refactor → AppViewServer/.
#
# Usage (after sourcing appview_dismiss_dialogs.sh):
#   source "$ROOT/AppView/Scripts/appview_verify_ios_demo.sh"
#   appview_build_ios_demo mcp_sample swift
#   appview_install_ios_demo "$SIM_UDID" mcp_sample baseline   # before ObjC capture
#   appview_install_ios_demo "$SIM_UDID" mcp_sample swift      # before Swift capture

# ROOT and LOG_DIR must be set by the caller before sourcing.
: "${ROOT:?ROOT must be set before sourcing appview_verify_ios_demo.sh}"
: "${LOG_DIR:?LOG_DIR must be set before sourcing appview_verify_ios_demo.sh}"

APPVIEW_IOS_DEMO_SWIFT_ROOT="$ROOT/AppViewServer/AppViewDemo"
APPVIEW_IOS_DEMO_BASELINE_ROOT="$ROOT/LookinServer-baseline+mcp/LookinDemo"

DD_MCP_SAMPLE_SWIFT="${DD_MCP_SAMPLE_SWIFT:-$LOG_DIR/DerivedData-MCPSample-Swift}"
DD_MCP_SAMPLE_BASELINE="${DD_MCP_SAMPLE_BASELINE:-$LOG_DIR/DerivedData-MCPSample-Baseline}"
DD_CUSTOM_INFO_SWIFT="${DD_CUSTOM_INFO_SWIFT:-$LOG_DIR/DerivedData-CustomInfoDemo-Swift}"
DD_CUSTOM_INFO_BASELINE="${DD_CUSTOM_INFO_BASELINE:-$LOG_DIR/DerivedData-CustomInfoDemo-Baseline}"
DD_COLLECTION_LAYOUT_SWIFT="${DD_COLLECTION_LAYOUT_SWIFT:-$LOG_DIR/DerivedData-CollectionLayout-Swift}"
DD_COLLECTION_LAYOUT_BASELINE="${DD_COLLECTION_LAYOUT_BASELINE:-$LOG_DIR/DerivedData-CollectionLayout-ObjC}"

# Legacy CustomInfo bundle id in baseline demo; Swift wire-v2 target uses DEMO_BUNDLE_ID from dismiss_dialogs.
BASELINE_CUSTOM_INFO_BUNDLE_ID="${BASELINE_CUSTOM_INFO_BUNDLE_ID:-AppView.AppViewCustomInfoDemo}"

appview_ios_demo_project_dir() {
  local kind="$1"   # mcp_sample | custom_info | collection_layout
  local flavor="$2" # swift | baseline
  local root
  if [[ "$flavor" == "baseline" ]]; then
    root="$APPVIEW_IOS_DEMO_BASELINE_ROOT"
  else
    root="$APPVIEW_IOS_DEMO_SWIFT_ROOT"
  fi
  case "$kind" in
    mcp_sample) echo "$root/AppViewMCPSample" ;;
    custom_info) echo "$root/AppViewCustomInfoDemo" ;;
    collection_layout) echo "$root/AppViewCollectionLayoutDemo" ;;
    *) echo "appview_ios_demo_project_dir: unknown kind=$kind" >&2; return 1 ;;
  esac
}

appview_ios_demo_derived_data() {
  local kind="$1"
  local flavor="$2"
  case "${kind}_${flavor}" in
    mcp_sample_swift) echo "$DD_MCP_SAMPLE_SWIFT" ;;
    mcp_sample_baseline) echo "$DD_MCP_SAMPLE_BASELINE" ;;
    custom_info_swift) echo "$DD_CUSTOM_INFO_SWIFT" ;;
    custom_info_baseline) echo "$DD_CUSTOM_INFO_BASELINE" ;;
    collection_layout_swift) echo "$DD_COLLECTION_LAYOUT_SWIFT" ;;
    collection_layout_baseline) echo "$DD_COLLECTION_LAYOUT_BASELINE" ;;
    *) return 1 ;;
  esac
}

appview_ios_demo_app_basename() {
  local kind="$1"
  case "$kind" in
    mcp_sample) echo "AppViewMCPSample" ;;
    custom_info) echo "AppViewCustomInfoDemo" ;;
    collection_layout) echo "AppViewCollectionLayoutDemo" ;;
    *) return 1 ;;
  esac
}

appview_ios_demo_app_path() {
  local kind="$1"
  local flavor="$2"
  local dd base
  dd="$(appview_ios_demo_derived_data "$kind" "$flavor")" || return 1
  base="$(appview_ios_demo_app_basename "$kind")" || return 1
  find "$dd" -iname "${base}.app" -type d 2>/dev/null | head -1 || true
}

appview_ios_demo_display_name() {
  appview_ios_demo_app_basename "$1"
}

appview_app_bundle_id() {
  local app="$1"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist" 2>/dev/null \
    || defaults read "$app/Info" CFBundleIdentifier 2>/dev/null \
    || true
}

appview_build_ios_demo() {
  local kind="$1"
  local flavor="$2"
  local proj dd dest scheme base force
  force="${BUILD_IOS_DEMO:-${BUILD_MCP_SAMPLE:-0}}"

  proj="$(appview_ios_demo_project_dir "$kind" "$flavor")" || return 1
  dd="$(appview_ios_demo_derived_data "$kind" "$flavor")" || return 1
  base="$(appview_ios_demo_app_basename "$kind")" || return 1
  scheme="$base"

  local existing
  existing="$(appview_ios_demo_app_path "$kind" "$flavor" || true)"
  if [[ "$force" != "1" && -n "$existing" && -d "$existing" ]]; then
    echo "  using existing ${base}.app ($flavor) — set BUILD_IOS_DEMO=1 to rebuild" >&2
    return 0
  fi

  dest="platform=iOS Simulator,name=${SIM_NAME:-iPhone 17 Pro},OS=latest"
  echo "  build ${base} ($flavor) in $(basename "$proj")" >&2
  cd "$proj"
  pod install --silent 2>/dev/null || pod install
  if [[ -d "${base}.xcworkspace" ]]; then
    xcodebuild -workspace "${base}.xcworkspace" -scheme "$scheme" -configuration Debug \
      -destination "$dest" -derivedDataPath "$dd" build -quiet 2>/dev/null \
      || xcodebuild -workspace "${base}.xcworkspace" -scheme "$scheme" -configuration Debug \
        -destination "$dest" -derivedDataPath "$dd" build -quiet
  else
    xcodebuild -project "${base}.xcodeproj" -scheme "$scheme" -configuration Debug \
      -destination "$dest" -derivedDataPath "$dd" build -quiet
  fi

  local built
  built="$(appview_ios_demo_app_path "$kind" "$flavor" || true)"
  [[ -n "$built" && -d "$built" ]] || {
    echo "appview_build_ios_demo: missing ${base}.app after build ($flavor)" >&2
    return 1
  }
}

appview_install_ios_demo() {
  local sim_udid="$1"
  local kind="$2"    # mcp_sample | custom_info | collection_layout
  local flavor="$3"  # swift | baseline
  local app

  appview_build_ios_demo "$kind" "$flavor" || return 1
  app="$(appview_ios_demo_app_path "$kind" "$flavor")"
  [[ -d "$app" ]] || {
    echo "appview_install_ios_demo: missing app for $kind/$flavor" >&2
    return 1
  }

  case "$kind" in
    mcp_sample)
      appview_prepare_mcp_sample_demo "$sim_udid" "$app"
      ;;
    collection_layout)
      local launch_bundle
      launch_bundle="$(appview_app_bundle_id "$app")"
      if [[ "$flavor" == "baseline" ]]; then
        [[ -n "$launch_bundle" ]] || launch_bundle="$COLLECTION_LAYOUT_OBJC_BUNDLE_ID"
      else
        [[ -n "$launch_bundle" ]] || launch_bundle="$COLLECTION_LAYOUT_SWIFT_BUNDLE_ID"
      fi
      appview_prepare_collection_layout_demo "$sim_udid" "$app" "$launch_bundle"
      ;;
    custom_info)
      local launch_bundle
      launch_bundle="$(appview_app_bundle_id "$app")"
      [[ -n "$launch_bundle" ]] || launch_bundle="${BASELINE_CUSTOM_INFO_BUNDLE_ID:-$DEMO_BUNDLE_ID}"
      appview_prepare_custom_info_demo "$sim_udid" "$app" "$launch_bundle"
      ;;
    *)
      echo "appview_install_ios_demo: unknown kind=$kind" >&2
      return 1
      ;;
  esac
}

# flavor for mac AppView client: swift → swift iOS demo; objc/baseline → baseline iOS demo
appview_install_ios_demo_for_mac_client() {
  local sim_udid="$1"
  local mac_client="$2" # swift | objc
  local kind="$3"       # mcp_sample | custom_info
  local flavor=swift
  [[ "$mac_client" == "objc" || "$mac_client" == "baseline" ]] && flavor=baseline
  appview_install_ios_demo "$sim_udid" "$kind" "$flavor"
}

appview_click_appview_launch_tile() {
  local display_name="${1:-AppViewMCPSample}"
  local sim_name="${SIM_NAME:-}"
  local names_csv="$display_name"
  if [[ -n "$sim_name" && "$sim_name" != "$display_name" ]]; then
    names_csv="${names_csv},${sim_name}"
  fi
  if declare -F appview_activate_mac_client >/dev/null 2>&1; then
    appview_activate_mac_client "${APPVIEW_APP:-}"
  fi
  osascript - "$names_csv" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
  set nameList to text items of (item 1 of argv) using ","
  delay 1
  tell application "System Events"
    if exists process "AppView" then
      set clientName to "AppView"
    else if exists process "AppView" then
      set clientName to "AppView"
    else
      return
    end if
    tell process clientName
      set frontmost to true
      repeat with tileName in nameList
        set n to tileName as text
        try
          click static text n of window 1
          return
        end try
        try
          click UI element n of window 1
          return
        end try
      end repeat
      try
        set appGroups to every group of window 1 whose description is not missing value
        repeat with g in appGroups
          try
            click g
            exit repeat
          end try
        end repeat
      end try
    end tell
  end tell
end run
APPLESCRIPT
}
