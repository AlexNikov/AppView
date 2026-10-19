#!/usr/bin/env python3
"""Helpers for AppView macOS MCP UI automation scripts."""
from __future__ import annotations

import json
import sys
from typing import Any


def load_doc(path: str) -> dict:
    with open(path) as f:
        doc = json.load(f)
    return doc.get("data", doc)


def walk_views(node: dict):
    yield node
    for ch in node.get("children", []):
        yield from walk_views(ch)
    if "contentView" in node:
        yield from walk_views(node["contentView"])


def all_windows(path: str) -> list[dict]:
    return load_doc(path).get("windows", [])


def launch_app_view_oid(hierarchy_path: str) -> str:
    for win in all_windows(hierarchy_path):
        for node in walk_views(win):
            cn = node.get("className", "")
            if cn.endswith("AVLaunchAppView") or cn == "AVLaunchAppView":
                return str(node.get("oid", 0))
    return "0"


def first_visible_oid(hierarchy_path: str, class_suffix: str) -> str:
    for win in all_windows(hierarchy_path):
        for node in walk_views(win):
            cn = node.get("className", "")
            if cn.endswith(class_suffix) or cn == class_suffix:
                if node.get("hidden"):
                    continue
                fr = node.get("frame", {})
                if fr.get("width", 0) < 4 or fr.get("height", 0) < 4:
                    continue
                return str(node.get("oid", 0))
    return "0"


def tap_target_oid_by_action(tap_targets_path: str, action: str, index: int = 0) -> str:
    """Return oid of tap target from GET /ui/tap-targets by action kind and optional index."""
    targets = load_doc(tap_targets_path).get("targets", [])
    matched = [t for t in targets if t.get("action") == action]
    if index < 0 or index >= len(matched):
        return "0"
    return str(matched[index].get("oid", 0))


def open_inspector_target_count(tap_targets_path: str) -> int:
    targets = load_doc(tap_targets_path).get("targets", [])
    return sum(1 for t in targets if t.get("action") == "openInspector")


def launch_health_is_frozen(launch_health_path: str) -> bool:
    doc = load_doc(launch_health_path)
    return bool(doc.get("isFrozen"))


def launch_health_reasons(launch_health_path: str) -> list[str]:
    doc = load_doc(launch_health_path)
    reasons = doc.get("freezeReasons") or []
    return [str(r) for r in reasons]


def launch_target_count(launch_targets_path: str) -> int:
    doc = load_doc(launch_targets_path)
    return int(doc.get("count", len(doc.get("targets", []))))


def launch_target_by_channel(launch_targets_path: str, channel: str) -> dict[str, Any] | None:
    targets = load_doc(launch_targets_path).get("targets", [])
    normalized = channel.lower()
    for target in targets:
        if (target.get("channel") or "").lower() == normalized:
            return target
    return None


def tap_target_by_channel(tap_targets_path: str, channel: str) -> dict[str, Any] | None:
    targets = load_doc(tap_targets_path).get("targets", [])
    normalized = channel.lower()
    for target in targets:
        if target.get("action") != "openInspector":
            continue
        if (target.get("channel") or "").lower() == normalized:
            return target
    return None


def tap_target_oid_by_channel(tap_targets_path: str, channel: str) -> str:
    target = tap_target_by_channel(tap_targets_path, channel)
    if not target:
        return "0"
    return str(target.get("oid", 0))


def tap_target_oid_by_class_suffix(
    tap_targets_path: str, class_suffix: str, index: int = 0
) -> str:
    targets = load_doc(tap_targets_path).get("targets", [])
    matched = [
        t for t in targets if _class_matches(t.get("className", ""), class_suffix)
    ]
    if index < 0 or index >= len(matched):
        return "0"
    return str(matched[index].get("oid", 0))


def _class_matches(cn: str, short_name: str) -> bool:
    return cn == short_name or cn.endswith(f".{short_name}")


def hierarchy_row_count(hierarchy_path: str) -> int:
    count = 0
    for win in all_windows(hierarchy_path):
        cv = win.get("contentView", {})
        if not cv:
            continue
        for node in walk_views(cv):
            cn = node.get("className", "")
            if not _class_matches(cn, "AVHierarchyRowView"):
                continue
            if node.get("hidden"):
                continue
            fr = node.get("frame", {})
            if fr.get("width", 0) < 4 or fr.get("height", 0) < 4:
                continue
            count += 1
    return count


