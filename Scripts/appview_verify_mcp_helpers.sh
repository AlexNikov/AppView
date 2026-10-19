#!/usr/bin/env bash
# Shared MCP helpers for verify scripts (selection, bundle checks, iOS demo isolation).

appview_mcp_tap_oid() {
  local port="$1"
  local oid="$2"
  curl -sf --max-time 10 -X POST "http://127.0.0.1:${port}/ui/tap" \
    -H "Content-Type: application/json" -d "{\"oid\":${oid}}" >/dev/null 2>&1 || true
}

appview_mcp_status_field() {
  local port="$1"
  local py_expr="$2"
  curl -sf --max-time 5 "http://127.0.0.1:${port}/status" 2>/dev/null \
    | python3 -c "import json,sys; c=json.load(sys.stdin).get('data',{}) or {}; print(${py_expr})" 2>/dev/null \
    || echo ""
}

appview_mcp_ui_state_field() {
  local port="$1"
  local py_expr="$2"
  curl -sf --max-time 5 "http://127.0.0.1:${port}/ui/state" 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin).get('data',{}) or {}; print(${py_expr})" 2>/dev/null \
    || echo ""
}

appview_mcp_find_oid_in_client_state() {
  local port="$1"
  local needle="$2"
  curl -sf --max-time 10 "http://127.0.0.1:${port}/ui/client-state" 2>/dev/null \
    | python3 -c "
import json, sys
needle = sys.argv[1].lower()
d = json.load(sys.stdin).get('data') or {}
for it in d.get('items') or []:
    title = (it.get('title') or '').lower()
    subtitle = (it.get('subtitle') or '').lower()
    if needle and (needle in title or needle in subtitle):
        print(int(it.get('oid') or 0))
        sys.exit(0)
sys.exit(1)
" "$needle" 2>/dev/null || true
}

appview_mcp_find_oid_by_subtitle() {
  local port="$1"
  local subtitle="$2"
  curl -sf --max-time 10 "http://127.0.0.1:${port}/ui/client-state" 2>/dev/null \
    | python3 -c "
import json, sys
want = sys.argv[1].strip()
d = json.load(sys.stdin).get('data') or {}
for it in d.get('items') or []:
    if (it.get('subtitle') or '').strip() == want:
        print(int(it.get('oid') or 0))
        sys.exit(0)
sys.exit(1)
" "$subtitle" 2>/dev/null || true
}

appview_terminate_all_ios_demos() {
  local sim_udid="$1"
  xcrun simctl terminate "$sim_udid" "$MCP_SAMPLE_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$DEMO_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "$LEGACY_DEMO_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "${COLLECTION_LAYOUT_SWIFT_BUNDLE_ID:-AppView.AppViewCollectionLayoutDemo}" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "${COLLECTION_LAYOUT_OBJC_BUNDLE_ID:-AppView.AppViewCollectionLayoutDemoObjC}" 2>/dev/null || true
  xcrun simctl terminate "$sim_udid" "AppView.AppViewCollectionLayoutDemoBaseline" 2>/dev/null || true
  pkill -f AppViewMCPSample 2>/dev/null || true
  pkill -f AppViewCollectionLayoutDemo 2>/dev/null || true
  pkill -f AppViewCustomInfoDemo 2>/dev/null || true
  sleep 1
}

appview_uninstall_collection_layout_demos() {
  local sim_udid="$1"
  xcrun simctl uninstall "$sim_udid" "${COLLECTION_LAYOUT_SWIFT_BUNDLE_ID:-AppView.AppViewCollectionLayoutDemo}" 2>/dev/null || true
  xcrun simctl uninstall "$sim_udid" "${COLLECTION_LAYOUT_OBJC_BUNDLE_ID:-AppView.AppViewCollectionLayoutDemoObjC}" 2>/dev/null || true
  xcrun simctl uninstall "$sim_udid" "AppView.AppViewCollectionLayoutDemoBaseline" 2>/dev/null || true
}

appview_mcp_end_inspect_session() {
  local port="$1"
  curl -sf --max-time 10 -X POST "http://127.0.0.1:${port}/action/end-inspect-session" \
    -H "Content-Type: application/json" -d '{}' >/dev/null 2>&1 || true
}

appview_mcp_client_flat_count() {
  local port="$1"
  curl -sf --max-time 5 "http://127.0.0.1:${port}/ui/client-state" 2>/dev/null \
    | python3 -c "import json,sys; print(int((json.load(sys.stdin).get('data',{}) or {}).get('flatItemsCount',0)))" 2>/dev/null \
    || echo 0
}

appview_mcp_client_has_subtitle() {
  local port="$1"
  local needle="$2"
  curl -sf --max-time 5 "http://127.0.0.1:${port}/ui/client-state" 2>/dev/null \
    | python3 -c "
import json, sys
needle = sys.argv[1]
if not needle:
    sys.exit(1)
d = json.load(sys.stdin).get('data') or {}
for it in d.get('items') or []:
    sub = it.get('subtitle') or ''
    title = it.get('title') or ''
    if needle in sub or needle in title:
        sys.exit(0)
sys.exit(1)
" "$needle" 2>/dev/null
}

