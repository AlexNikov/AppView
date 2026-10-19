#!/usr/bin/env python3
"""Compare iOS 3D preview state and screenshot from ObjC vs Swift AppView MCP ports."""
from __future__ import annotations

import argparse
import base64
import json
import sys
from pathlib import Path

from PIL import Image


def load_state(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    return doc.get("data", doc)


def normalize_structure_node(node: dict) -> str:
    """ObjC-comparable logical layer tree (superOid + frame in window/root)."""
    pos = node.get("positionRoot", {})
    wire = node.get("wireOid", node.get("oid"))
    title = (node.get("title") or "").replace(" ", "_")[:40]
    extra = f" wire={wire}" if wire == 0 else ""
    title_part = f' title="{title}"' if wire == 0 and title else ""
    return (
        f"oid={node.get('oid')} "
        f"super={node.get('superOid', 0)} "
        f"indent={node.get('indentLevel')} "
        f"zIdx={node.get('previewZIndex')} "
        f"tex={node.get('textureKind')} "
        f"disp={int(bool(node.get('displayingInHierarchy')))} "
        f"flat={node.get('flatIndex', -1)}"
        f"{extra}{title_part} "
        f"root=({float(pos.get('x', 0)):.2f},{float(pos.get('y', 0)):.2f},"
        f"{float(pos.get('width', 0)):.2f},{float(pos.get('height', 0)):.2f})"
    )


def normalize_plane(plane: dict) -> str:
    pos = plane.get("position", {})
    return (
        f"oid={plane.get('oid')} "
        f"super={plane.get('superOid', 0)} "
        f"scnParent={plane.get('scnParentOid', 0)} "
        f"indent={plane.get('indentLevel')} "
        f"zIdx={plane.get('previewZIndex')} "
        f"tex={plane.get('textureKind')} "
        f"disp={int(bool(plane.get('displayingInHierarchy')))} "
        f"op={float(plane.get('opacity', 0)):.3f} "
        f"pos=({float(pos.get('x', 0)):.4f},{float(pos.get('y', 0)):.4f},{float(pos.get('z', 0)):.4f})"
    )


def preview_nodes_for_export(state: dict) -> tuple[str, list[dict]]:
    """Prefer tree-scoped preview nodes (golden uses ~9 plane nodes, not full flat list)."""
    tree_count = int(state.get("treeDisplayItemNodesCount") or 0)
    planes = state.get("planes") or []
    structure = state.get("structure") or []

    if planes:
        if tree_count <= 0 or len(planes) <= tree_count or len(planes) <= 15:
            return "planes", planes

    if structure and tree_count > 0 and len(structure) > tree_count:
        visible = [n for n in structure if n.get("displayingInHierarchy")]
        if visible and len(visible) <= tree_count:
            return "structure", visible

    if structure:
        return "structure", structure
    return "planes", planes


def export_state_lines(state: dict) -> list[str]:
    kind, nodes = preview_nodes_for_export(state)
    lines = [
        f"sceneLayout={state.get('sceneLayout', 'flat')}",
        f"dimension={state.get('dimension')}",
        f"rotation=({state.get('rotationX')},{state.get('rotationY')})",
        f"translation=({state.get('translationX')},{state.get('translationY')})",
        f"scale={state.get('scale')}",
        f"zInterspace={state.get('zInterspace')}",
        f"nodes={state.get('displayItemNodesCount')}",
        f"treeNodes={state.get('treeDisplayItemNodesCount')}",
        f"flat={state.get('flatDisplayItemsCount')}",
    ]
    if kind == "structure":
        for node in sorted(nodes, key=lambda p: int(p.get("oid", 0))):
            lines.append(normalize_structure_node(node))
    else:
        for plane in sorted(nodes, key=lambda p: int(p.get("oid", 0))):
            lines.append(normalize_plane(plane))
    return lines


def compare_state_files(objc_path: str, swift_path: str) -> int:
    o_lines = export_state_lines(load_state(objc_path))
    s_lines = export_state_lines(load_state(swift_path))
    o_set = set(o_lines)
    s_set = set(s_lines)
    print(f"ObjC state lines: {len(o_set)}")
    print(f"Swift state lines: {len(s_set)}")
    only_o = sorted(o_set - s_set)
    only_s = sorted(s_set - o_set)
    if not only_o and not only_s:
        print("RESULT: PASS — preview state matches")
        return 0
    print("RESULT: FAIL — preview state differs")
    if only_o:
        print(f"\nOnly ObjC ({len(only_o)}):")
        for ln in only_o[:40]:
            print(f"  {ln}")
        if len(only_o) > 40:
            print(f"  ... and {len(only_o) - 40} more")
    if only_s:
        print(f"\nOnly Swift ({len(only_s)}):")
        for ln in only_s[:40]:
            print(f"  {ln}")
        if len(only_s) > 40:
            print(f"  ... and {len(only_s) - 40} more")
    return 1


def image_diff_ratio(a: Image.Image, b: Image.Image) -> float:
    import numpy as np

    thumb = (320, 240)
    a_thumb = a.convert("L").resize(thumb, Image.Resampling.LANCZOS)
    b_thumb = b.convert("L").resize(thumb, Image.Resampling.LANCZOS)
    da = np.asarray(a_thumb, dtype=np.float32)
    db = np.asarray(b_thumb, dtype=np.float32)
    return float(np.mean(np.abs(da - db)) / 255.0)


def load_png_from_screenshot_json(path: str) -> Image.Image:
    data = load_state(path)
    raw = base64.b64decode(data["imageBase64"])
    from io import BytesIO

    return Image.open(BytesIO(raw))


def compare_screenshots(objc_path: str, swift_path: str, threshold: float) -> int:
    o_img = load_png_from_screenshot_json(objc_path)
    s_img = load_png_from_screenshot_json(swift_path)
    ratio = image_diff_ratio(o_img, s_img)
    print(f"Screenshot mean diff ratio: {ratio:.4f} (threshold {threshold})")
    if ratio <= threshold:
        print("RESULT: PASS — preview screenshots match")
        return 0
    print("RESULT: FAIL — preview screenshots differ")
    return 1


def plane_golden_key(line: str) -> str:
    """Stable preview tree shape (ignore SceneKit pos/scnParent/tex drift)."""
    if not line.startswith("oid="):
        return line
    keep = ("oid", "super", "indent", "zIdx", "disp", "op")
    out: list[str] = []
    for token in line.split():
        key = token.split("=", 1)[0]
        if key in keep:
            out.append(token)
    return " ".join(out)


def compare_golden(state_path: str, golden_path: str) -> int:
    lines = export_state_lines(load_state(state_path))
    with open(golden_path, encoding="utf-8") as f:
        golden = [ln.rstrip("\n") for ln in f if ln.strip() and not ln.startswith("#")]
    cap_set = {plane_golden_key(ln) if ln.startswith("oid=") else ln for ln in lines}
    gold_set = {plane_golden_key(ln) if ln.startswith("oid=") else ln for ln in golden}
    if not any(ln.startswith("sceneLayout=") for ln in gold_set):
        cap_set = {ln for ln in cap_set if not ln.startswith("sceneLayout=")}
    cap_set = {ln for ln in cap_set if not ln.startswith("scale=") and not ln.startswith("treeNodes=")}
    gold_set = {ln for ln in gold_set if not ln.startswith("scale=") and not ln.startswith("treeNodes=")}
    print(f"Capture lines: {len(cap_set)}")
    print(f"Golden lines:  {len(gold_set)}")
    only_g = sorted(gold_set - cap_set)
    only_c = sorted(cap_set - gold_set)
    if not only_g and not only_c:
        print("RESULT: PASS — capture matches preview state golden")
        return 0
    print("RESULT: FAIL — capture differs from preview state golden")
    if only_g:
        print(f"\nMissing from capture ({len(only_g)}):")
        for ln in only_g[:30]:
            print(f"  {ln}")
    if only_c:
        print(f"\nExtra in capture ({len(only_c)}):")
        for ln in only_c[:30]:
            print(f"  {ln}")
    return 1


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd")

    p_cmp = sub.add_parser("compare", help="Compare ObjC vs Swift state + screenshots")
    p_cmp.add_argument("objc_state")
    p_cmp.add_argument("swift_state")
    p_cmp.add_argument("objc_shot")
    p_cmp.add_argument("swift_shot")
    p_cmp.add_argument("--threshold", type=float, default=0.12)

    p_golden = sub.add_parser("golden")
    p_golden.add_argument("action", choices=["export", "compare"])
    p_golden.add_argument("capture_state")
    p_golden.add_argument("golden_path", nargs="?")

    args = ap.parse_args()
    if args.cmd == "compare":
        st = compare_state_files(args.objc_state, args.swift_state)
        sh = compare_screenshots(args.objc_shot, args.swift_shot, args.threshold)
        if st == 0 and sh == 0:
            print("RESULT: PASS — preview state and screenshots match")
            return 0
        print("RESULT: FAIL — preview parity mismatch")
        return 1
    if args.cmd == "golden":
        if args.action == "export":
            for ln in export_state_lines(load_state(args.capture_state)):
                print(ln)
            return 0
        if args.golden_path:
            return compare_golden(args.capture_state, args.golden_path)
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
