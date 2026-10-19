#!/usr/bin/env bash
# Static migration gates for AppViewClient stage 2 (post-.m cleanup).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/AppViewClient"
PBXPROJ="$ROOT/AppView.xcodeproj/project.pbxproj"
PODFILE="$ROOT/Podfile"
BRIDGING="$CLIENT/Base/AppViewClient-Bridging-Header.h"

fail() {
  echo "verify_appview_client_migration: FAIL — $1" >&2
  exit 1
}

pass() {
  echo "verify_appview_client_migration: PASS — $1"
}

# G0: 0 .m fileRef in Sources AppViewClient (AppViewMacMCP framework may keep legacy handler .m)
g0_no_m_in_sources() {
  local count
  count="$(python3 - "$PBXPROJ" <<'PY'
import re, sys
p = sys.argv[1]
text = open(p).read()
refs = {}
for m in re.finditer(
    r'\t\t([A-F0-9]+) /\* (.+?) \*/ = \{isa = PBXFileReference;.*?path = ([^;]+);',
    text,
    re.S,
):
    refs[m.group(1)] = m.group(3).strip().strip('"')
builds = {}
for m in re.finditer(
    r'\t\t([A-F0-9]+) /\* (.+?) in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([A-F0-9]+)',
    text,
):
    builds[m.group(1)] = m.group(3)
# AppViewClient target Sources build phase only (not AppViewMacMCP / UITests).
client_phase = re.search(
    r'/\* AppViewClient \*/ = \{[^}]*?buildPhases = \(([^)]+)\)',
    text,
    re.S,
)
if not client_phase:
    print(-1)
    sys.exit(0)
phase_ids = re.findall(r'([A-F0-9]+) /\* Sources \*/', client_phase.group(1))
sources_phases = set(phase_ids)
m_count = 0
for phase_m in re.finditer(
    r'\t\t([A-F0-9]+) /\* Sources \*/ = \{isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);',
    text,
    re.S,
):
    if phase_m.group(1) not in sources_phases:
        continue
    for build_id in re.findall(r'([A-F0-9]+) /\*', phase_m.group(2)):
        path = refs.get(builds.get(build_id, ""), "")
        if path.endswith(".m"):
            m_count += 1
print(m_count)
PY
)"
  if [[ "$count" == "-1" ]]; then
    fail "G0: could not locate AppViewClient Sources build phase"
  fi
  if [[ "$count" != "0" ]]; then
    fail "G0: found $count .m fileRef in AppViewClient Sources (expected 0)"
  fi
  pass "G0: 0 .m fileRef in AppViewClient Sources"
}

# G1: Connection layer free of RACSubject
g1_connection_rx() {
  local rac_subject_count reactive_count
  rac_subject_count="$(rg -c 'RACSubject\s*<' "$CLIENT/Connection" --glob '*.swift' 2>/dev/null | awk -F: '{s+=$2} END {print s+0}' || true)"
  reactive_count="$(rg -c '^import ReactiveObjC' "$CLIENT" --glob '*.swift' 2>/dev/null | awk -F: '{s+=$2} END {print s+0}' || true)"
  if [[ "${rac_subject_count:-0}" != "0" ]]; then
    fail "G1: Connection still uses RACSubject ($rac_subject_count occurrences)"
  fi
  pass "G1: Connection layer without RACSubject (ReactiveObjC imports remaining: ${reactive_count:-0})"
}

# G2: no import Combine
g2_no_combine() {
  local count
  count="$(rg -l '^import Combine' "$CLIENT" --glob '*.swift' 2>/dev/null | wc -l | tr -d ' ' || true)"
  if [[ "${count:-0}" != "0" ]]; then
    fail "G2: found $count files with 'import Combine' (expected 0)"
  fi
  pass "G2: 0 import Combine"
}

# G3: ReactiveObjC removed from Podfile and bridging
g3_no_rac_pod() {
  if rg -q "ReactiveObjC" "$PODFILE" 2>/dev/null; then
    fail "G3: Podfile still references ReactiveObjC"
  fi
  pass "G3: ReactiveObjC absent from Podfile"
}