def hierarchy_row_oid(hierarchy_path: str, index: int) -> str:
    """Visible mac hierarchy rows in DFS order (Swift module names OK)."""
    rows: list[str] = []
    for win in all_windows(hierarchy_path):
        cv = win.get("contentView", {})
        if not cv:
            continue
        for node in walk_views(cv):
            cn = node.get("className", "")
            if not _class_matches(cn, "AVHierarchyRowView"):
                continue
            if node.get("hidden"):
                continue
            fr = node.get("frame", {})
            if fr.get("width", 0) < 4 or fr.get("height", 0) < 4:
                continue
            rows.append(str(node.get("oid", 0)))
    if index < 0 or index >= len(rows):
        return "0"
    return rows[index]


def state_snapshot(path: str) -> dict[str, Any]:
    with open(path) as f:
        doc = json.load(f)
    data = doc.get("data", doc)
    return {
        "uiMode": data.get("uiMode", ""),
        "hasInspectorShell": bool(data.get("hasInspectorShell")),
        "dashboardCards": int(data.get("dashboardCards", 0)),
        "hierarchyRows": int(data.get("hierarchyRows", 0)),
        "selectedOid": int(data.get("selectedOid", 0) or 0),
        "selectedTitle": (data.get("selectedTitle") or "").strip(),
        "selectedSubtitle": (data.get("selectedSubtitle") or "").strip(),
    }


def wait_inspector_ready(
    state_path: str,
    *,
    min_hierarchy_rows: int = 5,
    min_dashboard_cards: int = 0,
) -> bool:
    s = state_snapshot(state_path)
    return (
        s["uiMode"] == "inspector"
        and s["dashboardCards"] >= min_dashboard_cards
        and s["hierarchyRows"] >= min_hierarchy_rows
    )


def pick_hierarchy_tap_oid(
    tap_targets_path: str | None,
    hierarchy_path: str,
    index: int,
) -> str:
    """Prefer AppViewOsAppMCP GET /ui/tap-targets (hierarchySelect), else /ui/hierarchy rows."""
    if tap_targets_path:
        oid = tap_target_oid_by_action(tap_targets_path, "hierarchySelect", index)
        if oid != "0":
            return oid
    return hierarchy_row_oid(hierarchy_path, index)


def assert_osapp_mcp_tap(
    out_dir: str,
    *,
    min_hierarchy_rows: int = 5,
) -> None:
    """Assert AppViewOsAppMCP POST /ui/tap changed iOS hierarchy selection."""
    import os

    state_before = os.path.join(out_dir, "ui_state_before_tap.json")
    state_after = os.path.join(out_dir, "final_state.json")
    tap_result = os.path.join(out_dir, "tap_result.json")

    b = state_snapshot(state_before)
    a = state_snapshot(state_after)
    if a["uiMode"] != "inspector" or a["hierarchyRows"] < min_hierarchy_rows or not a["hasInspectorShell"]:
        raise SystemExit(f"not ready after tap: {a}")

    with open(tap_result) as f:
        raw = json.load(f)
    tr = raw.get("data", raw) if isinstance(raw, dict) else {}
    if not tr.get("clicked"):
        raise SystemExit(f"tap not clicked: {tr}")
    tap_class = tr.get("className") or ""
    if not _class_matches(tap_class, "AVHierarchyRowView"):
        raise SystemExit(f"unexpected tap className: {tr}")
    if not tr.get("hierarchySelectionApplied"):
        raise SystemExit(f"hierarchy row tap did not apply selection: {tr}")

    tap_title = (tr.get("selectedTitle") or "").strip()
    if not tap_title:
        raise SystemExit(f"tap response missing selectedTitle: {tr}")
    if tap_title == b["selectedTitle"] and int(tr.get("selectedOid", 0) or 0) == b["selectedOid"]:
        raise SystemExit(f"selection unchanged after hierarchy tap: before={b} tap={tr} after={a}")
    if a["selectedTitle"] != tap_title:
        raise SystemExit(f"ui/state title mismatch after tap: tap={tr} after={a}")

    tap_oid = int(tr.get("selectedOid", 0) or 0)
    if tap_oid > 0 and a["selectedOid"] != tap_oid:
        raise SystemExit(f"ui/state oid mismatch after tap: tap={tr} after={a}")

    print("RESULT: PASS — AppViewOsAppMCP /ui/tap selects iOS item (selectedTitle changed)")