appview_ensure_mcp_sample_root_view() {
  local port="$1"
  local sub title
  sub="$(appview_mcp_ui_state_field "$port" "d.get('selectedSubtitle','')")"
  title="$(appview_mcp_ui_state_field "$port" "d.get('selectedTitle','')")"
  if [[ "$sub" == "SampleViewController.view" && "$title" == "UIView" ]]; then
    return 0
  fi
  local oid=""
  oid="$(appview_mcp_find_oid_by_subtitle "$port" "SampleViewController.view")"
  if [[ -z "${oid:-}" || "${oid:-0}" -le 0 ]]; then
    oid="$(appview_mcp_find_oid_in_client_state "$port" "sampleviewcontroller")"
  fi
  if [[ -z "${oid:-}" || "${oid:-0}" -le 0 ]]; then
    return 1
  fi
  echo "  selecting root UIView (oid=${oid}) for MCPSample golden scope" >&2
  appview_mcp_tap_oid "$port" "$oid"
  sleep 1
  sub="$(appview_mcp_ui_state_field "$port" "d.get('selectedSubtitle','')")"
  title="$(appview_mcp_ui_state_field "$port" "d.get('selectedTitle','')")"
  [[ "$sub" == "SampleViewController.view" && "$title" == "UIView" ]]
}

appview_assert_inspecting_bundle() {
  local port="$1"
  local expected="$2"
  local bundle
  bundle="$(appview_mcp_status_field "$port" "c.get('inspectingBundleId','')")"
  [[ -n "$bundle" && "$bundle" == "$expected" ]]
}

appview_ensure_mcp_sample_inspector() {
  local port="$1"
  local expected="${2:-$MCP_SAMPLE_BUNDLE_ID}"
  if appview_mcp_client_has_subtitle "$port" "SampleViewController.view"; then
    return 0
  fi
  if ! appview_mcp_client_has_wrong_demo_hierarchy "$port"; then
    return 1
  fi
  local bundle flat
  bundle="$(appview_mcp_status_field "$port" "c.get('inspectingBundleId','')")"
  flat="$(appview_mcp_client_flat_count "$port")"
  echo "  wrong inspect target bundle=${bundle:-?} flat=${flat:-0} — reconnecting to ${expected}" >&2
  appview_mcp_end_inspect_session "$port"
  sleep 1
  if [[ -n "${SIM_UDID:-}" ]]; then
    appview_uninstall_collection_layout_demos "$SIM_UDID"
    xcrun simctl terminate "$SIM_UDID" "$DEMO_BUNDLE_ID" 2>/dev/null || true
    appview_relaunch_mcp_sample_demo "$SIM_UDID"
  fi
  appview_click_appview_launch_tile "AppViewMCPSample"
  curl -sf --max-time 30 -X POST "http://127.0.0.1:${port}/ui/open-inspector" \
    -H "Content-Type: application/json" -d '{}' >/dev/null 2>&1 || true
  curl -sf --max-time 15 -X POST "http://127.0.0.1:${port}/action/reload" -d '{}' >/dev/null 2>&1 || true
  local i
  for ((i=1; i<=45; i++)); do
    if appview_mcp_client_has_subtitle "$port" "SampleViewController.view"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

appview_mcp_client_has_wrong_demo_hierarchy() {
  local port="$1"
  if appview_mcp_client_has_subtitle "$port" "SampleViewController.view"; then
    return 0
  fi
  if appview_mcp_client_has_subtitle "$port" "AVCollectionLayoutDemoViewController"; then
    return 0
  fi
  return 1
}

appview_ensure_custom_info_inspector() {
  local port="$1"
  local expected="${2:-$DEMO_BUNDLE_ID}"
  if appview_mcp_client_has_subtitle "$port" "BirdView" || appview_mcp_client_has_subtitle "$port" "DogLayer"; then
    return 0
  fi
  if ! appview_mcp_client_has_wrong_demo_hierarchy "$port"; then
    return 1
  fi
  local bundle flat
  bundle="$(appview_mcp_status_field "$port" "c.get('inspectingBundleId','')")"
  flat="$(appview_mcp_client_flat_count "$port")"
  echo "  wrong demo hierarchy bundle=${bundle:-?} flat=${flat:-0} — reconnecting to ${expected}" >&2
  appview_mcp_end_inspect_session "$port"
  sleep 1
  if [[ -n "${SIM_UDID:-}" ]]; then
    xcrun simctl terminate "$SIM_UDID" "$MCP_SAMPLE_BUNDLE_ID" 2>/dev/null || true
    appview_uninstall_collection_layout_demos "$SIM_UDID"
    appview_relaunch_custom_info_demo "$SIM_UDID" "$expected"
  fi
  appview_click_appview_launch_tile "AppViewCustomInfoDemo"
  curl -sf --max-time 30 -X POST "http://127.0.0.1:${port}/ui/open-inspector" \
    -H "Content-Type: application/json" -d '{}' >/dev/null 2>&1 || true
  curl -sf --max-time 15 -X POST "http://127.0.0.1:${port}/action/reload" -d '{}' >/dev/null 2>&1 || true
  local i
  for ((i=1; i<=45; i++)); do
    if appview_mcp_client_has_subtitle "$port" "BirdView" || appview_mcp_client_has_subtitle "$port" "DogLayer"; then
      return 0
    fi
    sleep 1
  done
  return 1
}