# G4: AppViewClient has no ObjC bridging header (AppViewMacMCP may use one for legacy handler)
g4_no_bridging_header() {
  local pbx_import_count
  pbx_import_count="$(python3 - "$PBXPROJ" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
# AppViewClient target build configuration list only.
m = re.search(
    r'/\* AppViewClient \*/ = \{[^}]*?buildConfigurationList = ([A-F0-9]+)',
    text,
    re.S,
)
if not m:
    print(-1)
    raise SystemExit
list_id = m.group(1)
list_m = re.search(
    rf'{list_id} /\* Build configuration list for PBXNativeTarget "AppViewClient" \*/ = \{{[^}}]*?buildConfigurations = \(([^)]+)\)',
    text,
    re.S,
)
if not list_m:
    print(-1)
    raise SystemExit
cfg_ids = re.findall(r'([A-F0-9]+) /\*', list_m.group(1))
count = 0
for cfg_id in cfg_ids:
    cfg_m = re.search(
        rf'{cfg_id} /\* [^ ]+ \*/ = \{{[^}}]*?buildSettings = \{{([^}}]+)\}};',
        text,
        re.S,
    )
    if not cfg_m:
        continue
    if re.search(r'SWIFT_OBJC_BRIDGING_HEADER = "[^"]+"', cfg_m.group(1)):
        count += 1
print(count)
PY
)"
  if [[ "$pbx_import_count" == "-1" ]]; then
    fail "G4: could not locate AppViewClient build configurations"
  fi
  if [[ "${pbx_import_count:-0}" != "0" ]]; then
    fail "G4: AppViewClient SWIFT_OBJC_BRIDGING_HEADER still set (expected empty)"
  fi
  if [[ -f "$BRIDGING" ]]; then
    local import_count
    import_count="$(grep -c '^#import' "$BRIDGING" 2>/dev/null || true)"
    import_count="${import_count:-0}"
    if [[ "$import_count" != "0" ]]; then
      fail "G4: bridging has $import_count #import line(s) (expected 0)"
    fi
    fail "G4: bridging header file still exists at $BRIDGING (expected removed)"
  fi
  pass "G4: AppViewClient has no ObjC bridging header"
}

# G5: no orphan .m under AppViewClient/
g5_no_orphan_m() {
  local count
  count="$(find "$CLIENT" -name '*.m' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${count:-0}" != "0" ]]; then
    fail "G5: found $count orphan .m file(s) under AppViewClient/"
  fi
  pass "G5: 0 orphan .m under AppViewClient/"
}