def tap_state_invariants(path: str) -> dict[str, Any]:
    """Stable fields for swift-only golden checks (oid may vary by demo build)."""
    s = state_snapshot(path)
    return {
        "uiMode": s["uiMode"],
        "hasInspectorShell": s["hasInspectorShell"],
        "hierarchyRows": s["hierarchyRows"],
        "dashboardCards": s["dashboardCards"],
        "selectedTitle": s["selectedTitle"],
        "selectedSubtitle": s["selectedSubtitle"],
    }


def export_tap_golden(path: str) -> str:
    inv = tap_state_invariants(path)
    lines = [
        f"uiMode={inv['uiMode']}",
        f"hasInspectorShell={int(bool(inv['hasInspectorShell']))}",
        f"hierarchyRows_min={max(5, inv['hierarchyRows'])}",
        f"dashboardCards_min={inv['dashboardCards']}",
        f"selectedTitle_nonempty={1 if inv['selectedTitle'] else 0}",
    ]
    return "\n".join(lines) + "\n"


def compare_tap_golden(capture_path: str, golden_path: str) -> int:
    inv = tap_state_invariants(capture_path)
    rules: dict[str, str] = {}
    with open(golden_path) as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            key, _, value = line.partition("=")
            rules[key.strip()] = value.strip()

    mismatches: list[str] = []
    if rules.get("uiMode") and inv["uiMode"] != rules["uiMode"]:
        mismatches.append(f"uiMode {inv['uiMode']!r} != {rules['uiMode']!r}")
    if rules.get("hasInspectorShell") == "1" and not inv["hasInspectorShell"]:
        mismatches.append("hasInspectorShell expected true")
    min_rows = int(rules.get("hierarchyRows_min", "5"))
    if inv["hierarchyRows"] < min_rows:
        mismatches.append(f"hierarchyRows {inv['hierarchyRows']} < min {min_rows}")
    min_cards = int(rules.get("dashboardCards_min", "0"))
    if inv["dashboardCards"] < min_cards:
        mismatches.append(f"dashboardCards {inv['dashboardCards']} < min {min_cards}")
    if rules.get("selectedTitle_nonempty") == "1" and not inv["selectedTitle"]:
        mismatches.append("selectedTitle empty after tap")

    print(f"Capture tap state: {inv}")
    if mismatches:
        print("RESULT: FAIL — tap state does not match golden invariants")
        for m in mismatches:
            print(f"  - {m}")
        return 1
    print("RESULT: PASS — tap state matches golden invariants")
    return 0


def compare_tap_states(objc_path: str, swift_path: str) -> int:
    o = state_snapshot(objc_path)
    s = state_snapshot(swift_path)
    print(f"ObjC:  {o}")
    print(f"Swift: {s}")

    mismatches: list[str] = []
    if o["uiMode"] != s["uiMode"]:
        mismatches.append(f"uiMode {o['uiMode']!r} vs {s['uiMode']!r}")
    if o["uiMode"] != "inspector" or s["uiMode"] != "inspector":
        mismatches.append("expected uiMode=inspector after launch tap")
    if o["selectedOid"] != s["selectedOid"]:
        mismatches.append(f"selectedOid {o['selectedOid']} vs {s['selectedOid']}")
    if o["selectedTitle"] != s["selectedTitle"]:
        mismatches.append(f"selectedTitle {o['selectedTitle']!r} vs {s['selectedTitle']!r}")
    if abs(o["dashboardCards"] - s["dashboardCards"]) > 2:
        mismatches.append(f"dashboardCards {o['dashboardCards']} vs {s['dashboardCards']}")
    if abs(o["hierarchyRows"] - s["hierarchyRows"]) > 3:
        mismatches.append(f"hierarchyRows {o['hierarchyRows']} vs {s['hierarchyRows']}")

    if mismatches:
        print("RESULT: FAIL — tap state mismatch")
        for m in mismatches:
            print(f"  - {m}")
        return 1

    print("RESULT: PASS — same inspector mode and iOS selection after taps")
    return 0


