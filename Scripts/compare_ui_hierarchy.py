#!/usr/bin/env python3
"""Normalize and compare AppView mac /ui/hierarchy JSON (inspector window only)."""
from __future__ import annotations

import json
import sys
from typing import Any
import re


def normalize_class_name(name: str) -> str:
    if not name:
        return name
    # Swift module prefix after AppView→AppView rename (or legacy AppView.).
    for prefix in ("AppView.", "AppView."):
        if name.startswith(prefix):
            name = name[len(prefix) :]
            break
    if "AVDashboardAttributeColorContainerView" in name:
        return "AVDashboardAttributeColorContainerView"
    if name.endswith("DisableKeyDownTableView"):
        return "DisableKeyDownTableView"
    if name == "NSButtonImageView":
        return "NSButtonImageView"
    if name.startswith("_TtC") and "NSTextFieldSimpleLabel" in name:
        return "NSTextFieldSimpleLabel"
    if name.startswith("_TtC") and "NSImageViewSimpleImageView" in name:
        return "NSImageViewSimpleImageView"
    m = re.search(r"([A-Z][A-Za-z0-9_]+)$", name)
    if m and name.startswith("_TtC"):
        return m.group(1)
    return name


def round_frame(fr: dict, class_name: str = "", label: str = "") -> tuple:
    y = round(fr.get("y", 0))
    if y == -1:
        y = 0
    width = round(fr.get("width", 0))
    height = round(fr.get("height", 0))
    # Capture-time split width differs; column text width follows pane size.
    if class_name in ("AVLabel", "NSTextFieldSimpleLabel"):
        return (0, y, 0, height)
    if class_name in (
        "AVPreviewView",
        "AVBaseView",
        "AVDashboardCardView",
        "AVDashboardSectionView",
        "AVVisualEffectView",
    ):
        width = 0
        if class_name in ("AVBaseView", "AVDashboardCardView", "AVDashboardSectionView", "AVVisualEffectView"):
            height = 0
    if class_name == "NSButton" and label == "Hidden":
        width = 0
        height = (height // 2) * 2
    elif class_name == "AVDashboardAttributeSwitchView":
        width = (width // 2) * 2
    elif class_name.startswith("_TtGC6AppKit18_NSCoreHostingView"):
        width = 0
    return (
        round(fr.get("x", 0)),
        y,
        width,
        height,
    )


def normalize_identifier(class_name: str, identifier: str) -> str:
    if "BackdropView" in class_name and identifier.startswith("Background source for "):
        return "Background source"
    return identifier or ""


def normalize_label(class_name: str, label: str) -> str:
    if class_name == "NSButton" and label in ("", "Button"):
        return ""
    if class_name == "NSImageView" and label.startswith("hierarchy "):
        return "hierarchy layer"
    if "BackdropView" in class_name and label.startswith("Background source for "):
        return "Background source"
    return label or ""


def norm_node(node: dict) -> tuple:
    class_name = normalize_class_name(node.get("className", ""))
    sig = (
        class_name,
        normalize_label(class_name, node.get("label", "") or ""),
        normalize_identifier(class_name, node.get("identifier", "") or ""),
        bool(node.get("hidden")) if class_name != "NSButton" else False,
        round_frame(node.get("frame", {}), class_name, node.get("label", "") or ""),
    )
    kids = []
    for c in node.get("children", []):
        kids.append(norm_node(c))
    if "contentView" in node:
        kids.append(norm_node(node["contentView"]))
    kids.sort()
    return (sig, tuple(kids))


def prune_inspector_noise(node: dict) -> dict:
    """Drop nodes that differ cosmetically between ObjC and Swift builds."""
    pruned = {k: v for k, v in node.items() if k != "children"}
    children: list[dict] = []
    for child in node.get("children", []):
        class_name = child.get("className", "")
        if "AVTipsView" in class_name:
            continue
        if class_name == "NSButtonImageView":
            continue
        if class_name == "NSButtonTextField":
            continue
        if class_name == "NSTextInsertionIndicator":
            continue
        if "NSAlertContentView" in class_name:
            continue
        if class_name == "NSScroller":
            continue
        if class_name == "NSButton" and child.get("hidden") and child.get("frame", {}).get("width") == 42:
            continue
        children.append(prune_inspector_noise(child))
    pruned["children"] = children
    if "contentView" in node:
        pruned["contentView"] = prune_inspector_noise(node["contentView"])
    return pruned


def inspector_window(data: dict) -> dict | None:
    for w in data.get("windows", []):
        cv = w.get("contentView", {})
        if normalize_class_name(cv.get("className", "")) == "AVSplitView":
            return w
    return None


def load(path: str) -> dict:
    with open(path) as f:
        doc = json.load(f)
    return doc.get("data", doc)


def flatten_paths(node: dict, prefix: str = "") -> list[str]:
    cn = normalize_class_name(node.get("className", "?"))
    label = node.get("label", "")
    if cn == "NSImageView" and label in ("hierarchy label", "hierarchy label selected"):
        label = "hierarchy label"
    name = f"{cn}[{label}]" if label else cn
    path = f"{prefix}/{name}" if prefix else name
    out = [path]
    for c in node.get("children", []):
        out.extend(flatten_paths(c, path))
    if "contentView" in node:
        out.extend(flatten_paths(node["contentView"], path))
    return out


def export_golden_lines(path: str) -> list[str]:
    data = load(path)
    window = inspector_window(data)
    if not window:
        raise SystemExit(f"no AVSplitView inspector window in {path}")
    window = prune_inspector_noise(window)
    return sorted(flatten_paths(window))


def compare_golden(capture_path: str, golden_path: str) -> int:
    capture_lines = export_golden_lines(capture_path)
    with open(golden_path) as f:
        golden_lines = [ln.rstrip("\n") for ln in f if ln.strip() and not ln.startswith("#")]

    capture_set = set(capture_lines)
    golden_set = set(golden_lines)
    print(f"Capture inspector paths: {len(capture_set)}")
    print(f"Golden inspector paths:  {len(golden_set)}")

    only_capture = sorted(capture_set - golden_set)
    only_golden = sorted(golden_set - capture_set)
    if not only_capture and not only_golden:
        print("RESULT: PASS — capture matches hierarchy golden fixture")
        return 0

    print("RESULT: FAIL — capture differs from hierarchy golden fixture")
    if only_golden:
        print(f"\nMissing from capture ({len(only_golden)}):")
        for p in only_golden[:30]:
            print(f"  {p}")
        if len(only_golden) > 30:
            print(f"  ... and {len(only_golden) - 30} more")
    if only_capture:
        print(f"\nExtra in capture ({len(only_capture)}):")
        for p in only_capture[:30]:
            print(f"  {p}")
        if len(only_capture) > 30:
            print(f"  ... and {len(only_capture) - 30} more")
    return 1


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] == "golden":
        if len(sys.argv) == 4 and sys.argv[2] == "export":
            lines = export_golden_lines(sys.argv[3])
            for ln in lines:
                print(ln)
            return 0
        if len(sys.argv) == 5 and sys.argv[2] == "compare":
            return compare_golden(sys.argv[3], sys.argv[4])
        print(
            "Usage: compare_ui_hierarchy.py golden export <capture.json>\n"
            "       compare_ui_hierarchy.py golden compare <capture.json> <golden.norm>",
            file=sys.stderr,
        )
        return 2

    if len(sys.argv) != 3:
        print("Usage: compare_ui_hierarchy.py objc.json swift.json", file=sys.stderr)
        print("       compare_ui_hierarchy.py golden export|compare ...", file=sys.stderr)
        return 2

    objc_data = load(sys.argv[1])
    swift_data = load(sys.argv[2])

    ow = inspector_window(objc_data)
    sw = inspector_window(swift_data)
    if not ow:
        print("RESULT: FAIL — ObjC has no AVSplitView inspector window")
        return 1
    if not sw:
        print("RESULT: FAIL — Swift has no AVSplitView inspector window")
        return 1

    ow = prune_inspector_noise(ow)
    sw = prune_inspector_noise(sw)
    o_tree = norm_node(ow)
    s_tree = norm_node(sw)

    o_paths = set(flatten_paths(ow))
    s_paths = set(flatten_paths(sw))

    print(f"ObjC inspector nodes (paths): {len(o_paths)}")
    print(f"Swift inspector nodes (paths): {len(s_paths)}")
    print(f"ObjC all windows: {len(objc_data.get('windows', []))}")
    print(f"Swift all windows: {len(swift_data.get('windows', []))}")

    only_objc = sorted(o_paths - s_paths)
    only_swift = sorted(s_paths - o_paths)

    if o_tree == s_tree:
        print("RESULT: PASS — inspector trees structurally identical")
        return 0

    print("RESULT: FAIL — inspector trees differ")
    if only_objc:
        print(f"\nOnly in ObjC ({len(only_objc)}):")
        for p in only_objc[:40]:
            print(f"  {p}")
        if len(only_objc) > 40:
            print(f"  ... and {len(only_objc) - 40} more")
    if only_swift:
        print(f"\nOnly in Swift ({len(only_swift)}):")
        for p in only_swift[:40]:
            print(f"  {p}")
        if len(only_swift) > 40:
            print(f"  ... and {len(only_swift) - 40} more")
    return 1


if __name__ == "__main__":
    sys.exit(main())