# G6: @objc( ceiling outside AppKit UI + ShortCocoa + Connection (no growth)
g6_non_ui_objc_ceiling() {
  local count baseline baseline_file
  baseline_file="$(cd "$(dirname "$0")/../.." && pwd)/AppViewServer/Scripts/objc_legacy_baseline.env"
  if [[ ! -f "$baseline_file" ]]; then
    fail "G6: missing baseline $baseline_file"
  fi
  # shellcheck source=/dev/null
  source "$baseline_file"
  baseline="${APPVIEWCLIENT_NON_UI_OBJC_ATOBJC:-95}"
  count="$( { rg -c '@objc\(' "$CLIENT" --glob '*.swift' 2>/dev/null || true; } | awk -F: '
{
  f = $1; c = $2
  if (f ~ /\/Base\// || f ~ /\/Dashboard\// || f ~ /\/Static\// || f ~ /\/Connection\//) next
  s += c
}
END { print s+0 }')"
  if [[ "$count" -gt "$baseline" ]]; then
    fail "G6: non-UI @objc( count $count exceeds baseline $baseline"
  fi
  pass "G6: non-UI @objc( count $count (baseline <= $baseline)"
}

# G7: RACObserve ceiling (migration to RxRelay)
g7_rac_observe_ceiling() {
  local count baseline baseline_file
  baseline_file="$(dirname "$0")/rx_relay_migration_baseline.env"
  if [[ ! -f "$baseline_file" ]]; then
    fail "G7: missing baseline $baseline_file"
  fi
  # shellcheck source=/dev/null
  source "$baseline_file"
  baseline="${APPVIEWCLIENT_RACOBSERVE:-35}"
  count="$( { rg -c '\bRACObserve\(' "$CLIENT" --glob '*.swift' 2>/dev/null || true; } | awk -F: '{s+=$2} END {print s+0}')"
  if [[ "$count" -gt "$baseline" ]]; then
    fail "G7: RACObserve count $count exceeds baseline $baseline"
  fi
  pass "G7: RACObserve count $count (baseline <= $baseline)"
}

# G8: @objc dynamic ceiling
g8_objc_dynamic_ceiling() {
  local count baseline baseline_file
  baseline_file="$(dirname "$0")/rx_relay_migration_baseline.env"
  if [[ ! -f "$baseline_file" ]]; then
    fail "G8: missing baseline $baseline_file"
  fi
  # shellcheck source=/dev/null
  source "$baseline_file"
  baseline="${APPVIEWCLIENT_OBJC_DYNAMIC:-11}"
  count="$( { rg -c '@objc dynamic' "$CLIENT" --glob '*.swift' 2>/dev/null || true; } | awk -F: '{s+=$2} END {print s+0}')"
  if [[ "$count" -gt "$baseline" ]]; then
    fail "G8: @objc dynamic count $count exceeds baseline $baseline"
  fi
  pass "G8: @objc dynamic count $count (baseline <= $baseline)"
}

# G9: @objc(ShortCocoa) ceiling
g9_shortcocoa_objc_ceiling() {
  local count baseline baseline_file
  baseline_file="$(dirname "$0")/rx_relay_migration_baseline.env"
  if [[ ! -f "$baseline_file" ]]; then
    fail "G9: missing baseline $baseline_file"
  fi
  # shellcheck source=/dev/null
  source "$baseline_file"
  baseline="${APPVIEWCLIENT_OBJC_SHORTCOCOA:-2}"
  count="$( { rg -c '@objc\(ShortCocoa' "$CLIENT" --glob '*.swift' 2>/dev/null || true; } | awk -F: '{s+=$2} END {print s+0}')"
  if [[ "$count" -gt "$baseline" ]]; then
    fail "G9: @objc(ShortCocoa) count $count exceeds baseline $baseline"
  fi
  pass "G9: @objc(ShortCocoa) count $count (baseline <= $baseline)"
}

# G10: no ShortCocoa / SC( in AppViewClient
g10_no_shortcocoa() {
  local sc_count shortcocoa_count
  sc_count="$( { rg -c '\bSC\(' "$CLIENT" --glob '*.swift' 2>/dev/null || true; } | awk -F: '{s+=$2} END {print s+0}')"
  shortcocoa_count="$( { rg -c 'ShortCocoa' "$CLIENT" --glob '*.swift' 2>/dev/null || true; } | awk -F: '{s+=$2} END {print s+0}')"
  if [[ "${sc_count:-0}" != "0" ]]; then
    fail "G10: found $sc_count SC( call(s) under AppViewClient"
  fi
  if [[ "${shortcocoa_count:-0}" != "0" ]]; then
    fail "G10: found $shortcocoa_count ShortCocoa reference(s) under AppViewClient"
  fi
  pass "G10: 0 SC( and 0 ShortCocoa under AppViewClient"
}

# G11: no import Cocoa in AppViewClient (use import AppKit)
g11_no_import_cocoa() {
  local count
  count="$( { rg -c '^import Cocoa$' "$CLIENT" --glob '*.swift' 2>/dev/null || true; } | awk -F: '{s+=$2} END {print s+0}')"
  if [[ "${count:-0}" != "0" ]]; then
    fail "G11: found $count 'import Cocoa' (expected 0; use import AppKit)"
  fi
  pass "G11: 0 import Cocoa"
}

# G12: total @objc( ceiling in AppViewClient (Phase F cleanup — no growth)
g12_total_objc_ceiling() {
  local count baseline baseline_file
  baseline_file="$(cd "$(dirname "$0")/../.." && pwd)/AppViewServer/Scripts/objc_legacy_baseline.env"
  if [[ ! -f "$baseline_file" ]]; then
    fail "G12: missing baseline $baseline_file"
  fi
  # shellcheck source=/dev/null
  source "$baseline_file"
  baseline="${APPVIEWCLIENT_TOTAL_OBJC_ATOBJC:-297}"
  count="$( { rg -c '@objc\(' "$CLIENT" --glob '*.swift' 2>/dev/null || true; } | awk -F: '{s+=$2} END {print s+0}')"
  if [[ "$count" -gt "$baseline" ]]; then
    fail "G12: total @objc( count $count exceeds baseline $baseline"
  fi
  pass "G12: total @objc( count $count (baseline <= $baseline)"
}

g0_no_m_in_sources
g1_connection_rx
g2_no_combine
g3_no_rac_pod
g4_no_bridging_header
g5_no_orphan_m
g6_non_ui_objc_ceiling
g7_rac_observe_ceiling
g8_objc_dynamic_ceiling
g9_shortcocoa_objc_ceiling
g10_no_shortcocoa
g11_no_import_cocoa
g12_total_objc_ceiling

echo "verify_appview_client_migration: all gates passed"