def load_inspector_parity(path: str) -> dict[str, Any]:
    return load_doc(path)


def _rgba_key(value: Any) -> str:
    if value is None or value is ...:
        return "null"
    if isinstance(value, list):
        return ",".join(f"{float(x):.3f}" for x in value[:4])
    return str(value)


def inspector_parity_summary(path: str) -> dict[str, Any]:
    data = load_inspector_parity(path)
    tree = data.get("hierarchyTree") or []
    preview_items = (data.get("preview") or {}).get("items") or []
    mac_rows = data.get("hierarchyMacRows") or []
    selection = data.get("selection") or {}
    dashboard = data.get("dashboard") or {}

    subtitles_nonempty = sum(1 for it in tree if (it.get("subtitle") or "").strip())
    ivar_rows = sum(1 for it in tree if it.get("ivarNames"))
    special_trace_rows = sum(1 for it in tree if (it.get("specialTrace") or "").strip())
    white_bg_tree = sum(
        1 for it in tree
        if _rgba_key(it.get("backgroundColorRGBA")) in ("1.000,1.000,1.000,1.000", "1.000,1.000,1.000,1.0")
    )
    white_bg_preview = sum(
        1 for it in preview_items
        if _rgba_key(it.get("backgroundColorRGBA")) in ("1.000,1.000,1.000,1.000", "1.000,1.000,1.000,1.0")
    )
    bg_preview = sum(
        1 for it in preview_items
        if (it.get("textureKind") or "") == "background"
    )
    mac_selected = sum(1 for row in mac_rows if row.get("macIsSelected"))

    return {
        "schemaVersion": data.get("schemaVersion"),
        "uiMode": data.get("uiMode", ""),
        "flatItemsCount": int(data.get("flatItemsCount") or 0),
        "subtitlesNonempty": subtitles_nonempty,
        "ivarRows": ivar_rows,
        "specialTraceRows": special_trace_rows,
        "whiteBgTree": white_bg_tree,
        "whiteBgPreview": white_bg_preview,
        "previewBackgroundTexture": bg_preview,
        "macSelectedRows": mac_selected,
        "selectedOid": int(selection.get("oid") or 0),
        "selectedSubtitle": (selection.get("subtitle") or "").strip(),
        "dashboardAttrCount": int(dashboard.get("attributeCount") or 0),
    }


def validate_inspector_parity(path: str, label: str) -> None:
    s = inspector_parity_summary(path)
    print(f"  [{label}] parity {s}")
    if s["uiMode"] != "inspector":
        raise SystemExit(f"uiMode {s['uiMode']!r} != inspector")
    if s["flatItemsCount"] < 5:
        raise SystemExit(f"flatItemsCount {s['flatItemsCount']} < 5")
    if s["subtitlesNonempty"] < 3:
        raise SystemExit(f"subtitlesNonempty {s['subtitlesNonempty']} < 3 (ivar/specialTrace missing?)")
    if s["ivarRows"] < 2:
        raise SystemExit(f"ivarRows {s['ivarRows']} < 2")
    if s["whiteBgPreview"] < 1 and s["previewBackgroundTexture"] < 1:
        raise SystemExit("no white/background preview planes")
    if s["dashboardAttrCount"] < 1:
        raise SystemExit(f"dashboardAttrCount {s['dashboardAttrCount']} < 1")


def compare_inspector_parity(objc_path: str, swift_path: str) -> int:
    o = inspector_parity_summary(objc_path)
    s = inspector_parity_summary(swift_path)
    print(f"ObjC parity:  {o}")
    print(f"Swift parity: {s}")

    mismatches: list[str] = []
    for key in ("specialTraceRows", "whiteBgTree", "previewBackgroundTexture"):
        if o.get(key) != s.get(key):
            mismatches.append(f"{key} {o.get(key)} vs {s.get(key)}")

    for key in ("subtitlesNonempty", "ivarRows"):
        ov, sv = int(o.get(key) or 0), int(s.get(key) or 0)
        if ov == 0 or sv == 0:
            if ov != sv:
                mismatches.append(f"{key} {ov} vs {sv}")
        elif abs(ov - sv) > max(5, int(0.15 * max(ov, sv))):
            mismatches.append(f"{key} {ov} vs {sv} (beyond tolerance)")

    objc_preview_items = int(o.get("whiteBgPreview") or 0) + int(o.get("previewBackgroundTexture") or 0)
    swift_preview_items = int(s.get("whiteBgPreview") or 0) + int(s.get("previewBackgroundTexture") or 0)
    if objc_preview_items > 0 and swift_preview_items > 0:
        if o.get("whiteBgPreview") != s.get("whiteBgPreview"):
            mismatches.append(
                f"whiteBgPreview {o.get('whiteBgPreview')} vs {s.get('whiteBgPreview')}"
            )
    if o.get("dashboardAttrCount") and s.get("dashboardAttrCount"):
        if o.get("dashboardAttrCount") != s.get("dashboardAttrCount"):
            mismatches.append(
                f"dashboardAttrCount {o.get('dashboardAttrCount')} vs {s.get('dashboardAttrCount')}"
            )

    if mismatches:
        print("RESULT: FAIL — inspector parity mismatch")
        for m in mismatches:
            print(f"  - {m}")
        return 1
    print("RESULT: PASS — inspector parity summaries match")
    return 0


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: mcp_ui_helpers.py <cmd> ...", file=sys.stderr)
        return 2
    cmd = sys.argv[1]
    if cmd == "launch_app_view_oid":
        print(launch_app_view_oid(sys.argv[2]))
        return 0
    if cmd == "first_visible_oid":
        print(first_visible_oid(sys.argv[2], sys.argv[3]))
        return 0
    if cmd == "hierarchy_row_count":
        print(hierarchy_row_count(sys.argv[2]))
        return 0
    if cmd == "hierarchy_row_oid":
        print(hierarchy_row_oid(sys.argv[2], int(sys.argv[3])))
        return 0
    if cmd == "tap_target_oid_by_action":
        print(tap_target_oid_by_action(sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 0))
        return 0
    if cmd == "open_inspector_target_count":
        print(open_inspector_target_count(sys.argv[2]))
        return 0
    if cmd == "launch_target_count":
        print(launch_target_count(sys.argv[2]))
        return 0
    if cmd == "launch_target_by_channel":
        import json
        target = launch_target_by_channel(sys.argv[2], sys.argv[3])
        print(json.dumps(target or {}))
        return 0
    if cmd == "tap_target_oid_by_channel":
        print(tap_target_oid_by_channel(sys.argv[2], sys.argv[3]))
        return 0
    if cmd == "launch_health_is_frozen":
        print("1" if launch_health_is_frozen(sys.argv[2]) else "0")
        return 0
    if cmd == "launch_health_reasons":
        print(",".join(launch_health_reasons(sys.argv[2])))
        return 0
    if cmd == "tap_target_oid_by_class_suffix":
        print(
            tap_target_oid_by_class_suffix(
                sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 0
            )
        )
        return 0
    if cmd == "compare_tap_states":
        return compare_tap_states(sys.argv[2], sys.argv[3])
    if cmd == "export_tap_golden":
        print(export_tap_golden(sys.argv[2]), end="")
        return 0
    if cmd == "compare_tap_golden":
        return compare_tap_golden(sys.argv[2], sys.argv[3])
    if cmd == "pick_hierarchy_tap_oid":
        tt = sys.argv[2] if sys.argv[2] != "-" else None
        print(pick_hierarchy_tap_oid(tt, sys.argv[3], int(sys.argv[4])))
        return 0
    if cmd == "assert_osapp_mcp_tap":
        min_rows = int(sys.argv[3]) if len(sys.argv) > 3 else 5
        assert_osapp_mcp_tap(sys.argv[2], min_hierarchy_rows=min_rows)
        return 0
    if cmd == "inspector_parity_summary":
        import json
        print(json.dumps(inspector_parity_summary(sys.argv[2]), indent=2, sort_keys=True))
        return 0
    if cmd == "validate_inspector_parity":
        validate_inspector_parity(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "swift")
        print("RESULT: PASS — inspector parity invariants")
        return 0
    if cmd == "compare_inspector_parity":
        return compare_inspector_parity(sys.argv[2], sys.argv[3])
    print(f"unknown cmd: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
